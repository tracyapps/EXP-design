import Foundation
import Observation

/// Deliberately closed vocabularies. This service never accepts a model, URL,
/// filename, action name, account identity, document UUID or arbitrary metadata.
enum UsageSource: String, Codable, Sendable {
    case newDocument = "new", openedDocument = "opened", svg, image, pdf, xd, figma, html, codepen, storybook
}
enum UsageOutput: String, Codable, Sendable {
    case png, jpg, pdf, svg, batch, handoff, html, tokens, codepenLauncher = "codepen_launcher"
}
enum UsageMutation { case edit, imported(UsageSource), none }

protocol UsageTransport: Sendable {
    func send(_ body: Data) async throws -> Bool
}

/// No cookies, credential sharing, caches, redirects or background transfers.
final class UsageHTTPTransport: NSObject, UsageTransport, URLSessionTaskDelegate, @unchecked Sendable {
    let endpoint: URL
    init(endpoint: URL) { self.endpoint = endpoint }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
    func send(_ body: Data) async throws -> Bool {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.httpAdditionalHeaders = ["User-Agent": "EXP-Usage/1"]
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 204
    }
}

@MainActor @Observable
final class UsageMetrics {
    static let storageKey = "exp.usage.v1"
    static let consentVersion = "usage-v1"
    static let queueLimit = 64
    static let localRetention: TimeInterval = 7 * 86400

    static let shared: UsageMetrics = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "EXPUsageEndpoint") as? String ?? ""
        let url = URL(string: raw)
        let endpoint = url.flatMap { value -> URL? in
            guard value.scheme == "https", value.host != nil, value.user == nil, value.password == nil,
                  value.query == nil, value.fragment == nil, value.path == "/api/usage" else { return nil }
            return value
        }
        var preview = false
        #if DEBUG
        // The disposable UI fixture has no outgoing-network entitlement.
        preview = Bundle.main.bundleIdentifier?.hasPrefix("design.tapps.exp.a11y-fixture.") == true
            && UserDefaults.standard.bool(forKey: "EXPUsageLocalPreview")
        #endif
        return UsageMetrics(defaults: .standard,
                            transport: endpoint.map { UsageHTTPTransport(endpoint: $0) },
                            available: endpoint != nil || preview,
                            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0")
    }()

    enum EventName: String, Codable {
        case firstRun = "eligible_first_run", started = "work_started", edited = "work_edited"
        case output = "output_completed", activation = "activation_completed", activeDay = "active_day"
    }
    struct Event: Codable {
        let id: UUID
        let name: EventName
        let day: String
        let appVersion: String
        let osMajor: Int
        let source: UsageSource?
        let output: UsageOutput?
    }
    struct Envelope: Codable {
        let schemaVersion: Int
        let consentVersion: String
        let installID: UUID
        let events: [Event]
    }
    private struct Pending: Codable { let event: Event; let queuedAt: Date }
    private struct State: Codable {
        var consentVersion: String
        var installID: UUID
        var grantedAt: Date
        var activated: Bool = false
        var lastActiveDay: String? = nil
        var queue: [Pending] = []
        var failures: Int = 0
        var nextAttempt: Date? = nil
    }
    private final class Work {
        weak var owner: AnyObject?
        let source: UsageSource
        var edited = false
        var outputs: Set<UsageOutput> = []
        init(_ owner: AnyObject, source: UsageSource) { self.owner = owner; self.source = source }
    }

    private(set) var isEnabled = false
    let isAvailable: Bool
    var queuedCount: Int { state?.queue.count ?? 0 }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let transport: (any UsageTransport)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let appVersion: String
    @ObservationIgnored private let osMajor: Int
    @ObservationIgnored private var state: State?
    @ObservationIgnored private var works: [ObjectIdentifier: Work] = [:]
    @ObservationIgnored private var uploadTask: Task<Void, Never>?
    @ObservationIgnored private var sending = false
    @ObservationIgnored private var scheduleSerial = 0
    @ObservationIgnored private let deliveryDelay: TimeInterval

    init(defaults: UserDefaults, transport: (any UsageTransport)?, available: Bool = true,
         appVersion: String = "2.7", osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
         now: @escaping () -> Date = Date.init, deliveryDelay: TimeInterval = 5) {
        self.defaults = defaults; self.transport = transport; self.isAvailable = available; self.now = now
        self.deliveryDelay = max(0.001, deliveryDelay)
        let pieces = appVersion.split(separator: ".").prefix(2).map(String.init)
        self.appVersion = pieces.count == 2 && pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && $0.count <= 3 })
            ? pieces.joined(separator: ".") : "0.0"
        self.osMajor = max(1, min(99, osMajor))
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(State.self, from: data),
           saved.consentVersion == Self.consentVersion, saved.grantedAt <= now(),
           saved.queue.count <= Self.queueLimit {
            state = saved; isEnabled = true
            prune(); persist(); schedule()
        }
        // Missing, malformed or obsolete consent fails closed. Preserve unknown
        // stored data until the person explicitly chooses on/off; never infer opt-in.
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled || !enabled else { return }
        scheduleSerial &+= 1
        uploadTask?.cancel(); uploadTask = nil
        works.removeAll()
        if !enabled {
            isEnabled = false; state = nil
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        guard isAvailable else { return }
        isEnabled = true
        state = State(consentVersion: Self.consentVersion, installID: UUID(), grantedAt: now())
        append(.firstRun)
        persist(); schedule()
    }

    /// Called when a usable editor appears, not from document decoding or a
    /// ReferenceFileDocument factory (which SwiftUI can call speculatively).
    func opened(_ owner: AnyObject, source: UsageSource) {
        guard isEnabled else { return }
        let key = ObjectIdentifier(owner)
        if works[key]?.owner === owner { return }
        begin(owner, source: source)
    }
    func imported(_ owner: AnyObject, source: UsageSource) {
        guard isEnabled else { return }
        begin(owner, source: source) // Import itself is not a subsequent edit.
    }
    func edited(_ owner: AnyObject) {
        guard isEnabled else { return }
        let work = context(owner)
        var changed = false
        if !work.edited { work.edited = true; append(.edited, source: work.source); changed = true }
        let day = Self.day(now())
        if state?.lastActiveDay != day { state?.lastActiveDay = day; append(.activeDay); changed = true }
        if changed { persist(); schedule() }
    }
    func output(_ owner: AnyObject, kind: UsageOutput) {
        guard isEnabled else { return }
        let work = context(owner)
        guard work.edited, work.outputs.insert(kind).inserted else { return }
        append(.output, source: work.source, output: kind)
        if state?.activated == false, work.source != .openedDocument,
           let granted = state?.grantedAt, now().timeIntervalSince(granted) >= 0,
           now().timeIntervalSince(granted) <= 7 * 86400 {
            state?.activated = true; append(.activation)
        }
        persist(); schedule()
    }

    private func begin(_ owner: AnyObject, source: UsageSource) {
        works = works.filter { $0.value.owner != nil }
        if works.count >= 32 { works.removeAll() }
        works[ObjectIdentifier(owner)] = Work(owner, source: source)
        append(.started, source: source)
        persist(); schedule()
    }
    private func context(_ owner: AnyObject) -> Work {
        if let work = works[ObjectIdentifier(owner)], work.owner === owner { return work }
        // A document already open at consent/relaunch is an existing work
        // session. No earlier creation, import or editing is reconstructed.
        begin(owner, source: .openedDocument)
        return works[ObjectIdentifier(owner)]!
    }
    private func append(_ name: EventName, source: UsageSource? = nil, output: UsageOutput? = nil) {
        guard state != nil else { return }
        prune()
        let event = Event(id: UUID(), name: name, day: Self.day(now()), appVersion: appVersion,
                          osMajor: osMajor, source: source, output: output)
        state?.queue.append(Pending(event: event, queuedAt: now()))
        if state!.queue.count > Self.queueLimit { state?.queue.removeFirst() }
    }
    private func prune() {
        let cutoff = now().addingTimeInterval(-Self.localRetention)
        state?.queue.removeAll { $0.queuedAt < cutoff || $0.queuedAt > now() }
    }
    private func persist() {
        if let state, let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.storageKey) }
    }
    private func schedule() {
        guard isAvailable, isEnabled, transport != nil, uploadTask == nil, state?.queue.isEmpty == false else { return }
        let delay = max(deliveryDelay, state?.nextAttempt?.timeIntervalSince(now()) ?? 0)
        scheduleSerial &+= 1
        let serial = scheduleSerial
        uploadTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            await self?.flush()
            guard let self, self.scheduleSerial == serial else { return }
            self.uploadTask = nil
            self.schedule()
        }
    }
    /// Bounded best-effort delivery. Callers never await this from editing/writes.
    /// Completion is guarded against consent withdrawal and a newer identity.
    func flush() async {
        guard !sending, isEnabled, isAvailable, let transport else { return }
        prune(); persist()
        guard let snapshot = state, !snapshot.queue.isEmpty,
              snapshot.nextAttempt.map({ $0 <= now() }) ?? true else { return }
        let batch = Array(snapshot.queue.prefix(32))
        let envelope = Envelope(schemaVersion: 1, consentVersion: Self.consentVersion,
                                installID: snapshot.installID, events: batch.map(\.event))
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        sending = true
        let accepted = (try? await transport.send(data)) == true
        sending = false
        guard !Task.isCancelled, isEnabled, state?.installID == snapshot.installID else { return }
        if accepted {
            let ids = Set(batch.map { $0.event.id })
            state?.queue.removeAll { ids.contains($0.event.id) }
            state?.failures = 0; state?.nextAttempt = nil
        } else {
            state?.failures += 1
            if state!.failures >= 3 {
                let ids = Set(batch.map { $0.event.id })
                state?.queue.removeAll { ids.contains($0.event.id) }
                state?.failures = 0
            }
            let failures = state?.failures ?? 0
            state?.nextAttempt = now().addingTimeInterval(60 * pow(2, Double(failures)))
        }
        persist()
    }
    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

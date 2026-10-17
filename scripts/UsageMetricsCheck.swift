import Foundation

actor CaptureUsage: UsageTransport {
    var bodies: [Data] = []
    var accepted = true
    var suspend = false
    var cancellations = 0
    func send(_ body: Data) async throws -> Bool {
        bodies.append(body)
        if suspend {
            do { try await Task.sleep(for: .seconds(30)) }
            catch { cancellations += 1; throw error }
        }
        return accepted
    }
    func configure(accepted: Bool = true, suspend: Bool = false) { self.accepted = accepted; self.suspend = suspend }
    func captured() -> [Data] { bodies }
    func cancelled() -> Int { cancellations }
}
actor LateUsage: UsageTransport {
    var calls = 0
    var waiting: CheckedContinuation<Bool, Never>?
    func send(_ body: Data) async throws -> Bool {
        calls += 1
        if calls == 1 { return await withCheckedContinuation { waiting = $0 } }
        return true
    }
    func count() -> Int { calls }
    func finishOldRequest() { waiting?.resume(returning: false); waiting = nil }
}
@MainActor final class UsageClock { var date = Date(timeIntervalSince1970: 1_792_195_200) }
@main enum Check {
    @MainActor static func main() async throws {
        let suite = "exp.usage.check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = UsageClock(), sink = CaptureUsage(), work = NSObject(), other = NSObject()
        func metrics() -> UsageMetrics { UsageMetrics(defaults: defaults, transport: sink, now: { clock.date }) }
        let service = metrics()
        service.opened(work, source: .newDocument); service.edited(work); service.output(work, kind: .png)
        await service.flush()
        let initialBodies = await sink.captured(); precondition(initialBodies.isEmpty)
        precondition(defaults.data(forKey: UsageMetrics.storageKey) == nil, "No identifier/queue before consent")
        service.setEnabled(true)
        service.opened(work, source: .newDocument)
        service.output(work, kind: .png) // No edit, therefore no output/activation.
        service.edited(work); service.edited(work)
        service.output(other, kind: .svg) // Another document cannot finish the loop.
        service.output(work, kind: .png); service.output(work, kind: .png)
        await service.flush()
        var envelope = try JSONDecoder().decode(UsageMetrics.Envelope.self, from: await sink.captured().last!)
        let originalID = envelope.installID
        precondition(envelope.events.filter { $0.name == .firstRun }.count == 1)
        precondition(envelope.events.filter { $0.name == .edited }.count == 1)
        precondition(envelope.events.filter { $0.name == .output }.count == 1)
        precondition(envelope.events.filter { $0.name == .activation }.count == 1)
        precondition(envelope.events.filter { $0.name == .activeDay }.count == 1)
        precondition(service.queuedCount == 0)
        let json = try JSONSerialization.jsonObject(with: await sink.captured().last!) as! [String: Any]
        precondition(Set(json.keys) == ["schemaVersion", "consentVersion", "installID", "events"])
        for event in json["events"] as! [[String: Any]] {
            precondition(Set(event.keys).isSubset(of: ["id", "name", "day", "appVersion", "osMajor", "source", "output"]))
        }
        print("PASS: no pre-consent storage/network; same-work ordered activation; typed payload; dedup")

        let reopened = metrics()
        reopened.opened(work, source: .openedDocument); reopened.edited(work); reopened.output(work, kind: .pdf)
        await reopened.flush()
        envelope = try JSONDecoder().decode(UsageMetrics.Envelope.self, from: await sink.captured().last!)
        precondition(envelope.installID == originalID)
        precondition(!envelope.events.contains { $0.name == .firstRun || $0.name == .activation || $0.name == .activeDay })
        print("PASS: relaunch preserves identity and install/day dedup, without reconstructing prior work")
        reopened.setEnabled(false)
        let countBefore = await sink.captured().count
        reopened.edited(work); reopened.output(work, kind: .handoff); await reopened.flush()
        let afterWithdrawal = await sink.captured(); precondition(afterWithdrawal.count == countBefore)
        precondition(defaults.data(forKey: UsageMetrics.storageKey) == nil && reopened.queuedCount == 0)
        reopened.setEnabled(true); reopened.opened(work, source: .newDocument)
        reopened.imported(work, source: .svg); reopened.output(work, kind: .svg)
        precondition(reopened.queuedCount == 3, "Import must not count as edit/output")
        reopened.edited(work); reopened.output(work, kind: .svg)
        await reopened.flush()
        envelope = try JSONDecoder().decode(UsageMetrics.Envelope.self, from: await sink.captured().last!)
        precondition(envelope.installID != originalID)
        precondition(envelope.events.contains { $0.name == .activation })
        print("PASS: withdrawal clears identity/queue and stops delivery; re-consent starts fresh; import requires subsequent edit")

        reopened.setEnabled(false); reopened.setEnabled(true)
        clock.date.addTimeInterval(8 * 86400)
        reopened.opened(work, source: .newDocument); reopened.edited(work); reopened.output(work, kind: .jpg)
        await reopened.flush()
        envelope = try JSONDecoder().decode(UsageMetrics.Envelope.self, from: await sink.captured().last!)
        precondition(!envelope.events.contains { $0.name == .activation }, "Seven-day activation window must expire")
        await sink.configure(accepted: false)
        reopened.imported(work, source: .pdf)
        let queued = reopened.queuedCount
        await reopened.flush()
        precondition(reopened.queuedCount == queued)
        clock.date.addTimeInterval(121); await reopened.flush()
        clock.date.addTimeInterval(241); await reopened.flush()
        precondition(reopened.queuedCount == 0, "Three failed attempts drop the batch")
        for _ in 0..<100 { reopened.imported(work, source: .image) }
        precondition(reopened.queuedCount <= 64)
        clock.date.addTimeInterval(8 * 86400); await reopened.flush()
        precondition(reopened.queuedCount == 0)
        print("PASS: expired activation, bounded offline retry/queue and seven-day local retention")

        await sink.configure(suspend: true)
        reopened.imported(work, source: .xd)
        let pending = Task { await reopened.flush() }
        for _ in 0..<100 { await Task.yield() }
        reopened.setEnabled(false); reopened.setEnabled(true)
        pending.cancel(); await pending.value
        precondition(reopened.isEnabled && reopened.queuedCount == 1, "Old request completion must not alter a new consent identity")
        reopened.setEnabled(false)
        defaults.set(Data("malformed".utf8), forKey: UsageMetrics.storageKey)
        let invalid = metrics()
        precondition(!invalid.isEnabled && defaults.data(forKey: UsageMetrics.storageKey) == Data("malformed".utf8))
        print("PASS: stale in-flight completion cannot resurrect erased state; invalid consent fails closed and is preserved")

        let cancellable = CaptureUsage()
        await cancellable.configure(suspend: true)
        let automatic = UsageMetrics(defaults: defaults, transport: cancellable, now: { clock.date }, deliveryDelay: 0.01)
        automatic.setEnabled(true); automatic.opened(work, source: .newDocument)
        for _ in 0..<100 {
            if await cancellable.captured().count > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let inFlight = await cancellable.captured().count
        precondition(inFlight == 1)
        automatic.setEnabled(false)
        for _ in 0..<100 {
            if await cancellable.cancelled() > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let cancellations = await cancellable.cancelled()
        precondition(cancellations == 1 && automatic.queuedCount == 0)
        precondition(defaults.data(forKey: UsageMetrics.storageKey) == nil)
        print("PASS: withdrawing consent actually cancels the scheduled in-flight transport")

        let lateSink = LateUsage()
        let lateMetrics = UsageMetrics(defaults: defaults, transport: lateSink, now: { clock.date })
        lateMetrics.setEnabled(true); lateMetrics.opened(work, source: .newDocument)
        let oldRequest = Task { await lateMetrics.flush() }
        for _ in 0..<100 {
            if await lateSink.count() == 1 { break }
            await Task.yield()
        }
        lateMetrics.setEnabled(false); lateMetrics.setEnabled(true)
        await lateSink.finishOldRequest(); await oldRequest.value
        await lateMetrics.flush()
        let lateCalls = await lateSink.count()
        precondition(lateCalls == 2 && lateMetrics.queuedCount == 0,
                     "An old failure must not impose backoff on a fresh consent identity")
        lateMetrics.setEnabled(false)
        print("PASS: even a non-cancellable old response cannot delay a fresh consent episode")

        if CommandLine.arguments.count > 1 {
            clock.date = Date()
            let url = URL(string: CommandLine.arguments[1])!
            let live = UsageMetrics(defaults: defaults, transport: UsageHTTPTransport(endpoint: url), now: { clock.date })
            live.opened(work, source: .newDocument); live.edited(work); live.output(work, kind: .png)
            await live.flush() // The real HTTP server must still receive nothing.
            live.setEnabled(true); live.opened(work, source: .newDocument); live.edited(work); live.output(work, kind: .png)
            await live.flush()
            precondition(live.queuedCount == 0, "Real first-party collector must acknowledge a durable batch")
            live.setEnabled(false)
            live.edited(work); live.output(work, kind: .handoff); await live.flush()
            if CommandLine.arguments.count > 2 {
                let redirected = try await UsageHTTPTransport(endpoint: URL(string: CommandLine.arguments[2])!).send(Data("{}".utf8))
                precondition(!redirected, "Redirect must not send usage to a different destination")
            }
            print("PASS: actual URLSession → local HTTP collector → PostgreSQL completion; redirects refused")
        }
    }
}

//
//  SanaaRuntimeProtocol.swift
//  EXP [design]
//
//  The provider-neutral, line-delimited JSON contract between EXP and its
//  bundled Sanaa Runtime. This file is compiled into both executables so the
//  panel side never has to parse a host-specific Codex message.
//

import Foundation

enum SanaaRuntimeProtocol {
    static let version = 1
    static let helperName = "sanaa-runtime"
}

enum SanaaRuntimeCommandKind: String, Codable, Sendable {
    case hello
    case connect
    case startConversation
    case sendMessage
    case stop
    case resumeConversation
    case deleteConversation
    case refreshAccountStatus
    case shutdown
}

struct SanaaRuntimeAccount: Codable, Equatable, Sendable {
    var type: String
    var email: String?
    var planType: String?
}

struct SanaaRuntimeUsageWindow: Codable, Equatable, Sendable {
    var usedPercent: Double
    var windowDurationMins: Int?
    var resetsAt: Int64?
}

struct SanaaRuntimeRateLimit: Codable, Equatable, Identifiable, Sendable {
    var id: String { limitID }
    var limitID: String
    var name: String?
    var planType: String?
    var primary: SanaaRuntimeUsageWindow?
    var secondary: SanaaRuntimeUsageWindow?
    var reachedType: String?
}

struct SanaaRuntimeUsageSummary: Codable, Equatable, Sendable {
    var lifetimeTokens: Int64?
    var peakDailyTokens: Int64?
    var currentStreakDays: Int?
    var longestStreakDays: Int?
    var latestDate: String?
    var latestTokens: Int64?
}

struct SanaaRuntimeCommand: Codable, Sendable {
    var protocolVersion = SanaaRuntimeProtocol.version
    var sessionID: String
    var requestID: String
    var kind: SanaaRuntimeCommandKind
    var hostExecutablePath: String?
    var conversationID: String?
    var text: String?

    init(sessionID: String,
         requestID: String = UUID().uuidString,
         kind: SanaaRuntimeCommandKind,
         hostExecutablePath: String? = nil,
         conversationID: String? = nil,
         text: String? = nil) {
        self.sessionID = sessionID
        self.requestID = requestID
        self.kind = kind
        self.hostExecutablePath = hostExecutablePath
        self.conversationID = conversationID
        self.text = text
    }
}

/// Tool events stay provider-neutral: the EXP UI never parses host-specific
/// Codex item JSON, and approval requests remain a refused boundary.
enum SanaaRuntimeEventKind: String, Codable, Sendable {
    case ready
    case hostReady
    case accountStatus
    case conversationStarted
    case conversationResumed
    case userMessage
    case assistantDelta
    case toolRequest
    case toolResult
    case approvalRequired
    case interrupted
    case completed
    case conversationDeleted
    case failed
}

enum SanaaRuntimeErrorCode: String, Codable, Sendable {
    case invalidProtocol
    case unauthenticated
    case invalidRequest
    case helperUnavailable
    case hostMissing
    case hostLaunchFailed
    case signedOut
    case unsupportedHostProtocol
    case noConversation
    case noActiveTurn
    case unexpectedHostRequest
    case hostDisconnected
    case timedOut
    case internalFailure
}

struct SanaaRuntimeFailure: Codable, Equatable, Sendable {
    var code: SanaaRuntimeErrorCode
    var message: String
    var recoverable: Bool
}

struct SanaaRuntimeEvent: Codable, Equatable, Sendable {
    var protocolVersion = SanaaRuntimeProtocol.version
    var sessionID: String
    var requestID: String?
    var kind: SanaaRuntimeEventKind
    var host: String?
    var hostVersion: String?
    var conversationID: String?
    var turnID: String?
    var text: String?
    var status: String?
    var accountAvailable: Bool?
    var account: SanaaRuntimeAccount?
    var rateLimits: [SanaaRuntimeRateLimit]?
    var usageSummary: SanaaRuntimeUsageSummary?
    var failure: SanaaRuntimeFailure?

    init(sessionID: String,
         requestID: String? = nil,
         kind: SanaaRuntimeEventKind,
         host: String? = nil,
         hostVersion: String? = nil,
         conversationID: String? = nil,
         turnID: String? = nil,
         text: String? = nil,
         status: String? = nil,
         accountAvailable: Bool? = nil,
         account: SanaaRuntimeAccount? = nil,
         rateLimits: [SanaaRuntimeRateLimit]? = nil,
         usageSummary: SanaaRuntimeUsageSummary? = nil,
         failure: SanaaRuntimeFailure? = nil) {
        self.sessionID = sessionID
        self.requestID = requestID
        self.kind = kind
        self.host = host
        self.hostVersion = hostVersion
        self.conversationID = conversationID
        self.turnID = turnID
        self.text = text
        self.status = status
        self.accountAvailable = accountAvailable
        self.account = account
        self.rateLimits = rateLimits
        self.usageSummary = usageSummary
        self.failure = failure
    }
}

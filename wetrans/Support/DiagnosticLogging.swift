import Foundation
import OSLog

public enum DiagnosticLogEvent: String, Equatable, Sendable {
    case localRefreshFailed
    case remoteRefreshFailed
    case transferTasksEnqueued
    case transferCompletionObserved
}

public struct DiagnosticLogEntry: Equatable, Sendable {
    public let event: DiagnosticLogEvent
    public let message: String
    public let metadata: [String: String]

    public init(event: DiagnosticLogEvent, message: String, metadata: [String: String]) {
        self.event = event
        self.message = message
        self.metadata = metadata
    }
}

public protocol DiagnosticLogging: Sendable {
    func log(_ event: DiagnosticLogEvent, message: String, metadata: [String: String])
}

public struct OSLogDiagnosticLogger: DiagnosticLogging {
    private let logger: Logger

    public init(
        subsystem: String = "wetrans",
        category: String = "diagnostics"
    ) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func log(_ event: DiagnosticLogEvent, message: String, metadata: [String: String] = [:]) {
        let entry = DiagnosticLogEntry.redacted(event: event, message: message, metadata: metadata)
        let metadataText = entry.metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        logger.info("\(entry.event.rawValue, privacy: .public) \(entry.message, privacy: .public) \(metadataText, privacy: .public)")
    }
}

public final class RecordingDiagnosticLogger: DiagnosticLogging, @unchecked Sendable {
    public private(set) var entries: [DiagnosticLogEntry] = []

    public init() {}

    public func log(_ event: DiagnosticLogEvent, message: String, metadata: [String: String] = [:]) {
        entries.append(.redacted(event: event, message: message, metadata: metadata))
    }
}

private extension DiagnosticLogEntry {
    static func redacted(
        event: DiagnosticLogEvent,
        message: String,
        metadata: [String: String]
    ) -> DiagnosticLogEntry {
        DiagnosticLogEntry(
            event: event,
            message: DiagnosticDetail.redact(message),
            metadata: metadata.mapValues(DiagnosticDetail.redact)
        )
    }
}

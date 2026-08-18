// AdventurersCore - Event Journal
// Append-only JSONL event store for agent behavior analysis

import Foundation

/// Every phase transition, gate check, and model turn is logged.
public actor EventJournal {
    private var events: [JournalEvent] = []
    private var sequenceNumber: Int = 0

    public struct JournalEvent: Sendable, Codable {
        public let sequence: Int
        public let timestamp: Date
        public let type: EventType
        public let payload: [String: String]

        public enum EventType: String, Sendable, Codable {
            case roundStart
            case toolExecution
            case gateCheck
            case gateFailed
            case gatePassed
            case taskCompleted
            case taskFailed
            case phaseTransition
            case mitigation
        }
    }

    public init() {}

    public func append(_ type: JournalEvent.EventType, payload: [String: String] = [:]) {
        sequenceNumber += 1
        let event = JournalEvent(sequence: sequenceNumber, timestamp: Date(), type: type, payload: payload)
        events.append(event)
    }

    public func allEvents() -> [JournalEvent] { events }

    public func events(ofType type: JournalEvent.EventType) -> [JournalEvent] {
        events.filter { $0.type == type }
    }

    public func phaseTrace() -> [(from: String, to: String)] {
        events.compactMap { event in
            guard event.type == .phaseTransition,
                  let from = event.payload["from"],
                  let to = event.payload["to"] else { return nil }
            return (from, to)
        }
    }

    public func exportJSONL() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return events.compactMap { try? encoder.encode($0) }
            .map { String(data: $0, encoding: .utf8)! }
            .joined(separator: "\n")
    }
}

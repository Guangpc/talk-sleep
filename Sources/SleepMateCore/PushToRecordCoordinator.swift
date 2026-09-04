public enum PushToRecordState: Equatable, Sendable {
    case idle
    case recording
}

public enum PushToRecordAction: Equatable, Sendable {
    case startRecording
    case stopRecording
}

/// Keeps the record button transition deterministic while AVFoundation stays at the App edge.
public struct PushToRecordCoordinator: Sendable {
    public private(set) var state: PushToRecordState = .idle

    public init() {}

    @discardableResult
    public mutating func press() -> PushToRecordAction {
        switch state {
        case .idle:
            state = .recording
            return .startRecording
        case .recording:
            state = .idle
            return .stopRecording
        }
    }

    public mutating func reset() {
        state = .idle
    }
}

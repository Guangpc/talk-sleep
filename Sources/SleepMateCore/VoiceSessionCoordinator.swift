import Foundation

public enum VoiceSessionEvent: Equatable, Sendable {
    case start
    case userSpeechStarted
    case responseReady(String)
    case playbackFinished
    case pause
    case resume
    case end
}

public enum VoiceSessionState: Equatable, Sendable {
    case idle
    case listening
    case speaking
    case paused
    case ended
}

public enum VoiceSessionEffect: Equatable, Sendable {
    case listeningStarted
    case startPlayback(String)
    case stopPlayback
    case listeningResumed
    case listeningPaused
    case sessionEnded
}

/// Pure coordinator for voice-session intent; iOS adapters perform actual audio I/O.
public struct VoiceSessionCoordinator {
    public private(set) var state: VoiceSessionState = .idle

    public init() {}

    @discardableResult
    public mutating func handle(_ event: VoiceSessionEvent) -> [VoiceSessionEffect] {
        switch event {
        case .start:
            guard state == .idle else { return [] }
            state = .listening
            return [.listeningStarted]
        case .userSpeechStarted:
            guard state == .speaking else { return [] }
            state = .listening
            return [.stopPlayback, .listeningResumed]
        case let .responseReady(text):
            guard state == .listening else { return [] }
            state = .speaking
            return [.startPlayback(text)]
        case .playbackFinished:
            guard state == .speaking else { return [] }
            state = .listening
            return [.listeningResumed]
        case .pause:
            guard state == .listening || state == .speaking else { return [] }
            let wasSpeaking = state == .speaking
            state = .paused
            return wasSpeaking ? [.stopPlayback, .listeningPaused] : [.listeningPaused]
        case .resume:
            guard state == .paused else { return [] }
            state = .listening
            return [.listeningResumed]
        case .end:
            guard state != .idle, state != .ended else { return [] }
            let wasSpeaking = state == .speaking
            state = .ended
            return wasSpeaking ? [.stopPlayback, .sessionEnded] : [.sessionEnded]
        }
    }
}

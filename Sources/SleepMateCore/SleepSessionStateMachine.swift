import Foundation

public enum SleepSessionEvent: Equatable, Sendable {
    case tick
    case userSpeech
    case pauseListening
    case resumeListening
    case endChat
    case appOpened
    case confirmWake(source: WakeSource)
    case editWake(at: Date, source: WakeSource)
}

public enum SleepSessionState: Equatable, Sendable {
    case chatting(lastUserSpeechAt: Date)
    case checkingIn(promptedAt: Date, lastUserSpeechAt: Date)
    case awaitingWakeConfirmation(SleepRecord)
    case completed(record: SleepRecord)
    case paused
    case ended
}

public enum SleepSessionEffect: Equatable, Sendable {
    case askIfAwake
    case enteredPossiblyAsleep(at: Date)
    case wakeConfirmationRequired
    case listeningPaused
    case listeningResumed
    case chatEnded
    case wakeConfirmed(record: SleepRecord)
    case wakeRecordUpdated(record: SleepRecord)
}

/// Pure session policy driven by an injected clock; audio and UI remain outside this type.
public struct SleepSessionStateMachine {
    public private(set) var state: SleepSessionState
    public let durations: SleepMateDurations

    private let clock: any SleepMateClock
    private var stateBeforePause: SleepSessionState?

    public init(
        startedAt: Date,
        clock: any SleepMateClock,
        durations: SleepMateDurations = .default
    ) {
        self.state = .chatting(lastUserSpeechAt: startedAt)
        self.durations = durations
        self.clock = clock
        self.stateBeforePause = nil
    }

    @discardableResult
    public mutating func handle(_ event: SleepSessionEvent) -> [SleepSessionEffect] {
        switch event {
        case .tick:
            return handleTick()
        case .userSpeech:
            switch state {
            case .chatting, .checkingIn:
                state = .chatting(lastUserSpeechAt: clock.now)
            case .awaitingWakeConfirmation, .completed, .paused, .ended:
                break
            }
            return []
        case .pauseListening:
            guard state != .paused, state != .ended else { return [] }
            stateBeforePause = state
            state = .paused
            return [.listeningPaused]
        case .resumeListening:
            guard state == .paused, let stateBeforePause else { return [] }
            state = stateBeforePause
            self.stateBeforePause = nil
            return [.listeningResumed]
        case .endChat:
            guard state != .ended else { return [] }
            state = .ended
            stateBeforePause = nil
            return [.chatEnded]
        case .appOpened:
            guard case .awaitingWakeConfirmation = state else { return [] }
            // Opening the app never silently becomes a wake time, especially after ten hours.
            return [.wakeConfirmationRequired]
        case let .confirmWake(source):
            guard case let .awaitingWakeConfirmation(record) = state else { return [] }
            var completed = record
            completed.wakeAt = clock.now
            completed.wakeSource = source
            state = .completed(record: completed)
            return [.wakeConfirmed(record: completed)]
        case let .editWake(at, source):
            guard case let .completed(record) = state else { return [] }
            var updated = record
            updated.wakeAt = at
            updated.wakeSource = source
            state = .completed(record: updated)
            return [.wakeRecordUpdated(record: updated)]
        }
    }

    private mutating func handleTick() -> [SleepSessionEffect] {
        let now = clock.now
        switch state {
        case let .chatting(lastUserSpeechAt):
            guard now.timeIntervalSince(lastUserSpeechAt) >= durations.idleBeforePrompt else { return [] }
            state = .checkingIn(promptedAt: now, lastUserSpeechAt: lastUserSpeechAt)
            return [.askIfAwake]
        case let .checkingIn(promptedAt, _):
            guard now.timeIntervalSince(promptedAt) >= durations.promptGrace else { return [] }
            let record = SleepRecord(possibleSleepAt: now)
            state = .awaitingWakeConfirmation(record)
            return [.enteredPossiblyAsleep(at: now)]
        case .awaitingWakeConfirmation, .completed, .paused, .ended:
            return []
        }
    }
}

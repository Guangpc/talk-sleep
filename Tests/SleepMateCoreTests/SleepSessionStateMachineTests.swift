import Foundation
import XCTest
@testable import SleepMateCore

final class SleepSessionStateMachineTests: XCTestCase {
    private final class TestClock: SleepMateClock {
        var now: Date

        init(_ now: Date) {
            self.now = now
        }
    }

    func testSilencePromptsAtNineMinutesThirtyAndInfersSleepAfterThirtyMoreSeconds() {
        let start = Date(timeIntervalSince1970: 0)
        let clock = TestClock(start)
        var machine = SleepSessionStateMachine(startedAt: start, clock: clock)

        clock.now = Date(timeIntervalSince1970: 570)
        let promptEffects = machine.handle(.tick)
        XCTAssertEqual(promptEffects, [.askIfAwake])
        guard case let .checkingIn(promptedAt, _) = machine.state else {
            return XCTFail("Expected checking-in state")
        }
        XCTAssertEqual(promptedAt.timeIntervalSince1970, 570)

        clock.now = Date(timeIntervalSince1970: 600)
        let sleepEffects = machine.handle(.tick)
        XCTAssertEqual(sleepEffects, [.enteredPossiblyAsleep(at: clock.now)])
        guard case let .awaitingWakeConfirmation(record) = machine.state else {
            return XCTFail("Expected awaiting-wake-confirmation state")
        }
        XCTAssertEqual(record.possibleSleepAt, clock.now)
    }

    func testUserSpeechAfterPromptReturnsToChattingAndResetsSilenceTimer() {
        let start = Date(timeIntervalSince1970: 0)
        let clock = TestClock(start)
        var machine = SleepSessionStateMachine(startedAt: start, clock: clock)

        clock.now = Date(timeIntervalSince1970: 570)
        _ = machine.handle(.tick)
        clock.now = Date(timeIntervalSince1970: 580)
        XCTAssertEqual(machine.handle(.userSpeech), [])
        guard case let .chatting(lastUserSpeechAt) = machine.state else {
            return XCTFail("Expected chatting state")
        }
        XCTAssertEqual(lastUserSpeechAt, clock.now)

        clock.now = Date(timeIntervalSince1970: 580 + 569)
        XCTAssertEqual(machine.handle(.tick), [])
    }

    func testPauseStopsTimerUntilResumedAndEndIsTerminal() {
        let start = Date(timeIntervalSince1970: 0)
        let clock = TestClock(start)
        var machine = SleepSessionStateMachine(startedAt: start, clock: clock)

        XCTAssertEqual(machine.handle(.pauseListening), [.listeningPaused])
        clock.now = Date(timeIntervalSince1970: 3_600)
        XCTAssertEqual(machine.handle(.tick), [])
        XCTAssertEqual(machine.state, .paused)
        XCTAssertEqual(machine.handle(.resumeListening), [.listeningResumed])

        XCTAssertEqual(machine.handle(.endChat), [.chatEnded])
        XCTAssertEqual(machine.state, .ended)
        XCTAssertEqual(machine.handle(.userSpeech), [])
    }

    func testMoreThanTenHoursDoesNotAutoFillWakeTimeButExplicitConfirmationWorks() {
        let start = Date(timeIntervalSince1970: 0)
        let clock = TestClock(start)
        var machine = SleepSessionStateMachine(startedAt: start, clock: clock)
        clock.now = Date(timeIntervalSince1970: 570)
        _ = machine.handle(.tick)
        clock.now = Date(timeIntervalSince1970: 600)
        _ = machine.handle(.tick)

        clock.now = Date(timeIntervalSince1970: 10 * 60 * 60 + 601)
        XCTAssertEqual(machine.handle(.appOpened), [.wakeConfirmationRequired])
        guard case .awaitingWakeConfirmation = machine.state else {
            return XCTFail("Opening after ten hours must not auto-complete wake")
        }

        let wake = Date(timeIntervalSince1970: 10 * 60 * 60 + 700)
        clock.now = wake
        let effects = machine.handle(.confirmWake(source: .manualEntry))
        XCTAssertEqual(effects.count, 1)
        guard case let .wakeConfirmed(record) = effects[0] else {
            return XCTFail("Expected explicit wake confirmation")
        }
        XCTAssertEqual(record.wakeAt, wake)
        XCTAssertEqual(record.wakeSource, .manualEntry)
        XCTAssertEqual(machine.state, .completed(record: record))
    }
}

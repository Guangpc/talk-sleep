import XCTest
@testable import SleepMateCore

final class VoiceSessionCoordinatorTests: XCTestCase {
    func testStartingSessionEntersListening() {
        var coordinator = VoiceSessionCoordinator()

        XCTAssertEqual(coordinator.handle(.start), [.listeningStarted])
        XCTAssertEqual(coordinator.state, .listening)
    }

    func testUserSpeechImmediatelyStopsTTSAndKeepsNewSpeechPriority() {
        var coordinator = VoiceSessionCoordinator()
        _ = coordinator.handle(.start)
        XCTAssertEqual(
            coordinator.handle(.responseReady("晚安，慢慢休息")),
            [.startPlayback("晚安，慢慢休息")]
        )

        XCTAssertEqual(coordinator.state, .speaking)
        XCTAssertEqual(
            coordinator.handle(.userSpeechStarted),
            [.stopPlayback, .listeningResumed]
        )
        XCTAssertEqual(coordinator.state, .listening)

        var finishedCoordinator = VoiceSessionCoordinator()
        _ = finishedCoordinator.handle(.start)
        _ = finishedCoordinator.handle(.responseReady("播放完回到监听"))
        XCTAssertEqual(finishedCoordinator.handle(.playbackFinished), [.listeningResumed])
        XCTAssertEqual(finishedCoordinator.state, .listening)
    }

    func testPauseResumeAndEndExposeControllableSessionStates() {
        var coordinator = VoiceSessionCoordinator()
        _ = coordinator.handle(.start)

        XCTAssertEqual(coordinator.handle(.pause), [.listeningPaused])
        XCTAssertEqual(coordinator.state, .paused)
        XCTAssertEqual(coordinator.handle(.resume), [.listeningResumed])
        XCTAssertEqual(coordinator.state, .listening)
        XCTAssertEqual(coordinator.handle(.end), [.sessionEnded])
        XCTAssertEqual(coordinator.state, .ended)
        XCTAssertEqual(coordinator.handle(.resume), [])

        var speakingCoordinator = VoiceSessionCoordinator()
        _ = speakingCoordinator.handle(.start)
        _ = speakingCoordinator.handle(.responseReady("晚安"))
        XCTAssertEqual(speakingCoordinator.handle(.end), [.stopPlayback, .sessionEnded])

        var pausingSpeakingCoordinator = VoiceSessionCoordinator()
        _ = pausingSpeakingCoordinator.handle(.start)
        _ = pausingSpeakingCoordinator.handle(.responseReady("请先休息一下"))
        XCTAssertEqual(
            pausingSpeakingCoordinator.handle(.pause),
            [.stopPlayback, .listeningPaused]
        )
    }
}

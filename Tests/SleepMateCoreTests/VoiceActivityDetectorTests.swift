import XCTest
@testable import SleepMateCore

final class VoiceActivityDetectorTests: XCTestCase {
    func testNormalConversationLevelTriggersAfterQuietRoomCalibration() {
        var detector = VoiceActivityDetector()

        for level in [Float(0.0008), 0.0010, 0.0009, 0.0011, 0.0009, 0.0010, 0.0008, 0.0011] {
            XCTAssertFalse(detector.observe(rmsLevel: level))
        }

        XCTAssertFalse(detector.observe(rmsLevel: 0.0042))
        XCTAssertTrue(detector.observe(rmsLevel: 0.0048))
    }

    func testGateDiscardsSilenceAndClosesAfterTrailingSilence() {
        var detector = VoiceActivityDetector(
            configuration: .init(trailingSilenceFrames: 2)
        )

        for level in [Float(0.0010), 0.0009, 0.0011, 0.0010, 0.0008, 0.0010, 0.0009, 0.0011] {
            XCTAssertEqual(detector.observeActivity(rmsLevel: level), .calibrating)
        }
        XCTAssertEqual(detector.observeActivity(rmsLevel: 0.0011), .silence)
        XCTAssertEqual(detector.observeActivity(rmsLevel: 0.0048), .silence)
        XCTAssertEqual(detector.observeActivity(rmsLevel: 0.0050), .speechStarted)
        XCTAssertEqual(detector.observeActivity(rmsLevel: 0.0049), .speechContinues)
        XCTAssertEqual(detector.observeActivity(rmsLevel: 0.0011), .speechSilence)
        XCTAssertEqual(detector.observeActivity(rmsLevel: 0.0011), .speechEnded)
        XCTAssertEqual(detector.observeActivity(rmsLevel: 0.0011), .silence)
    }

    func testSingleNoiseSpikeDoesNotStartSpeech() {
        var detector = VoiceActivityDetector()

        for level in [Float(0.0010), 0.0009, 0.0011, 0.0010, 0.0008, 0.0010, 0.0009, 0.0011] {
            XCTAssertFalse(detector.observe(rmsLevel: level))
        }

        XCTAssertFalse(detector.observe(rmsLevel: 0.0048))
        XCTAssertFalse(detector.observe(rmsLevel: 0.0012))
    }
}

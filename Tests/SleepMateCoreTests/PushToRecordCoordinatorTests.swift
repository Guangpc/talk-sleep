import XCTest
@testable import SleepMateCore

final class PushToRecordCoordinatorTests: XCTestCase {
    func testFirstPressStartsRecordingAndSecondPressStopsIt() {
        var coordinator = PushToRecordCoordinator()

        XCTAssertEqual(coordinator.press(), .startRecording)
        XCTAssertEqual(coordinator.state, .recording)
        XCTAssertEqual(coordinator.press(), .stopRecording)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testDefaultStockVoiceCanBeUsedWithoutCloneUpload() {
        XCTAssertEqual(VoiceConfiguration.defaultStock.reference, "Chinese (Mandarin)_Soft_Girl")
    }
}

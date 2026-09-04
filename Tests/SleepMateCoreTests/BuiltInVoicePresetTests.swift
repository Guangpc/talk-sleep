import XCTest
@testable import SleepMateCore

final class BuiltInVoicePresetTests: XCTestCase {
    func testCatalogOffersDistinctChineseFemaleVoicesWithTTSSettings() {
        let presets = BuiltInVoicePreset.chineseFemaleChoices

        XCTAssertEqual(presets.map(\.kind), [.gentleWoman, .matureWoman, .warmBestie, .wiseWoman, .sweetLady])
        XCTAssertEqual(Set(presets.map(\.voiceID)).count, presets.count)
        XCTAssertEqual(presets.first?.voiceID, "Chinese (Mandarin)_Soft_Girl")
        XCTAssertEqual(presets.first?.configuration.pitch, 1)
        XCTAssertEqual(presets[1].configuration.pitch, -2)
    }

    func testConfigurationRestoresPresetToneFromPersistedVoiceID() {
        let configuration = BuiltInVoicePreset.configuration(for: "Chinese (Mandarin)_Mature_Woman")

        XCTAssertEqual(configuration.reference, "Chinese (Mandarin)_Mature_Woman")
        XCTAssertEqual(configuration.speed, 0.90)
        XCTAssertEqual(configuration.pitch, -2)
    }

    func testUnknownClonedVoiceUsesNeutralTTSSettings() {
        let configuration = BuiltInVoicePreset.configuration(for: "cloned-friend-voice")

        XCTAssertEqual(configuration.reference, "cloned-friend-voice")
        XCTAssertEqual(configuration.speed, 1.0)
        XCTAssertEqual(configuration.pitch, 0)
    }
}

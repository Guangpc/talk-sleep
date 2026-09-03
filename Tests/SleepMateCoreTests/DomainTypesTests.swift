import Foundation
import XCTest
@testable import SleepMateCore

final class DomainTypesTests: XCTestCase {
    func testDefaultDurationsMatchProductDecisions() {
        let durations = SleepMateDurations.default
        XCTAssertEqual(durations.idleBeforePrompt, 9 * 60 + 30)
        XCTAssertEqual(durations.promptGrace, 30)
        XCTAssertEqual(durations.wakeConfirmationWindow, 10 * 60 * 60)
        XCTAssertEqual(durations.defaultRetention, 30 * 24 * 60 * 60)
        XCTAssertEqual(durations.singleUtteranceLimit, 3 * 60)
    }

    func testFriendProfileHoldsEditableVoiceStyleAndMemoryConfiguration() {
        let friend = AIFriendProfile(
            id: UUID(),
            name: "小林",
            avatarReference: "avatar://xiaolin",
            voiceConfiguration: VoiceConfiguration(reference: "voice://xiaolin"),
            styleSummary: StyleSummary(traits: ["温和", "爱开玩笑"], catchphrases: ["你慢慢说"]),
            memories: [Memory(id: UUID(), text: "一起去过海边")],
            topicPreferences: ["旅行"],
            doNotMentionTopics: ["未确认的隐私"]
        )

        XCTAssertEqual(friend.name, "小林")
        XCTAssertEqual(friend.voiceConfiguration.reference, "voice://xiaolin")
        XCTAssertEqual(friend.styleSummary.catchphrases, ["你慢慢说"])
        XCTAssertEqual(friend.memories.count, 1)
    }

    func testSourceMaterialAndTranscriptRepresentSpeakerConfidence() {
        let material = SourceMaterial(id: UUID(), kind: .audio, fileReference: "file://sample", importedAt: Date(timeIntervalSince1970: 100))
        let transcript = TranscriptSegment(
            id: UUID(),
            sourceMaterialID: material.id,
            text: "晚安",
            speaker: .friend,
            confidence: 0.92
        )

        XCTAssertEqual(material.kind, .audio)
        XCTAssertEqual(transcript.speaker, .friend)
        XCTAssertEqual(transcript.confidence, 0.92, accuracy: 0.001)
    }

    func testSleepRecordUsesExplicitWakeSourceAndComputesDuration() {
        let record = SleepRecord(
            possibleSleepAt: Date(timeIntervalSince1970: 100),
            wakeAt: Date(timeIntervalSince1970: 400),
            wakeSource: .lockScreenAction
        )

        XCTAssertEqual(record.duration, 300)
        XCTAssertEqual(record.wakeSource, .lockScreenAction)
    }
}

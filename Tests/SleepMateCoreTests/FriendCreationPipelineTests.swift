import Foundation
import XCTest
@testable import SleepMateCore

final class FriendCreationPipelineTests: XCTestCase {
    private final class FakeAnalyzer: FriendMaterialAnalyzer {
        let result: FriendAnalysis
        var receivedMaterials: [SourceMaterial] = []

        init(result: FriendAnalysis) {
            self.result = result
        }

        func analyze(materials: [SourceMaterial]) -> FriendAnalysis {
            receivedMaterials = materials
            return result
        }
    }

    private final class FakeBuilder: AIFriendProfileBuilder {
        var receivedAnalysis: FriendAnalysis?

        func buildProfile(name: String, avatarReference: String, analysis: FriendAnalysis, confirmedMemories: [Memory]) -> AIFriendProfile {
            receivedAnalysis = analysis
            return AIFriendProfile(
                id: UUID(),
                name: name,
                avatarReference: avatarReference,
                voiceConfiguration: analysis.voiceConfiguration,
                styleSummary: analysis.styleSummary,
                memories: confirmedMemories
            )
        }
    }

    private func analysis(confidence: Double, hasConflict: Bool = false) -> FriendAnalysis {
        FriendAnalysis(
            transcriptSegments: [],
            voiceConfiguration: VoiceConfiguration(reference: "voice://fake"),
            styleSummary: StyleSummary(traits: ["温和"], catchphrases: ["慢慢说"]),
            candidateMemories: [Memory(id: UUID(), text: "一起看过海")],
            confidence: confidence,
            hasConflict: hasConflict
        )
    }

    func testHighConfidenceMaterialAnalysisCreatesReadyFriend() {
        let result = analysis(confidence: 0.95)
        let analyzer = FakeAnalyzer(result: result)
        let builder = FakeBuilder()
        var pipeline = FriendCreationPipeline(
            name: "小林",
            avatarReference: "avatar://xiaolin",
            analyzer: analyzer,
            builder: builder
        )
        let material = SourceMaterial(id: UUID(), kind: .text, fileReference: "text://chat", importedAt: Date())

        let effects = pipeline.handle(.begin(materials: [material]))

        XCTAssertEqual(analyzer.receivedMaterials, [material])
        XCTAssertEqual(builder.receivedAnalysis, result)
        guard case let .ready(profile) = pipeline.state else {
            return XCTFail("Expected a ready AI friend")
        }
        XCTAssertEqual(profile.name, "小林")
        XCTAssertEqual(profile.styleSummary.catchphrases, ["慢慢说"])
        XCTAssertTrue(effects.contains(.friendReady(profile)))
    }

    func testLowConfidenceAnalysisWaitsForConfirmationBeforeBuildingFriend() {
        let result = analysis(confidence: 0.4)
        let analyzer = FakeAnalyzer(result: result)
        let builder = FakeBuilder()
        var pipeline = FriendCreationPipeline(
            name: "小林",
            avatarReference: "avatar://xiaolin",
            analyzer: analyzer,
            builder: builder
        )

        let effects = pipeline.handle(.begin(materials: []))

        guard case let .awaitingConfirmation(pending) = pipeline.state else {
            return XCTFail("Expected confirmation state")
        }
        XCTAssertEqual(pending, result)
        XCTAssertTrue(effects.contains(.confirmationRequired(result)))
        XCTAssertNil(builder.receivedAnalysis)

        let confirmationEffects = pipeline.handle(.confirmAnalysis(confirmedMemoryIDs: Set(result.candidateMemories.map(\.id))))
        guard case let .ready(profile) = pipeline.state else {
            return XCTFail("Expected ready state after confirmation")
        }
        XCTAssertEqual(builder.receivedAnalysis, result)
        XCTAssertTrue(confirmationEffects.contains(.friendReady(profile)))
    }

    func testConflictingAnalysisCanBeRejectedWithoutCreatingFriend() {
        let analyzer = FakeAnalyzer(result: analysis(confidence: 0.95, hasConflict: true))
        let builder = FakeBuilder()
        var pipeline = FriendCreationPipeline(
            name: "小林",
            avatarReference: "avatar://xiaolin",
            analyzer: analyzer,
            builder: builder
        )

        _ = pipeline.handle(.begin(materials: []))
        XCTAssertEqual(pipeline.handle(.rejectAnalysis), [.creationRejected])
        XCTAssertEqual(pipeline.state, .rejected)
        XCTAssertNil(builder.receivedAnalysis)
    }
}


extension FriendCreationPipelineTests {
    func testCandidateMemoriesStayUnconfirmedUntilExplicitlySelected() {
        let result = analysis(confidence: 0.4)
        let builder = FakeBuilder()
        var pipeline = FriendCreationPipeline(
            name: "小林",
            avatarReference: "avatar://xiaolin",
            analyzer: FakeAnalyzer(result: result),
            builder: builder
        )

        _ = pipeline.handle(.begin(materials: []))
        let effects = pipeline.handle(.confirmAnalysis(confirmedMemoryIDs: []))

        guard case let .ready(profile) = pipeline.state else {
            return XCTFail("Expected ready state after analysis confirmation")
        }
        XCTAssertTrue(profile.memories.isEmpty)
        XCTAssertTrue(effects.contains(.friendReady(profile)))
    }
}

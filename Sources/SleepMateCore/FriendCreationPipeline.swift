import Foundation

public struct FriendAnalysis: Equatable, Sendable {
    public let transcriptSegments: [TranscriptSegment]
    public let voiceConfiguration: VoiceConfiguration
    public let styleSummary: StyleSummary
    public let candidateMemories: [Memory]
    public let confidence: Double
    public let hasConflict: Bool

    public init(
        transcriptSegments: [TranscriptSegment],
        voiceConfiguration: VoiceConfiguration,
        styleSummary: StyleSummary,
        candidateMemories: [Memory],
        confidence: Double,
        hasConflict: Bool = false
    ) {
        self.transcriptSegments = transcriptSegments
        self.voiceConfiguration = voiceConfiguration
        self.styleSummary = styleSummary
        self.candidateMemories = candidateMemories
        self.confidence = confidence
        self.hasConflict = hasConflict
    }
}

public typealias FriendMaterialAnalyzer = MaterialAnalysisService

public protocol AIFriendProfileBuilder {
    func buildProfile(
        name: String,
        avatarReference: String,
        analysis: FriendAnalysis,
        confirmedMemories: [Memory]
    ) -> AIFriendProfile
}

public enum FriendCreationStage: String, Equatable, Sendable {
    case importing
    case ocrAndTranscription
    case speakerSeparation
    case analysis
    case awaitingConfirmation
    case buildingProfile
    case ready
}

public enum FriendCreationEvent: Equatable, Sendable {
    case begin(materials: [SourceMaterial])
    case confirmAnalysis(confirmedMemoryIDs: Set<UUID>)
    case rejectAnalysis
}

public enum FriendCreationState: Equatable, Sendable {
    case idle
    case analyzing
    case awaitingConfirmation(FriendAnalysis)
    case ready(AIFriendProfile)
    case rejected
}

public enum FriendCreationEffect: Equatable, Sendable {
    case stageChanged(FriendCreationStage)
    case analysisCompleted(FriendAnalysis)
    case confirmationRequired(FriendAnalysis)
    case friendReady(AIFriendProfile)
    case creationRejected
}

/// Coordinates material analysis without owning OCR, ASR, storage, or network code.
public struct FriendCreationPipeline {
    public private(set) var state: FriendCreationState = .idle
    public private(set) var stage: FriendCreationStage = .importing
    public let minimumConfidence: Double

    private let name: String
    private let avatarReference: String
    private let analyzer: any FriendMaterialAnalyzer
    private let builder: any AIFriendProfileBuilder

    public init(
        name: String,
        avatarReference: String,
        analyzer: any FriendMaterialAnalyzer,
        builder: any AIFriendProfileBuilder,
        minimumConfidence: Double = 0.8
    ) {
        self.name = name
        self.avatarReference = avatarReference
        self.analyzer = analyzer
        self.builder = builder
        self.minimumConfidence = minimumConfidence
    }

    @discardableResult
    public mutating func handle(_ event: FriendCreationEvent) -> [FriendCreationEffect] {
        switch event {
        case let .begin(materials):
            guard state == .idle || state == .rejected else { return [] }
            state = .analyzing
            stage = .importing
            var effects: [FriendCreationEffect] = [.stageChanged(.importing)]
            stage = .ocrAndTranscription
            effects.append(.stageChanged(.ocrAndTranscription))
            stage = .speakerSeparation
            effects.append(.stageChanged(.speakerSeparation))
            stage = .analysis
            let result = analyzer.analyze(materials: materials)
            effects.append(.stageChanged(.analysis))
            effects.append(.analysisCompleted(result))
            if result.confidence < minimumConfidence || result.hasConflict {
                state = .awaitingConfirmation(result)
                stage = .awaitingConfirmation
                effects.append(.stageChanged(.awaitingConfirmation))
                effects.append(.confirmationRequired(result))
                return effects
            }
            let profile = builder.buildProfile(
                name: name,
                avatarReference: avatarReference,
                analysis: result,
                confirmedMemories: []
            )
            stage = .buildingProfile
            state = .ready(profile)
            effects.append(.stageChanged(.buildingProfile))
            stage = .ready
            effects.append(.stageChanged(.ready))
            effects.append(.friendReady(profile))
            return effects
        case let .confirmAnalysis(confirmedMemoryIDs):
            guard case let .awaitingConfirmation(analysis) = state else { return [] }
            let confirmedMemories = analysis.candidateMemories.filter { confirmedMemoryIDs.contains($0.id) }
            let profile = builder.buildProfile(
                name: name,
                avatarReference: avatarReference,
                analysis: analysis,
                confirmedMemories: confirmedMemories
            )
            stage = .buildingProfile
            state = .ready(profile)
            stage = .ready
            return [.stageChanged(.buildingProfile), .stageChanged(.ready), .friendReady(profile)]
        case .rejectAnalysis:
            guard case .awaitingConfirmation = state else { return [] }
            state = .rejected
            return [.creationRejected]
        }
    }
}

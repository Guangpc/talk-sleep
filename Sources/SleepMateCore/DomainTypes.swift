import Foundation

public struct VoiceConfiguration: Equatable, Sendable {
    public let reference: String
    public let speed: Double
    public let pitch: Int

    public init(reference: String, speed: Double = 1.0, pitch: Int = 0) {
        self.reference = reference
        self.speed = min(max(speed, 0.5), 2.0)
        self.pitch = min(max(pitch, -12), 12)
    }

    /// A provider-supported gentle stock voice used until the user binds another preset or clone.
    public static let defaultStock = VoiceConfiguration(
        reference: "Chinese (Mandarin)_Soft_Girl",
        speed: 0.92,
        pitch: 1
    )
}

public struct StyleSummary: Equatable, Sendable {
    public var traits: [String]
    public var catchphrases: [String]

    public init(traits: [String] = [], catchphrases: [String] = []) {
        self.traits = traits
        self.catchphrases = catchphrases
    }
}

public struct Memory: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var text: String

    public init(id: UUID, text: String) {
        self.id = id
        self.text = text
    }
}

public struct AIFriendProfile: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var avatarReference: String
    public var voiceConfiguration: VoiceConfiguration
    public var styleSummary: StyleSummary
    public var memories: [Memory]
    public var topicPreferences: [String]
    public var doNotMentionTopics: [String]

    public init(
        id: UUID,
        name: String,
        avatarReference: String,
        voiceConfiguration: VoiceConfiguration,
        styleSummary: StyleSummary = StyleSummary(),
        memories: [Memory] = [],
        topicPreferences: [String] = [],
        doNotMentionTopics: [String] = []
    ) {
        self.id = id
        self.name = name
        self.avatarReference = avatarReference
        self.voiceConfiguration = voiceConfiguration
        self.styleSummary = styleSummary
        self.memories = memories
        self.topicPreferences = topicPreferences
        self.doNotMentionTopics = doNotMentionTopics
    }
}

public enum SourceMaterialKind: String, Equatable, Sendable {
    case screenshot
    case text
    case audio
}

public enum SpeakerAttribution: String, Equatable, Sendable {
    case user
    case friend
    case unknown
    case needsConfirmation
}

public struct SourceMaterial: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: SourceMaterialKind
    public let fileReference: String
    public let importedAt: Date
    public var speakerAttribution: SpeakerAttribution

    public init(
        id: UUID,
        kind: SourceMaterialKind,
        fileReference: String,
        importedAt: Date,
        speakerAttribution: SpeakerAttribution = .unknown
    ) {
        self.id = id
        self.kind = kind
        self.fileReference = fileReference
        self.importedAt = importedAt
        self.speakerAttribution = speakerAttribution
    }
}

public enum MaterialProcessingStage: String, Equatable, Sendable {
    case imported
    case ocrAndTranscription
    case speakerSeparation
    case analysis
    case awaitingConfirmation
    case ready
}

public struct SourceMaterialBatch: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var materials: [SourceMaterial]
    public var stage: MaterialProcessingStage
    public let importedAt: Date

    public init(
        id: UUID,
        materials: [SourceMaterial],
        stage: MaterialProcessingStage = .imported,
        importedAt: Date
    ) {
        self.id = id
        self.materials = materials
        self.stage = stage
        self.importedAt = importedAt
    }
}

public enum TranscriptSpeaker: String, Equatable, Sendable {
    case user
    case friend
    case unknown
}

public struct TranscriptSegment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceMaterialID: UUID
    public let text: String
    public let speaker: TranscriptSpeaker
    public let confidence: Double

    public init(id: UUID, sourceMaterialID: UUID, text: String, speaker: TranscriptSpeaker, confidence: Double) {
        self.id = id
        self.sourceMaterialID = sourceMaterialID
        self.text = text
        self.speaker = speaker
        self.confidence = confidence
    }
}

public enum TurnSpeaker: String, Equatable, Sendable {
    case user
    case assistant
}

public struct ConversationTurn: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let speaker: TurnSpeaker
    public let text: String
    public let createdAt: Date

    public init(id: UUID, speaker: TurnSpeaker, text: String, createdAt: Date) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.createdAt = createdAt
    }
}

public enum WakeSource: String, Equatable, Sendable {
    case lockScreenAction
    case appAction
    case manualEntry
}

public struct SleepRecord: Equatable, Sendable {
    public let possibleSleepAt: Date
    public var wakeAt: Date?
    public var wakeSource: WakeSource?
    public var summary: String?
    public var sleepAdvice: [String]
    public var recommendedTopics: [String]

    public init(
        possibleSleepAt: Date,
        wakeAt: Date? = nil,
        wakeSource: WakeSource? = nil,
        summary: String? = nil,
        sleepAdvice: [String] = [],
        recommendedTopics: [String] = []
    ) {
        self.possibleSleepAt = possibleSleepAt
        self.wakeAt = wakeAt
        self.wakeSource = wakeSource
        self.summary = summary
        self.sleepAdvice = sleepAdvice
        self.recommendedTopics = recommendedTopics
    }

    public var duration: TimeInterval? {
        guard let wakeAt else { return nil }
        return max(0, wakeAt.timeIntervalSince(possibleSleepAt))
    }
}

public struct SleepMateDurations: Equatable, Sendable {
    public var idleBeforePrompt: TimeInterval
    public var promptGrace: TimeInterval
    public var wakeConfirmationWindow: TimeInterval
    public var defaultRetention: TimeInterval
    public var singleUtteranceLimit: TimeInterval

    public init(
        idleBeforePrompt: TimeInterval = 9 * 60 + 30,
        promptGrace: TimeInterval = 30,
        wakeConfirmationWindow: TimeInterval = 10 * 60 * 60,
        defaultRetention: TimeInterval = 30 * 24 * 60 * 60,
        singleUtteranceLimit: TimeInterval = 3 * 60
    ) {
        self.idleBeforePrompt = idleBeforePrompt
        self.promptGrace = promptGrace
        self.wakeConfirmationWindow = wakeConfirmationWindow
        self.defaultRetention = defaultRetention
        self.singleUtteranceLimit = singleUtteranceLimit
    }

    public static let `default` = SleepMateDurations()
}

public protocol SleepMateClock {
    var now: Date { get }
}

public struct SystemSleepMateClock: SleepMateClock {
    public init() {}

    public var now: Date { Date() }
}

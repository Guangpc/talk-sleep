import Foundation

public struct VoiceConfiguration: Equatable, Sendable {
    public let reference: String

    public init(reference: String) {
        self.reference = reference
    }
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

public struct SourceMaterial: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: SourceMaterialKind
    public let fileReference: String
    public let importedAt: Date

    public init(id: UUID, kind: SourceMaterialKind, fileReference: String, importedAt: Date) {
        self.id = id
        self.kind = kind
        self.fileReference = fileReference
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

    public init(possibleSleepAt: Date, wakeAt: Date? = nil, wakeSource: WakeSource? = nil) {
        self.possibleSleepAt = possibleSleepAt
        self.wakeAt = wakeAt
        self.wakeSource = wakeSource
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

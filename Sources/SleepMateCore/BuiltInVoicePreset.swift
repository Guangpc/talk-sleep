import Foundation

/// A curated subset of provider-supported Mandarin voices suitable for bedtime conversation.
/// Voice IDs come from the MiniMax system voice catalog; only IDs and safe TTS controls cross the App seam.
public struct BuiltInVoicePreset: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case gentleWoman
        case matureWoman
        case warmBestie
        case wiseWoman
        case sweetLady
    }

    public let kind: Kind
    public let voiceID: String
    public let speed: Double
    public let pitch: Int

    public var id: String { voiceID }
    public var configuration: VoiceConfiguration {
        VoiceConfiguration(reference: voiceID, speed: speed, pitch: pitch)
    }

    public static let chineseFemaleChoices: [Self] = [
        Self(kind: .gentleWoman, voiceID: "Chinese (Mandarin)_Soft_Girl", speed: 0.92, pitch: 1),
        Self(kind: .matureWoman, voiceID: "Chinese (Mandarin)_Mature_Woman", speed: 0.90, pitch: -2),
        Self(kind: .warmBestie, voiceID: "Chinese (Mandarin)_Warm_Bestie", speed: 0.96, pitch: 0),
        Self(kind: .wiseWoman, voiceID: "Chinese (Mandarin)_Wise_Women", speed: 0.90, pitch: -1),
        Self(kind: .sweetLady, voiceID: "Chinese (Mandarin)_Sweet_Lady", speed: 1.00, pitch: 2),
    ]

    public static func configuration(for reference: String) -> VoiceConfiguration {
        if reference.hasPrefix("voice://stock") { return .defaultStock }
        return chineseFemaleChoices.first(where: { $0.voiceID == reference })?.configuration
            ?? VoiceConfiguration(reference: reference)
    }
}

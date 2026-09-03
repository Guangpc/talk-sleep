import Foundation

/// Device-facing audio control. The iOS shell supplies the AVAudioSession adapter.
public protocol AudioSession: AnyObject {
    func pauseListening()
    func resumeListening()
    func end()
}

/// Speech-to-text adapter. Implementations may use on-device or approved cloud processing.
public protocol ASRService {
    func transcribe(audio: Data) async throws -> String
}

/// Text-to-speech adapter for the selected AI friend's voice configuration.
public protocol TTSService {
    func synthesize(text: String, voice: VoiceConfiguration) async throws -> Data
}

/// Material analysis adapter. The Foundation implementation remains fake/injected.
public protocol MaterialAnalysisService {
    func analyze(materials: [SourceMaterial]) -> FriendAnalysis
}

/// Persistence boundary for profiles and sleep records; storage policy is implemented later.
public protocol SleepMateStore {
    func save(_ profile: AIFriendProfile) async throws
    func save(_ record: SleepRecord) async throws
    func deleteFriend(id: UUID) async throws
}

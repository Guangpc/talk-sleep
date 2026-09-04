import Foundation

/// The consent facts that must be acknowledged before an audio source can leave the device.
public struct VoiceCloneConsent: Equatable, Sendable {
    public let authorized: Bool
    public let intendedUseAcknowledged: Bool
    public let cloudProcessingAcknowledged: Bool
    public let retentionAndDeletionAcknowledged: Bool
    public let acceptedAt: Date

    public init(
        authorized: Bool,
        intendedUseAcknowledged: Bool,
        cloudProcessingAcknowledged: Bool,
        retentionAndDeletionAcknowledged: Bool,
        acceptedAt: Date
    ) {
        self.authorized = authorized
        self.intendedUseAcknowledged = intendedUseAcknowledged
        self.cloudProcessingAcknowledged = cloudProcessingAcknowledged
        self.retentionAndDeletionAcknowledged = retentionAndDeletionAcknowledged
        self.acceptedAt = acceptedAt
    }

    public var isComplete: Bool {
        authorized && intendedUseAcknowledged && cloudProcessingAcknowledged && retentionAndDeletionAcknowledged
    }
}

public struct AuthorizedVoiceSource: Equatable, Sendable {
    public let data: Data
    public let filename: String
    public let durationSeconds: TimeInterval
    public let consent: VoiceCloneConsent

    public init(data: Data, filename: String, durationSeconds: TimeInterval, consent: VoiceCloneConsent) {
        self.data = data
        self.filename = filename
        self.durationSeconds = durationSeconds
        self.consent = consent
    }
}

public struct ImportedFriendText: Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public enum AuthorizedVoiceSourceError: Error, Equatable, Sendable, LocalizedError {
    case consentRequired
    case unsupportedAudioFormat
    case emptyAudio
    case audioTooLarge
    case durationOutOfRange
    case invalidFilename

    public var errorDescription: String? {
        switch self {
        case .consentRequired: return "Voice authorization must be confirmed before upload."
        case .unsupportedAudioFormat: return "Choose an MP3, M4A, or WAV audio file."
        case .emptyAudio: return "The selected audio file is empty."
        case .audioTooLarge: return "The audio file must be 20 MB or smaller."
        case .durationOutOfRange: return "Clone audio must be between 10 seconds and 5 minutes."
        case .invalidFilename: return "The selected filename is invalid."
        }
    }
}

public enum AuthorizedSourceTextError: Error, Equatable, Sendable, LocalizedError {
    case empty
    case tooLong

    public var errorDescription: String? {
        switch self {
        case .empty: return "Enter friend context before importing it."
        case .tooLong: return "Friend context is too long."
        }
    }
}

/// Validates friend source material before the App creates an upload request.
public struct AuthorizedVoiceSourceValidator: Sendable {
    public static let minimumCloneDuration: TimeInterval = 10
    public static let maximumCloneDuration: TimeInterval = 5 * 60
    public static let maximumAudioBytes = 20 * 1024 * 1024
    public static let defaultMaximumTextCharacters = 20_000

    private let maxTextCharacters: Int

    public init(maxTextCharacters: Int = AuthorizedVoiceSourceValidator.defaultMaximumTextCharacters) {
        precondition(maxTextCharacters > 0)
        self.maxTextCharacters = maxTextCharacters
    }

    public func validateCloneAudio(
        data: Data,
        filename: String,
        durationSeconds: TimeInterval,
        consent: VoiceCloneConsent
    ) throws -> AuthorizedVoiceSource {
        guard consent.isComplete else { throw AuthorizedVoiceSourceError.consentRequired }
        guard isSafeAudioFilename(filename) else { throw AuthorizedVoiceSourceError.invalidFilename }
        guard ["mp3", "m4a", "wav"].contains(filename.lowercased().split(separator: ".").last.map(String.init) ?? "") else {
            throw AuthorizedVoiceSourceError.unsupportedAudioFormat
        }
        guard !data.isEmpty else { throw AuthorizedVoiceSourceError.emptyAudio }
        guard data.count <= Self.maximumAudioBytes else { throw AuthorizedVoiceSourceError.audioTooLarge }
        guard durationSeconds.isFinite,
              durationSeconds >= Self.minimumCloneDuration,
              durationSeconds <= Self.maximumCloneDuration else {
            throw AuthorizedVoiceSourceError.durationOutOfRange
        }
        return AuthorizedVoiceSource(data: data, filename: filename, durationSeconds: durationSeconds, consent: consent)
    }

    public func validateFriendText(_ text: String) throws -> ImportedFriendText {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw AuthorizedSourceTextError.empty }
        guard cleaned.count <= maxTextCharacters else { throw AuthorizedSourceTextError.tooLong }
        return ImportedFriendText(text: cleaned)
    }

    private func isSafeAudioFilename(_ filename: String) -> Bool {
        !filename.isEmpty && filename.count <= 255 && !filename.contains(where: { $0 == "/" || $0 == "\\" })
    }
}

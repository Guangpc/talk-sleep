import XCTest
@testable import SleepMateCore

final class VoiceSourceIntakeTests: XCTestCase {
    func testAudioRequiresExplicitConsentAndVerifiedCloneBounds() throws {
        let validator = AuthorizedVoiceSourceValidator()
        let consent = VoiceCloneConsent(
            authorized: true,
            intendedUseAcknowledged: true,
            cloudProcessingAcknowledged: true,
            retentionAndDeletionAcknowledged: true,
            acceptedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let source = try validator.validateCloneAudio(
            data: Data(repeating: 0x49, count: 128),
            filename: "friend.m4a",
            durationSeconds: 12,
            consent: consent
        )

        XCTAssertEqual(source.filename, "friend.m4a")
        XCTAssertEqual(source.durationSeconds, 12)
        XCTAssertEqual(source.data.count, 128)
        XCTAssertEqual(source.consent, consent)
    }

    func testAudioRejectsMissingConsentInvalidExtensionAndUnverifiedDuration() {
        let validator = AuthorizedVoiceSourceValidator()
        let consent = VoiceCloneConsent(
            authorized: false,
            intendedUseAcknowledged: false,
            cloudProcessingAcknowledged: false,
            retentionAndDeletionAcknowledged: false,
            acceptedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertThrowsError(try validator.validateCloneAudio(
            data: Data([0x01]),
            filename: "friend.mp3",
            durationSeconds: 12,
            consent: consent
        )) { error in
            XCTAssertEqual(error as? AuthorizedVoiceSourceError, .consentRequired)
        }
        XCTAssertThrowsError(try validator.validateCloneAudio(
            data: Data([0x01]),
            filename: "friend.wav",
            durationSeconds: 301,
            consent: VoiceCloneConsent(
                authorized: true,
                intendedUseAcknowledged: true,
                cloudProcessingAcknowledged: true,
                retentionAndDeletionAcknowledged: true,
                acceptedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )) { error in
            XCTAssertEqual(error as? AuthorizedVoiceSourceError, .durationOutOfRange)
        }
        XCTAssertThrowsError(try validator.validateCloneAudio(
            data: Data([0x01]),
            filename: "friend.txt",
            durationSeconds: 12,
            consent: VoiceCloneConsent(
                authorized: true,
                intendedUseAcknowledged: true,
                cloudProcessingAcknowledged: true,
                retentionAndDeletionAcknowledged: true,
                acceptedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )) { error in
            XCTAssertEqual(error as? AuthorizedVoiceSourceError, .unsupportedAudioFormat)
        }
    }

    func testCloneAudioAcceptsExactDurationAndRejectsInvalidDurations() {
        let validator = AuthorizedVoiceSourceValidator()
        let consent = completeConsent()
        for duration in [10.0, 300.0] {
            XCTAssertNoThrow(try validator.validateCloneAudio(
                data: Data([0x01]), filename: "friend.wav", durationSeconds: duration, consent: consent
            ))
        }
        for duration in [9.99, 300.01, .nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try validator.validateCloneAudio(
                data: Data([0x01]), filename: "friend.wav", durationSeconds: duration, consent: consent
            )) { error in
                XCTAssertEqual(error as? AuthorizedVoiceSourceError, .durationOutOfRange)
            }
        }
    }

    func testCloneAudioRejectsPathNamesEmptyAndOversizedData() {
        let validator = AuthorizedVoiceSourceValidator()
        let consent = completeConsent()
        for filename in ["../friend.wav", "folder/friend.wav", "friend\\voice.wav"] {
            XCTAssertThrowsError(try validator.validateCloneAudio(
                data: Data([0x01]), filename: filename, durationSeconds: 10, consent: consent
            )) { error in
                XCTAssertEqual(error as? AuthorizedVoiceSourceError, .invalidFilename)
            }
        }
        XCTAssertThrowsError(try validator.validateCloneAudio(
            data: Data(), filename: "friend.wav", durationSeconds: 10, consent: consent
        )) { error in
            XCTAssertEqual(error as? AuthorizedVoiceSourceError, .emptyAudio)
        }
        XCTAssertThrowsError(try validator.validateCloneAudio(
            data: Data(repeating: 0x01, count: AuthorizedVoiceSourceValidator.maximumAudioBytes + 1),
            filename: "friend.wav", durationSeconds: 10, consent: consent
        )) { error in
            XCTAssertEqual(error as? AuthorizedVoiceSourceError, .audioTooLarge)
        }
    }

    private func completeConsent() -> VoiceCloneConsent {
        VoiceCloneConsent(
            authorized: true,
            intendedUseAcknowledged: true,
            cloudProcessingAcknowledged: true,
            retentionAndDeletionAcknowledged: true,
            acceptedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testTextSourceTrimsAndBoundsImportedFriendContext() throws {
        let validator = AuthorizedVoiceSourceValidator(maxTextCharacters: 40)
        let source = try validator.validateFriendText("  朋友喜欢在睡前聊海边和音乐。  ")

        XCTAssertEqual(source.text, "朋友喜欢在睡前聊海边和音乐。")
        XCTAssertThrowsError(try validator.validateFriendText(String(repeating: "x", count: 41))) { error in
            XCTAssertEqual(error as? AuthorizedSourceTextError, .tooLong)
        }
    }
}

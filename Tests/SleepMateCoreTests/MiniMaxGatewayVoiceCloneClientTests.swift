import XCTest
@testable import SleepMateCore

final class MiniMaxGatewayVoiceCloneClientTests: XCTestCase {
    func testAuthorizedSourceUploadsThenClonesAndReturnsBoundVoice() async throws {
        let transport = RecordingVoiceCloneTransport(responses: [
            MiniMaxGatewayTTSHTTPResponse(
                statusCode: 200,
                body: Data(#"{"fileId":"file-123"}"#.utf8)
            ),
            MiniMaxGatewayTTSHTTPResponse(
                statusCode: 200,
                body: Data(#"{"voiceId":"voice-friend-123"}"#.utf8)
            )
        ])
        let client = MiniMaxGatewayVoiceCloneClient(
            baseURL: URL(string: "https://gateway.example")!,
            gatewayToken: "gateway-token-123456",
            transport: transport
        )
        let source = try makeSource()

        let voice = try await client.clone(
            source: source,
            requestedVoiceId: "sleepmate-friend-123",
            promptText: "温柔、自然地说话。"
        )

        XCTAssertEqual(voice, VoiceConfiguration(reference: "voice-friend-123"))
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.path, "/v1/tts/upload")
        XCTAssertEqual(transport.requests[1].url?.path, "/v1/tts/clone")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer gateway-token-123456")
        XCTAssertNil(transport.requests[0].value(forHTTPHeaderField: "X-MiniMax-Api-Key"))
        let upload = try XCTUnwrap(json(transport.requests[0]))
        XCTAssertEqual(upload["purpose"] as? String, "voice_clone")
        XCTAssertEqual(upload["filename"] as? String, "friend.m4a")
        XCTAssertEqual(upload["durationSeconds"] as? Double, 12)
        XCTAssertNotNil(upload["audioBase64"] as? String)
        let consent = try XCTUnwrap(upload["consent"] as? [String: Any])
        XCTAssertEqual(consent["authorized"] as? Bool, true)
        XCTAssertEqual(consent["intendedUseAcknowledged"] as? Bool, true)
        XCTAssertEqual(consent["cloudProcessingAcknowledged"] as? Bool, true)
        XCTAssertEqual(consent["retentionAndDeletionAcknowledged"] as? Bool, true)
        XCTAssertEqual(consent["acceptedAt"] as? String, "2023-11-14T22:13:20Z")
        let clone = try XCTUnwrap(json(transport.requests[1]))
        XCTAssertEqual(clone["fileId"] as? String, "file-123")
        XCTAssertEqual(clone["voiceId"] as? String, "sleepmate-friend-123")
        XCTAssertEqual(clone["promptText"] as? String, "温柔、自然地说话。")
    }

    func testInvalidGatewayTokenDoesNotUploadSource() async throws {
        let transport = RecordingVoiceCloneTransport(responses: [])
        let client = MiniMaxGatewayVoiceCloneClient(
            baseURL: URL(string: "https://gateway.example")!,
            gatewayToken: "bad token",
            transport: transport
        )

        do {
            _ = try await client.clone(source: try makeSource(), requestedVoiceId: "voice-1")
            XCTFail("expected invalid token")
        } catch let error as MiniMaxGatewayVoiceCloneClientError {
            XCTAssertEqual(error, .invalidGatewayToken)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    private func makeSource() throws -> AuthorizedVoiceSource {
        let consent = VoiceCloneConsent(
            authorized: true,
            intendedUseAcknowledged: true,
            cloudProcessingAcknowledged: true,
            retentionAndDeletionAcknowledged: true,
            acceptedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        return try AuthorizedVoiceSourceValidator().validateCloneAudio(
            data: Data([0x49, 0x44, 0x33]),
            filename: "friend.m4a",
            durationSeconds: 12,
            consent: consent
        )
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
        )
    }
}

private final class RecordingVoiceCloneTransport: MiniMaxGatewayTTSHTTPTransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private var responses: [MiniMaxGatewayTTSHTTPResponse]

    init(responses: [MiniMaxGatewayTTSHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> MiniMaxGatewayTTSHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.cannotConnectToHost) }
        return responses.removeFirst()
    }
}

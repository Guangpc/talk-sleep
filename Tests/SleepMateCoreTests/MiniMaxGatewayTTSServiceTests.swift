import Foundation
import XCTest
@testable import SleepMateCore

final class MiniMaxGatewayTTSServiceTests: XCTestCase {
    func testSuccessfulResponseUsesGatewayTokenAndVoiceReferenceAndReturnsDecodedAudio() async throws {
        let transport = RecordingTransport(outcome: .response(Self.response(audioBase64: "AAECAwQ=", format: "mp3", sampleRate: 32_000)))
        let service = MiniMaxGatewayTTSService(
            baseURL: URL(string: "https://gateway.example.test")!,
            gatewayToken: "gateway-token-for-tests",
            transport: transport
        )

        let audio = try await service.synthesize(
            text: "晚安，先陪你待一会儿。",
            voice: VoiceConfiguration(reference: "voice://friend-123")
        )

        XCTAssertEqual(audio, Data([0, 1, 2, 3, 4]))
        let request = try await transport.onlyRequest()
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example.test/v1/tts/synthesize")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gateway-token-for-tests")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["text"] as? String, "晚安，先陪你待一会儿。")
        XCTAssertEqual(object["voiceId"] as? String, "voice://friend-123")
        XCTAssertEqual(object["model"] as? String, "speech-2.8-hd")
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("gateway-token-for-tests"))
    }

    func testGatewayJSONErrorNormalizesWithoutLeakingTokenOrProviderMessage() async {
        let transport = RecordingTransport(outcome: .response(
            .init(
                statusCode: 401,
                headers: [:],
                body: Data(#"{"error":{"code":"gateway_unauthorized","message":"Bearer gateway-token-for-tests rejected"}}"#.utf8)
            )
        ))
        let service = MiniMaxGatewayTTSService(
            baseURL: URL(string: "https://gateway.example.test")!,
            gatewayToken: "gateway-token-for-tests",
            transport: transport
        )

        do {
            _ = try await service.synthesize(text: "晚安", voice: VoiceConfiguration(reference: "voice://friend-123"))
            XCTFail("expected gateway error")
        } catch let error as MiniMaxGatewayTTSServiceError {
            XCTAssertEqual(error, .gatewayError(code: "gateway_unauthorized"))
            XCTAssertFalse(error.localizedDescription.contains("gateway-token-for-tests"))
            XCTAssertFalse(error.localizedDescription.contains("rejected"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testHTTPErrorWithoutJSONNormalizesToStatusOnly() async {
        let transport = RecordingTransport(outcome: .response(
            .init(statusCode: 502, headers: [:], body: Data("upstream provider details".utf8))
        ))
        let service = MiniMaxGatewayTTSService(
            baseURL: URL(string: "https://gateway.example.test")!,
            gatewayToken: "gateway-token-for-tests",
            transport: transport
        )

        do {
            _ = try await service.synthesize(text: "晚安", voice: VoiceConfiguration(reference: "voice://friend-123"))
            XCTFail("expected HTTP error")
        } catch let error as MiniMaxGatewayTTSServiceError {
            XCTAssertEqual(error, .httpStatus(502))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testMalformedJSONNormalizesToInvalidResponse() async {
        let transport = RecordingTransport(outcome: .response(
            .init(statusCode: 200, headers: [:], body: Data("not-json".utf8))
        ))
        let service = MiniMaxGatewayTTSService(
            baseURL: URL(string: "https://gateway.example.test")!,
            gatewayToken: "gateway-token-for-tests",
            transport: transport
        )

        do {
            _ = try await service.synthesize(text: "晚安", voice: VoiceConfiguration(reference: "voice://friend-123"))
            XCTFail("expected malformed response")
        } catch let error as MiniMaxGatewayTTSServiceError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testInvalidAudioBase64NormalizesToInvalidResponse() async {
        let transport = RecordingTransport(outcome: .response(Self.response(audioBase64: "not base64", format: "mp3", sampleRate: 32_000)))
        let service = MiniMaxGatewayTTSService(
            baseURL: URL(string: "https://gateway.example.test")!,
            gatewayToken: "gateway-token-for-tests",
            transport: transport
        )

        do {
            _ = try await service.synthesize(text: "晚安", voice: VoiceConfiguration(reference: "voice://friend-123"))
            XCTFail("expected invalid audio response")
        } catch let error as MiniMaxGatewayTTSServiceError {
            XCTAssertEqual(error, .invalidResponse)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testInvalidFormatOrSampleRateNormalizesToInvalidResponse() async {
        for response in [
            Self.response(audioBase64: "AAE=", format: "", sampleRate: 32_000),
            Self.response(audioBase64: "AAE=", format: "mp3", sampleRate: 0),
        ] {
            let transport = RecordingTransport(outcome: .response(response))
            let service = MiniMaxGatewayTTSService(
                baseURL: URL(string: "https://gateway.example.test")!,
                gatewayToken: "gateway-token-for-tests",
                transport: transport
            )

            do {
                _ = try await service.synthesize(text: "晚安", voice: VoiceConfiguration(reference: "voice://friend-123"))
                XCTFail("expected invalid response")
            } catch let error as MiniMaxGatewayTTSServiceError {
                XCTAssertEqual(error, .invalidResponse)
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testCancellationWhileTransportIsInFlightNormalizesToCancelled() async {
        let transport = RecordingTransport(outcome: .waitForCancellation)
        let service = MiniMaxGatewayTTSService(
            baseURL: URL(string: "https://gateway.example.test")!,
            gatewayToken: "gateway-token-for-tests",
            transport: transport
        )

        let task = Task { () -> MiniMaxGatewayTTSServiceError? in
            do {
                _ = try await service.synthesize(text: "晚安", voice: VoiceConfiguration(reference: "voice://friend-123"))
                return nil
            } catch let error as MiniMaxGatewayTTSServiceError {
                return error
            } catch {
                return nil
            }
        }
        while !(await transport.hasRequest()) {
            await Task.yield()
        }
        task.cancel()

        let result = await task.value
        XCTAssertEqual(result, .cancelled)
    }

    func testCancellationNormalizesToCancelled() async {
        let transport = RecordingTransport(outcome: .cancelled)
        let service = MiniMaxGatewayTTSService(
            baseURL: URL(string: "https://gateway.example.test")!,
            gatewayToken: "gateway-token-for-tests",
            transport: transport
        )

        do {
            _ = try await service.synthesize(text: "晚安", voice: VoiceConfiguration(reference: "voice://friend-123"))
            XCTFail("expected cancellation")
        } catch let error as MiniMaxGatewayTTSServiceError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private static func response(audioBase64: String, format: String, sampleRate: Int) -> MiniMaxGatewayTTSHTTPResponse {
        let payload: [String: Any] = [
            "audioBase64": audioBase64,
            "format": format,
            "sampleRate": sampleRate,
        ]
        return .init(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: try! JSONSerialization.data(withJSONObject: payload)
        )
    }
}

private actor RecordingTransport: MiniMaxGatewayTTSHTTPTransport {
    enum Outcome: Sendable {
        case response(MiniMaxGatewayTTSHTTPResponse)
        case cancelled
        case waitForCancellation
    }

    private let outcome: Outcome
    private var requests: [URLRequest] = []

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func send(_ request: URLRequest) async throws -> MiniMaxGatewayTTSHTTPResponse {
        requests.append(request)
        switch outcome {
        case let .response(response):
            return response
        case .cancelled:
            throw CancellationError()
        case .waitForCancellation:
            try await Task.sleep(nanoseconds: 60_000_000_000)
            throw NSError(domain: "RecordingTransport", code: 2)
        }
    }

    func hasRequest() -> Bool {
        !requests.isEmpty
    }

    func onlyRequest() throws -> URLRequest {
        guard requests.count == 1, let request = requests.first else {
            throw NSError(domain: "RecordingTransport", code: 1)
        }
        return request
    }
}

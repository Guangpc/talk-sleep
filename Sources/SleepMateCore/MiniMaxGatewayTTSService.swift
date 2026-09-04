import Foundation

/// The app-facing response returned by the server gateway, kept independent of provider SDKs.
public struct MiniMaxGatewayTTSHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

/// Injectable HTTP boundary for the gateway client. Tests provide a fake; production uses URLSession.
public protocol MiniMaxGatewayTTSHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> MiniMaxGatewayTTSHTTPResponse
}

public enum MiniMaxGatewayTTSServiceError: Error, Equatable, LocalizedError, Sendable {
    case invalidGatewayToken
    case httpStatus(Int)
    case gatewayError(code: String)
    case invalidResponse
    case cancelled
    case transportFailure

    public var errorDescription: String? {
        switch self {
        case .invalidGatewayToken:
            return "The gateway token is not configured."
        case let .httpStatus(statusCode):
            return "The speech gateway returned HTTP \(statusCode)."
        case let .gatewayError(code):
            return "The speech gateway reported error \(code)."
        case .invalidResponse:
            return "The speech gateway returned an invalid response."
        case .cancelled:
            return "Speech synthesis was cancelled."
        case .transportFailure:
            return "The speech gateway could not be reached."
        }
    }
}

/// Core client for the app-facing POST /v1/tts/synthesize gateway route.
/// The token is a gateway credential, never a MiniMax provider credential.
public struct MiniMaxGatewayTTSService: TTSService, Sendable {
    private struct RequestBody: Encodable {
        let model: String
        let text: String
        let voiceId: String
    }

    private struct ResponseBody: Decodable {
        let audioBase64: String
        let format: String
        let sampleRate: Int?
    }

    private let endpoint: URL
    private let gatewayToken: String
    private let model: String
    private let transport: any MiniMaxGatewayTTSHTTPTransport

    public init(
        baseURL: URL,
        gatewayToken: String,
        model: String = "speech-2.8-hd",
        transport: any MiniMaxGatewayTTSHTTPTransport = URLSessionMiniMaxGatewayTTSHTTPTransport()
    ) {
        self.endpoint = baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("tts")
            .appendingPathComponent("synthesize")
        self.gatewayToken = gatewayToken
        self.model = model
        self.transport = transport
    }

    public func synthesize(text: String, voice: VoiceConfiguration) async throws -> Data {
        guard !gatewayToken.isEmpty, !gatewayToken.contains(where: { $0.isWhitespace }) else {
            throw MiniMaxGatewayTTSServiceError.invalidGatewayToken
        }
        guard !text.isEmpty, !voice.reference.isEmpty else {
            throw MiniMaxGatewayTTSServiceError.invalidResponse
        }
        try checkCancellation()

        let request = try makeRequest(text: text, voice: voice)
        let response: MiniMaxGatewayTTSHTTPResponse
        do {
            response = try await transport.send(request)
        } catch is CancellationError {
            throw MiniMaxGatewayTTSServiceError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw MiniMaxGatewayTTSServiceError.cancelled
        } catch {
            throw MiniMaxGatewayTTSServiceError.transportFailure
        }
        try checkCancellation()

        guard (200..<300).contains(response.statusCode) else {
            throw normalizedHTTPError(response)
        }

        guard let payload = try? JSONDecoder().decode(ResponseBody.self, from: response.body),
              !payload.audioBase64.isEmpty,
              !payload.format.isEmpty,
              payload.sampleRate.map({ $0 > 0 }) ?? true,
              let audio = Data(base64Encoded: payload.audioBase64),
              !audio.isEmpty else {
            throw MiniMaxGatewayTTSServiceError.invalidResponse
        }
        return audio
    }

    private func checkCancellation() throws {
        do {
            try Task.checkCancellation()
        } catch {
            throw MiniMaxGatewayTTSServiceError.cancelled
        }
    }

    private func makeRequest(text: String, voice: VoiceConfiguration) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(gatewayToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(RequestBody(model: model, text: text, voiceId: voice.reference))
        return request
    }

    private func normalizedHTTPError(_ response: MiniMaxGatewayTTSHTTPResponse) -> MiniMaxGatewayTTSServiceError {
        guard let payload = try? JSONDecoder().decode(GatewayErrorBody.self, from: response.body),
              let code = payload.error?.code,
              !code.isEmpty else {
            return .httpStatus(response.statusCode)
        }
        return .gatewayError(code: code)
    }

    private struct GatewayErrorBody: Decodable {
        struct Detail: Decodable {
            let code: String?
        }

        let error: Detail?
    }
}

public struct URLSessionMiniMaxGatewayTTSHTTPTransport: MiniMaxGatewayTTSHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> MiniMaxGatewayTTSHTTPResponse {
        let (body, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MiniMaxGatewayTTSServiceError.invalidResponse
        }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key] = value
            }
        }
        return MiniMaxGatewayTTSHTTPResponse(statusCode: response.statusCode, headers: headers, body: body)
    }
}

import Foundation

public enum MiniMaxGatewayVoiceCloneClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidGatewayToken
    case invalidRequest
    case consentRequired
    case httpStatus(Int)
    case gatewayError(code: String)
    case invalidResponse
    case transportFailure
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidGatewayToken:
            return "The gateway token is not configured."
        case .invalidRequest:
            return "The voice clone request is invalid."
        case .consentRequired:
            return "Voice authorization must be confirmed before upload."
        case let .httpStatus(statusCode):
            return "The voice gateway returned HTTP \(statusCode)."
        case let .gatewayError(code):
            return "The voice gateway reported error \(code)."
        case .invalidResponse:
            return "The voice gateway returned an invalid response."
        case .transportFailure:
            return "The voice gateway could not be reached."
        case .cancelled:
            return "Voice cloning was cancelled."
        }
    }
}

/// Uploads one consented source and binds the gateway clone to a requested friend voice ID.
/// Provider credentials and provider-specific request fields remain server-side.
public struct MiniMaxGatewayVoiceCloneClient: Sendable {
    private struct UploadRequest: Encodable {
        let purpose: String
        let filename: String
        let audioBase64: String
        let durationSeconds: TimeInterval
    }

    private struct UploadResponse: Decodable {
        let fileId: String
    }

    private struct CloneRequest: Encodable {
        let fileId: String
        let voiceId: String
        let promptText: String?
    }

    private struct CloneResponse: Decodable {
        let voiceId: String
    }

    private let baseURL: URL
    private let gatewayToken: String
    private let transport: any MiniMaxGatewayTTSHTTPTransport

    public init(
        baseURL: URL,
        gatewayToken: String,
        transport: any MiniMaxGatewayTTSHTTPTransport = URLSessionMiniMaxGatewayTTSHTTPTransport()
    ) {
        self.baseURL = baseURL
        self.gatewayToken = gatewayToken
        self.transport = transport
    }

    public func clone(
        source: AuthorizedVoiceSource,
        requestedVoiceId: String,
        promptText: String? = nil
    ) async throws -> VoiceConfiguration {
        guard !gatewayToken.isEmpty, !gatewayToken.contains(where: { $0.isWhitespace }) else {
            throw MiniMaxGatewayVoiceCloneClientError.invalidGatewayToken
        }
        guard source.consent.isComplete else {
            throw MiniMaxGatewayVoiceCloneClientError.consentRequired
        }
        guard !requestedVoiceId.isEmpty,
              requestedVoiceId.count <= 200,
              !requestedVoiceId.contains(where: { $0.isWhitespace }) else {
            throw MiniMaxGatewayVoiceCloneClientError.invalidRequest
        }
        try checkCancellation()

        let fileId = try await upload(source)
        try checkCancellation()
        let response = try await send(
            path: ["v1", "tts", "clone"],
            body: CloneRequest(fileId: fileId, voiceId: requestedVoiceId, promptText: promptText)
        )
        guard (200..<300).contains(response.statusCode),
              let payload = try? JSONDecoder().decode(CloneResponse.self, from: response.body),
              !payload.voiceId.isEmpty else {
            throw error(for: response)
        }
        return VoiceConfiguration(reference: payload.voiceId)
    }

    private func upload(_ source: AuthorizedVoiceSource) async throws -> String {
        let response = try await send(
            path: ["v1", "tts", "upload"],
            body: UploadRequest(
                purpose: "voice_clone",
                filename: source.filename,
                audioBase64: source.data.base64EncodedString(),
                durationSeconds: source.durationSeconds
            )
        )
        guard (200..<300).contains(response.statusCode),
              let payload = try? JSONDecoder().decode(UploadResponse.self, from: response.body),
              !payload.fileId.isEmpty else {
            throw error(for: response)
        }
        return payload.fileId
    }

    private func send<Body: Encodable>(path: [String], body: Body) async throws -> MiniMaxGatewayTTSHTTPResponse {
        var endpoint = baseURL
        for component in path {
            endpoint.appendPathComponent(component)
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(gatewayToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        do {
            return try await transport.send(request)
        } catch is CancellationError {
            throw MiniMaxGatewayVoiceCloneClientError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw MiniMaxGatewayVoiceCloneClientError.cancelled
        } catch {
            throw MiniMaxGatewayVoiceCloneClientError.transportFailure
        }
    }

    private func checkCancellation() throws {
        guard !Task.isCancelled else { throw MiniMaxGatewayVoiceCloneClientError.cancelled }
    }

    private func error(for response: MiniMaxGatewayTTSHTTPResponse) -> MiniMaxGatewayVoiceCloneClientError {
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

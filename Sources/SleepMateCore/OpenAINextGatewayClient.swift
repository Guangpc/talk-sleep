import Foundation

/// The roles accepted by the server-side LLM gateway.
public struct LLMMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Equatable, Sendable {
        case system
        case user
        case assistant
    }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// Models exposed by the current OpenAI-compatible gateway configuration.
public enum LLMModel: String, Codable, Equatable, Sendable {
    case gpt56Sol = "gpt-5.6-sol"
    case gpt56Terra = "gpt-5.6-terra"
}

/// The only reasoning effort values allowed at the app-facing seam.
public enum LLMReasoningEffort: String, Codable, Equatable, Sendable {
    case medium
    case high
    case xhigh
}

public enum LLMStreamEvent: Equatable, Sendable {
    case text(String)
    case done
}

public enum OpenAINextGatewayError: Error, Equatable, Sendable, LocalizedError {
    case invalidConfiguration
    case http(statusCode: Int, code: String?)
    case gateway(code: String)
    case invalidSSE
    case transport
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "The LLM gateway configuration is invalid."
        case let .http(statusCode, code):
            if let code {
                return "The LLM gateway returned HTTP \(statusCode) (\(code))."
            }
            return "The LLM gateway returned HTTP \(statusCode)."
        case let .gateway(code):
            return "The LLM gateway reported \(code)."
        case .invalidSSE:
            return "The LLM gateway returned an invalid stream."
        case .transport:
            return "The LLM gateway could not be reached."
        case .cancelled:
            return "The LLM request was cancelled."
        }
    }
}

/// The app-facing text-generation seam. Provider credentials never cross this boundary.
public protocol LLMClient: Sendable {
    func streamChat(
        messages: [LLMMessage],
        model: LLMModel,
        reasoningEffort: LLMReasoningEffort,
        maxTokens: Int?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error>
}

/// A transport seam for deterministic tests and for replacing URLSession at the edge.
public protocol LLMGatewayTransport: Sendable {
    func send(_ request: URLRequest) async throws -> LLMGatewayResponse
}

public struct LLMGatewayResponse: Sendable {
    public let statusCode: Int
    public let body: AsyncThrowingStream<Data, Error>

    public init(statusCode: Int, body: AsyncThrowingStream<Data, Error>) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// Client for the normalized server gateway, not for the upstream provider.
public final class OpenAINextGatewayClient: LLMClient, @unchecked Sendable {
    private let gatewayEndpoint: URL
    private let gatewayToken: String
    private let transport: any LLMGatewayTransport

    public init(
        gatewayEndpoint: URL,
        gatewayToken: String,
        transport: any LLMGatewayTransport
    ) {
        self.gatewayEndpoint = gatewayEndpoint
        self.gatewayToken = gatewayToken
        self.transport = transport
    }

    public convenience init(gatewayEndpoint: URL, gatewayToken: String) {
        self.init(
            gatewayEndpoint: gatewayEndpoint,
            gatewayToken: gatewayToken,
            transport: URLSessionLLMGatewayTransport()
        )
    }

    public func streamChat(
        messages: [LLMMessage],
        model: LLMModel,
        reasoningEffort: LLMReasoningEffort,
        maxTokens: Int? = nil
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [gatewayEndpoint, gatewayToken, transport] in
                do {
                    guard !gatewayToken.isEmpty, gatewayEndpoint.scheme != nil, gatewayEndpoint.host != nil else {
                        throw OpenAINextGatewayError.invalidConfiguration
                    }

                    var request = URLRequest(url: gatewayEndpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(gatewayToken)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(
                        ChatRequest(
                            model: model.rawValue,
                            messages: messages,
                            reasoningEffort: reasoningEffort.rawValue,
                            maxTokens: maxTokens
                        )
                    )

                    let response = try await transport.send(request)
                    guard (200..<300).contains(response.statusCode) else {
                        let body = await Self.collectBody(response.body)
                        throw Self.httpError(statusCode: response.statusCode, body: body)
                    }

                    var parser = SSEParser()
                    for try await chunk in response.body {
                        try Task.checkCancellation()
                        for event in try parser.consume(chunk) {
                            continuation.yield(event)
                        }
                    }
                    for event in try parser.finish() {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.normalize(error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                continuation.finish(throwing: OpenAINextGatewayError.cancelled)
            }
        }
    }

    private static func collectBody(_ body: AsyncThrowingStream<Data, Error>) async -> Data {
        var collected = Data()
        do {
            for try await chunk in body {
                try Task.checkCancellation()
                collected.append(chunk)
            }
        } catch {
            // The status code remains the stable signal if the error body is incomplete.
        }
        return collected
    }

    private static func httpError(statusCode: Int, body: Data) -> OpenAINextGatewayError {
        .http(statusCode: statusCode, code: errorCode(from: body))
    }

    private static func errorCode(from body: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: body),
            let root = object as? [String: Any],
            let error = root["error"] as? [String: Any],
            let code = error["code"] as? String
        else {
            return nil
        }
        return normalizedCode(code)
    }

    private static func normalizedCode(_ code: String) -> String {
        let normalized = String(code.unicodeScalars.filter(isSafeCodeScalar).prefix(80))
        return normalized.isEmpty ? "unknown" : normalized
    }

    private static func isSafeCodeScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 45, 46, 48...57, 65...90, 95, 97...122:
            return true
        default:
            return false
        }
    }

    private static func normalize(_ error: Error) -> Error {
        if let error = error as? OpenAINextGatewayError {
            return error
        }
        if error is CancellationError || Task.isCancelled {
            return OpenAINextGatewayError.cancelled
        }
        return OpenAINextGatewayError.transport
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [LLMMessage]
    let reasoningEffort: String
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case reasoningEffort
        case maxTokens
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(reasoningEffort, forKey: .reasoningEffort)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
    }
}

private struct SSEParser {
    private var buffer: [UInt8] = []
    private var eventName: String?
    private var dataLines: [String] = []
    private var didEmitDone = false

    mutating func consume(_ data: Data) throws -> [LLMStreamEvent] {
        buffer.append(contentsOf: data)
        var events: [LLMStreamEvent] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = Array(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if line.last == 0x0D {
                line.removeLast()
            }
            try process(line: line, into: &events)
        }
        return events
    }

    mutating func finish() throws -> [LLMStreamEvent] {
        var events: [LLMStreamEvent] = []
        if !buffer.isEmpty {
            var line = buffer
            buffer.removeAll(keepingCapacity: true)
            if line.last == 0x0D {
                line.removeLast()
            }
            try process(line: line, into: &events)
        }
        try flushEvent(into: &events)
        return events
    }

    private mutating func process(line: [UInt8], into events: inout [LLMStreamEvent]) throws {
        if line.isEmpty {
            try flushEvent(into: &events)
            return
        }
        guard let value = String(bytes: line, encoding: .utf8) else {
            throw OpenAINextGatewayError.invalidSSE
        }
        if value.hasPrefix(":") {
            return
        }
        if value.hasPrefix("event:") {
            eventName = value.dropFirst(6).trimmingCharacters(in: .whitespaces)
        } else if value.hasPrefix("data:") {
            var data = String(value.dropFirst(5))
            if data.first == " " {
                data.removeFirst()
            }
            dataLines.append(data)
        }
    }

    private mutating func flushEvent(into events: inout [LLMStreamEvent]) throws {
        guard !dataLines.isEmpty else {
            eventName = nil
            return
        }
        let payload = dataLines.joined(separator: "\n")
        dataLines.removeAll(keepingCapacity: true)
        defer { eventName = nil }

        if payload == "[DONE]" {
            if !didEmitDone {
                didEmitDone = true
                events.append(.done)
            }
            return
        }

        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any]
        else {
            throw OpenAINextGatewayError.invalidSSE
        }

        if let error = root["error"] as? [String: Any] {
            let code = (error["code"] as? String).map(Self.normalizedCode) ?? "unknown"
            throw OpenAINextGatewayError.gateway(code: code)
        }
        if eventName == "error" {
            throw OpenAINextGatewayError.gateway(code: "unknown")
        }

        guard let type = root["type"] as? String else {
            throw OpenAINextGatewayError.invalidSSE
        }
        switch type {
        case "text":
            guard let text = root["text"] as? String, !text.isEmpty else {
                throw OpenAINextGatewayError.invalidSSE
            }
            guard !didEmitDone else { return }
            events.append(.text(text))
        case "done":
            if !didEmitDone {
                didEmitDone = true
                events.append(.done)
            }
        default:
            throw OpenAINextGatewayError.invalidSSE
        }
    }

    private static func normalizedCode(_ code: String) -> String {
        let normalized = String(code.unicodeScalars.filter(isSafeCodeScalar).prefix(80))
        return normalized.isEmpty ? "unknown" : normalized
    }

    private static func isSafeCodeScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 45, 46, 48...57, 65...90, 95, 97...122:
            return true
        default:
            return false
        }
    }
}

private struct URLSessionLLMGatewayTransport: LLMGatewayTransport {
    func send(_ request: URLRequest) async throws -> LLMGatewayResponse {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw OpenAINextGatewayError.transport
        }
        let body = AsyncThrowingStream<Data, Error> { continuation in
            let producer = Task {
                do {
                    var chunk: [UInt8] = []
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        chunk.append(byte)
                        if chunk.count >= 4_096 {
                            continuation.yield(Data(chunk))
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    if !chunk.isEmpty {
                        continuation.yield(Data(chunk))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                producer.cancel()
            }
        }
        return LLMGatewayResponse(statusCode: response.statusCode, body: body)
    }
}

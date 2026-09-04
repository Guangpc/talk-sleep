import XCTest
@testable import SleepMateCore

final class OpenAINextGatewayClientTests: XCTestCase {
    func testStreamingTextAcrossChunksBuildsRequestAndUsesGatewayBearerToken() async throws {
        let transport = RecordingTransport(response: .sse(chunks: [
            Data("data: {\"type\":\"text\",\"text\":\"你\"}\r".utf8),
            Data("\n\ndata: {\"type\":\"text\",\"text\":\"好\"}\r\n\r\ndata: {\"type\":\"done\"}\r\n\r\ndata: [DONE]\r\n\r\n".utf8)
        ]))
        let client = OpenAINextGatewayClient(
            gatewayEndpoint: URL(string: "https://gateway.example/v1/llm/chat")!,
            gatewayToken: "device-gateway-token",
            transport: transport
        )

        let events = try await collect(client.streamChat(
            messages: [
                LLMMessage(role: .system, content: "你是睡前陪伴 AI"),
                LLMMessage(role: .user, content: "陪我聊两句")
            ],
            model: .gpt56Terra,
            reasoningEffort: .medium,
            maxTokens: 80
        ))

        XCTAssertEqual(events, [.text("你"), .text("好"), .done])
        let request = await transport.request()
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.url?.absoluteString, "https://gateway.example/v1/llm/chat")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer device-gateway-token")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Accept"), "text/event-stream")

        let payload = try XCTUnwrap(request?.httpBody).jsonObject()
        XCTAssertEqual(payload["model"] as? String, "gpt-5.6-terra")
        XCTAssertEqual(payload["reasoningEffort"] as? String, "medium")
        XCTAssertEqual(payload["maxTokens"] as? Int, 80)
        XCTAssertEqual((payload["messages"] as? [[String: Any]])?.count, 2)
    }

    func testAllSupportedReasoningEffortsEncodeWithoutProviderKey() async throws {
        for effort in [LLMReasoningEffort.medium, .high, .xhigh] {
            let transport = RecordingTransport(response: .sse(chunks: [
                Data("data: {\"type\":\"done\"}\n\n".utf8)
            ]))
            let client = OpenAINextGatewayClient(
                gatewayEndpoint: URL(string: "https://gateway.example/v1/llm/chat")!,
                gatewayToken: "gateway-token",
                transport: transport
            )

            _ = try await collect(client.streamChat(
                messages: [LLMMessage(role: .user, content: "测试")],
                model: .gpt56Sol,
                reasoningEffort: effort
            ))

            let request = await transport.request()
            let payload = try XCTUnwrap(request?.httpBody).jsonObject()
            XCTAssertEqual(payload["reasoningEffort"] as? String, effort.rawValue)
            XCTAssertNil(payload["apiKey"])
            XCTAssertNil(payload["providerKey"])
        }
    }

    func testGatewayErrorEventBecomesNormalizedError() async throws {
        let transport = RecordingTransport(response: .sse(chunks: [
            Data("event: error\r\ndata: {\"error\":{\"code\":\"provider_unavailable\"}}\r\n\r\n".utf8)
        ]))
        let client = OpenAINextGatewayClient(
            gatewayEndpoint: URL(string: "https://gateway.example/v1/llm/chat")!,
            gatewayToken: "gateway-token",
            transport: transport
        )

        do {
            _ = try await collect(client.streamChat(
                messages: [LLMMessage(role: .user, content: "测试")],
                model: .gpt56Sol,
                reasoningEffort: .high
            ))
            XCTFail("expected gateway error")
        } catch let error as OpenAINextGatewayError {
            XCTAssertEqual(error, .gateway(code: "provider_unavailable"))
        }
    }

    func testNon2xxResponseBecomesNormalizedHTTPErrorWithoutProviderPayload() async throws {
        let transport = RecordingTransport(response: .http(
            statusCode: 401,
            body: Data("{\"error\":{\"code\":\"gateway_unauthorized\",\"message\":\"secret details\"}}".utf8)
        ))
        let client = OpenAINextGatewayClient(
            gatewayEndpoint: URL(string: "https://gateway.example/v1/llm/chat")!,
            gatewayToken: "gateway-token",
            transport: transport
        )

        do {
            _ = try await collect(client.streamChat(
                messages: [LLMMessage(role: .user, content: "测试")],
                model: .gpt56Sol,
                reasoningEffort: .medium
            ))
            XCTFail("expected HTTP error")
        } catch let error as OpenAINextGatewayError {
            XCTAssertEqual(error, .http(statusCode: 401, code: "gateway_unauthorized"))
            XCTAssertFalse(String(describing: error).contains("secret details"))
        }
    }

    func testMalformedSSEPayloadBecomesNormalizedError() async throws {
        let transport = RecordingTransport(response: .sse(chunks: [
            Data("data: {not-json}\n\n".utf8)
        ]))
        let client = OpenAINextGatewayClient(
            gatewayEndpoint: URL(string: "https://gateway.example/v1/llm/chat")!,
            gatewayToken: "gateway-token",
            transport: transport
        )

        do {
            _ = try await collect(client.streamChat(
                messages: [LLMMessage(role: .user, content: "测试")],
                model: .gpt56Sol,
                reasoningEffort: .medium
            ))
            XCTFail("expected malformed SSE error")
        } catch let error as OpenAINextGatewayError {
            XCTAssertEqual(error, .invalidSSE)
        }
    }

    func testCancellingConsumerCancelsTransportAndFinishesAsCancelled() async throws {
        let transport = RecordingTransport(response: .neverEnding)
        let client = OpenAINextGatewayClient(
            gatewayEndpoint: URL(string: "https://gateway.example/v1/llm/chat")!,
            gatewayToken: "gateway-token",
            transport: transport
        )

        let stream = client.streamChat(
            messages: [LLMMessage(role: .user, content: "测试")],
            model: .gpt56Sol,
            reasoningEffort: .medium
        )
        let task = Task {
            do {
                for try await _ in stream { }
                return "finished"
            } catch {
                return String(describing: error)
            }
        }

        await transport.waitUntilStarted()
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.contains("cancelled"))
        let transportWasCancelled = await transport.wasCancelled()
        XCTAssertTrue(transportWasCancelled)
    }

    private func collect(_ stream: AsyncThrowingStream<LLMStreamEvent, Error>) async throws -> [LLMStreamEvent] {
        var events: [LLMStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}

private actor RecordingTransport: LLMGatewayTransport {
    enum Response {
        case sse(chunks: [Data])
        case http(statusCode: Int, body: Data)
        case neverEnding
    }

    private let response: Response
    private var capturedRequest: URLRequest?
    private var started = false
    private var cancelled = false

    init(response: Response) {
        self.response = response
    }

    func send(_ request: URLRequest) async throws -> LLMGatewayResponse {
        capturedRequest = request
        started = true
        switch response {
        case let .sse(chunks):
            return LLMGatewayResponse(statusCode: 200, body: stream(chunks: chunks))
        case let .http(statusCode, body):
            return LLMGatewayResponse(statusCode: statusCode, body: stream(chunks: [body]))
        case .neverEnding:
            return LLMGatewayResponse(statusCode: 200, body: AsyncThrowingStream { continuation in
                continuation.onTermination = { @Sendable [weak self] _ in
                    Task { await self?.markCancelled() }
                }
            })
        }
    }

    func request() -> URLRequest? {
        capturedRequest
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func wasCancelled() -> Bool {
        cancelled
    }

    private func stream(chunks: [Data]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    private func markCancelled() {
        cancelled = true
    }
}

private extension Data {
    func jsonObject() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: self) as? [String: Any])
    }
}

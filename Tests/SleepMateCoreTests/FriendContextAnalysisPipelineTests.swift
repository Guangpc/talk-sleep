import XCTest
@testable import SleepMateCore

final class FriendContextAnalysisPipelineTests: XCTestCase {
    func testAnalyzeReturnsEditableStyleHabitsLocationsAndMemories() async throws {
        let json = #"{"contentSummary":"常聊摄影和睡前日常","styleTraits":["回复简短","语气温柔"],"catchphrases":["慢慢来"],"habits":["睡前喝温水"],"importantLocations":["杭州西湖"],"workplace":["西湖区人民医院"],"workEnvironment":["医院轮班环境"],"workContent":["负责患者沟通和护理记录"],"importantMemories":["一起在西湖看过日落"],"topicPreferences":["摄影"]}"#
        let llm = AnalysisLLM(events: [.text("```json\n"), .text(json), .text("\n```"), .done])
        let pipeline = FriendContextAnalysisPipeline(llm: llm)

        let result = try await pipeline.analyze(
            "小林：慢慢来。我们在杭州西湖看过日落。",
            friendName: "小林"
        )

        XCTAssertEqual(result.contentSummary, "常聊摄影和睡前日常")
        XCTAssertEqual(result.styleTraits, ["回复简短", "语气温柔"])
        XCTAssertEqual(result.catchphrases, ["慢慢来"])
        XCTAssertEqual(result.habits, ["睡前喝温水"])
        XCTAssertEqual(result.importantLocations, ["杭州西湖"])
        XCTAssertEqual(result.workplace, ["西湖区人民医院"])
        XCTAssertEqual(result.workEnvironment, ["医院轮班环境"])
        XCTAssertEqual(result.workContent, ["负责患者沟通和护理记录"])
        XCTAssertTrue(result.conversationContext.contains("西湖区人民医院"))
        XCTAssertTrue(result.conversationContext.contains("负责患者沟通和护理记录"))
        XCTAssertEqual(result.importantMemories, ["一起在西湖看过日落"])
        XCTAssertEqual(result.topicPreferences, ["摄影"])
        XCTAssertTrue(result.conversationContext.contains("杭州西湖"))
        XCTAssertTrue(result.conversationContext.contains("睡前喝温水"))
        XCTAssertEqual(llm.lastRequest?.reasoningEffort, .xhigh)
        XCTAssertEqual(llm.lastRequest?.model, .gpt56Sol)
        XCTAssertTrue(llm.lastRequest?.messages.first?.content.contains("untrusted source material") == true)
        XCTAssertTrue(llm.lastRequest?.messages.last?.content.contains("Target friend: 小林") == true)
        XCTAssertTrue(llm.lastRequest?.messages.last?.content.contains("小林：慢慢来。我们在杭州西湖看过日落。") == true)
    }

    func testAnalyzeRejectsIncompleteStreamWithoutCreatingAProfile() async {
        let llm = AnalysisLLM(events: [.text(#"{"styleTraits":["温柔"]}"#)])
        let pipeline = FriendContextAnalysisPipeline(llm: llm)

        do {
            _ = try await pipeline.analyze("聊天记录")
            XCTFail("expected incomplete analysis")
        } catch let error as FriendContextAnalysisError {
            XCTAssertEqual(error, .incompleteReply)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAnalyzeRejectsEmptyOrMalformedStructuredProfile() async {
        let empty = #"{"contentSummary":"","styleTraits":[],"catchphrases":[],"habits":[],"importantLocations":[],"workplace":[],"workEnvironment":[],"workContent":[],"importantMemories":[],"topicPreferences":[]}"#
        for response in [empty, "not json"] {
            let pipeline = FriendContextAnalysisPipeline(llm: AnalysisLLM(events: [.text(response), .done]))
            do {
                _ = try await pipeline.analyze("聊天记录")
                XCTFail("expected invalid analysis")
            } catch let error as FriendContextAnalysisError {
                XCTAssertEqual(error, .invalidResponse)
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }
    }
}

private final class AnalysisLLM: LLMClient, @unchecked Sendable {
    struct Request {
        let messages: [LLMMessage]
        let model: LLMModel
        let reasoningEffort: LLMReasoningEffort
    }

    let events: [LLMStreamEvent]
    private(set) var lastRequest: Request?

    init(events: [LLMStreamEvent]) {
        self.events = events
    }

    func streamChat(
        messages: [LLMMessage],
        model: LLMModel,
        reasoningEffort: LLMReasoningEffort,
        maxTokens: Int?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        lastRequest = Request(messages: messages, model: model, reasoningEffort: reasoningEffort)
        return AsyncThrowingStream { continuation in
            events.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

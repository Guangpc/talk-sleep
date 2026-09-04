import XCTest
@testable import SleepMateCore

final class VoiceReplyPipelineTests: XCTestCase {
    func testReplyUsesOneTranscriptHistoryAndFriendVoiceAcrossLLMAndTTS() async throws {
        let llm = RecordingLLM(events: [.text("先 "), .text("慢慢休息"), .done])
        let tts = RecordingTTS(audio: Data([0x49, 0x44, 0x33]))
        let pipeline = VoiceReplyPipeline(llm: llm, tts: tts)
        let voice = VoiceConfiguration(reference: "voice://friend-123")
        let history = [LLMMessage(role: .system, content: "你是温柔的睡眠陪伴者") , LLMMessage(role: .assistant, content: "我在这里") ]

        let reply = try await pipeline.reply(
            to: "我今天有点累",
            history: history,
            voice: voice,
            model: .gpt56Terra,
            reasoningEffort: .medium
        )

        XCTAssertEqual(reply.text, "先 慢慢休息")
        XCTAssertEqual(reply.audio, Data([0x49, 0x44, 0x33]))
        XCTAssertEqual(llm.lastRequest?.messages, history + [LLMMessage(role: .user, content: "我今天有点累")])
        XCTAssertEqual(llm.lastRequest?.model, .gpt56Terra)
        XCTAssertEqual(llm.lastRequest?.reasoningEffort, .medium)
        XCTAssertEqual(tts.lastText, "先 慢慢休息")
        XCTAssertEqual(tts.lastVoice, voice)
    }

    func testContextIsBoundedWhilePreservingSystemInstructionAndNewestTurn() async throws {
        let llm = RecordingLLM(events: [.text("收到"), .done])
        let tts = RecordingTTS(audio: Data([0x01]))
        let pipeline = VoiceReplyPipeline(llm: llm, tts: tts, maxContextMessages: 4)
        let history = [
            LLMMessage(role: .system, content: "系统约束"),
            LLMMessage(role: .user, content: "旧一"),
            LLMMessage(role: .assistant, content: "旧二"),
            LLMMessage(role: .user, content: "较新一"),
            LLMMessage(role: .assistant, content: "较新二"),
            LLMMessage(role: .user, content: "较新三")
        ]

        _ = try await pipeline.reply(
            to: "最新问题",
            history: history,
            voice: VoiceConfiguration(reference: "voice://friend-123"),
            model: .gpt56Sol,
            reasoningEffort: .medium
        )

        XCTAssertEqual(llm.lastRequest?.messages, [
            LLMMessage(role: .system, content: "系统约束"),
            LLMMessage(role: .assistant, content: "较新二"),
            LLMMessage(role: .user, content: "较新三"),
            LLMMessage(role: .user, content: "最新问题")
        ])
    }

    func testIncompleteLLMStreamNeverCallsTTSOrCreatesPartialSuccess() async {
        let llm = RecordingLLM(events: [.text("未完成")])
        let tts = RecordingTTS(audio: Data([0x01]))
        let pipeline = VoiceReplyPipeline(llm: llm, tts: tts)

        do {
            _ = try await pipeline.reply(
                to: "你好",
                history: [],
                voice: VoiceConfiguration(reference: "voice://friend-123"),
                model: .gpt56Sol,
                reasoningEffort: .medium
            )
            XCTFail("expected incomplete reply")
        } catch let error as VoiceReplyPipelineError {
            XCTAssertEqual(error, .incompleteReply)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertNil(tts.lastText)
    }

    func testEmptyLLMReplyNeverCallsTTSOrCreatesFakeSuccess() async {
        let llm = RecordingLLM(events: [.done])
        let tts = RecordingTTS(audio: Data([0x01]))
        let pipeline = VoiceReplyPipeline(llm: llm, tts: tts)

        do {
            _ = try await pipeline.reply(
                to: "你好",
                history: [],
                voice: VoiceConfiguration(reference: "voice://friend-123"),
                model: .gpt56Sol,
                reasoningEffort: .high
            )
            XCTFail("expected empty reply")
        } catch let error as VoiceReplyPipelineError {
            XCTAssertEqual(error, .emptyReply)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertNil(tts.lastText)
    }
}

private final class RecordingLLM: LLMClient, @unchecked Sendable {
    struct Request: Sendable {
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

private final class RecordingTTS: TTSService {
    let audio: Data
    private(set) var lastText: String?
    private(set) var lastVoice: VoiceConfiguration?

    init(audio: Data) {
        self.audio = audio
    }

    func synthesize(text: String, voice: VoiceConfiguration) async throws -> Data {
        lastText = text
        lastVoice = voice
        return audio
    }
}

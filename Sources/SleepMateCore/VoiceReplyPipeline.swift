import Foundation

/// The result of one user turn after the server-side LLM and voice gateway.
public struct VoiceReply: Equatable, Sendable {
    public let text: String
    public let audio: Data

    public init(text: String, audio: Data) {
        self.text = text
        self.audio = audio
    }
}

public enum VoiceReplyPipelineError: Error, Equatable, Sendable, LocalizedError {
    case emptyReply
    case incompleteReply
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .emptyReply:
            return "The AI gateway returned no reply."
        case .incompleteReply:
            return "The AI gateway returned an incomplete reply."
        case .cancelled:
            return "The AI reply was cancelled."
        }
    }
}

/// Joins one transcript to the active conversation, then runs the real LLM and TTS seams.
/// Provider credentials remain behind the injected app-facing gateway clients.
public final class VoiceReplyPipeline {
    private let llm: any LLMClient
    private let tts: any TTSService
    private let maxContextMessages: Int

    public init(llm: any LLMClient, tts: any TTSService, maxContextMessages: Int = 20) {
        precondition(maxContextMessages >= 2)
        self.llm = llm
        self.tts = tts
        self.maxContextMessages = maxContextMessages
    }

    public func reply(
        to transcript: String,
        history: [LLMMessage],
        voice: VoiceConfiguration,
        model: LLMModel,
        reasoningEffort: LLMReasoningEffort,
        maxTokens: Int? = nil
    ) async throws -> VoiceReply {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else { throw VoiceReplyPipelineError.emptyReply }
        do {
            try Task.checkCancellation()
            var messages = boundedContext(from: history)
            messages.append(LLMMessage(role: .user, content: cleanedTranscript))
            var text = ""
            var didFinish = false
            for try await event in llm.streamChat(
                messages: messages,
                model: model,
                reasoningEffort: reasoningEffort,
                maxTokens: maxTokens
            ) {
                try Task.checkCancellation()
                switch event {
                case let .text(fragment):
                    guard !didFinish else { continue }
                    text.append(fragment)
                case .done:
                    didFinish = true
                }
            }
            let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard didFinish else { throw VoiceReplyPipelineError.incompleteReply }
            guard !cleanedText.isEmpty else { throw VoiceReplyPipelineError.emptyReply }
            try Task.checkCancellation()
            let audio = try await tts.synthesize(text: cleanedText, voice: voice)
            try Task.checkCancellation()
            guard !audio.isEmpty else { throw VoiceReplyPipelineError.emptyReply }
            return VoiceReply(text: cleanedText, audio: audio)
        } catch is CancellationError {
            throw VoiceReplyPipelineError.cancelled
        }
    }

    private func boundedContext(from history: [LLMMessage]) -> [LLMMessage] {
        guard history.count >= maxContextMessages else { return history }
        let systemMessage = history.first.flatMap { $0.role == .system ? $0 : nil }
        let remainingHistory = systemMessage == nil ? history : Array(history.dropFirst())
        let tailBudget = maxContextMessages - (systemMessage == nil ? 1 : 2)
        let tail = Array(remainingHistory.suffix(max(0, tailBudget)))
        var bounded: [LLMMessage] = []
        if let systemMessage { bounded.append(systemMessage) }
        bounded.append(contentsOf: tail)
        return bounded
    }
}

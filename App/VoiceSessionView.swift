import AVFoundation
import Speech
import SwiftUI
import SleepMateCore


private struct SleepMateGatewayConfiguration {
    let baseURL: URL
    let token: String
    let voice: VoiceConfiguration
    let model: LLMModel
    let reasoningEffort: LLMReasoningEffort

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        voiceIDOverride: String? = nil
    ) -> Self? {
        guard
            let rawURL = environment["SLEEPMATE_GATEWAY_URL"],
            let baseURL = URL(string: rawURL),
            baseURL.scheme != nil,
            baseURL.host != nil,
            let token = environment["SLEEPMATE_GATEWAY_TOKEN"],
            !token.isEmpty
        else { return nil }

        let requestedVoiceID = voiceIDOverride ?? environment["SLEEPMATE_VOICE_ID"] ?? VoiceConfiguration.defaultStock.reference
        let voiceID = requestedVoiceID.hasPrefix("voice://stock")
            ? VoiceConfiguration.defaultStock.reference
            : requestedVoiceID
        guard !voiceID.isEmpty,
              voiceID.count <= 200,
              voiceID.trimmingCharacters(in: .whitespacesAndNewlines) == voiceID,
              !voiceID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }

        let model: LLMModel
        switch environment["SLEEPMATE_LLM_MODEL"] {
        case nil, LLMModel.gpt56Sol.rawValue:
            model = .gpt56Sol
        case LLMModel.gpt56Terra.rawValue:
            model = .gpt56Terra
        default:
            return nil
        }
        let reasoningEffort: LLMReasoningEffort
        switch environment["SLEEPMATE_LLM_REASONING"] {
        case nil, LLMReasoningEffort.medium.rawValue:
            reasoningEffort = .medium
        case LLMReasoningEffort.high.rawValue:
            reasoningEffort = .high
        case LLMReasoningEffort.xhigh.rawValue:
            // xhigh is reserved for profiling/summaries, not live dialogue.
            return nil
        default:
            return nil
        }
        return Self(
            baseURL: baseURL,
            token: token,
            voice: BuiltInVoicePreset.configuration(for: voiceID),
            model: model,
            reasoningEffort: reasoningEffort
        )
    }

    func makeFriendContextAnalysisPipeline() -> FriendContextAnalysisPipeline {
        let llmEndpoint = baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("llm")
            .appendingPathComponent("chat")
        return FriendContextAnalysisPipeline(
            llm: OpenAINextGatewayClient(gatewayEndpoint: llmEndpoint, gatewayToken: token),
            model: model
        )
    }

    func makeReplyPipeline() -> VoiceReplyPipeline {
        let llmEndpoint = baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("llm")
            .appendingPathComponent("chat")
        return VoiceReplyPipeline(
            llm: OpenAINextGatewayClient(gatewayEndpoint: llmEndpoint, gatewayToken: token),
            tts: MiniMaxGatewayTTSService(baseURL: baseURL, gatewayToken: token)
        )
    }
}

private enum VoiceSessionConfigurationError: Error, LocalizedError {
    case gatewayUnavailable

    var errorDescription: String? {
        String(localized: "ai_friend.gateway_unavailable")
    }
}

private enum VoiceLocale {
    static var preferredLanguage: String {
        Locale.preferredLanguages.first ?? "zh-Hans"
    }

    static var speechLanguageIdentifier: String {
        preferredLanguage.hasPrefix("en") ? "en-US" : "zh-CN"
    }
}
private final class LiveSpeechAudioSession: NSObject, @unchecked Sendable, AudioSession, AVAudioPlayerDelegate {
    private let audioEngine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayer?
    private let recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isTapInstalled = false
    private var isFinishingUtterance = false
    private var recognitionGeneration = 0
    private let analysisQueue = DispatchQueue(label: "com.sleepmate.voice-analysis")
    private var voiceActivityDetector = VoiceActivityDetector()

    var onSpeechStarted: (() -> Void)?
    var onSpeechEnded: (() -> Void)?
    var onTranscript: ((String, Bool) -> Void)?
    var onPlaybackFinished: (() -> Void)?
    var onError: ((String) -> Void)?

    var isListening: Bool { audioEngine.isRunning }

    override init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: VoiceLocale.speechLanguageIdentifier))
        super.init()
    }

    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let session = AVAudioApplication.shared
        switch session.recordPermission {
        case .granted:
            DispatchQueue.main.async { completion(true) }
        case .denied:
            DispatchQueue.main.async { completion(false) }
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        @unknown default:
            DispatchQueue.main.async { completion(false) }
        }
    }

    func requestSpeechPermissionAndStart(completion: @escaping (Bool) -> Void) {
        requestMicrophonePermission { [weak self] microphoneGranted in
            guard microphoneGranted else {
                completion(false)
                return
            }
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard status == .authorized else {
                        completion(false)
                        return
                    }
                    do {
                        try self.startListening()
                        completion(true)
                    } catch {
                        self.onError?(error.localizedDescription)
                        completion(false)
                    }
                }
            }
        }
    }

    func startListening() throws {
        guard !audioEngine.isRunning else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw LiveSpeechError.recognizerUnavailable
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        analysisQueue.sync {
            voiceActivityDetector = VoiceActivityDetector()
        }
        recognitionGeneration += 1
        let generation = recognitionGeneration
        isFinishingUtterance = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        if isTapInstalled {
            inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let level = Self.rmsLevel(in: buffer)
            let observation = self.analysisQueue.sync {
                self.voiceActivityDetector.observeActivity(rmsLevel: level)
            }

            switch observation {
            case .speechStarted, .speechContinues, .speechSilence:
                request.append(buffer)
            case .calibrating, .silence, .speechEnded:
                break
            }

            switch observation {
            case .speechStarted:
                DispatchQueue.main.async { [weak self] in
                    self?.onSpeechStarted?()
                }
            case .speechEnded:
                DispatchQueue.main.async { [weak self] in
                    self?.finishCurrentUtterance()
                }
            default:
                break
            }
        }
        isTapInstalled = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.recognitionGeneration == generation else { return }
                    let text = result.bestTranscription.formattedString
                    self.onTranscript?(text, result.isFinal)
                    if result.isFinal {
                        self.isFinishingUtterance = false
                        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.onSpeechEnded?()
                        }
                    }
                }
            }
            if let error {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.recognitionGeneration == generation else { return }
                    let wasFinishingUtterance = self.isFinishingUtterance
                    self.isFinishingUtterance = false
                    if wasFinishingUtterance {
                        self.onSpeechEnded?()
                    } else if self.audioEngine.isRunning {
                        self.onError?(error.localizedDescription)
                    }
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stopListening(deactivateSession: true)
            throw error
        }
    }

    private func finishCurrentUtterance() {
        guard audioEngine.isRunning, !isFinishingUtterance else { return }
        isFinishingUtterance = true
        audioEngine.stop()
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        recognitionRequest?.endAudio()
        let generation = recognitionGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self,
                  self.recognitionGeneration == generation,
                  self.isFinishingUtterance else { return }
            self.isFinishingUtterance = false
            self.onSpeechEnded?()
        }
    }

    func pauseListening() {
        stopListening(deactivateSession: false)
    }

    func resumeListening() {
        guard !audioEngine.isRunning else { return }
        do {
            try startListening()
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func end() {
        stopListening(deactivateSession: true)
        stopPlayback()
    }

    func stopListening(deactivateSession: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        isFinishingUtterance = false
        recognitionGeneration += 1
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    @discardableResult
    func play(audio: Data) -> Bool {
        stopPlayback()
        do {
            let player = try AVAudioPlayer(data: audio)
            player.delegate = self
            audioPlayer = player
            guard player.play() else {
                audioPlayer = nil
                onError?(String(localized: "voice_session.playback_error"))
                return false
            }
            return true
        } catch {
            audioPlayer = nil
            onError?(String(localized: "voice_session.playback_error"))
            return false
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard audioPlayer === player else { return }
        audioPlayer = nil
        guard flag else {
            DispatchQueue.main.async { [weak self] in
                self?.onError?(String(localized: "voice_session.playback_error"))
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onPlaybackFinished?()
        }
    }

    private static func rmsLevel(in buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = channelData[0][index]
            sum += sample * sample
        }
        return sqrt(sum / Float(frameCount))
    }
}

private enum LiveSpeechError: LocalizedError {
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return String(localized: "voice_session.recognizer_unavailable")
        }
    }
}

@MainActor
final class VoiceSessionViewModel: NSObject, ObservableObject {
    @Published private(set) var state: VoiceSessionState = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var response = ""
    @Published private(set) var errorMessage = ""
    @Published private(set) var responseWasInterrupted = false

    private var coordinator = VoiceSessionCoordinator()
    private let audio = LiveSpeechAudioSession()
    private var replyPipeline: VoiceReplyPipeline?
    private var voiceConfiguration: VoiceConfiguration
    private var model: LLMModel
    private var reasoningEffort: LLMReasoningEffort
    private weak var gatewaySettings: GatewaySettings?
    @Published private(set) var friendName = "AI Friend"
    @Published private(set) var persistedFriends: [StoredAIFriend] = []
    private var friendContext = ""
    private var friendID: UUID?
    @Published private(set) var friendReady = false
    private var replyTask: Task<Void, Never>?
    private var pendingAudio: Data?
    private var pendingConversationAssistant: String?
    private var conversation: [LLMMessage] = []
    private var latestTranscript = ""
    private var lastRespondedTranscript = ""
    private let friendRepository: any AIFriendRepository

    override convenience init() {
        self.init(gatewaySettings: nil)
    }

    convenience init(gatewaySettings: GatewaySettings?) {
        let saved = gatewaySettings?.configuration
        let environmentConfiguration = SleepMateGatewayConfiguration.current()
        let configuration = saved.map {
            SleepMateGatewayConfiguration(
                baseURL: $0.baseURL,
                token: $0.appToken,
                voice: BuiltInVoicePreset.configuration(
                    for: ProcessInfo.processInfo.environment["SLEEPMATE_VOICE_ID"] ?? VoiceConfiguration.defaultStock.reference
                ),
                model: Self.model(from: ProcessInfo.processInfo.environment["SLEEPMATE_LLM_MODEL"]),
                reasoningEffort: Self.reasoning(from: ProcessInfo.processInfo.environment["SLEEPMATE_LLM_REASONING"])
            )
        } ?? environmentConfiguration
        let repository = try? FileAIFriendRepository(fileURL: Self.defaultFriendStoreURL)
        self.init(
            replyPipeline: configuration?.makeReplyPipeline(),
            voiceConfiguration: configuration?.voice ?? .defaultStock,
            model: configuration?.model ?? .gpt56Sol,
            reasoningEffort: configuration?.reasoningEffort ?? .medium,
            friendRepository: repository ?? InMemoryAIFriendRepository(),
            gatewaySettings: gatewaySettings
        )
    }

    init(
        replyPipeline: VoiceReplyPipeline?,
        voiceConfiguration: VoiceConfiguration,
        model: LLMModel,
        reasoningEffort: LLMReasoningEffort,
        friendRepository: any AIFriendRepository = InMemoryAIFriendRepository(),
        gatewaySettings: GatewaySettings? = nil
    ) {
        self.replyPipeline = replyPipeline
        self.voiceConfiguration = voiceConfiguration
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.friendRepository = friendRepository
        self.gatewaySettings = gatewaySettings
        super.init()
        reloadPersistedFriends()
        restorePersistedFriend()
        audio.onSpeechStarted = { [weak self] in
            Task { @MainActor in self?.receiveSpeechStarted() }
        }
        audio.onSpeechEnded = { [weak self] in
            Task { @MainActor in self?.receiveSpeechEnded() }
        }
        audio.onTranscript = { [weak self] text, isFinal in
            Task { @MainActor in self?.receiveTranscript(text, isFinal: isFinal) }
        }
        audio.onPlaybackFinished = { [weak self] in
            Task { @MainActor in self?.handle(.playbackFinished) }
        }
        audio.onError = { [weak self] message in
            Task { @MainActor in self?.errorMessage = message }
        }
    }

    private func normalizedVoice(_ reference: String) -> VoiceConfiguration {
        BuiltInVoicePreset.configuration(for: reference)
    }

    private static func model(from rawValue: String?) -> LLMModel {
        rawValue == LLMModel.gpt56Terra.rawValue ? .gpt56Terra : .gpt56Sol
    }

    private static func reasoning(from rawValue: String?) -> LLMReasoningEffort {
        rawValue == LLMReasoningEffort.high.rawValue ? .high : .medium
    }

    private func currentGatewayConfiguration(voiceIDOverride: String? = nil) -> SleepMateGatewayConfiguration? {
        if let configured = gatewaySettings?.configuration {
            return SleepMateGatewayConfiguration(
                baseURL: configured.baseURL,
                token: configured.appToken,
                voice: normalizedVoice(voiceIDOverride ?? ProcessInfo.processInfo.environment["SLEEPMATE_VOICE_ID"] ?? VoiceConfiguration.defaultStock.reference),
                model: Self.model(from: ProcessInfo.processInfo.environment["SLEEPMATE_LLM_MODEL"]),
                reasoningEffort: Self.reasoning(from: ProcessInfo.processInfo.environment["SLEEPMATE_LLM_REASONING"])
            )
        }
        return SleepMateGatewayConfiguration.current(voiceIDOverride: voiceIDOverride)
    }

    private func reloadPersistedFriends() {
        persistedFriends = (try? friendRepository.loadAll()) ?? []
    }

    func beginFriendSetup() {
        replyTask?.cancel()
        pendingAudio = nil
        pendingConversationAssistant = nil
        conversation.removeAll()
        response = ""
        transcript = ""
        errorMessage = ""
        friendReady = false
        friendID = nil
    }

    func configureFriend(name: String, voice: VoiceConfiguration, context: String) -> Bool {
        guard let configuration = currentGatewayConfiguration(voiceIDOverride: voice.reference) else {
            return false
        }
        replyPipeline = configuration.makeReplyPipeline()
        voiceConfiguration = voice
        model = configuration.model
        reasoningEffort = configuration.reasoningEffort
        friendName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "AI Friend" : name.trimmingCharacters(in: .whitespacesAndNewlines)
        friendContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        friendReady = true
        let stored = StoredAIFriend(
            id: friendID ?? UUID(),
            name: friendName,
            reviewedProfile: friendContext,
            voiceReference: voice.reference,
            createdAt: Date()
        )
        friendID = stored.id
        do {
            try friendRepository.save(stored)
            reloadPersistedFriends()
        } catch {
            errorMessage = String(localized: "ai_friend.persistence_error")
            return false
        }
        return true
    }

    private static var defaultFriendStoreURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent("SleepMate/friends.json")
    }

    private func restorePersistedFriend() {
        guard let stored = persistedFriends.first,
              let configuration = currentGatewayConfiguration(voiceIDOverride: stored.voiceReference) else { return }
        replyPipeline = configuration.makeReplyPipeline()
        voiceConfiguration = normalizedVoice(stored.voiceReference)
        model = configuration.model
        reasoningEffort = configuration.reasoningEffort
        friendID = stored.id
        friendName = stored.name
        friendContext = stored.reviewedProfile
        friendReady = true
    }

    func configureFriendUsingEnvironment(name: String, context: String) -> Bool {
        guard let configuration = currentGatewayConfiguration() else { return false }
        return configureFriend(name: name, voice: configuration.voice, context: context)
    }

    func analyzeFriendContext(_ sourceText: String, friendName: String) async throws -> FriendContextAnalysis {
        guard let configuration = currentGatewayConfiguration(voiceIDOverride: "analysis-only") else {
            throw VoiceSessionConfigurationError.gatewayUnavailable
        }
        return try await configuration.makeFriendContextAnalysisPipeline().analyze(sourceText, friendName: friendName)
    }

    func cloneVoice(source: AuthorizedVoiceSource) async throws -> VoiceConfiguration {
        guard let configuration = currentGatewayConfiguration(voiceIDOverride: "pending-voice") else {
            throw VoiceSessionConfigurationError.gatewayUnavailable
        }
        let client = MiniMaxGatewayVoiceCloneClient(
            baseURL: configuration.baseURL,
            gatewayToken: configuration.token
        )
        let requestedVoiceID = "sleepmate-\(UUID().uuidString.lowercased())"
        return try await client.clone(source: source, requestedVoiceId: requestedVoiceID)
    }


    @discardableResult
    func activateFriend(id: UUID) -> Bool {
        guard let friend = persistedFriends.first(where: { $0.id == id }) else { return false }
        return activateFriendRecord(friend)
    }

    @discardableResult
    private func activateFriendRecord(_ friend: StoredAIFriend) -> Bool {
        guard let configuration = currentGatewayConfiguration(voiceIDOverride: friend.voiceReference) else {
            return false
        }
        replyPipeline = configuration.makeReplyPipeline()
        voiceConfiguration = normalizedVoice(friend.voiceReference)
        model = configuration.model
        reasoningEffort = configuration.reasoningEffort
        friendID = friend.id
        friendName = friend.name
        friendContext = friend.reviewedProfile
        friendReady = true
        return true
    }

    func bindVoice(_ voice: VoiceConfiguration, to friendID: UUID) throws -> StoredAIFriend {
        let friend = try friendRepository.bindVoice(voice.reference, to: friendID)
        reloadPersistedFriends()
        guard self.friendID == friendID else { return friend }
        guard activateFriendRecord(friend) else {
            replyPipeline = nil
            voiceConfiguration = normalizedVoice(friend.voiceReference)
            friendReady = false
            throw VoiceSessionConfigurationError.gatewayUnavailable
        }
        return friend
    }

    func bindClonedVoice(_ voice: VoiceConfiguration, to friendID: UUID) throws -> StoredAIFriend {
        try bindVoice(voice, to: friendID)
    }

    deinit {
        replyTask?.cancel()
        audio.end()
    }

    func start() {
        errorMessage = ""
        replyTask?.cancel()
        pendingAudio = nil
        pendingConversationAssistant = nil
        conversation.removeAll()
        if !friendContext.isEmpty {
            conversation.append(LLMMessage(role: .system, content: friendContext))
        }
        latestTranscript = ""
        lastRespondedTranscript = ""
        transcript = ""
        response = ""
        responseWasInterrupted = false
        audio.requestSpeechPermissionAndStart { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.errorMessage = String(localized: "voice_session.permission_error")
                return
            }
            if self.coordinator.state == .ended {
                self.coordinator = VoiceSessionCoordinator()
            }
            self.transition(.start)
        }
    }

    func pause() {
        handle(.pause)
    }

    func resume() {
        transition(.resume)
    }

    func end() {
        handle(.end)
    }

    var stateLabel: String {
        switch state {
        case .idle: return String(localized: "voice_session.state.starting")
        case .listening: return String(localized: "voice_session.state.listening")
        case .processing: return String(localized: "voice_session.state.processing")
        case .speaking: return String(localized: "voice_session.state.speaking")
        case .paused: return String(localized: "voice_session.state.paused")
        case .ended: return String(localized: "voice_session.state.ended")
        }
    }

    var microphoneStatusLabel: String {
        switch state {
        case .listening, .speaking: return String(localized: "voice_session.microphone.active")
        case .processing: return String(localized: "voice_session.microphone.processing")
        case .paused: return String(localized: "voice_session.microphone.paused")
        case .idle, .ended: return String(localized: "voice_session.microphone.inactive")
        }
    }

    var gatewayStatusLabel: String {
        replyPipeline == nil
            ? String(localized: "voice_session.network.local")
            : String(localized: "voice_session.network.connected")
    }

    var gatewayStatusIcon: String {
        replyPipeline == nil ? "network.slash" : "network"
    }

    var modelStatusLabel: String {
        "\(model.rawValue) · \(reasoningEffort.rawValue)"
    }

    private func receiveSpeechStarted() {
        if coordinator.state == .speaking {
            handle(.userSpeechStarted)
        }
        guard coordinator.state == .listening else { return }
        latestTranscript = ""
        lastRespondedTranscript = ""
    }

    private func receiveSpeechEnded() {
        guard coordinator.state == .listening else { return }
        if latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            audio.resumeListening()
        } else {
            respondIfNeeded()
        }
    }

    private func receiveTranscript(_ text: String, isFinal: Bool) {
        guard coordinator.state == .listening else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        transcript = cleaned
        latestTranscript = cleaned
        if isFinal {
            respondIfNeeded()
        }
    }

    private func respondIfNeeded() {
        guard coordinator.state == .listening else { return }
        let text = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != lastRespondedTranscript else { return }
        guard let replyPipeline else {
            errorMessage = String(localized: "voice_session.gateway_unavailable")
            return
        }

        lastRespondedTranscript = text
        transition(.responseRequested)
        replyTask?.cancel()
        let history = conversation
        let voiceConfiguration = self.voiceConfiguration
        let model = self.model
        let reasoningEffort = self.reasoningEffort
        replyTask = Task { [weak self, replyPipeline, voiceConfiguration, model, reasoningEffort] in
            do {
                let reply = try await replyPipeline.reply(
                    to: text,
                    history: history,
                    voice: voiceConfiguration,
                    model: model,
                    reasoningEffort: reasoningEffort
                )
                guard !Task.isCancelled else { return }
                Task { @MainActor [weak self] in
                    self?.completeReply(reply, for: text)
                }
            } catch {
                guard !Task.isCancelled else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
                    if let pipelineError = error as? VoiceReplyPipelineError, pipelineError == .cancelled { return }
                    self.errorMessage = error.localizedDescription
                    self.transition(.responseFailed)
                }
            }
        }
    }

    private func completeReply(_ reply: VoiceReply, for userText: String) {
        guard coordinator.state == .processing,
              latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines) == userText,
              !reply.audio.isEmpty else { return }
        conversation.append(LLMMessage(role: .user, content: userText))
        pendingConversationAssistant = reply.text
        pendingAudio = reply.audio
        transition(.responseReady(reply.text))
    }

    private func handle(_ event: VoiceSessionEvent) {
        switch event {
        case .userSpeechStarted, .pause, .end:
            replyTask?.cancel()
            pendingAudio = nil
            if coordinator.state == .speaking {
                // The generated text remains visible but is not promoted to the next context as a completed turn.
                pendingConversationAssistant = nil
            }
        case .playbackFinished:
            if let assistantText = pendingConversationAssistant {
                conversation.append(LLMMessage(role: .assistant, content: assistantText))
                pendingConversationAssistant = nil
            }
        default:
            break
        }
        transition(event)
    }

    private func transition(_ event: VoiceSessionEvent) {
        if coordinator.state == .speaking {
            switch event {
            case .userSpeechStarted, .pause, .end:
                responseWasInterrupted = true
            default:
                break
            }
        }
        apply(coordinator.handle(event))
    }

    private func apply(_ effects: [VoiceSessionEffect]) {
        for effect in effects {
            switch effect {
            case .listeningStarted:
                state = .listening
            case .listeningStoppedForResponse:
                state = .processing
                audio.pauseListening()
            case let .startPlayback(text):
                response = text
                responseWasInterrupted = false
                state = .speaking
                // Resume VAD during playback so user speech can still interrupt the AI voice.
                audio.resumeListening()
                guard let audioData = pendingAudio else {
                    errorMessage = String(localized: "voice_session.playback_error")
                    apply(coordinator.handle(.playbackFinished))
                    return
                }
                pendingAudio = nil
                if !audio.play(audio: audioData) {
                    pendingConversationAssistant = nil
                    transition(.playbackFinished)
                }
            case .stopPlayback:
                audio.stopPlayback()
            case .listeningResumed:
                state = .listening
                audio.resumeListening()
            case .listeningPaused:
                state = .paused
                audio.pauseListening()
            case .sessionEnded:
                state = .ended
                audio.end()
            }
        }
    }
}

struct VoiceSessionView: View {
    @ObservedObject var session: VoiceSessionViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "ai_friend.badge"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.tint.opacity(0.12), in: Capsule())

            Image(systemName: session.state == .listening ? "waveform.circle.fill" : "waveform.circle")
                .font(.system(size: 56))
                .foregroundStyle(session.state == .listening ? Color.accentColor : Color.secondary)
                .accessibilityLabel(String(localized: "voice_session.status"))

            Text(session.friendName)
                .font(.headline)

            Text(session.stateLabel)
                .font(.title3.weight(.medium))
                .accessibilityIdentifier("voice-session-state")

            HStack(spacing: 12) {
                Label(session.microphoneStatusLabel, systemImage: "mic.fill")
                Label(session.gatewayStatusLabel, systemImage: session.gatewayStatusIcon)
                Label(session.modelStatusLabel, systemImage: "cpu")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("voice-session-device-status")

            if !session.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "voice_session.transcript"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(session.transcript)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }

            if !session.response.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: session.responseWasInterrupted ? "voice_session.response_interrupted" : "voice_session.response"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(session.response)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }

            if !session.errorMessage.isEmpty {
                Text(session.errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                if session.state == .ended || (session.state == .idle && !session.errorMessage.isEmpty) {
                    Button(String(localized: session.state == .ended ? "voice_session.restart" : "voice_session.retry")) {
                        session.start()
                    }
                    .buttonStyle(.borderedProminent)
                }
                if session.state == .listening || session.state == .speaking {
                    Button(String(localized: "voice_session.pause")) {
                        session.pause()
                    }
                    .buttonStyle(.bordered)
                }
                if session.state == .paused {
                    Button(String(localized: "voice_session.resume")) {
                        session.resume()
                    }
                    .buttonStyle(.borderedProminent)
                }
                if session.state != .idle && session.state != .ended {
                    Button(String(localized: "voice_session.end")) {
                        session.end()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text(String(localized: "voice_session.local_notice"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(String(localized: "voice_session.title"))
        .onAppear {
            if session.state == .idle || session.state == .ended {
                session.start()
            }
        }
    }
}

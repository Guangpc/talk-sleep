import AVFoundation
import Speech
import SwiftUI
import SleepMateCore


private enum VoiceLocale {
    static var preferredLanguage: String {
        Locale.preferredLanguages.first ?? "zh-Hans"
    }

    static var speechLanguageIdentifier: String {
        preferredLanguage.hasPrefix("en") ? "en-US" : "zh-CN"
    }
}
private final class LiveSpeechAudioSession: NSObject, @unchecked Sendable, AudioSession, AVSpeechSynthesizerDelegate {
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let analysisQueue = DispatchQueue(label: "com.sleepmate.voice-analysis")
    private var voiceActivityDetector = VoiceActivityDetector()

    var onSpeechStarted: (() -> Void)?
    var onTranscript: ((String, Bool) -> Void)?
    var onPlaybackFinished: (() -> Void)?
    var onError: ((String) -> Void)?

    var isListening: Bool { audioEngine.isRunning }

    override init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: VoiceLocale.speechLanguageIdentifier))
        super.init()
        synthesizer.delegate = self
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

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
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

            if observation == .speechStarted {
                DispatchQueue.main.async { [weak self] in
                    self?.onSpeechStarted?()
                }
            }
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                DispatchQueue.main.async { [weak self] in
                    self?.onTranscript?(result.bestTranscription.formattedString, result.isFinal)
                }
            }
            if let error {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.audioEngine.isRunning else { return }
                    self.onError?(error.localizedDescription)
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
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func speak(_ text: String) {
        stopPlayback()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: VoiceLocale.speechLanguageIdentifier)
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }

    func stopPlayback() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
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

final class VoiceSessionViewModel: NSObject, ObservableObject {
    @Published private(set) var state: VoiceSessionState = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var response = ""
    @Published private(set) var errorMessage = ""
    @Published private(set) var responseWasInterrupted = false

    private var coordinator = VoiceSessionCoordinator()
    private let audio = LiveSpeechAudioSession()
    private var responseTimer: Timer?
    private var latestTranscript = ""
    private var lastRespondedTranscript = ""

    override init() {
        super.init()
        audio.onSpeechStarted = { [weak self] in
            self?.handle(.userSpeechStarted)
        }
        audio.onTranscript = { [weak self] text, isFinal in
            self?.receiveTranscript(text, isFinal: isFinal)
        }
        audio.onPlaybackFinished = { [weak self] in
            self?.handle(.playbackFinished)
        }
        audio.onError = { [weak self] message in
            self?.errorMessage = message
        }
    }

    deinit {
        responseTimer?.invalidate()
        audio.end()
    }

    func start() {
        errorMessage = ""
        responseTimer?.invalidate()
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
        transition(.pause)
    }

    func resume() {
        transition(.resume)
    }

    func end() {
        responseTimer?.invalidate()
        transition(.end)
    }

    var stateLabel: String {
        switch state {
        case .idle: return String(localized: "voice_session.state.starting")
        case .listening: return String(localized: "voice_session.state.listening")
        case .speaking: return String(localized: "voice_session.state.speaking")
        case .paused: return String(localized: "voice_session.state.paused")
        case .ended: return String(localized: "voice_session.state.ended")
        }
    }

    var microphoneStatusLabel: String {
        switch state {
        case .listening, .speaking: return String(localized: "voice_session.microphone.active")
        case .paused: return String(localized: "voice_session.microphone.paused")
        case .idle, .ended: return String(localized: "voice_session.microphone.inactive")
        }
    }

    private func receiveTranscript(_ text: String, isFinal: Bool) {
        guard !text.isEmpty else { return }
        transcript = text
        latestTranscript = text
        responseTimer?.invalidate()
        let delay: TimeInterval = isFinal ? 0.2 : 1.2
        responseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.respondIfNeeded()
        }
    }

    private func respondIfNeeded() {
        guard coordinator.state == .listening else { return }
        let text = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != lastRespondedTranscript else { return }
        lastRespondedTranscript = text
        let format = String(localized: "voice_session.demo_response_format")
        let localResponse = String(format: format, locale: .current, text)
        transition(.responseReady(localResponse))
    }

    private func handle(_ event: VoiceSessionEvent) {
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
            case let .startPlayback(text):
                response = text
                responseWasInterrupted = false
                state = .speaking
                audio.speak(text)
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

            Text(String(localized: "voice_session.friend_name"))
                .font(.headline)

            Text(session.stateLabel)
                .font(.title3.weight(.medium))
                .accessibilityIdentifier("voice-session-state")

            HStack(spacing: 12) {
                Label(session.microphoneStatusLabel, systemImage: "mic.fill")
                Label(String(localized: "voice_session.network.local"), systemImage: "network.slash")
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

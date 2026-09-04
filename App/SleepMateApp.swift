import AVFoundation
import SwiftUI
import SleepMateCore
import UniformTypeIdentifiers

@main
struct SleepMateApp: App {
    @StateObject private var gatewaySettings: GatewaySettings
    @StateObject private var session: VoiceSessionViewModel

    init() {
        let settings = GatewaySettings()
        _gatewaySettings = StateObject(wrappedValue: settings)
        _session = StateObject(wrappedValue: VoiceSessionViewModel(gatewaySettings: settings))
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(session: session, gatewaySettings: gatewaySettings)
        }
    }
}

private struct MainTabView: View {
    @ObservedObject var session: VoiceSessionViewModel
    @ObservedObject var gatewaySettings: GatewaySettings
    @State private var selectedTab: AppTab = .text

    var body: some View {
        TabView(selection: $selectedTab) {
            TextFriendWorkspace(session: session, gatewaySettings: gatewaySettings)
                .tabItem { Label("文字与文件", systemImage: "doc.text") }
                .tag(AppTab.text)
                .accessibilityIdentifier("text-file-tab")

            VoiceFriendWorkspace(session: session, onCreateFriend: { selectedTab = .text })
                .tabItem { Label("朋友语音", systemImage: "waveform") }
                .tag(AppTab.voice)
                .accessibilityIdentifier("voice-tab")
        }
        .tint(.indigo)
    }
}

private enum AppTab: Hashable {
    case text
    case voice
}

private struct TextFriendWorkspace: View {
    @ObservedObject var session: VoiceSessionViewModel
    @ObservedObject var gatewaySettings: GatewaySettings

    var body: some View {
        FriendListView(session: session, gatewaySettings: gatewaySettings)
    }
}

private struct VoiceFriendWorkspace: View {
    @ObservedObject var session: VoiceSessionViewModel
    let onCreateFriend: () -> Void
    @StateObject private var voiceRecorder = FriendVoiceRecorder()
    @State private var selectedFriendID: UUID?
    @State private var selectedAudio: PendingVoiceAudio?
    @State private var consentConfirmed = false
    @State private var isImportingAudio = false
    @State private var isBinding = false
    @State private var bindingTask: Task<Void, Never>?
    @State private var operationID = UUID()
    @State private var status = ""
    @State private var error = ""

    private let validator = AuthorizedVoiceSourceValidator()
    private let supportedAudioTypes = ["mp3", "m4a", "wav"].compactMap {
        UTType(filenameExtension: $0, conformingTo: .audio)
    }

    private var selectedFriend: StoredAIFriend? {
        guard let selectedFriendID else { return nil }
        return session.persistedFriends.first { $0.id == selectedFriendID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "voice_setup.title"))
                            .font(.largeTitle.bold())
                        Text(String(localized: "voice_setup.subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if session.persistedFriends.isEmpty {
                        ContentUnavailableView(
                            String(localized: "voice_setup.no_friends"),
                            systemImage: "person.2",
                            description: Text(String(localized: "voice_setup.no_friends_hint"))
                        )
                        Button(String(localized: "voice_setup.go_to_text"), action: onCreateFriend)
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                    } else {
                        friendPicker
                    }

                    if let selectedFriend {
                        voicePicker(for: selectedFriend)
                    }

                    if !status.isEmpty {
                        Label(status, systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                    if !error.isEmpty {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .navigationTitle(String(localized: "voice_setup.title"))
        }
    }

    private var friendPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "voice_setup.choose_friend"))
                .font(.headline)
            ForEach(session.persistedFriends) { friend in
                Button {
                    bindingTask?.cancel()
                    voiceRecorder.cancel()
                    operationID = UUID()
                    isBinding = false
                    selectedFriendID = friend.id
                    _ = session.activateFriend(id: friend.id)
                    selectedAudio = nil
                    consentConfirmed = false
                    status = ""
                    error = ""
                } label: {
                    HStack {
                        Image(systemName: selectedFriendID == friend.id ? "checkmark.circle.fill" : "circle")
                        VStack(alignment: .leading) {
                            Text(friend.name).font(.headline)
                            Text(friend.voiceReference)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(14)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("voice-friend-\(friend.id.uuidString)")
            }
        }
    }

    private func voicePicker(for friend: StoredAIFriend) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(format: String(localized: "voice_setup.selected_friend"), friend.name), systemImage: "person.crop.circle.badge.checkmark")
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 10) {
                Label(String(localized: "voice_setup.builtin_section"), systemImage: "person.wave.2")
                    .font(.headline)
                Text(String(localized: "voice_setup.builtin_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(BuiltInVoicePreset.chineseFemaleChoices) { preset in
                    builtInVoiceRow(preset, friend: friend)
                }
            }

            Divider()

            Text(String(localized: "voice_setup.custom_voice_section"))
                .font(.headline)

            Button {
                error = ""
                isImportingAudio = true
            } label: {
                Label(
                    String(localized: selectedAudio == nil ? "voice_setup.choose_audio" : "voice_setup.replace_audio"),
                    systemImage: "waveform.badge.plus"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(voiceRecorder.isRecording || isBinding)
            .accessibilityIdentifier("friend-audio-import-button")
            .fileImporter(
                isPresented: $isImportingAudio,
                allowedContentTypes: supportedAudioTypes,
                allowsMultipleSelection: false,
                onCompletion: importAudio
            )

            Button {
                toggleRecording()
            } label: {
                Label(
                    String(localized: voiceRecorder.isRecording ? "voice_setup.stop_recording" : "voice_setup.start_recording"),
                    systemImage: voiceRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(voiceRecorder.isRecording ? .red : .indigo)
            .controlSize(.large)
            .disabled(isBinding || voiceRecorder.isPreparing)
            .accessibilityIdentifier("friend-audio-record-button")

            if voiceRecorder.isRecording {
                Label(String(localized: "voice_setup.recording"), systemImage: "waveform")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let selectedAudio {
                Label(
                    String(format: String(localized: "voice_setup.audio_selected"), selectedAudio.filename, selectedAudio.durationSeconds),
                    systemImage: "doc.badge.waveform"
                )
                .font(.footnote)
            }

            Toggle(String(localized: "voice_setup.authorize"), isOn: $consentConfirmed)
                .disabled(selectedAudio == nil || isBinding || voiceRecorder.isRecording)
            Text(String(localized: "voice_setup.authorize_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                bindVoice(to: friend)
            } label: {
                if isBinding {
                    ProgressView()
                } else {
                    Label(String(localized: "voice_setup.bind"), systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedAudio == nil || !consentConfirmed || isBinding || voiceRecorder.isRecording)

            NavigationLink {
                VoiceSessionView(session: session)
            } label: {
                Label(String(localized: "voice_setup.start_session"), systemImage: "waveform")
            }
            .simultaneousGesture(TapGesture().onEnded { _ = session.activateFriend(id: friend.id) })

            if friend.voiceReference == VoiceConfiguration.defaultStock.reference || friend.voiceReference.hasPrefix("voice://stock") {
                Text(String(localized: "voice_setup.default_voice_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
    }

    private func builtInVoiceRow(_ preset: BuiltInVoicePreset, friend: StoredAIFriend) -> some View {
        let isSelected = friend.voiceReference == preset.voiceID
            || (preset.kind == .gentleWoman && friend.voiceReference.hasPrefix("voice://stock"))
        return Button {
            selectBuiltInVoice(preset, for: friend)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.localizedName).font(.headline)
                    Text(preset.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(preset.toneLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .disabled(isBinding || voiceRecorder.isRecording)
        .accessibilityIdentifier("builtin-voice-\(preset.kind.rawValue)")
    }

    private func selectBuiltInVoice(_ preset: BuiltInVoicePreset, for friend: StoredAIFriend) {
        error = ""
        do {
            _ = try session.bindVoice(preset.configuration, to: friend.id)
            selectedAudio = nil
            consentConfirmed = false
            status = String(format: String(localized: "voice_setup.builtin_selected"), preset.localizedName, friend.name)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggleRecording() {
        error = ""
        status = ""
        Task { @MainActor in
            do {
                if let recording = try await voiceRecorder.press() {
                    guard recording.durationSeconds >= AuthorizedVoiceSourceValidator.minimumCloneDuration,
                          recording.durationSeconds <= AuthorizedVoiceSourceValidator.maximumCloneDuration else {
                        throw AuthorizedVoiceSourceError.durationOutOfRange
                    }
                    guard recording.data.count <= AuthorizedVoiceSourceValidator.maximumAudioBytes else {
                        throw AuthorizedVoiceSourceError.audioTooLarge
                    }
                    selectedAudio = recording
                    operationID = UUID()
                    consentConfirmed = false
                    status = String(localized: "voice_setup.recording_ready")
                }
            } catch is CancellationError {
                voiceRecorder.cancel()
            } catch {
                voiceRecorder.cancel()
                self.error = error.localizedDescription
            }
        }
    }

    private func importAudio(_ result: Result<[URL], Error>) {
        switch result {
        case let .failure(error):
            if (error as NSError).code != NSUserCancelledError {
                self.error = String(localized: "ai_friend.audio_read_error")
            }
        case let .success(urls):
            guard let url = urls.first else { return }
            Task { @MainActor in
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                    if let fileSize = resourceValues.fileSize, fileSize > AuthorizedVoiceSourceValidator.maximumAudioBytes {
                        throw AuthorizedVoiceSourceError.audioTooLarge
                    }
                    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                    let duration = try await AVURLAsset(url: url).load(.duration).seconds
                    let localAudio = PendingVoiceAudio(data: data, filename: url.lastPathComponent, durationSeconds: duration)
                    selectedAudio = localAudio
                    operationID = UUID()
                    consentConfirmed = false
                    error = ""
                } catch let validationError as AuthorizedVoiceSourceError {
                    selectedAudio = nil
                    error = validationError.localizedDescription
                } catch let audioReadError {
                    selectedAudio = nil
                    self.error = String(localized: "ai_friend.audio_read_error")
                    _ = audioReadError
                }
            }
        }
    }

    private func bindVoice(to friend: StoredAIFriend) {
        guard let selectedAudio else { return }
        error = ""
        status = ""
        isBinding = true
        bindingTask?.cancel()
        let requestedFriendID = friend.id
        let requestedOperationID = UUID()
        operationID = requestedOperationID
        let requestedAudio = selectedAudio
        bindingTask = Task { @MainActor in
            defer {
                if selectedFriendID == requestedFriendID, operationID == requestedOperationID { isBinding = false }
            }
            do {
                let consent = VoiceCloneConsent(
                    authorized: consentConfirmed,
                    intendedUseAcknowledged: consentConfirmed,
                    cloudProcessingAcknowledged: consentConfirmed,
                    retentionAndDeletionAcknowledged: consentConfirmed,
                    acceptedAt: Date()
                )
                let source = try validator.validateCloneAudio(
                    data: selectedAudio.data,
                    filename: selectedAudio.filename,
                    durationSeconds: selectedAudio.durationSeconds,
                    consent: consent
                )
                let voice = try await session.cloneVoice(source: source)
                guard !Task.isCancelled, selectedFriendID == requestedFriendID, operationID == requestedOperationID,
                      selectedAudio.filename == requestedAudio.filename else {
                    error = String(localized: "voice_setup.friend_missing")
                    return
                }
                _ = try session.bindClonedVoice(voice, to: requestedFriendID)
                status = String(format: String(localized: "voice_setup.bound"), friend.name)
                self.selectedAudio = nil
                consentConfirmed = false
            } catch let bindingError {
                guard !Task.isCancelled, selectedFriendID == requestedFriendID, operationID == requestedOperationID else { return }
                self.error = bindingError.localizedDescription
            }
        }
    }
}

private extension BuiltInVoicePreset {
    var localizedName: String {
        switch kind {
        case .gentleWoman: return String(localized: "voice_preset.gentle_woman.name")
        case .matureWoman: return String(localized: "voice_preset.mature_woman.name")
        case .warmBestie: return String(localized: "voice_preset.warm_bestie.name")
        case .wiseWoman: return String(localized: "voice_preset.wise_woman.name")
        case .sweetLady: return String(localized: "voice_preset.sweet_lady.name")
        }
    }

    var localizedDescription: String {
        switch kind {
        case .gentleWoman: return String(localized: "voice_preset.gentle_woman.description")
        case .matureWoman: return String(localized: "voice_preset.mature_woman.description")
        case .warmBestie: return String(localized: "voice_preset.warm_bestie.description")
        case .wiseWoman: return String(localized: "voice_preset.wise_woman.description")
        case .sweetLady: return String(localized: "voice_preset.sweet_lady.description")
        }
    }

    var toneLabel: String {
        String(format: String(localized: "voice_preset.tone"), pitch, speed)
    }
}

@MainActor
private final class FriendVoiceRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPreparing = false

    private var coordinator = PushToRecordCoordinator()
    private var preparationID: UUID?
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    func press() async throws -> PendingVoiceAudio? {
        guard !isPreparing else { return nil }
        switch coordinator.press() {
        case .startRecording:
            let operationID = UUID()
            preparationID = operationID
            isPreparing = true
            defer {
                if preparationID == operationID {
                    preparationID = nil
                    isPreparing = false
                }
            }
            do {
                try await startRecording(operationID: operationID)
                isRecording = true
                return nil
            } catch {
                if preparationID == operationID { coordinator.reset() }
                throw error
            }
        case .stopRecording:
            preparationID = nil
            defer { isRecording = false }
            return try stopRecording()
        }
    }

    func cancel() {
        preparationID = nil
        recorder?.stop()
        recorder = nil
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        coordinator.reset()
        isPreparing = false
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startRecording(operationID: UUID) async throws {
        guard await requestPermission() else { throw FriendVoiceRecorderError.permissionDenied }
        guard preparationID == operationID else { throw CancellationError() }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepmate-recording-\(UUID().uuidString.lowercased())")
            .appendingPathExtension("m4a")
        recordingURL = url
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.prepareToRecord(), recorder.record() else {
            throw FriendVoiceRecorderError.couldNotStart
        }
        self.recorder = recorder
    }

    private func stopRecording() throws -> PendingVoiceAudio {
        guard let recorder, let recordingURL else { throw FriendVoiceRecorderError.noActiveRecording }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        defer {
            try? FileManager.default.removeItem(at: recordingURL)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        let data = try Data(contentsOf: recordingURL, options: [.mappedIfSafe])
        guard !data.isEmpty else { throw AuthorizedVoiceSourceError.emptyAudio }
        return PendingVoiceAudio(data: data, filename: recordingURL.lastPathComponent, durationSeconds: duration)
    }

    private func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}

private enum FriendVoiceRecorderError: LocalizedError {
    case permissionDenied
    case couldNotStart
    case noActiveRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return String(localized: "voice_setup.recording_permission_denied")
        case .couldNotStart: return String(localized: "voice_setup.recording_start_failed")
        case .noActiveRecording: return String(localized: "voice_setup.recording_missing")
        }
    }
}

private struct PendingVoiceAudio {
    let data: Data
    let filename: String
    let durationSeconds: TimeInterval
}

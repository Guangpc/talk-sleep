import AVFoundation
import SwiftUI
import SleepMateCore
import UniformTypeIdentifiers

@main
struct SleepMateApp: App {
    @StateObject private var session = VoiceSessionViewModel()

    var body: some Scene {
        WindowGroup {
            MainTabView(session: session)
        }
    }
}

private struct MainTabView: View {
    @ObservedObject var session: VoiceSessionViewModel
    @State private var selectedTab: AppTab = .text

    var body: some View {
        TabView(selection: $selectedTab) {
            TextFriendWorkspace(session: session)
                .tabItem { Label("文字与文件", systemImage: "doc.text") }
                .tag(AppTab.text)
                .accessibilityIdentifier("text-file-tab")

            VoiceFriendWorkspace(session: session)
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

    var body: some View {
        FriendListView(session: session)
    }
}

private struct VoiceFriendWorkspace: View {
    @ObservedObject var session: VoiceSessionViewModel
    @State private var selectedFriendID: UUID?
    @State private var selectedAudio: PendingVoiceAudio?
    @State private var consentConfirmed = false
    @State private var isImportingAudio = false
    @State private var isBinding = false
    @State private var bindingTask: Task<Void, Never>?
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
                        Text("为 AI 好友添加声音")
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
            .navigationTitle("朋友语音")
        }
    }

    private var friendPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "voice_setup.choose_friend"))
                .font(.headline)
            ForEach(session.persistedFriends) { friend in
                Button {
                    bindingTask?.cancel()
                    isBinding = false
                    selectedFriendID = friend.id
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
            .accessibilityIdentifier("friend-audio-import-button")
            .fileImporter(
                isPresented: $isImportingAudio,
                allowedContentTypes: supportedAudioTypes,
                allowsMultipleSelection: false,
                onCompletion: importAudio
            )

            if let selectedAudio {
                Label(
                    String(format: String(localized: "voice_setup.audio_selected"), selectedAudio.filename, selectedAudio.durationSeconds),
                    systemImage: "doc.badge.waveform"
                )
                .font(.footnote)
            }

            Toggle(String(localized: "voice_setup.authorize"), isOn: $consentConfirmed)
                .disabled(selectedAudio == nil || isBinding)
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
            .disabled(selectedAudio == nil || !consentConfirmed || isBinding)

            NavigationLink {
                VoiceSessionView(session: session)
            } label: {
                Label(String(localized: "voice_setup.start_session"), systemImage: "waveform")
            }
            .disabled(friend.voiceReference.isEmpty || friend.voiceReference.hasPrefix("voice://stock"))
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
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
                    selectedAudio = PendingVoiceAudio(data: data, filename: url.lastPathComponent, durationSeconds: duration)
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
        bindingTask = Task { @MainActor in
            defer {
                if selectedFriendID == requestedFriendID { isBinding = false }
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
                guard !Task.isCancelled, selectedFriendID == requestedFriendID else {
                    error = String(localized: "voice_setup.friend_missing")
                    return
                }
                _ = try session.bindClonedVoice(voice, to: requestedFriendID)
                status = String(format: String(localized: "voice_setup.bound"), friend.name)
                self.selectedAudio = nil
                consentConfirmed = false
            } catch let bindingError {
                self.error = bindingError.localizedDescription
            }
        }
    }
}

private struct PendingVoiceAudio {
    let data: Data
    let filename: String
    let durationSeconds: TimeInterval
}

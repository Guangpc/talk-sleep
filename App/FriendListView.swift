import AVFoundation
import SwiftUI
import SleepMateCore
import UniformTypeIdentifiers

private enum FriendInputField: Hashable {
    case name
    case context
    case analysis
}

struct FriendListView: View {
    @ObservedObject var voiceSession: VoiceSessionViewModel

    init(session: VoiceSessionViewModel? = nil) {
        _voiceSession = ObservedObject(wrappedValue: session ?? VoiceSessionViewModel())
    }
    @State private var friendName = ""
    @State private var friendContext = ""
    @State private var analysisDraft = ""
    @State private var selectedAudio: PendingAudio?
    @State private var existingFriendID: UUID?
    @State private var consentConfirmed = false
    @State private var isImportingAudio = false
    @State private var isImportingText = false
    @State private var isAnalyzing = false
    @State private var isWorking = false
    @State private var setupStatus = ""
    @State private var setupError = ""
    @FocusState private var focusedInput: FriendInputField?

    private let validator = AuthorizedVoiceSourceValidator()
    private let supportedAudioTypes = ["mp3", "m4a", "wav"].compactMap {
        UTType(filenameExtension: $0, conformingTo: .audio)
    }

    private var isBusy: Bool { isAnalyzing || isWorking }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    workspaceHeader
                    if let existingFriend = voiceSession.persistedFriends.first {
                        Label("已载入好友：\(existingFriend.name)", systemImage: "arrow.clockwise.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .onAppear {
                                if existingFriendID == nil {
                                    existingFriendID = existingFriend.id
                                    friendName = existingFriend.name
                                    analysisDraft = existingFriend.reviewedProfile
                                }
                            }
                    }
                    profileEditor
                    sourceEditor
                    primaryAction
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("文字与文件")
        }
        .simultaneousGesture(TapGesture().onEnded { focusedInput = nil })
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "keyboard.done")) { focusedInput = nil }
            }
        }
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "ai_friend.setup_title"))
                .font(.largeTitle.bold())
            Text(String(localized: "ai_friend.setup_message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var profileEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("朋友性格 / 好友画像", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)
            TextField(String(localized: "ai_friend.name"), text: $friendName)
                .focused($focusedInput, equals: .name)
                .submitLabel(.done)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("friend-name-input")
                .onChange(of: friendName) { _, _ in analysisDraft = "" }
            TextEditor(text: $analysisDraft)
                .focused($focusedInput, equals: .analysis)
                .frame(minHeight: 190)
                .padding(8)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topLeading) {
                    if analysisDraft.isEmpty {
                        Text("总结后，朋友性格、聊天风格、地址、重要地点、工作地点、工作环境、工作内容、生活习惯和重要记忆会显示在这里。")
                            .foregroundStyle(.tertiary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityIdentifier("friend-analysis-input")
            if !analysisDraft.isEmpty {
                Text(String(localized: "ai_friend.analysis_confirmation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
    }

    private var sourceEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("聊天记录与文字资料", systemImage: "text.bubble")
                .font(.headline)
            TextEditor(text: $friendContext)
                .focused($focusedInput, equals: .context)
                .frame(minHeight: 210)
                .padding(8)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topLeading) {
                    if friendContext.isEmpty {
                        Text(String(localized: "ai_friend.context_placeholder"))
                            .foregroundStyle(.tertiary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityIdentifier("friend-context-input")
            HStack {
                Button { setupError = ""; isImportingText = true } label: {
                    Label(String(localized: "ai_friend.import_text_file"), systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .fileImporter(isPresented: $isImportingText, allowedContentTypes: [.plainText, .utf8PlainText], allowsMultipleSelection: false, onCompletion: importText)
                Button { analyzeFriendContext() } label: {
                    if isAnalyzing { ProgressView() } else { Label(String(localized: "ai_friend.analyze"), systemImage: "sparkles") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(friendContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
            }
            .controlSize(.large)
        }
    }

    private var primaryAction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { createFriend() } label: {
                Label(String(localized: "ai_friend.create"), systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy)
            if !setupStatus.isEmpty { Text(setupStatus).font(.footnote).foregroundStyle(.secondary) }
            if !setupError.isEmpty { Text(setupError).font(.footnote).foregroundStyle(.red) }
            if voiceSession.friendReady {
                Label(String(localized: "ai_friend.ready"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func importAudio(_ result: Result<[URL], Error>) {
        switch result {
        case let .failure(error):
            if (error as NSError).code != NSUserCancelledError {
                setupError = String(localized: "ai_friend.audio_read_error")
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
                    selectedAudio = PendingAudio(data: data, filename: url.lastPathComponent, durationSeconds: duration)
                    setupError = ""
                } catch let error as AuthorizedVoiceSourceError {
                    selectedAudio = nil
                    setupError = error.localizedDescription
                } catch {
                    selectedAudio = nil
                    setupError = String(localized: "ai_friend.audio_read_error")
                }
            }
        }
    }

    private func importText(_ result: Result<[URL], Error>) {
        switch result {
        case let .failure(error):
            if (error as NSError).code != NSUserCancelledError {
                setupError = String(localized: "ai_friend.text_read_error")
            }
        case let .success(urls):
            guard let url = urls.first else { return }
            Task { @MainActor in
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    friendContext = try String(contentsOf: url, encoding: .utf8)
                    setupError = ""
                } catch {
                    setupError = String(localized: "ai_friend.text_read_error")
                }
            }
        }
    }

    private func analyzeFriendContext() {
        setupError = ""
        setupStatus = ""
        let source: String
        do {
            source = try validator.validateFriendText(friendContext).text
        } catch {
            setupError = error.localizedDescription
            return
        }

        let targetName = friendName.trimmingCharacters(in: .whitespacesAndNewlines)
        isAnalyzing = true
        setupStatus = String(localized: "ai_friend.analyzing")
        Task { @MainActor in
            defer { isAnalyzing = false }
            do {
                let analysis = try await voiceSession.analyzeFriendContext(source, friendName: targetName)
                guard friendContext.trimmingCharacters(in: .whitespacesAndNewlines) == source,
                      friendName.trimmingCharacters(in: .whitespacesAndNewlines) == targetName else {
                    setupStatus = ""
                    return
                }
                analysisDraft = analysis.conversationContext
                setupStatus = String(localized: "ai_friend.analysis_ready")
            } catch let error as FriendContextAnalysisError {
                setupStatus = ""
                if error == .cancelled { return }
                setupError = String(localized: "ai_friend.analysis_error")
            } catch {
                setupStatus = ""
                setupError = error.localizedDescription
            }
        }
    }

    private func createFriend() {
        setupError = ""
        setupStatus = ""
        voiceSession.beginFriendSetup()
        let contextInput = analysisDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? friendContext
            : analysisDraft
        let context: String
        do {
            context = try validator.validateFriendText(contextInput).text
        } catch let error as AuthorizedSourceTextError {
            if contextInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                context = ""
            } else {
                setupError = error.localizedDescription
                return
            }
        } catch {
            setupError = error.localizedDescription
            return
        }
        guard selectedAudio != nil || !context.isEmpty else {
            setupError = String(localized: "ai_friend.source_required")
            return
        }
        if selectedAudio != nil && !consentConfirmed {
            setupError = String(localized: "ai_friend.consent_required")
            return
        }

        setupStatus = String(localized: "ai_friend.creating")
        isWorking = true
        Task { @MainActor in
            defer {
                isWorking = false
                setupStatus = ""
            }
            do {
                let voice: VoiceConfiguration
                if let selectedAudio {
                    setupStatus = String(localized: "ai_friend.uploading")
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
                    voice = try await voiceSession.cloneVoice(source: source)
                } else {
                    guard voiceSession.configureFriendUsingEnvironment(name: friendName, context: context) else {
                        setupError = String(localized: "ai_friend.gateway_unavailable")
                        return
                    }
                    return
                }
                guard voiceSession.configureFriend(name: friendName, voice: voice, context: context) else {
                    setupError = String(localized: "ai_friend.gateway_unavailable")
                    return
                }
                selectedAudio = nil
            } catch {
                setupError = error.localizedDescription
            }
        }
    }
}

private struct PendingAudio {
    let data: Data
    let filename: String
    let durationSeconds: TimeInterval
}

#Preview {
    FriendListView()
}

import AVFoundation
import SwiftUI
import SleepMateCore
import UniformTypeIdentifiers

struct FriendListView: View {
    @StateObject private var voiceSession = VoiceSessionViewModel()
    @State private var friendName = ""
    @State private var friendContext = ""
    @State private var analysisDraft = ""
    @State private var selectedAudio: PendingAudio?
    @State private var consentConfirmed = false
    @State private var isImportingAudio = false
    @State private var isImportingText = false
    @State private var isAnalyzing = false
    @State private var isWorking = false
    @State private var setupStatus = ""
    @State private var setupError = ""

    private let validator = AuthorizedVoiceSourceValidator()
    private let supportedAudioTypes = ["mp3", "m4a", "wav"].compactMap {
        UTType(filenameExtension: $0, conformingTo: .audio)
    }

    private var isBusy: Bool { isAnalyzing || isWorking }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(String(localized: "ai_friend.setup_title"))
                        .font(.headline)
                    Text(String(localized: "ai_friend.setup_message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section(String(localized: "ai_friend.profile_section")) {
                    TextField(String(localized: "ai_friend.name"), text: $friendName)
                        .onChange(of: friendName) { _, _ in
                            analysisDraft = ""
                        }
                    Text(String(localized: "ai_friend.context_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $friendContext)
                        .frame(minHeight: 110)
                        .overlay(alignment: .topLeading) {
                            if friendContext.isEmpty {
                                Text(String(localized: "ai_friend.context_placeholder"))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                        .onChange(of: friendContext) { _, _ in
                            analysisDraft = ""
                        }

                    Button {
                        setupError = ""
                        isImportingText = true
                    } label: {
                        Label(String(localized: "ai_friend.import_text_file"), systemImage: "doc.text")
                    }
                    .fileImporter(
                        isPresented: $isImportingText,
                        allowedContentTypes: [.plainText, .utf8PlainText],
                        allowsMultipleSelection: false,
                        onCompletion: importText
                    )

                    Button {
                        analyzeFriendContext()
                    } label: {
                        if isAnalyzing {
                            HStack {
                                ProgressView()
                                Text(String(localized: "ai_friend.analyzing"))
                            }
                        } else {
                            Label(String(localized: "ai_friend.analyze"), systemImage: "sparkles")
                        }
                    }
                    .disabled(friendContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)

                    if !analysisDraft.isEmpty {
                        Text(String(localized: "ai_friend.analysis_result"))
                            .font(.subheadline.weight(.semibold))
                        TextEditor(text: $analysisDraft)
                            .frame(minHeight: 180)
                        Text(String(localized: "ai_friend.analysis_confirmation"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(String(localized: "ai_friend.voice_section")) {
                    Text(String(localized: "ai_friend.voice_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        setupError = ""
                        isImportingAudio = true
                    } label: {
                        Label(String(localized: "ai_friend.choose_audio"), systemImage: "waveform")
                    }
                    .accessibilityIdentifier("friend-audio-import-button")
                    .fileImporter(
                        isPresented: $isImportingAudio,
                        allowedContentTypes: supportedAudioTypes,
                        allowsMultipleSelection: false,
                        onCompletion: importAudio
                    )

                    if let selectedAudio {
                        Label(
                            String(format: String(localized: "ai_friend.audio_selected"), selectedAudio.filename, selectedAudio.durationSeconds),
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.secondary)
                    }
                    Toggle(String(localized: "ai_friend.consent_toggle"), isOn: $consentConfirmed)
                    Text(String(localized: "ai_friend.consent_message"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        createFriend()
                    } label: {
                        if isWorking {
                            ProgressView()
                        } else {
                            Label(String(localized: "ai_friend.create"), systemImage: "person.badge.plus")
                        }
                    }
                    .disabled(isBusy)

                    if !setupStatus.isEmpty {
                        Label(setupStatus, systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if !setupError.isEmpty {
                        Text(setupError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if voiceSession.friendReady {
                        NavigationLink {
                            VoiceSessionView(session: voiceSession)
                        } label: {
                            Label(String(localized: "ai_friend.start_session"), systemImage: "waveform")
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "ai_friend.title"))
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

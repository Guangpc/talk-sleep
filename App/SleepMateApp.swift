import SwiftUI
import SleepMateCore

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("为 AI 好友添加声音")
                            .font(.largeTitle.bold())
                        Text("只能为文字界面已经创建的好友选择并绑定授权音色。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    let friends = session.persistedFriends
                    if friends.isEmpty {
                        ContentUnavailableView("还没有 AI 好友", systemImage: "person.2", description: Text("请先切换到“文字与文件”创建 AI 好友。"))
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("选择 AI 好友")
                                .font(.headline)
                            ForEach(friends) { friend in
                                Button {
                                    selectedFriendID = friend.id
                                } label: {
                                    HStack {
                                        Image(systemName: selectedFriendID == friend.id ? "checkmark.circle.fill" : "circle")
                                        VStack(alignment: .leading) {
                                            Text(friend.name).font(.headline)
                                            Text(friend.voiceReference).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(14)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    if let selectedFriendID,
                       let selected = friends.first(where: { $0.id == selectedFriendID }) {
                        Label("已选择：\(selected.name)", systemImage: "person.crop.circle.badge.checkmark")
                            .foregroundStyle(.tint)
                        Button {
                            // Audio picker/binding is the next vertical slice.
                        } label: {
                            Label("选择朋友声音", systemImage: "waveform.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(true)
                        NavigationLink {
                            VoiceSessionView(session: session)
                        } label: {
                            Label("开始语音对话", systemImage: "waveform")
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("朋友语音")
        }
    }
}

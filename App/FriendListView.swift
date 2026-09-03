import SwiftUI
import SleepMateCore

struct FriendListView: View {
    @StateObject private var voiceSession = VoiceSessionViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(String(localized: "ai_friend.badge"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.tint.opacity(0.12), in: Capsule())

                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)

                Text(String(localized: "ai_friend.empty"))
                    .foregroundStyle(.secondary)

                NavigationLink {
                    VoiceSessionView(session: voiceSession)
                } label: {
                    Label(String(localized: "voice_session.open"), systemImage: "waveform")
                }
                .buttonStyle(.borderedProminent)

                Text("SleepMateCore \(SleepMateCore.version)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(String(localized: "ai_friend.title"))
        }
    }
}

#Preview {
    FriendListView()
}

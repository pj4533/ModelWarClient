import SwiftUI

struct ContentView: View {
    @Bindable var appSession: AppSession

    var body: some View {
        IDELayout(appSession: appSession)
            .frame(minWidth: 1200, minHeight: 800)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    if let player = appSession.player {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                            Text(player.name)
                                .fontWeight(.medium)
                            Text("(\(Int(player.rating)))")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }

                ToolbarItemGroup {
                    Button {
                        appSession.showingLeaderboard = true
                    } label: {
                        Label("Leaderboard", systemImage: "list.number")
                    }

                    Button {
                        appSession.showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .sheet(isPresented: $appSession.showingSettings) {
                SettingsView(appSession: appSession)
            }
            .sheet(isPresented: $appSession.showingLeaderboard) {
                LeaderboardView(appSession: appSession)
            }
            .onDisappear {
                appSession.shutdown()
            }
    }
}

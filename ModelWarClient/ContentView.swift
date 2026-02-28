import SwiftUI

struct ContentView: View {
    @Bindable var appSession: AppSession

    var body: some View {
        IDELayout(appSession: appSession)
            .frame(minWidth: 1200, minHeight: 800)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    if let player = appSession.player {
                        Button {
                            appSession.fetchPlayerProfile(id: player.id)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                Text(player.name)
                                    .fontWeight(.medium)
                                Text("(\(Int(player.rating)))")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                        }
                    }
                }

                ToolbarItemGroup {
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
            .sheet(isPresented: $appSession.showingPlayerProfile) {
                PlayerProfileView(appSession: appSession)
            }
            .onDisappear {
                appSession.shutdown()
            }
    }
}

import SwiftUI

struct EditorToolbar: View {
    @Bindable var appSession: AppSession

    var body: some View {
        HStack(spacing: 8) {
            Text("Editor")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 4) {
                TextField("Warrior Name", text: $appSession.warriorName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
            }

            Menu {
                ForEach(RedcodeTemplates.allTemplates, id: \.name) { template in
                    Button(template.name) {
                        appSession.warriorCode = template.code
                        appSession.warriorName = template.name
                    }
                }
            } label: {
                Label("Templates", systemImage: "doc.text")
                    .font(.caption)
            }

            Button {
                appSession.uploadWarrior()
            } label: {
                if appSession.isUploading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Label("Upload", systemImage: "arrow.up.circle")
                        .font(.caption)
                }
            }
            .disabled(appSession.isUploading || appSession.apiKey == nil || appSession.warriorCode.isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

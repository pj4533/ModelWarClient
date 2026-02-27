import SwiftUI

struct ChatInputView: View {
    @Binding var inputText: String
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Ask Claude about strategies...", text: $inputText)
                .textFieldStyle(.plain)
                .onSubmit { onSend() }

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

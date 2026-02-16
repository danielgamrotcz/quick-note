import SwiftUI

struct NoteInputView: View {
    @State private var text = ""
    @State private var status: SubmitStatus = .idle
    @State private var pendingCount = 0

    var body: some View {
        VStack(spacing: 0) {
            NoteTextEditor(
                text: $text,
                onCommandReturn: { submit() },
                onEscape: {
                    text = ""
                    status = .idle
                    AppDelegate.shared.hidePanel()
                }
            )
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 16)

            bottomBar
        }
        .frame(width: 480, height: 180)
        .background {
            VisualEffectBackground()
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            pendingCount = NoteQueue.shared.pendingCount
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteSubmitted)) { _ in
            status = .success
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                text = ""
                status = .idle
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteQueued)) { _ in
            status = .queued
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                text = ""
                status = .idle
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteSubmitFailed)) { notification in
            let message = notification.userInfo?["error"] as? String ?? "Neznámá chyba"
            status = .error(message)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pendingNotesChanged)) { _ in
            pendingCount = NoteQueue.shared.pendingCount
        }
    }

    private var bottomBar: some View {
        HStack {
            statusText

            if pendingCount > 0 && status == .idle {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                    Text("\(pendingCount) čeká na odeslání")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }

            Spacer()
            Text("⌘↩ Odeslat  ·  Esc Zrušit")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var statusText: some View {
        switch status {
        case .idle:
            EmptyView()
        case .sending:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Odesílání...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .success:
            Label("Odesláno", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        case .queued:
            Label("Uloženo, odešle se automaticky", systemImage: "arrow.clockwise.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        case .error(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        status = .sending
        AppDelegate.shared.submitNote(text: trimmed)
    }
}

private enum SubmitStatus: Equatable {
    case idle, sending, success, queued, error(String)
}

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

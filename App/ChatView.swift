import Agent
import Core
import SwiftUI

/// The conversation with the agent: the messages above, the input below.
/// Files dropped here or picked with the paperclip go with the next message
/// instead of into the import.
struct ChatView: View {
    @Bindable var model: AppModel
    @State private var text = ""
    @State private var files: [URL] = []
    @State private var picking = false
    @State private var historyVisible = false
    @State private var isDropTarget = false
    @FocusState private var focused: Bool

    private var busy: Bool {
        model.pendingMessage != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.chatMessages.isEmpty, busy == false {
                Text("Frag nach deinen Buchungen oder hänge eine Datei an, etwa einen Kontoauszug zum Abgleichen.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                transcript
            }
            Divider()
            composer
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        // Inside the chat a drop attaches; the window-wide drop imports.
        .dropDestination(for: URL.self) { urls, _ in
            attach(urls)
            return true
        } isTargeted: { isDropTarget = $0 }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result {
                attach(urls)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Verlauf", systemImage: "clock") {
                    model.loadConversations()
                    historyVisible = true
                }
                .disabled(busy)
                .popover(isPresented: $historyVisible, arrowEdge: .bottom) { history }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Neues Gespräch", systemImage: "square.and.pencil") {
                    model.newConversation()
                    text = ""
                    files = []
                    focused = true
                }
                .disabled(busy)
            }
        }
        .navigationTitle(model.conversation?.titel ?? "Chat")
        .alert("Fehler", isPresented: $model.showsError, presenting: model.errorMessage) { _ in
            Button("OK") {}
        } message: { text in
            Text(text)
        }
        .onAppear { focused = true }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.chatMessages) { message in
                        MessageRow(fromUser: message.fromUser, text: message.text)
                    }
                    if let pending = model.pendingMessage {
                        MessageRow(fromUser: true, text: pending)
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Pfennig arbeitet …").foregroundStyle(.secondary)
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(16)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.chatMessages.count) { proxy.scrollTo("end") }
            .onChange(of: model.pendingMessage) { proxy.scrollTo("end") }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if files.isEmpty == false {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(files, id: \.self) { file in
                            HStack(spacing: 4) {
                                Image(systemName: "doc")
                                Text(file.lastPathComponent).lineLimit(1)
                                Button("Entfernen", systemImage: "xmark") { files.removeAll { $0 == file } }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                            }
                            .font(.callout)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button("Datei anhängen", systemImage: "paperclip") { picking = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Datei anhängen")
                TextField("Nachricht", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 8)
                    .focused($focused)
                    // Return sends, Shift-Return starts a new line.
                    .onKeyPress(.return) {
                        if NSEvent.modifierFlags.contains(.shift) {
                            text += "\n"
                        } else {
                            send()
                        }
                        return .handled
                    }
                Button("Senden", systemImage: "arrow.up.circle.fill") { send() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.title2)
                    .disabled(canSend == false)
            }
        }
        .padding(12)
        .disabled(busy)
    }

    @ViewBuilder
    private var history: some View {
        if model.conversations.isEmpty {
            Text("Noch keine Gespräche")
                .foregroundStyle(.secondary)
                .padding(24)
        } else {
            List(model.conversations) { gespraech in
                HStack {
                    Button {
                        model.open(gespraech)
                        historyVisible = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gespraech.titel).lineLimit(1)
                            Text(gespraech.geaendertAm.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    Button("Löschen", systemImage: "trash") { model.deleteConversation(gespraech) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Gespräch löschen")
                }
            }
            .frame(width: 320, height: 320)
        }
    }

    private var canSend: Bool {
        busy == false &&
            (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || files.isEmpty == false)
    }

    private func attach(_ urls: [URL]) {
        let allowed = FileIntake.files(in: urls).filter { files.contains($0) == false }
        files.append(contentsOf: allowed)
    }

    /// The fields empty at once; a failed round gives them back.
    private func send() {
        guard canSend else { return }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attached = files
        text = ""
        files = []
        Task {
            if await model.send(message, files: attached) == false {
                text = message
                files = attached
            }
            focused = true
        }
    }
}

/// The user's text on the right on a quiet background, the agent's answer on
/// the left as Markdown.
private struct MessageRow: View {
    let fromUser: Bool
    let text: String

    var body: some View {
        if fromUser {
            HStack {
                Spacer(minLength: 80)
                Text(text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            }
        } else {
            Text(markdown)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 80)
        }
    }

    private var markdown: AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

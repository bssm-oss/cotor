import SwiftUI


// MARK: - File Overview
// DirectChatView belongs to the native macOS client layer for the Cotor desktop application.
// It collects declarations centered on direct chat so the native shell code stays easier to navigate.
// Start with this file when tracing how the desktop client presents, stores, or moves state in this area.

struct DirectChatView: View {
    let companyId: String

    @State private var conversations: [DirectChatConversation] = []
    @State private var selectedConversationId: String? = nil
    @State private var inputText: String = ""
    @State private var isStreaming: Bool = false
    @State private var streamingMessageId: String? = nil
    @State private var streamingContent: String = ""
    @State private var availableModels: [DirectChatAvailableModel] = []
    @State private var providerCatalog: [DirectChatProviderCatalogEntryRecord] = []
    @State private var isLoadingConversations: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showNewChatSheet: Bool = false

    private var selectedConversation: DirectChatConversation? {
        conversations.first { $0.id == selectedConversationId }
    }

    var body: some View {
        HSplitView {
            conversationSidebar
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)

            if let conversation = selectedConversation {
                chatArea(conversation: conversation)
            } else {
                emptyState
            }
        }
        .task { await loadConversations() }
        .task { await loadProviderCatalog() }
        .task { await loadModels() }
        .sheet(isPresented: $showNewChatSheet) {
            NewChatSheet(
                companyId: companyId,
                availableModels: availableModels,
                providers: providerCatalog,
                onCreated: { conversation in
                    conversations.insert(conversation, at: 0)
                    selectedConversationId = conversation.id
                    showNewChatSheet = false
                }
            )
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sidebar

    private var conversationSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chats")
                    .font(.headline)
                    .foregroundColor(ShellPalette.text)
                Spacer()
                Button(action: { showNewChatSheet = true }) {
                    Image(systemName: "square.and.pencil")
                        .imageScale(.medium)
                        .foregroundColor(ShellPalette.muted)
                }
                .buttonStyle(.plain)
                .help("New conversation")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if isLoadingConversations {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if conversations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32))
                        .foregroundColor(ShellPalette.faint)
                    Text("No conversations yet")
                        .font(.subheadline)
                        .foregroundColor(ShellPalette.muted)
                    Button("Start a chat") { showNewChatSheet = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(conversations) { conversation in
                            conversationRow(conversation)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(ShellPalette.panel)
    }

    private func conversationRow(_ conversation: DirectChatConversation) -> some View {
        Button(action: { selectedConversationId = conversation.id }) {
            HStack(spacing: 10) {
                Image(systemName: providerIcon(conversation.provider))
                    .foregroundColor(ShellPalette.accent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title.isEmpty ? "New conversation" : conversation.title)
                        .font(.subheadline)
                        .fontWeight(selectedConversationId == conversation.id ? .semibold : .regular)
                        .foregroundColor(ShellPalette.text)
                        .lineLimit(1)
                    Text(conversation.model)
                        .font(.caption)
                        .foregroundColor(ShellPalette.muted)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                selectedConversationId == conversation.id
                    ? ShellPalette.accentSoft
                    : Color.clear
            )
            .cornerRadius(ShellMetrics.radiusSmall)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive) {
                Task { await deleteConversation(conversation) }
            }
        }
    }

    // MARK: - Chat Area

    private func chatArea(conversation: DirectChatConversation) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title.isEmpty ? "Conversation" : conversation.title)
                        .font(.headline)
                        .foregroundColor(ShellPalette.text)
                    HStack(spacing: 4) {
                        Image(systemName: providerIcon(conversation.provider))
                            .font(.caption)
                            .foregroundColor(ShellPalette.muted)
                        Text("\(conversation.provider) · \(conversation.model)")
                            .font(.caption)
                            .foregroundColor(ShellPalette.muted)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(conversation.messages) { message in
                            messageRow(message)
                        }
                        if isStreaming, let msgId = streamingMessageId, !streamingContent.isEmpty {
                            messageRow(DirectChatMessage(
                                id: msgId,
                                role: "assistant",
                                content: streamingContent,
                                createdAt: 0
                            ))
                            .id("streaming")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: streamingContent) {
                    withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                }
                .onChange(of: conversation.messages.count) {
                    if let last = conversation.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(10)
                    .background(ShellPalette.panelAlt)
                    .cornerRadius(ShellMetrics.radiusMedium)
                    .onSubmit {
                        if !isStreaming { Task { await sendMessage() } }
                    }

                Button(action: { Task { await sendMessage() } }) {
                    if isStreaming {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(inputText.isEmpty ? ShellPalette.faint : ShellPalette.accent)
                    }
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || isStreaming)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(ShellPalette.panel)
    }

    private func messageRow(_ message: DirectChatMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == "assistant" {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 14))
                    .foregroundColor(ShellPalette.accent)
                    .frame(width: 24, height: 24)
                    .background(ShellPalette.accentSoft)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 14))
                    .foregroundColor(ShellPalette.muted)
                    .frame(width: 24, height: 24)
                    .background(ShellPalette.panelRaised)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == "assistant" ? "AI" : "You")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(message.role == "assistant" ? ShellPalette.accent : ShellPalette.muted)

                Text(message.content)
                    .font(.body)
                    .foregroundColor(ShellPalette.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .id(message.id)
        .padding(.vertical, 2)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundColor(ShellPalette.faint)
            Text("Select or start a conversation")
                .font(.title3)
                .foregroundColor(ShellPalette.muted)
            Button("New Chat") { showNewChatSheet = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShellPalette.panel)
    }

    // MARK: - Actions

    private func loadConversations() async {
        isLoadingConversations = true
        let api = DesktopAPI()
        do {
            let loaded = try await api.listDirectChatConversations(companyId: companyId)
            await MainActor.run {
                conversations = loaded.sorted { $0.updatedAt > $1.updatedAt }
                isLoadingConversations = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoadingConversations = false
            }
        }
    }

    private func loadModels() async {
        let api = DesktopAPI()
        do {
            let models = try await api.listDirectChatModels(companyId: companyId)
            await MainActor.run { availableModels = models }
        } catch {
            // Ollama may not be running; silently ignore
        }
    }

    private func loadProviderCatalog() async {
        let api = DesktopAPI()
        do {
            let providers = try await api.directChatProviders()
            await MainActor.run { providerCatalog = providers }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func sendMessage() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let conversationId = selectedConversationId else { return }

        let api = DesktopAPI()
        await MainActor.run {
            inputText = ""
            isStreaming = true
            streamingContent = ""
            streamingMessageId = UUID().uuidString
        }

        do {
            let stream = api.streamDirectChatMessage(
                companyId: companyId,
                conversationId: conversationId,
                message: trimmed
            )
            for try await chunk in stream {
                await MainActor.run {
                    streamingContent += chunk.content
                    if chunk.done {
                        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
                            let now = Int64(Date().timeIntervalSince1970 * 1000)
                            let userMsg = DirectChatMessage(
                                id: UUID().uuidString,
                                role: "user",
                                content: trimmed,
                                createdAt: now
                            )
                            let assistantMsg = DirectChatMessage(
                                id: chunk.messageId,
                                role: "assistant",
                                content: streamingContent,
                                createdAt: now
                            )
                            conversations[idx].messages.append(userMsg)
                            conversations[idx].messages.append(assistantMsg)
                            conversations[idx].updatedAt = now
                        }
                        isStreaming = false
                        streamingContent = ""
                        streamingMessageId = nil
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isStreaming = false
                streamingContent = ""
                streamingMessageId = nil
            }
        }
    }

    private func deleteConversation(_ conversation: DirectChatConversation) async {
        let api = DesktopAPI()
        do {
            try await api.deleteDirectChatConversation(
                conversationId: conversation.id,
                companyId: companyId
            )
            await MainActor.run {
                conversations.removeAll { $0.id == conversation.id }
                if selectedConversationId == conversation.id {
                    selectedConversationId = conversations.first?.id
                }
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func providerIcon(_ provider: String) -> String {
        providerCatalog.first { $0.id == provider || $0.providerId == provider }?.iconSystemName ?? "bubble.left.fill"
    }
}

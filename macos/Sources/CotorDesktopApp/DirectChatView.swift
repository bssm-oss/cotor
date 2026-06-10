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
                VStack(alignment: .leading, spacing: 2) {
                    Text("운영 채팅")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(conversations.count) conversations")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(ShellPalette.muted)
                }
                    .foregroundColor(ShellPalette.text)
                Spacer()
                Button(action: { showNewChatSheet = true }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(ShellIconButtonStyle())
                .help("새 대화")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if isLoadingConversations {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if conversations.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "message.badge.waveform")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(ShellPalette.accent)
                        .frame(width: 42, height: 42)
                        .background(ShellPalette.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
                    Text("아직 대화가 없습니다")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ShellPalette.text)
                    Text("Codex OAuth 또는 로컬 Ollama로 운영 대화를 시작하세요.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ShellPalette.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Button {
                        showNewChatSheet = true
                    } label: {
                        Label("새 대화", systemImage: "plus.message.fill")
                    }
                    .buttonStyle(ShellActionButtonStyle(role: .prominent, compact: true))
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(conversations) { conversation in
                            conversationRow(conversation)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(ShellPalette.panelAlt)
    }

    private func conversationRow(_ conversation: DirectChatConversation) -> some View {
        let isSelected = selectedConversationId == conversation.id
        return Button(action: { selectedConversationId = conversation.id }) {
            HStack(spacing: 10) {
                Image(systemName: providerIcon(conversation.provider))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? ShellPalette.accent : ShellPalette.muted)
                    .frame(width: 28, height: 28)
                    .background(isSelected ? ShellPalette.accentSoft : ShellPalette.panelRaised)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title.isEmpty ? "New conversation" : conversation.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(ShellPalette.text)
                        .lineLimit(1)
                    Text("\(conversation.providerDisplayName) · \(conversation.model)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(ShellPalette.muted)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? ShellPalette.panelRaised
                    : ShellPalette.panel
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                    .stroke(isSelected ? ShellPalette.accent.opacity(0.42) : ShellPalette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("삭제", role: .destructive) {
                Task { await deleteConversation(conversation) }
            }
        }
    }

    // MARK: - Chat Area

    private func chatArea(conversation: DirectChatConversation) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: providerIcon(conversation.provider))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ShellPalette.accent)
                    .frame(width: 30, height: 30)
                    .background(ShellPalette.accentSoft)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(conversation.title.isEmpty ? "운영 대화" : conversation.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(ShellPalette.text)
                        .lineLimit(1)
                    Text("\(conversation.providerDisplayName) · \(conversation.model)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(ShellPalette.muted)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    showNewChatSheet = true
                } label: {
                    Image(systemName: "plus.message")
                }
                .buttonStyle(ShellIconButtonStyle())
                .help("새 대화")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(ShellPalette.panelAlt)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .center, spacing: 12) {
                        Text("오늘")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(ShellPalette.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(ShellPalette.panelRaised)
                            .clipShape(Capsule())
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
                TextField("운영 지시나 질문을 입력하세요...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(ShellPalette.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous)
                            .stroke(ShellPalette.line, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous))
                    .onSubmit {
                        if !isStreaming { Task { await sendMessage() } }
                    }

                Button(action: { Task { await sendMessage() } }) {
                    if isStreaming {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(ShellIconButtonStyle())
                .disabled(inputText.isEmpty || isStreaming)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(ShellPalette.canvasBottom)
    }

    private func messageRow(_ message: DirectChatMessage) -> some View {
        let isUser = message.role == "user"
        return HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 72)
            } else {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ShellPalette.accent)
                    .frame(width: 26, height: 26)
                    .background(ShellPalette.accentSoft)
                    .clipShape(Circle())
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                if !isUser {
                    Text("Cotor")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ShellPalette.muted)
                }

                Text(message.content.isEmpty ? "응답을 준비하고 있습니다..." : message.content)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(isUser ? ShellPalette.chatUserText : ShellPalette.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(isUser ? ShellPalette.chatUserBubble : ShellPalette.chatAssistantBubble)
                    .overlay(
                        RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous)
                            .stroke(isUser ? Color.clear : ShellPalette.line.opacity(0.6), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall, style: .continuous))
                    .frame(maxWidth: 520, alignment: isUser ? .trailing : .leading)
            }

            if isUser {
                Image(systemName: "person.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ShellPalette.muted)
                    .frame(width: 26, height: 26)
                    .background(ShellPalette.panelRaised)
                    .clipShape(Circle())
            } else {
                Spacer(minLength: 72)
            }
        }
        .id(message.id)
        .padding(.vertical, 2)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(ShellPalette.accent)
                .frame(width: 58, height: 58)
                .background(ShellPalette.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: ShellMetrics.radiusMedium, style: .continuous))
            Text("대화를 선택하거나 새로 시작하세요")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(ShellPalette.text)
            Text("로컬 모델과 Codex OAuth를 한 화면에서 바로 테스트할 수 있습니다.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ShellPalette.muted)
            Button {
                showNewChatSheet = true
            } label: {
                Label("새 대화", systemImage: "plus.message.fill")
            }
            .buttonStyle(ShellActionButtonStyle(role: .prominent, compact: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShellPalette.canvasBottom)
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

private extension DirectChatConversation {
    var providerDisplayName: String {
        switch provider {
        case "ollama":
            return "Ollama"
        case "lmstudio":
            return "LM Studio"
        case "codex-oauth":
            return "Codex OAuth"
        default:
            return provider
        }
    }
}

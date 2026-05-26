import SwiftUI


// MARK: - File Overview
// NewChatSheet belongs to the native macOS client layer for the Cotor desktop application.
// It collects declarations centered on new chat sheet so the native shell code stays easier to navigate.
// Start with this file when tracing how the desktop client presents, stores, or moves state in this area.

struct NewChatSheet: View {
    let companyId: String
    let availableModels: [DirectChatAvailableModel]
    let onCreated: (DirectChatConversation) -> Void

    @State private var title: String = ""
    @State private var selectedProvider: String = "ollama"
    @State private var customModel: String = "gemma3"
    @State private var systemPrompt: String = ""
    @State private var baseUrl: String = ""
    @State private var isCreating: Bool = false
    @State private var error: String? = nil
    @Environment(\.dismiss) private var dismiss

    private let providers: [(id: String, label: String, icon: String)] = [
        ("ollama", "Ollama (local)", "cpu.fill"),
        ("lmstudio", "LM Studio (local)", "server.rack"),
        ("claude-cli", "Claude CLI", "sparkles")
    ]

    private var ollamaModels: [String] {
        availableModels.filter { $0.provider == "ollama" }.map { $0.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    providerSection
                    modelSection
                    systemPromptSection
                    if selectedProvider != "claude-cli" {
                        baseUrlSection
                    }
                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(ShellPalette.danger)
                    }
                }
                .padding(16)
            }

            Divider()

            sheetFooter
        }
        .frame(width: 400, height: 480)
        .background(ShellPalette.panel)
    }

    // MARK: - Header / Footer

    private var sheetHeader: some View {
        HStack {
            Text("New Conversation")
                .font(.headline)
                .foregroundColor(ShellPalette.text)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundColor(ShellPalette.muted)
        }
        .padding(16)
    }

    private var sheetFooter: some View {
        HStack {
            Spacer()
            Button("Start Chat") {
                Task { await createConversation() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(customModel.isEmpty || isCreating)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(16)
    }

    // MARK: - Sections

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Provider")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(ShellPalette.text)

            ForEach(providers, id: \.id) { provider in
                Button(action: { selectedProvider = provider.id }) {
                    HStack {
                        Image(systemName: provider.icon)
                            .frame(width: 20)
                            .foregroundColor(
                                selectedProvider == provider.id
                                    ? ShellPalette.accent
                                    : ShellPalette.muted
                            )
                        Text(provider.label)
                            .foregroundColor(ShellPalette.text)
                        Spacer()
                        if selectedProvider == provider.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(ShellPalette.accent)
                        }
                    }
                    .padding(10)
                    .background(
                        selectedProvider == provider.id
                            ? ShellPalette.accentSoft
                            : ShellPalette.panelAlt
                    )
                    .cornerRadius(ShellMetrics.radiusSmall)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(ShellPalette.text)

            if selectedProvider == "ollama" && !ollamaModels.isEmpty {
                Picker("Model", selection: $customModel) {
                    ForEach(ollamaModels, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onAppear {
                    if !ollamaModels.contains(customModel),
                       let first = ollamaModels.first {
                        customModel = first
                    }
                }
            } else {
                TextField(
                    modelPlaceholder,
                    text: $customModel
                )
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var modelPlaceholder: String {
        switch selectedProvider {
        case "ollama": return "gemma3"
        case "claude-cli": return "claude"
        default: return "model-name"
        }
    }

    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("System prompt (optional)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(ShellPalette.text)
            TextEditor(text: $systemPrompt)
                .frame(minHeight: 60, maxHeight: 120)
                .font(.body)
                .scrollContentBackground(.hidden)
                .background(ShellPalette.panelAlt)
                .cornerRadius(ShellMetrics.radiusSmall)
                .overlay(
                    RoundedRectangle(cornerRadius: ShellMetrics.radiusSmall)
                        .stroke(ShellPalette.line, lineWidth: 1)
                )
        }
    }

    private var baseUrlSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Base URL (optional)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(ShellPalette.text)
            TextField("http://127.0.0.1:11434", text: $baseUrl)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Action

    private func createConversation() async {
        await MainActor.run {
            isCreating = true
            error = nil
        }
        let api = DesktopAPI()
        do {
            let conversation = try await api.createDirectChatConversation(
                companyId: companyId,
                title: title,
                model: customModel,
                provider: selectedProvider,
                baseUrl: baseUrl,
                systemPrompt: systemPrompt
            )
            await MainActor.run { onCreated(conversation) }
        } catch let err {
            await MainActor.run {
                error = err.localizedDescription
                isCreating = false
            }
        }
    }
}

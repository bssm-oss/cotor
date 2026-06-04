import SwiftUI


// MARK: - File Overview
// NewChatSheet belongs to the native macOS client layer for the Cotor desktop application.
// It collects declarations centered on new chat sheet so the native shell code stays easier to navigate.
// Start with this file when tracing how the desktop client presents, stores, or moves state in this area.

struct NewChatSheet: View {
    let companyId: String
    let availableModels: [DirectChatAvailableModel]
    let providers: [DirectChatProviderCatalogEntryRecord]
    let onCreated: (DirectChatConversation) -> Void

    @State private var title: String = ""
    @State private var selectedProvider: String = "ollama"
    @State private var customModel: String = "gemma3"
    @State private var systemPrompt: String = ""
    @State private var baseUrl: String = ""
    @State private var isCreating: Bool = false
    @State private var error: String? = nil
    @Environment(\.dismiss) private var dismiss

    private var selectedProviderEntry: DirectChatProviderCatalogEntryRecord? {
        providers.first { $0.id == selectedProvider } ?? providers.first
    }

    private var selectedProviderModels: [String] {
        guard let provider = selectedProviderEntry else { return [] }
        return availableModels.filter { $0.provider == provider.id }.map { $0.id }
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
                    if selectedProviderEntry?.allowsBaseUrl == true {
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
        .onAppear { applyProviderDefaultsIfNeeded() }
        .onChange(of: providers) { _, _ in applyProviderDefaultsIfNeeded() }
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
            .disabled(providers.isEmpty || customModel.isEmpty || isCreating)
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
                Button(action: { selectProvider(provider) }) {
                    HStack {
                        Image(systemName: provider.iconSystemName)
                            .frame(width: 20)
                            .foregroundColor(
                                selectedProvider == provider.id
                                    ? ShellPalette.accent
                                    : ShellPalette.muted
                            )
                        Text(provider.displayName)
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

            if providers.isEmpty {
                Text("Provider catalog unavailable")
                    .font(.caption)
                    .foregroundColor(ShellPalette.muted)
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(ShellPalette.text)

            if selectedProviderEntry?.supportsModelDiscovery == true && !selectedProviderModels.isEmpty {
                Picker("Model", selection: $customModel) {
                    ForEach(selectedProviderModels, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onAppear {
                    if !selectedProviderModels.contains(customModel),
                       let first = selectedProviderModels.first {
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
        selectedProviderEntry?.defaultModel ?? "model-name"
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
                provider: selectedProviderEntry?.id ?? selectedProvider,
                baseUrl: selectedProviderEntry?.allowsBaseUrl == true ? baseUrl : "",
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

    private func applyProviderDefaultsIfNeeded() {
        guard let provider = selectedProviderEntry else { return }
        if selectedProvider != provider.id {
            selectedProvider = provider.id
        }
        if customModel.isEmpty || customModel == "model-name" {
            customModel = provider.defaultModel
        }
        if baseUrl.isEmpty {
            baseUrl = provider.defaultBaseUrl
        }
    }

    private func selectProvider(_ provider: DirectChatProviderCatalogEntryRecord) {
        selectedProvider = provider.id
        customModel = provider.defaultModel
        baseUrl = provider.defaultBaseUrl
    }
}

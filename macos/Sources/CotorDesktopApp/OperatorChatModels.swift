import Foundation

struct ChatGoalProposal: Equatable {
    let title: String
    let description: String
}

struct ChatCompanyRequestProposal: Equatable {
    let title: String
    let request: String
    let ceoBrief: String
}

struct ChatIssueProposal: Equatable {
    let goalId: String
    let title: String
    let description: String
}

struct ChatMergeProposal: Equatable {
    let summary: String
}

struct ChatAgentProposal: Equatable {
    let title: String
    let agentCli: String
    let model: String?
    let roleSummary: String
    let specialties: [String]
    let collaborationInstructions: String?
    let memoryNotes: String?
    let enabled: Bool
}

enum ChatRuntimeAction: String, Equatable {
    case start
    case stop
}

struct ChatRuntimeProposal: Equatable {
    let action: ChatRuntimeAction
    let summary: String
}

enum ChatBackendAction: String, Equatable {
    case start
    case stop
    case restart
}

struct ChatBackendProposal: Equatable {
    let action: ChatBackendAction
    let summary: String
}

struct ChatExecutionProposal: Equatable {
    let summary: String
}

struct ChatDelegationProposal: Equatable {
    let summary: String
}

struct ChatGoalDecompositionProposal: Equatable {
    let summary: String
}

enum ChatGoalAutonomyMode: String, Equatable {
    case enable
    case disable
}

struct ChatGoalAutonomyProposal: Equatable {
    let mode: ChatGoalAutonomyMode
    let summary: String
}

enum ChatReviewStage: String, Equatable {
    case qa
    case ceo
}

struct ChatReviewProposal: Equatable {
    let stage: ChatReviewStage
    let verdict: String
    let feedback: String?
}

enum OperatorChatRole: String, Equatable {
    case user
    case assistant
    case system
}

enum OperatorChatCommandKind: String, Equatable {
    case sendPrompt
    case confirmFullAuto
    case confirmHrStaffing
    case confirmCompanyDelete
    case confirmMerge
    case cancelConfirmation
    case chooseCompanyFolder
}

struct OperatorChatCommand: Identifiable, Equatable {
    let id: String
    let title: String
    let prompt: String
    let kind: OperatorChatCommandKind
    let destructive: Bool

    init(
        id: String? = nil,
        title: String,
        prompt: String,
        kind: OperatorChatCommandKind = .sendPrompt,
        destructive: Bool = false
    ) {
        self.id = id ?? "\(kind.rawValue)-\(title)-\(prompt)"
        self.title = title
        self.prompt = prompt
        self.kind = kind
        self.destructive = destructive
    }
}

struct OperatorChatPendingPrompt: Equatable {
    let question: String
    let resumePrompt: String
}

struct OperatorChatMessage: Identifiable, Equatable {
    let id: String
    let role: OperatorChatRole
    let text: String
    let createdAt: Date
    let commands: [OperatorChatCommand]

    init(
        id: String = UUID().uuidString,
        role: OperatorChatRole,
        text: String,
        createdAt: Date = Date(),
        commands: [OperatorChatCommand] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.commands = commands
    }
}

enum OperatorChatProposalParser {
    static func goal(from draft: String) -> ChatGoalProposal? {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return nil }
        let normalizedDraft = strippedLeadingSlashCommand(
            from: strippedLeadingListPrefix(from: trimmedDraft),
            commands: ["goal", "objective", "목표"]
        )
        let title = normalizedTitle(
            from: normalizedDraft,
            fallbackLimit: 80,
            removingPrefixPattern: #"^(goal\s*:\s*|목표\s*:\s*)"#
        )
        guard !title.isEmpty else { return nil }

        return ChatGoalProposal(title: title, description: normalizedDraft)
    }

    static func companyRequest(
        from draft: String,
        companyName: String,
        language: AppLanguage
    ) -> ChatCompanyRequestProposal? {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return nil }
        let title = normalizedTitle(
            from: trimmedDraft,
            fallbackLimit: 96,
            removingPrefixPattern: #"^(goal|objective|request|ask|목표|요청|할일)\s*:\s*"#
        )
        guard !title.isEmpty else { return nil }

        let ceoBrief = language(
            "CEO will restate this as a clear outcome, create success criteria, split it into assigned issues, and keep QA/CEO review gates visible for \(companyName).",
            "CEO가 이 요청을 명확한 결과물로 다시 정리하고, 성공 기준을 만들고, 담당 이슈로 나눈 뒤 \(companyName)의 QA/CEO 검토 단계를 보이게 유지합니다."
        )
        return ChatCompanyRequestProposal(title: title, request: trimmedDraft, ceoBrief: ceoBrief)
    }

    static func issue(from draft: String, goalId: String?) -> ChatIssueProposal? {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty, let goalId else { return nil }
        let title = normalizedTitle(
            from: trimmedDraft,
            fallbackLimit: 80,
            removingPrefixPattern: #"^(issue\s*:\s*|task\s*:\s*|ticket\s*:\s*|이슈\s*:\s*)"#
        )
        guard !title.isEmpty else { return nil }

        return ChatIssueProposal(goalId: goalId, title: title, description: trimmedDraft)
    }

    static func review(from draft: String, kind: String) -> ChatReviewProposal? {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return nil }
        let normalized = " " + trimmedDraft.lowercased() + " "

        let verdict: String
        if normalized.contains(" changes requested ") ||
            normalized.contains(" request changes ") ||
            normalized.contains(" changes needed ") ||
            normalized.contains(" reject ") ||
            normalized.contains(" rejected ") ||
            normalized.contains(" fail ") ||
            normalized.contains(" failed ") {
            verdict = "CHANGES_REQUESTED"
        } else if kind == "qa" {
            verdict = "PASS"
        } else {
            verdict = "APPROVE"
        }

        return ChatReviewProposal(
            stage: kind == "qa" ? .qa : .ceo,
            verdict: verdict,
            feedback: trimmedDraft
        )
    }

    static func merge(from draft: String) -> ChatMergeProposal? {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return nil }
        let normalized = " " + trimmedDraft.lowercased() + " "
        let mergeSignals = [" merge ", " ship it ", " merge it ", " land it ", " merge now ", " approve and merge "]
        guard mergeSignals.contains(where: { normalized.contains($0) }) else { return nil }
        return ChatMergeProposal(summary: trimmedDraft)
    }

    static func runtime(from draft: String) -> ChatRuntimeProposal? {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return nil }
        let normalized = " " + trimmedDraft.lowercased() + " "

        if [" stop runtime ", " pause runtime ", " stop company ", " stop the runtime ", " runtime off "].contains(where: { normalized.contains($0) }) {
            return ChatRuntimeProposal(action: .stop, summary: trimmedDraft)
        }
        if [" start runtime ", " resume runtime ", " start company ", " start the runtime ", " runtime on "].contains(where: { normalized.contains($0) }) {
            return ChatRuntimeProposal(action: .start, summary: trimmedDraft)
        }
        return nil
    }

    static func agent(
        from draft: String,
        preferredCli: String,
        language: AppLanguage
    ) -> ChatAgentProposal? {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return nil }
        let normalized = " " + trimmedDraft.lowercased() + " "
        let agentSignals = [" agent ", " qa agent", " reviewer ", " review agent", " tester "]
        guard agentSignals.contains(where: { normalized.contains($0) }) else { return nil }

        if normalized.contains(" qa ") || normalized.contains(" review ") || normalized.contains(" test ") || normalized.contains(" verification ") {
            return ChatAgentProposal(
                title: language("QA Agent", "QA 에이전트"),
                agentCli: preferredCli,
                model: nil,
                roleSummary: language("Own verification, review-queue decisions, and regression feedback for delivered work.", "전달된 작업에 대한 검증, 리뷰 큐 판정, 회귀 피드백을 담당합니다."),
                specialties: ["qa", "review", "verification"],
                collaborationInstructions: trimmedDraft,
                memoryNotes: trimmedDraft,
                enabled: true
            )
        }

        return ChatAgentProposal(
            title: language("New Agent", "새 에이전트"),
            agentCli: preferredCli,
            model: nil,
            roleSummary: trimmedDraft,
            specialties: ["general"],
            collaborationInstructions: trimmedDraft,
            memoryNotes: trimmedDraft,
            enabled: true
        )
    }

    static func backend(from draft: String) -> ChatBackendProposal? {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return nil }
        let normalized = " " + trimmedDraft.lowercased() + " "

        if [" restart backend ", " reboot backend ", " restart app server ", " restart codex backend "].contains(where: { normalized.contains($0) }) {
            return ChatBackendProposal(action: .restart, summary: trimmedDraft)
        }
        if [" stop backend ", " stop app server ", " backend off ", " stop codex backend "].contains(where: { normalized.contains($0) }) {
            return ChatBackendProposal(action: .stop, summary: trimmedDraft)
        }
        if [" start backend ", " start app server ", " backend on ", " start codex backend "].contains(where: { normalized.contains($0) }) {
            return ChatBackendProposal(action: .start, summary: trimmedDraft)
        }
        return nil
    }

    static func execution(from draft: String) -> ChatExecutionProposal? {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return nil }
        let normalized = " " + trimmedDraft.lowercased() + " "
        let signals = [" run this issue ", " execute this issue ", " start this issue ", " work on this issue ", " run selected issue "]
        guard signals.contains(where: { normalized.contains($0) }) else { return nil }
        return ChatExecutionProposal(summary: trimmedDraft)
    }

    static func delegation(from draft: String) -> ChatDelegationProposal? {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return nil }
        let normalized = " " + trimmedDraft.lowercased() + " "
        let signals = [" delegate this issue ", " assign this issue ", " route this issue ", " delegate selected issue ", " assign selected issue "]
        guard signals.contains(where: { normalized.contains($0) }) else { return nil }
        return ChatDelegationProposal(summary: trimmedDraft)
    }

    static func goalDecomposition(from draft: String) -> ChatGoalDecompositionProposal? {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return nil }
        let normalized = " " + trimmedDraft.lowercased() + " "
        let signals = [" break this goal ", " decompose this goal ", " split this goal ", " generate issues for this goal ", " break selected goal "]
        guard signals.contains(where: { normalized.contains($0) }) else { return nil }
        return ChatGoalDecompositionProposal(summary: trimmedDraft)
    }

    static func goalAutonomy(from draft: String) -> ChatGoalAutonomyProposal? {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return nil }
        let normalized = " " + trimmedDraft.lowercased() + " "
        if [" enable autonomy ", " turn autonomy on ", " enable auto mode ", " make this goal autonomous "].contains(where: { normalized.contains($0) }) {
            return ChatGoalAutonomyProposal(mode: .enable, summary: trimmedDraft)
        }
        if [" disable autonomy ", " turn autonomy off ", " disable auto mode ", " make this goal manual "].contains(where: { normalized.contains($0) }) {
            return ChatGoalAutonomyProposal(mode: .disable, summary: trimmedDraft)
        }
        return nil
    }

    private static func normalizedTitle(
        from text: String,
        fallbackLimit: Int,
        removingPrefixPattern: String
    ) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let rawTitle = firstLine ?? String(text.prefix(fallbackLimit))
        let normalizedTitle = rawTitle
            .replacingOccurrences(
                of: #"^([\-*•]\s+|\d+[.)]\s+)"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: removingPrefixPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedTitle.isEmpty ? String(fallbackTitle.prefix(fallbackLimit)) : String(normalizedTitle.prefix(fallbackLimit))
    }

    private static func strippedLeadingListPrefix(from message: String) -> String {
        message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^([\-*•]\s+|\d+[.)]\s+)"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func strippedLeadingSlashCommand(from message: String, commands: [String]) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return trimmed }
        let escapedCommands = commands.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = #"(?i)^\s*/("# + escapedCommands + #")(?=$|[:：\-\s])\s*[:：\-]?\s*"#
        return trimmed
            .replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

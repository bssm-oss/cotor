import Foundation

func parseCodexArguments(_ raw: String) -> [String] {
    var args: [String] = []
    var current = ""
    var quote: Character?
    var escaping = false

    for character in raw {
        if escaping {
            current.append(character)
            escaping = false
            continue
        }

        if character == "\\" {
            escaping = true
            continue
        }

        if let activeQuote = quote {
            if character == activeQuote {
                quote = nil
            } else {
                current.append(character)
            }
            continue
        }

        if character == "\"" || character == "'" {
            quote = character
            continue
        }

        if character.isWhitespace {
            if !current.isEmpty {
                args.append(current)
                current = ""
            }
        } else {
            current.append(character)
        }
    }

    if escaping {
        current.append("\\")
    }
    if !current.isEmpty {
        args.append(current)
    }
    return args
}

func operatorAutomationModeDisplayName(_ mode: String, language: AppLanguage) -> String {
    switch (language, mode.uppercased()) {
    case (.english, "FULL_AUTO"):
        return "Full auto"
    case (.english, "AGENT_APPROVED"):
        return "Internal approval"
    case (.english, "ASK_ME"):
        return "Confirm first"
    case (.korean, "FULL_AUTO"):
        return "완전 자동"
    case (.korean, "AGENT_APPROVED"):
        return "내부 승인"
    case (.korean, "ASK_ME"):
        return "확인 후 실행"
    default:
        return mode.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

func operatorActionStatusDisplayName(_ status: String, language: AppLanguage) -> String {
    switch (language, status.uppercased()) {
    case (.english, "USER_CONFIRMATION_REQUIRED"):
        return "Needs confirmation"
    case (.english, "AGENT_APPROVAL_REQUESTED"):
        return "Internal approval pending"
    case (.english, "READY"):
        return "Ready"
    case (.english, "ATTENTION"):
        return "Needs attention"
    case (.english, "NOOP"):
        return "Nothing changed"
    case (.korean, "USER_CONFIRMATION_REQUIRED"):
        return "확인 필요"
    case (.korean, "AGENT_APPROVAL_REQUESTED"):
        return "내부 승인 대기"
    case (.korean, "READY"):
        return "준비됨"
    case (.korean, "ATTENTION"):
        return "확인 필요"
    case (.korean, "NOOP"):
        return "변경 없음"
    default:
        return DesktopStrings.status(status, language: language)
    }
}

func sanitizeOperatorUserText(_ text: String, language: AppLanguage) -> String {
    var sanitized = text
    let replacements = [
        "FULL_AUTO": operatorAutomationModeDisplayName("FULL_AUTO", language: language),
        "AGENT_APPROVED": operatorAutomationModeDisplayName("AGENT_APPROVED", language: language),
        "ASK_ME": operatorAutomationModeDisplayName("ASK_ME", language: language),
        "USER_CONFIRMATION_REQUIRED": operatorActionStatusDisplayName("USER_CONFIRMATION_REQUIRED", language: language),
        "AGENT_APPROVAL_REQUESTED": operatorActionStatusDisplayName("AGENT_APPROVAL_REQUESTED", language: language),
        "STOPPED": DesktopStrings.status("STOPPED", language: language),
        "RUNNING": DesktopStrings.status("RUNNING", language: language)
    ]
    for (raw, replacement) in replacements {
        sanitized = sanitized.replacingOccurrences(of: raw, with: replacement)
    }
    sanitized = sanitized.replacingOccurrences(
        of: #"\bruntime=[^,\s.;)]+"#,
        with: "",
        options: .regularExpression
    )
    sanitized = sanitized.replacingOccurrences(
        of: #"\bbackend=[^,\s.;)]+"#,
        with: "",
        options: .regularExpression
    )
    return sanitized
        .replacingOccurrences(of: " ,", with: ",")
        .replacingOccurrences(of: "  ", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func preferredDesktopAgent(from agents: [String]) -> String? {
    let normalized = agents.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    if let opencode = normalized.first(where: { $0.caseInsensitiveCompare("opencode") == .orderedSame }) {
        return opencode
    }
    if let gemma4 = normalized.first(where: { $0.caseInsensitiveCompare("gemma4") == .orderedSame }) {
        return gemma4
    }
    if let ollama = normalized.first(where: { $0.caseInsensitiveCompare("ollama") == .orderedSame }) {
        return ollama
    }
    if let lmstudio = normalized.first(where: { $0.caseInsensitiveCompare("lmstudio") == .orderedSame }) {
        return lmstudio
    }
    if let qwen = normalized.first(where: { $0.caseInsensitiveCompare("qwen") == .orderedSame }) {
        return qwen
    }
    if let codexOAuth = normalized.first(where: { $0.caseInsensitiveCompare("codex-oauth") == .orderedSame }) {
        return codexOAuth
    }
    if let codex = normalized.first(where: { $0.caseInsensitiveCompare("codex") == .orderedSame }) {
        return codex
    }
    return normalized.first
}

func splitAgentMeta(_ raw: String) -> [String] {
    raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

func trimmedOptional(_ raw: String) -> String? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

import Foundation

func userFacingPathLabel(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }
    if trimmed.contains("://") {
        return trimmed
    }
    let name = URL(fileURLWithPath: trimmed).lastPathComponent
    return name.isEmpty ? trimmed : name
}

func userFacingIssueTitle(_ title: String, language: AppLanguage) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }

    if trimmed.hasPrefix("QA review ") {
        let nested = userFacingIssueTitle(String(trimmed.dropFirst("QA review ".count)), language: language)
        return language("QA review · \(nested)", "QA 검토 · \(nested)")
    }
    if trimmed.hasPrefix("CEO approve ") {
        let nested = userFacingIssueTitle(String(trimmed.dropFirst("CEO approve ".count)), language: language)
        return language("CEO approval · \(nested)", "CEO 확인 · \(nested)")
    }
    if trimmed.hasPrefix("CEO plan and delegate ") {
        let goal = quotedGoal(in: trimmed) ?? trailingGoal(after: " ", in: trimmed)
        return issueTitle("CEO planning", "CEO 작업 분배", goal: goal, language: language)
    }
    if trimmed.hasPrefix("Restore GitHub publishing for ") {
        let nested = userFacingIssueTitle(
            String(trimmed.dropFirst("Restore GitHub publishing for ".count)),
            language: language
        )
        return language("Connect GitHub · \(nested)", "GitHub 연결 설정 · \(nested)")
    }

    let goal = quotedGoal(in: trimmed) ?? trailingGoal(after: " for ", in: trimmed)
    if trimmed.hasPrefix("Deliver the first implementation slice for ") ||
        trimmed.hasPrefix("Build the first working change for ") {
        return issueTitle("First working change", "첫 작업 만들기", goal: goal, language: language)
    }
    if trimmed.hasPrefix("Advance a second branchable improvement slice for ") ||
        trimmed.hasPrefix("Improve another small part of ") {
        return issueTitle("Improve another part", "다음 부분 개선", goal: goal, language: language)
    }
    if trimmed.hasPrefix("Harden the integration and failure-handling path for ") ||
        (trimmed.hasPrefix("Make ") && trimmed.hasSuffix(" more reliable")) {
        return issueTitle("Improve reliability", "안정성 개선", goal: goal, language: language)
    }
    if trimmed.hasPrefix("Prepare validation evidence and residual-risk callouts for ") ||
        trimmed.hasPrefix("Check the result and write down any remaining risks for ") {
        return issueTitle("Check results and risks", "결과와 위험 확인", goal: goal, language: language)
    }
    return trimmed
}

func userFacingMemoryEvent(_ event: String, language: AppLanguage) -> String {
    let trimmed = event.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }
    if trimmed.hasPrefix("Started issue run: ") {
        let title = userFacingIssueTitle(String(trimmed.dropFirst("Started issue run: ".count)), language: language)
        return language("Started: \(title)", "시작: \(title)")
    }
    if trimmed.hasPrefix("Delegated issue: ") {
        let remainder = String(trimmed.dropFirst("Delegated issue: ".count))
        let title = remainder.components(separatedBy: " -> ").first ?? remainder
        return language(
            "Assigned: \(userFacingIssueTitle(title, language: language))",
            "배정: \(userFacingIssueTitle(title, language: language))"
        )
    }
    if trimmed.hasPrefix("Created infra issue: ") {
        let title = String(trimmed.dropFirst("Created infra issue: ".count))
        return language(
            "Created connection task: \(userFacingIssueTitle(title, language: language))",
            "연결 작업 생성: \(userFacingIssueTitle(title, language: language))"
        )
    }
    if trimmed.hasPrefix("Blocked code issue: ") {
        let reason = String(trimmed.dropFirst("Blocked code issue: ".count))
        return language(
            "Code work blocked: \(userFacingIssueDescription(reason, language: language))",
            "코드 작업 차단: \(userFacingIssueDescription(reason, language: language))"
        )
    }
    return userFacingIssueTitle(trimmed, language: language)
}

func userFacingIssueDescription(_ description: String, language: AppLanguage) -> String {
    let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }

    if trimmed.hasPrefix("CEO planning issue for the company goal.") {
        return language(
            "CEO is turning the goal into team work.",
            "CEO가 목표를 팀 작업으로 나누는 준비입니다."
        )
    }

    if trimmed.hasPrefix("QA review issue for a concrete pull request.") {
        if let executionIssue = labeledLineValue("Execution issue:", in: trimmed) {
            let title = userFacingIssueTitle(executionIssue, language: language)
            return language("QA is reviewing \(title).", "QA 검토 중: \(title)")
        }
        return language("QA is reviewing the finished work.", "QA가 완료된 작업을 검토합니다.")
    }

    if trimmed.contains("GitHub publishing is required before this code issue can continue.") ||
        trimmed.contains("GitHub PR mode requires an existing origin remote.") ||
        trimmed.contains("GitHub is not connected.") {
        return language(
            "Connect an existing GitHub repository before starting PR-based code work. Cotor will not create one automatically.",
            "PR 기반 코드 작업을 시작하려면 기존 GitHub 저장소를 먼저 연결해야 합니다. Cotor가 저장소를 자동으로 만들지는 않습니다."
        )
    }

    if trimmed.contains("Owned subtasks:") || trimmed.contains("Shared checklist:") || trimmed.hasPrefix("Goal:") {
        let role = labeledLineValue("Role:", in: trimmed)
        let phase = labeledLineValue("Phase:", in: trimmed)
        let focus = labeledLineValue("Focus:", in: trimmed)

        var parts: [String] = []
        if let role {
            parts.append(language("\(role) owns this work.", "\(role)이(가) 맡은 작업입니다."))
        }
        if let phase {
            parts.append(language("Stage: \(plainPhaseLabel(phase, language: language)).", "단계: \(plainPhaseLabel(phase, language: language))."))
        }
        if let focus, !containsInternalMemoryDetail(focus) {
            parts.append(language("Focus is already set.", "작업 방향이 정해져 있습니다."))
        }
        return parts.isEmpty
            ? language("Assigned team work with checks prepared.", "검증까지 준비된 팀 작업입니다.")
            : parts.joined(separator: " ")
    }

    if containsInternalMemoryDetail(trimmed) {
        return language("Details available in the issue record.", "세부 정보는 이슈 기록에서 확인할 수 있습니다.")
    }
    return trimmed
}

func userFacingIssueKind(_ kind: String, language: AppLanguage) -> String {
    switch kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "code":
        return language("Code work", "코드 작업")
    case "infra":
        return language("Connection", "연결 문제")
    case "execution":
        return language("Team work", "팀 작업")
    case "planning":
        return language("Planning", "계획")
    case "review":
        return language("Review", "검토")
    case "approval":
        return language("Approval", "승인")
    default:
        return kind.isEmpty ? "—" : kind
    }
}

func userFacingDecisionTitle(_ title: String, language: AppLanguage) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }
    if trimmed == "Fallback planned execution graph" {
        return language("Fallback execution plan", "기본 실행 계획")
    }
    return trimmed
}

func userFacingDecisionSummary(_ summary: String, language: AppLanguage) -> String {
    let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }
    if trimmed.contains("Fallback planner decomposed") {
        return language(
            "CEO planning needed a fallback, so Cotor split the goal into clear team issues.",
            "CEO 계획이 막혀 기본 계획으로 목표를 팀 이슈로 나눴습니다."
        )
    }
    if containsInternalMemoryDetail(trimmed) {
        return language("Details available in the issue record.", "세부 정보는 이슈 기록에서 확인할 수 있습니다.")
    }
    return trimmed
}

func userFacingActivityTitle(_ title: String, language: AppLanguage) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }
    switch trimmed {
    case "Created infra issue":
        return language("Created connection task", "연결 작업 생성")
    case "Blocked code issue":
        return language("Code work blocked", "코드 작업 차단")
    case "Unblocked code issue":
        return language("Code work unblocked", "코드 작업 재개")
    case "Resolved infra issue":
        return language("Connection task resolved", "연결 작업 해결")
    default:
        return userFacingIssueTitle(trimmed, language: language)
    }
}

func userFacingActivityDetail(_ detail: String, language: AppLanguage) -> String {
    let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "—" }
    if trimmed.hasPrefix("Restore GitHub publishing for ") {
        return userFacingIssueTitle(trimmed, language: language)
    }
    if trimmed.contains("GitHub publishing is required before this code issue can continue.") ||
        trimmed.contains("GitHub is not connected.") ||
        trimmed.contains("GitHub PR mode requires an existing origin remote.") {
        return userFacingIssueDescription(trimmed, language: language)
    }
    if trimmed.contains("Fallback planner decomposed") {
        return userFacingDecisionSummary(trimmed, language: language)
    }
    if trimmed.contains("Owned subtasks:") || trimmed.hasPrefix("Goal:") || trimmed.hasPrefix("QA review issue for") {
        return userFacingIssueDescription(trimmed, language: language)
    }
    if containsInternalMemoryDetail(trimmed) {
        return language("Details available in the issue record.", "세부 정보는 이슈 기록에서 확인할 수 있습니다.")
    }
    return trimmed
}

func localizedSourceKind(_ sourceKind: String, language: AppLanguage) -> String {
    switch sourceKind.uppercased() {
    case "LOCAL":
        return language("Local", "로컬")
    case "CLONED":
        return language("Cloned", "복제됨")
    default:
        return sourceKind
    }
}

private func containsInternalMemoryDetail(_ value: String) -> Bool {
    let lowered = value.lowercased()
    return lowered.contains("/users/")
        || lowered.contains("graphify ")
        || lowered.contains("graphify=")
        || lowered.contains(".json")
}

private func labeledLineValue(_ label: String, in value: String) -> String? {
    let lines = value.split(whereSeparator: \.isNewline).map(String.init)
    for (index, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(label) {
            let inline = trimmed.dropFirst(label.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !inline.isEmpty {
                return inline
            }
            let nextIndex = index + 1
            guard nextIndex < lines.count else { return nil }
            let next = lines[nextIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            return next.isEmpty ? nil : next
        }
    }
    return nil
}

private func plainPhaseLabel(_ phase: String, language: AppLanguage) -> String {
    switch phase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "planning":
        return language("planning", "계획")
    case "execution":
        return language("execution", "실행")
    case "review":
        return language("review", "검토")
    case "approval":
        return language("approval", "승인")
    default:
        return phase
    }
}

private func quotedGoal(in value: String) -> String? {
    guard let firstQuote = value.firstIndex(of: "\"") else { return nil }
    let afterFirst = value.index(after: firstQuote)
    guard let secondQuote = value[afterFirst...].firstIndex(of: "\"") else { return nil }
    let goal = String(value[afterFirst..<secondQuote]).trimmingCharacters(in: .whitespacesAndNewlines)
    return goal.isEmpty ? nil : goal
}

private func trailingGoal(after marker: String, in value: String) -> String? {
    guard let markerRange = value.range(of: marker, options: [.backwards]) else { return nil }
    let goal = value[markerRange.upperBound...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return goal.isEmpty ? nil : goal
}

private func issueTitle(_ english: String, _ korean: String, goal: String?, language: AppLanguage) -> String {
    guard let goal, !goal.isEmpty else {
        return language(english, korean)
    }
    return language("\(english) · \(goal)", "\(korean) · \(goal)")
}

import Foundation

struct AgentSkillChipRecord: Identifiable, Hashable {
    let id: String
    let displayName: String
}

enum AgentSkillScope: String, CaseIterable, Identifiable, Hashable {
    case repositoryMap
    case browserQA
    case marketing
    case video
    case videoRender
    case videoUpload
    case buildTest
    case qaReview

    var id: String { rawValue }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .repositoryMap:
            return language("Repository Map", "리포지토리 맵")
        case .browserQA:
            return language("Browser QA", "브라우저 QA")
        case .marketing:
            return language("Marketing", "마케팅")
        case .video:
            return language("Video", "비디오")
        case .videoRender:
            return language("Video Render", "비디오 렌더")
        case .videoUpload:
            return language("Video Upload", "비디오 업로드")
        case .buildTest:
            return language("Build/Test", "코딩/빌드")
        case .qaReview:
            return language("QA/Review", "QA/리뷰")
        }
    }
}

enum AgentSkillPolicy: String, CaseIterable, Identifiable, Hashable {
    case auto = "AUTO"
    case approvalRequired = "APPROVAL_REQUIRED"
    case readOnly = "READ_ONLY"
    case disabled = "DISABLED"

    var id: String { rawValue }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .auto: return language("Auto", "자동 실행")
        case .approvalRequired: return language("Approval Required", "확인 후 실행")
        case .readOnly: return language("Read Only", "읽기 전용")
        case .disabled: return language("Disabled", "비활성")
        }
    }
}

struct AgentSkillCardRecord: Identifiable, Hashable {
    let id: String
    let companyId: String
    let title: String
    let agentCli: String
    let model: String?
    let roleSummary: String
    let enabled: Bool
    let selectedSkills: [AgentSkillChipRecord]
    /// Skills that can be launched immediately (SKILL_RUN=AUTO, all required capabilities also AUTO).
    let runnableSkills: [AgentSkillChipRecord]
    /// First skill that can be launched without approval; nil when no skill is immediately runnable.
    let primaryRunnableSkill: AgentSkillChipRecord?
    /// Per-skill reason why a selected skill is not immediately runnable.
    let blockedSkillReasons: [String: String]
    let capabilityScopes: [AgentSkillScope]
    let policyChips: [AgentSkillPolicy]
    let hasDisabledCapabilities: Bool
    let recentRun: SkillRunRecord?

    init(
        agent: CompanyAgentDefinitionRecord,
        profile: AgentCapabilityProfileRecord?,
        skillCatalog: [SkillCatalogEntryRecord],
        defaultSkillIDs: Set<String> = [],
        recentRuns: [SkillRunRecord] = []
    ) {
        id = agent.id
        companyId = agent.companyId
        title = agent.title
        agentCli = agent.agentCli
        model = agent.model
        roleSummary = agent.roleSummary
        enabled = agent.enabled

        let settings = profile?.settings ?? [:]
        let catalogByID = Dictionary(
            skillCatalog.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let selectedSkillIDs = Self.selectedSkillIDs(
            from: settings["SKILL_RUN"],
            defaultSkillIDs: defaultSkillIDs
        )
        selectedSkills = selectedSkillIDs.map { skillID in
            AgentSkillChipRecord(
                id: skillID,
                displayName: catalogByID[skillID]?.displayName ?? Self.fallbackSkillDisplayName(skillID)
            )
        }

        // Derive runnable skills: SKILL_RUN must be AUTO and all required capabilities must also be AUTO.
        let skillRunPolicy = settings["SKILL_RUN"].map { Self.policy(for: $0) }
        var runnableIDs: [String] = []
        var blockedReasons: [String: String] = [:]
        for skillID in selectedSkillIDs {
            let reqs = catalogByID[skillID]?.requiredCapabilities ?? []
            if skillRunPolicy == .auto {
                let blockedCap = reqs.first { cap in
                    let norm = Self.normalizedCapability(cap)
                    guard let s = settings[norm] else { return true }
                    return Self.policy(for: s) != .auto
                }
                if let cap = blockedCap {
                    blockedReasons[skillID] = "capability_\(Self.normalizedCapability(cap))_not_auto"
                } else {
                    runnableIDs.append(skillID)
                }
            } else if skillRunPolicy == .approvalRequired {
                blockedReasons[skillID] = "approval_required"
            } else {
                blockedReasons[skillID] = "not_configured"
            }
        }
        let runnableChips = runnableIDs.map { skillID in
            AgentSkillChipRecord(
                id: skillID,
                displayName: catalogByID[skillID]?.displayName ?? Self.fallbackSkillDisplayName(skillID)
            )
        }
        runnableSkills = runnableChips
        primaryRunnableSkill = runnableChips.first
        blockedSkillReasons = blockedReasons

        var activeCapabilityKeys = Set<String>()
        for skillID in selectedSkillIDs {
            for capability in catalogByID[skillID]?.requiredCapabilities ?? [] {
                activeCapabilityKeys.insert(Self.normalizedCapability(capability))
            }
        }
        for (capability, setting) in settings where Self.isActive(setting) {
            activeCapabilityKeys.insert(Self.normalizedCapability(capability))
        }

        var scopes: [AgentSkillScope] = []
        for skillID in selectedSkillIDs {
            Self.appendScopes(Self.scopes(forSkillID: skillID), to: &scopes)
        }
        for capability in activeCapabilityKeys.sorted() {
            Self.appendScopes(Self.scopes(forCapability: capability), to: &scopes)
        }
        if Self.hasQAReviewSignal(agent) {
            Self.appendScopes([.qaReview], to: &scopes)
        }
        capabilityScopes = scopes

        var policies = Set<AgentSkillPolicy>()
        var disabledCapabilitiesFound = false
        if let skillRun = settings["SKILL_RUN"] {
            let p = Self.policy(for: skillRun)
            if p == .disabled { disabledCapabilitiesFound = true } else { policies.insert(p) }
        }
        for (capability, setting) in settings {
            let normalized = Self.normalizedCapability(capability)
            guard activeCapabilityKeys.contains(normalized), !["SKILL_RUN"].contains(normalized) else { continue }
            guard !Self.scopes(forCapability: normalized).isEmpty else { continue }
            let p = Self.policy(for: setting)
            if p == .disabled { disabledCapabilitiesFound = true } else { policies.insert(p) }
        }
        policyChips = AgentSkillPolicy.allCases.filter { policies.contains($0) }
        hasDisabledCapabilities = agent.enabled && disabledCapabilitiesFound
        let selectedSkillSet = Set(selectedSkillIDs)
        recentRun = recentRuns
            .filter { $0.companyId == agent.companyId && $0.agentId == agent.id && selectedSkillSet.contains($0.skill) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    private static func selectedSkillIDs(
        from skillRunSetting: AgentCapabilitySettingRecord?,
        defaultSkillIDs: Set<String>
    ) -> [String] {
        guard let setting = skillRunSetting, isActive(setting) else { return [] }
        // Empty allowlist means "no explicit delegation" — not "all default skills".
        // An operator must name the skills they want to delegate.
        guard !setting.skillAllowlist.isEmpty else { return [] }
        return Array(Set(setting.skillAllowlist)).sorted()
    }

    private static func isActive(_ setting: AgentCapabilitySettingRecord) -> Bool {
        setting.enabled && normalizedCapability(setting.mode) != "DISABLED"
    }

    private static func policy(for setting: AgentCapabilitySettingRecord) -> AgentSkillPolicy {
        guard setting.enabled else { return .disabled }
        switch normalizedCapability(setting.mode) {
        case "AUTO":
            return .auto
        case "READ_ONLY":
            return .readOnly
        case "DISABLED":
            return .disabled
        default:
            return .approvalRequired
        }
    }

    private static func scopes(forSkillID skillID: String) -> [AgentSkillScope] {
        switch normalizedSkillID(skillID) {
        case "graphify":
            return [.repositoryMap]
        case "browser-smoke":
            return [.browserQA]
        case "marketing-operator":
            return [.marketing]
        case "video-plan":
            return [.video]
        default:
            return []
        }
    }

    private static func scopes(forCapability capability: String) -> [AgentSkillScope] {
        switch normalizedCapability(capability) {
        case "KNOWLEDGE_GRAPH_READ", "GRAPH_READ":
            return [.repositoryMap]
        case "BROWSER_READ", "BROWSER_SCREENSHOT":
            return [.browserQA]
        case "WEB_PUBLISH", "SOCIAL_POST_CREATE":
            return [.marketing]
        case "VIDEO_SCRIPT_WRITE":
            return [.video]
        case "VIDEO_RENDER_LOCAL", "VIDEO_GENERATE_REMOTE", "VIDEO_TRANSCODE":
            return [.videoRender]
        case "VIDEO_UPLOAD":
            return [.videoUpload]
        case "TEST_RUN", "BUILD_RUN", "LINT_RUN":
            return [.buildTest]
        default:
            return []
        }
    }

    private static func appendScopes(_ incoming: [AgentSkillScope], to scopes: inout [AgentSkillScope]) {
        for scope in incoming where !scopes.contains(scope) {
            scopes.append(scope)
        }
    }

    private static func hasQAReviewSignal(_ agent: CompanyAgentDefinitionRecord) -> Bool {
        let text = ([agent.title, agent.roleSummary] + agent.specialties)
            .joined(separator: " ")
            .lowercased()
        return ["qa", "review", "verification"].contains { text.contains($0) }
    }

    private static func fallbackSkillDisplayName(_ skillID: String) -> String {
        skillID
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private static func normalizedSkillID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedCapability(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
    }
}

extension DesktopStore {
    var agentSkillCards: [AgentSkillCardRecord] {
        companyAgentDefinitions.map { agent in
            let profile = dashboard.agentCapabilityProfiles.first {
                $0.companyId == agent.companyId && $0.agentId == agent.id
            }
            return AgentSkillCardRecord(
                agent: agent,
                profile: profile,
                skillCatalog: availableSkills,
                defaultSkillIDs: defaultCompanyAgentSkillIDs,
                recentRuns: skillRuns
            )
        }
    }
}

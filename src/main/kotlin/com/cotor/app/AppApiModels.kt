package com.cotor.app

/**
 * File overview for OpenRepositoryRequest.
 *
 * This file belongs to the app layer for the desktop shell and localhost app-server surface.
 * It groups declarations around app api models so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import kotlinx.serialization.Serializable

/**
 * Request payload for registering an existing local git checkout.
 */
@Serializable
data class CompanyMemorySnapshotResponse(
    val companyMemory: String,
    val workflowMemory: String,
    val agentMemory: String,
    val projectMemory: String = workflowMemory,
    val teamMemory: String = ""
)

@Serializable
data class OpenRepositoryRequest(
    val path: String
)

/**
 * Request payload for cloning a remote repository into the app-managed area.
 */
@Serializable
data class CloneRepositoryRequest(
    val url: String
)

/**
 * Request payload for creating a branch-pinned workspace under a repository.
 */
@Serializable
data class CreateWorkspaceRequest(
    val repositoryId: String,
    val name: String? = null,
    val baseBranch: String? = null
)

@Serializable
data class UpdateWorkspaceBaseBranchRequest(
    val baseBranch: String
)

/**
 * Request payload for creating a multi-agent task from the desktop shell.
 */
@Serializable
data class CreateTaskRequest(
    val workspaceId: String,
    val title: String? = null,
    val prompt: String,
    val agents: List<String> = emptyList(),
    val issueId: String? = null
)

/**
 * Request payload for creating an autonomous company goal.
 */
@Serializable
data class CreateGoalRequest(
    val title: String,
    val description: String,
    val successMetrics: List<String> = emptyList(),
    val autonomyEnabled: Boolean = true
)

@Serializable
data class ChatIntakeRequest(
    val message: String,
    val startRuntime: Boolean = false
)

@Serializable
data class ChatAssignmentPreview(
    val issueId: String,
    val title: String,
    val assigneeRole: String? = null,
    val phase: String,
    val reason: String
)

@Serializable
data class ChatIntakeResponse(
    val goal: CompanyGoal,
    val planningIssue: CompanyIssue? = null,
    val issues: List<CompanyIssue>,
    val ceoBrief: String,
    val assignmentPreview: List<ChatAssignmentPreview>,
    val message: AgentMessage
)

@Serializable
data class OperatorCommandRequest(
    val message: String,
    val automationMode: OperatorAutomationMode? = null,
    val confirmFullAuto: Boolean = false,
    val confirmStaffing: Boolean = false
)

@Serializable
data class RuntimeCleanupRequest(
    val companyId: String? = null,
    val allCompanies: Boolean = false,
    val olderThanDays: Int? = null,
    val dryRun: Boolean = true,
    val apply: Boolean = false
)

@Serializable
data class RuntimeCleanupCandidate(
    val id: String,
    val kind: String,
    val classification: String,
    val companyId: String? = null,
    val path: String? = null,
    val processId: Long? = null,
    val ageDays: Long? = null,
    val eligible: Boolean,
    val reason: String
)

@Serializable
data class RuntimeCleanupPreview(
    val companyId: String? = null,
    val allCompanies: Boolean = false,
    val generatedAt: Long,
    val terminalRetentionDays: Int,
    val orphanRetentionDays: Int,
    val candidates: List<RuntimeCleanupCandidate> = emptyList(),
    val eligibleCount: Int = candidates.count { it.eligible },
    val protectedCount: Int = candidates.count { !it.eligible }
)

@Serializable
data class RuntimeCleanupResult(
    val dryRun: Boolean,
    val preview: RuntimeCleanupPreview,
    val deletedWorktreeCount: Int = 0,
    val terminatedProcessCount: Int = 0,
    val skippedCount: Int = preview.protectedCount,
    val errors: List<String> = emptyList()
)

@Serializable
data class OperatorCommandAction(
    val type: String,
    val title: String,
    val detail: String,
    val status: String
)

@Serializable
data class OperatorCompanySummary(
    val runtimeStatus: String,
    val backendHealth: String,
    val activeAgentCount: Int,
    val blockedIssueCount: Int,
    val reviewQueueCount: Int,
    val pendingApprovalCount: Int,
    val budgetPaused: Boolean
)

@Serializable
data class OperatorCommandResponse(
    val message: String,
    val automationMode: OperatorAutomationMode,
    val actions: List<OperatorCommandAction> = emptyList(),
    val pendingApprovals: List<OperatorCommandAction> = emptyList(),
    val blockedActions: List<OperatorCommandAction> = emptyList(),
    val summary: OperatorCompanySummary? = null
)

@Serializable
data class OperatorAnswerSource(
    val type: String,
    val title: String,
    val detail: String? = null,
    val refId: String? = null
)

@Serializable
data class OperatorChatResponse(
    val message: String,
    val automationMode: OperatorAutomationMode,
    val actions: List<OperatorCommandAction> = emptyList(),
    val pendingApprovals: List<OperatorCommandAction> = emptyList(),
    val blockedActions: List<OperatorCommandAction> = emptyList(),
    val summary: OperatorCompanySummary? = null,
    val answerSources: List<OperatorAnswerSource> = emptyList()
)

@Serializable
data class UpdateGoalRequest(
    val title: String? = null,
    val description: String? = null,
    val successMetrics: List<String>? = null,
    val autonomyEnabled: Boolean? = null
)

@Serializable
data class CreateIssueRequest(
    val goalId: String,
    val title: String,
    val description: String,
    val priority: Int = 3,
    val kind: String = "manual"
)

@Serializable
data class CreateCompanyRequest(
    val name: String,
    val rootPath: String,
    val defaultBaseBranch: String? = null,
    val autonomyEnabled: Boolean = true,
    val operatorAutomationMode: OperatorAutomationMode? = null,
    val dailyBudgetCents: Int? = null,
    val monthlyBudgetCents: Int? = null
)

@Serializable
data class CreateCompanyResponse(
    val company: Company,
    val githubPublishStatus: GitHubPublishStatus
)

@Serializable
data class ConfigureGitHubOriginRequest(
    val remoteUrl: String
)

@Serializable
data class UpdateCompanyRequest(
    val name: String? = null,
    val defaultBaseBranch: String? = null,
    val autonomyEnabled: Boolean? = null,
    val backendKind: ExecutionBackendKind? = null,
    val dailyBudgetCents: Int? = null,
    val monthlyBudgetCents: Int? = null
)

@Serializable
data class UpdateCompanyLinearRequest(
    val enabled: Boolean,
    val endpoint: String? = null,
    val apiToken: String? = null,
    val teamId: String? = null,
    val projectId: String? = null,
    val stateMappings: List<LinearStateMapping>? = null,
    val useGlobalDefault: Boolean = false
)

@Serializable
data class CreateCompanyAgentDefinitionRequest(
    val title: String,
    val agentCli: String,
    val model: String? = null,
    val roleSummary: String,
    val specialties: List<String> = emptyList(),
    val collaborationInstructions: String? = null,
    val preferredCollaboratorIds: List<String> = emptyList(),
    val mentorAgentId: String? = null,
    val memoryNotes: String? = null,
    val enabled: Boolean = true
)

@Serializable
data class UpdateCompanyAgentDefinitionRequest(
    val title: String? = null,
    val agentCli: String? = null,
    val model: String? = null,
    val roleSummary: String? = null,
    val specialties: List<String>? = null,
    val collaborationInstructions: String? = null,
    val preferredCollaboratorIds: List<String>? = null,
    val mentorAgentId: String? = null,
    val memoryNotes: String? = null,
    val enabled: Boolean? = null,
    val displayOrder: Int? = null
)

@Serializable
data class BatchUpdateCompanyAgentDefinitionsRequest(
    val agentIds: List<String>,
    val agentCli: String? = null,
    val model: String? = null,
    val specialties: List<String>? = null,
    val enabled: Boolean? = null
)

@Serializable
data class UpdateBackendSettingsRequest(
    val defaultBackendKind: ExecutionBackendKind,
    val codePublishMode: CodePublishMode? = null,
    val codexLaunchMode: BackendLaunchMode? = null,
    val codexCommand: String? = null,
    val codexArgs: List<String>? = null,
    val codexWorkingDirectory: String? = null,
    val codexPort: Int? = null,
    val codexStartupTimeoutSeconds: Int? = null,
    val codexAppServerBaseUrl: String? = null,
    val codexAuthMode: String? = null,
    val codexToken: String? = null,
    val codexTimeoutSeconds: Int? = null
)

@Serializable
data class UpdateCompanyBackendRequest(
    val backendKind: ExecutionBackendKind,
    val launchMode: BackendLaunchMode? = null,
    val command: String? = null,
    val args: List<String>? = null,
    val workingDirectory: String? = null,
    val port: Int? = null,
    val startupTimeoutSeconds: Int? = null,
    val baseUrl: String? = null,
    val authMode: String? = null,
    val token: String? = null,
    val timeoutSeconds: Int? = null,
    val useGlobalDefault: Boolean = false
)

@Serializable
data class TestBackendRequest(
    val kind: ExecutionBackendKind,
    val launchMode: BackendLaunchMode? = null,
    val command: String? = null,
    val args: List<String>? = null,
    val workingDirectory: String? = null,
    val port: Int? = null,
    val startupTimeoutSeconds: Int? = null,
    val baseUrl: String? = null,
    val authMode: String? = null,
    val token: String? = null,
    val timeoutSeconds: Int? = null
)

@Serializable
data class DurableContinueRequest(
    val configPath: String? = null
)

@Serializable
data class DurableForkRequest(
    val checkpointId: String,
    val configPath: String? = null
)

@Serializable
data class DurableApproveRequest(
    val checkpointId: String? = null
)

@Serializable
data class CompanyEventEnvelope(
    val event: CompanyEvent,
    val dashboard: DashboardResponse? = null,
    val companyDashboard: CompanyDashboardResponse? = null
)

@Serializable
data class LinearSyncResponse(
    val ok: Boolean,
    val message: String,
    val syncedIssues: Int = 0,
    val createdIssues: Int = 0,
    val commentedIssues: Int = 0,
    val failedIssues: List<String> = emptyList()
)

/**
 * Focused autonomous-company dashboard contract used by the operations UI.
 */
@Serializable
data class CompanyDashboardResponse(
    val companies: List<Company> = emptyList(),
    val companyAgentDefinitions: List<CompanyAgentDefinition> = emptyList(),
    val agentCapabilityProfiles: List<AgentCapabilityProfile> = emptyList(),
    val projectContexts: List<CompanyProjectContext> = emptyList(),
    val goals: List<CompanyGoal> = emptyList(),
    val issues: List<CompanyIssue> = emptyList(),
    val tasks: List<AgentTask> = emptyList(),
    val issueDependencies: List<IssueDependency> = emptyList(),
    val reviewQueue: List<ReviewQueueItem> = emptyList(),
    val orgProfiles: List<OrgAgentProfile> = emptyList(),
    val workflowTopologies: List<WorkflowTopologySnapshot> = emptyList(),
    val goalDecisions: List<GoalOrchestrationDecision> = emptyList(),
    val runningAgentSessions: List<RunningAgentSession> = emptyList(),
    val backendStatuses: List<ExecutionBackendStatus> = emptyList(),
    val opsMetrics: OpsMetricSnapshot = OpsMetricSnapshot(),
    val runtime: CompanyRuntimeSnapshot = CompanyRuntimeSnapshot(),
    val signals: List<OpsSignal> = emptyList(),
    val activity: List<CompanyActivityItem> = emptyList(),
    val agentContextEntries: List<AgentContextEntry> = emptyList(),
    val agentMessages: List<AgentMessage> = emptyList(),
    val marketingDelegationPolicies: List<MarketingDelegationPolicy> = emptyList(),
    val marketingRuns: List<MarketingRunRecord> = emptyList(),
    val skillRuns: List<SkillRunRecord> = emptyList(),
    val agentPerformance: List<AgentPerformanceSnapshot> = emptyList()
)

internal fun BackendConnectionConfig.redactedForApi(): BackendConnectionConfig = copy(token = null)

internal fun ExecutionBackendStatus.redactedForApi(): ExecutionBackendStatus = copy(config = config.redactedForApi())

internal fun LinearConnectionConfig.redactedForApi(): LinearConnectionConfig = copy(apiToken = null)

internal fun DesktopLinearSettings.redactedForApi(): DesktopLinearSettings = copy(defaultConfig = defaultConfig.redactedForApi())

internal fun DesktopBackendSettings.redactedForApi(): DesktopBackendSettings = copy(
    backends = backends.map { it.redactedForApi() }
)

internal fun Company.redactedForApi(): Company = copy(
    backendConfigOverride = backendConfigOverride?.redactedForApi(),
    linearConfigOverride = linearConfigOverride?.redactedForApi()
)

internal fun DesktopSettings.redactedForApi(): DesktopSettings = copy(
    backendSettings = backendSettings.redactedForApi(),
    linearSettings = linearSettings.redactedForApi(),
    backendStatuses = backendStatuses.map { it.redactedForApi() }
)

// ── Direct Chat API Models ──────────────────────────────────────────

@Serializable
data class CreateDirectChatConversationRequest(
    val title: String = "",
    val model: String,
    val provider: String,
    val baseUrl: String = "",
    val systemPrompt: String = ""
)

@Serializable
data class SendDirectChatMessageRequest(val message: String)

@Serializable
data class DirectChatStreamChunk(
    val conversationId: String,
    val messageId: String,
    val content: String,
    val done: Boolean = false,
    val error: String? = null
)

@Serializable
data class DirectChatAvailableModel(
    val id: String,
    val provider: String,
    val displayName: String
)

internal fun CompanyDashboardResponse.redactedForApi(): CompanyDashboardResponse = copy(
    companies = companies.map { it.redactedForApi() },
    backendStatuses = backendStatuses.map { it.redactedForApi() }
)

/**
 * Top-level bootstrap response consumed by the Swift client after launch/refresh.
 */
@Serializable
data class DashboardResponse(
    val repositories: List<ManagedRepository>,
    val workspaces: List<Workspace>,
    val tasks: List<AgentTask>,
    val settings: DesktopSettings,
    val companies: List<Company> = emptyList(),
    val companyAgentDefinitions: List<CompanyAgentDefinition> = emptyList(),
    val agentCapabilityProfiles: List<AgentCapabilityProfile> = emptyList(),
    val projectContexts: List<CompanyProjectContext> = emptyList(),
    val goals: List<CompanyGoal> = emptyList(),
    val issues: List<CompanyIssue> = emptyList(),
    val reviewQueue: List<ReviewQueueItem> = emptyList(),
    val orgProfiles: List<OrgAgentProfile> = emptyList(),
    val workflowTopologies: List<WorkflowTopologySnapshot> = emptyList(),
    val goalDecisions: List<GoalOrchestrationDecision> = emptyList(),
    val runningAgentSessions: List<RunningAgentSession> = emptyList(),
    val backendStatuses: List<ExecutionBackendStatus> = emptyList(),
    val opsMetrics: OpsMetricSnapshot = OpsMetricSnapshot(),
    val activity: List<CompanyActivityItem> = emptyList(),
    val companyRuntimes: List<CompanyRuntimeSnapshot> = emptyList(),
    val agentContextEntries: List<AgentContextEntry> = emptyList(),
    val agentMessages: List<AgentMessage> = emptyList(),
    val marketingDelegationPolicies: List<MarketingDelegationPolicy> = emptyList(),
    val marketingRuns: List<MarketingRunRecord> = emptyList(),
    val skillRuns: List<SkillRunRecord> = emptyList(),
    val agentPerformance: List<AgentPerformanceSnapshot> = emptyList()
)

internal fun DashboardResponse.redactedForApi(): DashboardResponse = copy(
    settings = settings.redactedForApi(),
    companies = companies.map { it.redactedForApi() },
    backendStatuses = backendStatuses.map { it.redactedForApi() }
)

/**
 * Minimal readiness signal used by the desktop app before it attempts auth.
 */
@Serializable
data class HealthResponse(
    val ok: Boolean,
    val service: String,
    val owner: String = "cotor-desktop",
    val version: String = "unknown",
    val build: String = "unknown"
)

// ── Pipeline API Models ─────────────────────────────────────────────

@Serializable
data class CreatePipelineRequest(
    val name: String,
    val stages: List<PipelineStageRequest>
)

@Serializable
data class UpdatePipelineRequest(
    val name: String? = null,
    val stages: List<PipelineStageRequest>? = null
)

@Serializable
data class PipelineStageRequest(
    val id: String? = null,
    val kind: String,
    val title: String,
    val assigneeRoleName: String? = null,
    val verdictKey: String? = null,
    val verdictPassValue: String? = null,
    val verdictFailValue: String? = null,
    val skipWhen: String? = null
)

// ── Context Entry API Models ────────────────────────────────────────

@Serializable
data class CreateContextEntryRequest(
    val agentName: String,
    val kind: String,
    val title: String,
    val content: String,
    val issueId: String? = null,
    val goalId: String? = null,
    val visibility: String? = null
)

// ── Agent Message API Models ────────────────────────────────────────

@Serializable
data class BudgetResponse(
    val dailyBudgetCents: Int? = null,
    val monthlyBudgetCents: Int? = null,
    val todaySpentCents: Int = 0,
    val monthSpentCents: Int = 0,
    val budgetPaused: Boolean = false
)

@Serializable
data class IssueRuntimeProjection(
    val issue: CompanyIssue,
    val reviewQueueItem: ReviewQueueItem? = null,
    val runtime: CompanyRuntimeSnapshot
)

@Serializable
data class SendMessageRequest(
    val fromAgentName: String,
    val toAgentName: String? = null,
    val kind: String,
    val subject: String,
    val body: String,
    val issueId: String? = null,
    val goalId: String? = null
)

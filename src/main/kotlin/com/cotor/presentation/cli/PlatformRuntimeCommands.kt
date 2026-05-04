package com.cotor.presentation.cli

import com.cotor.app.AppServer
import com.cotor.app.BrowserSmokeRequest
import com.cotor.app.CapabilityKey
import com.cotor.app.DesktopAppService
import com.cotor.app.VideoPlanRequest
import com.cotor.app.capabilityCatalog
import com.cotor.policy.PolicyDocument
import com.cotor.policy.PolicyEngine
import com.cotor.policy.PolicyStore
import com.cotor.runtime.actions.ActionKind
import com.cotor.runtime.actions.ActionRequest
import com.cotor.runtime.actions.ActionScope
import com.cotor.runtime.actions.ActionSubject
import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.subcommands
import com.github.ajalt.clikt.parameters.arguments.argument
import com.github.ajalt.clikt.parameters.options.default
import com.github.ajalt.clikt.parameters.options.flag
import com.github.ajalt.clikt.parameters.options.option
import com.github.ajalt.clikt.parameters.options.required
import com.github.ajalt.clikt.parameters.types.int
import com.github.ajalt.clikt.parameters.types.path
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

private val platformJson = Json {
    prettyPrint = true
    encodeDefaults = true
}

class PolicyCommand : CliktCommand(name = "policy", help = "Validate and simulate policy decisions.") {
    init {
        subcommands(PolicyValidateCommand(), PolicySimulateCommand())
    }

    override fun run() = Unit
}

class CapabilityCommand : CliktCommand(name = "capability", help = "Inspect and simulate agent capability gates.") {
    init {
        subcommands(CapabilityListCommand(), CapabilityInspectCommand(), CapabilitySimulateCommand())
    }

    override fun run() = Unit
}

class ProviderCommand : CliktCommand(name = "provider", help = "Inspect local provider availability without network or cost side effects.") {
    init {
        subcommands(ProviderListCommand(), ProviderScanCommand(), ProviderTestCommand())
    }

    override fun run() = Unit
}

class SkillCommand : CliktCommand(name = "skill", help = "Inspect, validate, and gate skill runs.") {
    init {
        subcommands(SkillListCommand(), SkillInspectCommand(), SkillValidateCommand(), SkillRunCommand())
    }

    override fun run() = Unit
}

class BrowserCommand : CliktCommand(name = "browser", help = "Plan guarded browser automation with capability gates.") {
    init {
        subcommands(BrowserSmokeCommand())
    }

    override fun run() = Unit
}

class VideoCommand : CliktCommand(name = "video", help = "Plan guarded video work with capability gates.") {
    init {
        subcommands(VideoPlanCommand(), VideoRenderCommand(), VideoTranscodeCommand(), VideoGenerateRemoteCommand())
    }

    override fun run() = Unit
}

private abstract class VideoBaseCommand(name: String, help: String) : CliktCommand(name = name, help = help), KoinComponent {
    protected val desktopService: DesktopAppService by inject()
    protected val companyId by option("--company").required()
    protected val agentId by option("--agent").required()
    protected val issueId by option("--issue")
    protected val prompt by option("--prompt")
    protected val projectPath by option("--project")
    protected val inputPath by option("--input")
    protected val outputPath by option("--output")
    protected val provider by option("--provider")

    protected fun request(): VideoPlanRequest = VideoPlanRequest(
        companyId = companyId,
        agentId = agentId,
        issueId = issueId,
        prompt = prompt,
        projectPath = projectPath,
        inputPath = inputPath,
        outputPath = outputPath,
        provider = provider
    )
}

private class VideoPlanCommand : VideoBaseCommand(name = "plan", help = "Plan video script work for one company agent.") {
    override fun run() = runBlocking {
        echo(platformJson.encodeToString(desktopService.planVideoScript(request())))
    }
}

private class VideoRenderCommand : VideoBaseCommand(name = "render", help = "Plan a local video render for one company agent.") {
    override fun run() = runBlocking {
        echo(platformJson.encodeToString(desktopService.planVideoRenderLocal(request())))
    }
}

private class VideoTranscodeCommand : VideoBaseCommand(name = "transcode", help = "Plan a local video transcode for one company agent.") {
    override fun run() = runBlocking {
        echo(platformJson.encodeToString(desktopService.planVideoTranscode(request())))
    }
}

private class VideoGenerateRemoteCommand : VideoBaseCommand(name = "generate-remote", help = "Plan a remote video generation call for one company agent.") {
    override fun run() = runBlocking {
        echo(platformJson.encodeToString(desktopService.planVideoGenerateRemote(request())))
    }
}

private class BrowserSmokeCommand : CliktCommand(name = "smoke", help = "Plan a browser smoke check for one company agent."), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val companyId by option("--company").required()
    private val agentId by option("--agent").required()
    private val url by option("--url").required()
    private val screenshot by option("--screenshot").flag(default = false)
    private val trace by option("--trace").flag(default = false)
    private val record by option("--record").flag(default = false)
    private val interact by option("--interact").flag(default = false)

    override fun run() = runBlocking {
        echo(
            platformJson.encodeToString(
                desktopService.planBrowserSmoke(
                    BrowserSmokeRequest(
                        companyId = companyId,
                        agentId = agentId,
                        url = url,
                        screenshot = screenshot,
                        trace = trace,
                        record = record,
                        interact = interact
                    )
                )
            )
        )
    }
}

private class SkillListCommand : CliktCommand(name = "list", help = "List known skills."), KoinComponent {
    private val desktopService: DesktopAppService by inject()

    override fun run() {
        echo(platformJson.encodeToString(desktopService.skillCatalog()))
    }
}

private class SkillInspectCommand : CliktCommand(name = "inspect", help = "Inspect one skill."), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val name by argument("name")

    override fun run() {
        echo(platformJson.encodeToString(desktopService.inspectSkill(name)))
    }
}

private class SkillValidateCommand : CliktCommand(name = "validate", help = "Validate one skill manifest."), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val path by argument("path").path(mustExist = true)

    override fun run() {
        echo(platformJson.encodeToString(desktopService.validateSkill(path.toString())))
    }
}

private class SkillRunCommand : CliktCommand(name = "run", help = "Run the backend skill gate for one company agent."), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val name by argument("name")
    private val companyId by option("--company").required()
    private val agentId by option("--agent").required()
    private val input by option("--input")

    override fun run() = runBlocking {
        echo(platformJson.encodeToString(desktopService.runSkill(name, companyId, agentId, input)))
    }
}

private class ProviderListCommand : CliktCommand(name = "list", help = "List known providers.") {
    override fun run() {
        echo(platformJson.encodeToString(com.cotor.app.providerCatalog()))
    }
}

private class ProviderScanCommand : CliktCommand(name = "scan", help = "Scan local provider commands on PATH."), KoinComponent {
    private val desktopService: DesktopAppService by inject()

    override fun run() {
        echo(platformJson.encodeToString(desktopService.scanProviders()))
    }
}

private class ProviderTestCommand : CliktCommand(name = "test", help = "Test one provider command on PATH."), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val id by argument("id")

    override fun run() {
        echo(platformJson.encodeToString(desktopService.testProvider(id)))
    }
}

private class CapabilityListCommand : CliktCommand(name = "list", help = "List the capability catalog.") {
    override fun run() {
        echo(platformJson.encodeToString(capabilityCatalog()))
    }
}

private class CapabilityInspectCommand : CliktCommand(name = "inspect", help = "Inspect one capability.") {
    private val key by argument("key")

    override fun run() {
        val capability = CapabilityKey.valueOf(key.trim().uppercase().replace('-', '_').replace('.', '_'))
        val entry = capabilityCatalog().firstOrNull { it.key == capability }
            ?: error("Capability not found: $key")
        echo(platformJson.encodeToString(entry))
    }
}

private class CapabilitySimulateCommand : CliktCommand(name = "simulate", help = "Simulate one action against an agent capability profile."), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val companyId by option("--company").required()
    private val agentId by option("--agent").required()
    private val action by option("--action").required()
    private val path by option("--path")
    private val networkTarget by option("--network-target")
    private val command by option("--command")
    private val skill by option("--skill")

    override fun run() = runBlocking {
        echo(
            platformJson.encodeToString(
                desktopService.simulateAgentCapability(
                    companyId = companyId,
                    agentId = agentId,
                    action = action,
                    path = path,
                    networkTarget = networkTarget,
                    command = command,
                    skill = skill
                )
            )
        )
    }
}

private class PolicyValidateCommand : CliktCommand(name = "validate", help = "Validate one policy document.") {
    private val path by argument("path").path(mustExist = true)
    private val store = PolicyStore()

    override fun run() {
        val document = store.loadDocument(path)
        echo(platformJson.encodeToString(PolicyDocument.serializer(), document))
    }
}

private class PolicySimulateCommand : CliktCommand(name = "simulate", help = "Simulate one action against configured policies."), KoinComponent {
    private val policyEngine: PolicyEngine by inject()
    private val companyId by option("--company")
    private val issueId by option("--issue")
    private val agentName by option("--agent")
    private val action by option("--action").required()
    private val path by option("--path")
    private val networkTarget by option("--network-target")
    private val command by option("--command")
    private val skill by option("--skill")

    override fun run() {
        val kind = ActionKind.fromWireValue(action)
            ?: error("Unsupported action kind: $action")
        val decision = policyEngine.evaluate(
            ActionRequest(
                kind = kind,
                label = "simulate:$action",
                scope = when {
                    issueId != null -> ActionScope.ISSUE
                    companyId != null -> ActionScope.COMPANY
                    else -> ActionScope.GLOBAL
                },
                subject = ActionSubject(
                    companyId = companyId,
                    issueId = issueId,
                    agentName = agentName
                ),
                command = command?.let { listOf(it) }.orEmpty(),
                path = path,
                networkTarget = networkTarget,
                metadata = skillMetadata(skill)
            )
        )
        echo(platformJson.encodeToString(decision))
    }
}

private fun skillMetadata(skill: String?): Map<String, String> =
    skill?.trim()?.takeIf { it.isNotBlank() }?.let { mapOf("skill" to it) }.orEmpty()

class EvidenceCommand : CliktCommand(name = "evidence", help = "Inspect provenance bundles.") {
    init {
        subcommands(EvidenceRunCommand(), EvidenceFileCommand(), EvidencePullRequestCommand())
    }

    override fun run() = Unit
}

private class EvidenceRunCommand : CliktCommand(name = "run"), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val runId by argument("runId")

    override fun run() = runBlocking {
        echo(platformJson.encodeToString(desktopService.evidenceForRun(runId)))
    }
}

private class EvidenceFileCommand : CliktCommand(name = "file"), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val path by argument("path")

    override fun run() = runBlocking {
        echo(platformJson.encodeToString(desktopService.evidenceForFile(path)))
    }
}

private class EvidencePullRequestCommand : CliktCommand(name = "pr"), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val pullRequestNumber by argument("pullRequestNumber").int()

    override fun run() = runBlocking {
        echo(platformJson.encodeToString(desktopService.evidenceForPullRequest(pullRequestNumber)))
    }
}

class GitHubProviderCommand : CliktCommand(name = "github", help = "Inspect GitHub provider control plane state.") {
    init {
        subcommands(GitHubSyncCommand(), GitHubInspectPrCommand(), GitHubListPrCommand(), GitHubEventsCommand())
    }

    override fun run() = Unit
}

private class GitHubSyncCommand : CliktCommand(name = "sync"), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val companyId by option("--company").required()

    override fun run() = runBlocking {
        echo(platformJson.encodeToString(desktopService.syncGitHubProvider(companyId)))
    }
}

private class GitHubInspectPrCommand : CliktCommand(name = "inspect-pr"), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val pullRequestNumber by option("--pr").int().required()

    override fun run() = runBlocking {
        val snapshot = desktopService.inspectGitHubPullRequest(pullRequestNumber)
            ?: error("Pull request not found: $pullRequestNumber")
        echo(platformJson.encodeToString(snapshot))
    }
}

private class GitHubListPrCommand : CliktCommand(name = "list"), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val companyId by option("--company")

    override fun run() = runBlocking {
        echo(platformJson.encodeToString(desktopService.listGitHubPullRequests(companyId)))
    }
}

private class GitHubEventsCommand : CliktCommand(name = "events"), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val companyId by option("--company")

    override fun run() = runBlocking {
        echo(platformJson.encodeToString(desktopService.listGitHubEvents(companyId)))
    }
}

class KnowledgeCommand : CliktCommand(name = "knowledge", help = "Inspect structured knowledge records.") {
    init {
        subcommands(KnowledgeInspectCommand())
    }

    override fun run() = Unit
}

private class KnowledgeInspectCommand : CliktCommand(name = "inspect"), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val issueId by option("--issue").required()

    override fun run() = runBlocking {
        echo(platformJson.encodeToString(desktopService.issueKnowledge(issueId)))
    }
}

class VerificationCommand : CliktCommand(name = "verification", help = "Inspect verification bundles for workflow issues.") {
    init {
        subcommands(VerificationInspectCommand())
    }

    override fun run() = Unit
}

private class VerificationInspectCommand : CliktCommand(name = "inspect"), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val issueId by option("--issue").required()

    override fun run() = runBlocking {
        echo(platformJson.encodeToString(desktopService.verificationBundle(issueId)))
    }
}

class RuntimeProjectionCommand : CliktCommand(name = "runtime", help = "Inspect projected runtime state for workflow issues.") {
    init {
        subcommands(RuntimeInspectCommand())
    }

    override fun run() = Unit
}

private class RuntimeInspectCommand : CliktCommand(name = "inspect"), KoinComponent {
    private val desktopService: DesktopAppService by inject()
    private val issueId by option("--issue").required()

    override fun run() = runBlocking {
        echo(platformJson.encodeToString(desktopService.issueRuntimeProjection(issueId)))
    }
}

class McpCommand : CliktCommand(name = "mcp", help = "Serve read-only MCP runtime endpoints over the app-server.") {
    init {
        subcommands(McpServeCommand())
    }

    override fun run() = Unit
}

private class McpServeCommand : CliktCommand(name = "serve") {
    private val readonly by option("--readonly").flag(default = true)
    private val port by option("--port").int().default(8787)
    private val host by option("--host").default("127.0.0.1")
    private val token by option("--token")

    override fun run() {
        if (!readonly) {
            error("Only read-only MCP exposure is supported in this build.")
        }
        AppServer().start(port = port, host = host, wait = true, token = token)
    }
}

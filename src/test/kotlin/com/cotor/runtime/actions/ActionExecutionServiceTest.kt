package com.cotor.runtime.actions

import com.cotor.policy.PolicyDocument
import com.cotor.policy.PolicyEffect
import com.cotor.policy.PolicyEngine
import com.cotor.policy.PolicyRule
import com.cotor.policy.PolicyScopeLevel
import com.cotor.policy.PolicyStore
import com.cotor.provenance.EvidenceNodeKind
import com.cotor.provenance.ProvenanceService
import com.cotor.provenance.ProvenanceStore
import com.cotor.runtime.durable.DurableRunSnapshot
import com.cotor.runtime.durable.DurableRunStatus
import com.cotor.runtime.durable.DurableRuntimeContext
import com.cotor.runtime.durable.DurableRuntimeService
import com.cotor.runtime.durable.DurableRuntimeStore
import com.cotor.runtime.durable.ReplayMode
import com.cotor.runtime.durable.SideEffectKind
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.nio.file.Files

class ActionExecutionServiceTest : FunSpec({
    test("denied actions are recorded and block execution") {
        val appHome = Files.createTempDirectory("action-execution-test")
        val policyStore = PolicyStore { appHome }
        policyStore.saveDocument(
            PolicyDocument(
                name = "default",
                defaultEffect = PolicyEffect.ALLOW,
                rules = listOf(
                    PolicyRule(
                        description = "deny git publishes",
                        scopeLevel = PolicyScopeLevel.GLOBAL,
                        effect = PolicyEffect.DENY,
                        actionKinds = listOf(ActionKind.GIT_PUBLISH)
                    )
                )
            )
        )
        val actionStore = ActionStore { appHome }
        val service = ActionExecutionService(
            actionStore = actionStore,
            provenanceService = ProvenanceService(ProvenanceStore { appHome }),
            interceptors = listOf(PolicyEngine(policyStore))
        )

        val request = ActionRequest(
            kind = ActionKind.GIT_PUBLISH,
            label = "git.publish:test-branch"
        )
        val error = runCatching {
            kotlinx.coroutines.runBlocking {
                service.run(request = request) {
                    "should-not-run"
                }
            }
        }.exceptionOrNull()

        error shouldNotBe null
        (error is ActionDeniedException) shouldBe true
        val snapshot = actionStore.load(request.id)
        snapshot shouldNotBe null
        snapshot!!.records.single().status shouldBe ActionStatus.DENIED
    }

    test("action store summaries use compact index for company blocked counts") {
        val appHome = Files.createTempDirectory("action-summary-index")
        val actionStore = ActionStore { appHome }
        actionStore.append("run-1", actionRecord("denied-1", "run-1", "company-1", ActionStatus.DENIED))
        actionStore.append("run-1", actionRecord("waiting-1", "run-1", "company-1", ActionStatus.WAITING_FOR_APPROVAL))
        actionStore.append("run-1", actionRecord("success-1", "run-1", "company-1", ActionStatus.SUCCEEDED))
        actionStore.append("run-1", actionRecord("denied-2", "run-1", "company-2", ActionStatus.DENIED))

        val summary = actionStore.listSummaries().single()

        summary.runId shouldBe "run-1"
        summary.recordCount shouldBe 4
        summary.blockedByCompany shouldBe mapOf("company-1" to 2, "company-2" to 1)

        actionStore.replace("run-1", "waiting-1") { record -> record.copy(status = ActionStatus.SUCCEEDED) }
        actionStore.listSummaries().single().blockedByCompany shouldBe mapOf("company-1" to 1, "company-2" to 1)

        val actionPath = appHome.resolve("runtime").resolve("actions").resolve("run-1.json")
        val originalModifiedAt = Files.getLastModifiedTime(actionPath)
        Files.writeString(actionPath, "{not-json")
        Files.setLastModifiedTime(actionPath, originalModifiedAt)

        actionStore.listSummaries().single().blockedByCompany shouldBe mapOf("company-1" to 1, "company-2" to 1)
        actionStore.load("run-1") shouldBe null
    }

    test("file and secret actions record precise durable side effect kinds") {
        val appHome = Files.createTempDirectory("action-execution-side-effects")
        val runtimeStore = DurableRuntimeStore(appHome.resolve("runtime"))
        runtimeStore.saveRun(
            DurableRunSnapshot(
                runId = "run-side-effects",
                pipelineName = "side-effects",
                status = DurableRunStatus.RUNNING,
                createdAt = 1L,
                updatedAt = 1L
            )
        )
        val service = ActionExecutionService(
            actionStore = ActionStore { appHome },
            durableRuntimeService = DurableRuntimeService(runtimeStore = runtimeStore),
            provenanceService = ProvenanceService(ProvenanceStore { appHome })
        )

        runBlocking {
            withContext(DurableRuntimeContext(runId = "run-side-effects", replayMode = ReplayMode.LIVE)) {
                service.run(
                    request = ActionRequest(kind = ActionKind.FILE_WRITE, label = "file.write:test")
                ) {
                    "file"
                }
                service.run(
                    request = ActionRequest(kind = ActionKind.SECRET_READ, label = "secret.read:test")
                ) {
                    "secret"
                }
            }
        }

        runtimeStore.loadRun("run-side-effects")!!.sideEffects.map { it.kind } shouldBe listOf(
            SideEffectKind.FILE_WRITE,
            SideEffectKind.SECRET_READ
        )
    }

    test("provenance records evidence returned by action success hooks") {
        val appHome = Files.createTempDirectory("action-execution-provenance-evidence")
        val provenanceStore = ProvenanceStore { appHome }
        val service = ActionExecutionService(
            actionStore = ActionStore { appHome },
            provenanceService = ProvenanceService(provenanceStore)
        )

        runBlocking {
            service.run(
                request = ActionRequest(kind = ActionKind.GIT_PUBLISH, label = "git.publish:feature"),
                onSuccess = {
                    ActionEvidence(
                        branchName = "feature/test",
                        pullRequestNumber = 42,
                        pullRequestUrl = "https://github.com/example/cotor/pull/42"
                    )
                }
            ) {
                "published"
            }
        }

        val graph = provenanceStore.load()
        graph.nodes.any { it.kind == EvidenceNodeKind.BRANCH && it.ref == "branch:feature/test" } shouldBe true
        graph.nodes.any { it.kind == EvidenceNodeKind.PR && it.ref == "pr:42" } shouldBe true
        graph.edges.any { it.toRef == "pr:42" && it.relation == "published-pr" } shouldBe true
    }
})

private fun actionRecord(
    id: String,
    runId: String,
    companyId: String,
    status: ActionStatus
): ActionExecutionRecord =
    ActionExecutionRecord(
        id = id,
        runId = runId,
        request = ActionRequest(
            kind = ActionKind.GIT_PUBLISH,
            label = "git.publish:$id",
            scope = ActionScope.COMPANY,
            subject = ActionSubject(runId = runId, companyId = companyId)
        ),
        status = status,
        createdAt = 1L,
        updatedAt = 2L
    )

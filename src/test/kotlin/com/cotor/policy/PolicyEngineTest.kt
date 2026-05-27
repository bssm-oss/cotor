package com.cotor.policy

import com.cotor.runtime.actions.ActionKind
import com.cotor.runtime.actions.ActionRequest
import com.cotor.runtime.actions.ActionScope
import com.cotor.runtime.actions.ActionSubject
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class PolicyEngineTest : FunSpec({
    test("more specific issue scope overrides permissive global scope") {
        val appHome = Files.createTempDirectory("policy-engine-test")
        val store = PolicyStore { appHome }
        store.saveDocument(
            PolicyDocument(
                name = "default",
                defaultEffect = PolicyEffect.ALLOW,
                rules = listOf(
                    PolicyRule(
                        description = "deny github merge on blocked issue",
                        scopeLevel = PolicyScopeLevel.ISSUE,
                        scopeId = "issue-1",
                        effect = PolicyEffect.DENY,
                        actionKinds = listOf(ActionKind.GITHUB_MERGE)
                    )
                )
            )
        )
        val engine = PolicyEngine(store)

        val decision = engine.evaluate(
            ActionRequest(
                kind = ActionKind.GITHUB_MERGE,
                label = "github.merge:12",
                scope = ActionScope.ISSUE,
                subject = ActionSubject(issueId = "issue-1")
            )
        )

        decision.effect shouldBe PolicyEffect.DENY
        decision.explanation.matchedRuleIds.size shouldBe 1
    }

    test("appendDecision preserves concurrent audit entries") {
        val appHome = Files.createTempDirectory("policy-audit-concurrency")
        val store = PolicyStore { appHome }
        val executor = Executors.newFixedThreadPool(8)
        val start = CountDownLatch(1)
        val done = CountDownLatch(20)

        try {
            repeat(20) { index ->
                executor.submit {
                    start.await(5, TimeUnit.SECONDS)
                    store.appendDecision(
                        PolicyDecision(
                            request = ActionRequest(
                                id = "request-$index",
                                kind = ActionKind.AGENT_EXEC,
                                label = "request-$index",
                                scope = ActionScope.RUN,
                                subject = ActionSubject(runId = "run-1")
                            ),
                            effect = PolicyEffect.ALLOW,
                            explanation = PolicyExplanation("allowed")
                        )
                    )
                    done.countDown()
                }
            }

            start.countDown()
            done.await(10, TimeUnit.SECONDS) shouldBe true
            store.loadAudit().decisions.size shouldBe 20
        } finally {
            executor.shutdownNow()
            executor.awaitTermination(5, TimeUnit.SECONDS)
        }
    }
})

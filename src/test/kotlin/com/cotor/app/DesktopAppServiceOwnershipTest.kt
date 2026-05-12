package com.cotor.app

import com.cotor.data.config.ConfigRepository
import com.cotor.domain.executor.AgentExecutor
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.mockk.mockk
import java.nio.file.Files

class DesktopAppServiceOwnershipTest : FunSpec({
    afterTest {
        DesktopAppService.shutdownAllForTesting()
    }

    test("updatePipeline rejects cross-company ids without changing state") {
        val appHome = Files.createTempDirectory("desktop-ownership-pipeline")
        val stateStore = DesktopStateStore { appHome }
        val pipeline = WorkflowPipelineDefinition(
            id = "pipeline-a",
            companyId = "company-a",
            name = "Company A pipeline",
            stages = listOf(
                WorkflowStageDefinition(
                    id = "stage-a",
                    kind = "execution",
                    title = "Execute",
                    order = 0
                )
            ),
            createdAt = 1L,
            updatedAt = 1L
        )
        stateStore.save(DesktopAppState(workflowPipelines = listOf(pipeline)))
        val service = ownershipService(stateStore)

        shouldThrow<IllegalArgumentException> {
            service.updatePipeline(
                companyId = "company-b",
                pipelineId = pipeline.id,
                name = "Cross-company rewrite"
            )
        }

        stateStore.load().workflowPipelines.single() shouldBe pipeline
    }

    test("deletePipeline rejects cross-company ids without deleting state") {
        val appHome = Files.createTempDirectory("desktop-ownership-delete-pipeline")
        val stateStore = DesktopStateStore { appHome }
        val pipeline = WorkflowPipelineDefinition(
            id = "pipeline-a",
            companyId = "company-a",
            name = "Company A pipeline",
            stages = emptyList(),
            createdAt = 1L,
            updatedAt = 1L
        )
        stateStore.save(DesktopAppState(workflowPipelines = listOf(pipeline)))
        val service = ownershipService(stateStore)

        shouldThrow<IllegalArgumentException> {
            service.deletePipeline(companyId = "company-b", pipelineId = pipeline.id)
        }

        stateStore.load().workflowPipelines shouldBe listOf(pipeline)
    }

    test("deleteContextEntry rejects cross-company ids without deleting state") {
        val appHome = Files.createTempDirectory("desktop-ownership-context")
        val stateStore = DesktopStateStore { appHome }
        val entry = AgentContextEntry(
            id = "entry-a",
            companyId = "company-a",
            agentName = "codex",
            kind = "note",
            title = "Company A note",
            content = "Keep this scoped to company A.",
            createdAt = 1L
        )
        stateStore.save(DesktopAppState(agentContextEntries = listOf(entry)))
        val service = ownershipService(stateStore)

        shouldThrow<IllegalArgumentException> {
            service.deleteContextEntry(companyId = "company-b", entryId = entry.id)
        }

        stateStore.load().agentContextEntries shouldBe listOf(entry)
    }
})

private fun ownershipService(stateStore: DesktopStateStore): DesktopAppService =
    DesktopAppService(
        stateStore = stateStore,
        gitWorkspaceService = mockk(relaxed = true),
        configRepository = mockk<ConfigRepository>(relaxed = true),
        agentExecutor = mockk<AgentExecutor>(relaxed = true)
    )

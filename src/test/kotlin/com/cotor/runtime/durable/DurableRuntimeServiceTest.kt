package com.cotor.runtime.durable

import com.cotor.app.defaultDesktopAppHome
import com.cotor.checkpoint.CheckpointManager
import com.cotor.checkpoint.StageCheckpoint
import com.cotor.model.Pipeline
import com.cotor.model.PipelineContext
import com.cotor.model.PipelineStage
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldHaveSize
import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.nio.file.Files
import java.time.Instant

class DurableRuntimeServiceTest : FunSpec({
    test("default durable runtime store writes under desktop app home") {
        val runId = "default-root-${System.currentTimeMillis()}"
        val store = DurableRuntimeStore()
        val snapshot = DurableRunSnapshot(
            runId = runId,
            pipelineName = "default-root-pipeline",
            status = DurableRunStatus.RUNNING,
            createdAt = System.currentTimeMillis(),
            updatedAt = System.currentTimeMillis()
        )

        store.saveRun(snapshot)

        val expected = defaultDesktopAppHome().resolve("runtime").resolve("runs").resolve("$runId.json")
        Files.exists(expected) shouldBe true
        store.deleteRun(runId) shouldBe true
    }

    test("inspectRun imports a legacy checkpoint into the durable graph") {
        val checkpointDir = Files.createTempDirectory("durable-runtime-legacy-checkpoint")
        val runtimeDir = Files.createTempDirectory("durable-runtime-store")
        val checkpointManager = CheckpointManager(checkpointDir.toString())
        checkpointManager.saveCheckpoint(
            pipelineId = "pipeline-1",
            pipelineName = "legacy-pipeline",
            completedStages = listOf(
                StageCheckpoint("stage-1", "codex", "done-1", true, 11, Instant.now().toString()),
                StageCheckpoint("stage-2", "codex", "done-2", true, 12, Instant.now().toString())
            ),
            cotorVersion = "1.0.0",
            gitCommit = "abc123",
            os = "macOS",
            jvm = "17"
        )

        val service = DurableRuntimeService(
            checkpointManager = checkpointManager,
            runtimeStore = DurableRuntimeStore(runtimeDir)
        )

        val snapshot = service.inspectRun("pipeline-1")

        snapshot shouldNotBe null
        snapshot!!.importedLegacyCheckpoint shouldBe true
        snapshot.checkpoints shouldHaveSize 2
        snapshot.latestCompletedCheckpoint?.stageId shouldBe "stage-2"
    }

    test("replay-unsafe side effects require approval before replay can continue") {
        val runtimeDir = Files.createTempDirectory("durable-runtime-replay")
        val service = DurableRuntimeService(runtimeStore = DurableRuntimeStore(runtimeDir))
        val pipeline = Pipeline(
            name = "replay-pipeline",
            stages = listOf(PipelineStage(id = "stage-1"))
        )
        val context = PipelineContext(
            pipelineId = "run-1",
            pipelineName = pipeline.name,
            totalStages = pipeline.stages.size
        )
        DurableRuntimeFlags.enable(context)
        service.beginPipelineRun(pipeline, context)
        service.recordStageCompleted(
            context = context,
            stage = pipeline.stages.first(),
            result = com.cotor.model.AgentResult(
                agentName = "codex",
                isSuccess = true,
                output = "ok",
                error = null,
                duration = 10,
                metadata = emptyMap()
            )
        )

        val approvalError = runCatching {
            runBlocking {
                withContext(
                    DurableRuntimeContext(
                        runId = "run-1",
                        replayMode = ReplayMode.CONTINUE,
                        sourceRunId = "run-1",
                        sourceCheckpointId = service.inspectRun("run-1")!!.latestCompletedCheckpoint!!.id
                    )
                ) {
                    service.recordSideEffect(
                        kind = SideEffectKind.GIT_PUBLISH,
                        label = "git.publish:branch-1",
                        replaySafe = false,
                        approvalRequiredOnReplay = true
                    )
                }
            }
        }.exceptionOrNull()

        (approvalError is ReplayApprovalRequiredException) shouldBe true
        val waiting = service.inspectRun("run-1")!!
        waiting.status shouldBe DurableRunStatus.WAITING_FOR_APPROVAL
        waiting.approvalPauses.single().status shouldBe ApprovalPauseStatus.PENDING

        val approved = service.approve("run-1", waiting.approvalPauses.single().checkpointId)
        approved.status shouldBe DurableRunStatus.RUNNING

        runBlocking {
            withContext(
                DurableRuntimeContext(
                    runId = "run-1",
                    replayMode = ReplayMode.CONTINUE,
                    sourceRunId = "run-1",
                    sourceCheckpointId = approved.latestCompletedCheckpoint!!.id
                )
            ) {
                service.recordSideEffect(
                    kind = SideEffectKind.GIT_PUBLISH,
                    label = "git.publish:branch-1",
                    replaySafe = false,
                    approvalRequiredOnReplay = true
                )
            }
        }

        service.inspectRun("run-1")!!.sideEffects.last().status shouldBe SideEffectStatus.APPROVED
    }

    test("recordSideEffect treats replay-unsafe effects as approval-required even when caller omits the replay flag") {
        val runtimeDir = Files.createTempDirectory("durable-runtime-replay-invariant")
        val service = DurableRuntimeService(runtimeStore = DurableRuntimeStore(runtimeDir))
        val pipeline = Pipeline(
            name = "replay-invariant-pipeline",
            stages = listOf(PipelineStage(id = "stage-1"))
        )
        val context = PipelineContext(
            pipelineId = "run-invariant",
            pipelineName = pipeline.name,
            totalStages = pipeline.stages.size
        )
        DurableRuntimeFlags.enable(context)
        service.beginPipelineRun(pipeline, context)
        service.recordStageCompleted(
            context = context,
            stage = pipeline.stages.first(),
            result = com.cotor.model.AgentResult(
                agentName = "codex",
                isSuccess = true,
                output = "ok",
                error = null,
                duration = 10,
                metadata = emptyMap()
            )
        )

        val approvalError = runCatching {
            runBlocking {
                withContext(
                    DurableRuntimeContext(
                        runId = "run-invariant",
                        replayMode = ReplayMode.CONTINUE,
                        sourceRunId = "run-invariant",
                        sourceCheckpointId = service.inspectRun("run-invariant")!!.latestCompletedCheckpoint!!.id
                    )
                ) {
                    service.recordSideEffect(
                        kind = SideEffectKind.FILE_WRITE,
                        label = "file.write:state",
                        replaySafe = false,
                        approvalRequiredOnReplay = false
                    )
                }
            }
        }.exceptionOrNull()

        (approvalError is ReplayApprovalRequiredException) shouldBe true
        val waiting = service.inspectRun("run-invariant")!!
        waiting.approvalPauses.single().status shouldBe ApprovalPauseStatus.PENDING
        waiting.sideEffects.single().approvalRequiredOnReplay shouldBe true
    }

    test("parallel checkpoint appends preserve every completion with unique ordinals") {
        val runtimeDir = Files.createTempDirectory("durable-runtime-parallel")
        val service = DurableRuntimeService(runtimeStore = DurableRuntimeStore(runtimeDir))
        val pipeline = Pipeline(
            name = "parallel-checkpoint-pipeline",
            stages = (1..20).map { index -> PipelineStage(id = "stage-$index") }
        )
        val context = PipelineContext(
            pipelineId = "parallel-run",
            pipelineName = pipeline.name,
            totalStages = pipeline.stages.size
        )
        DurableRuntimeFlags.enable(context)
        service.beginPipelineRun(pipeline, context)

        runBlocking {
            pipeline.stages.map { stage ->
                async {
                    service.recordStageCompleted(
                        context = context,
                        stage = stage,
                        result = com.cotor.model.AgentResult(
                            agentName = "codex",
                            isSuccess = true,
                            output = stage.id,
                            error = null,
                            duration = 10,
                            metadata = emptyMap()
                        )
                    )
                }
            }.awaitAll()
        }

        val snapshot = service.inspectRun("parallel-run")!!
        snapshot.checkpoints shouldHaveSize 20
        snapshot.checkpoints.map { it.ordinal }.sorted() shouldBe (1..20).toList()
    }

    test("fork copies pending approval state into paused fork snapshot") {
        val runtimeDir = Files.createTempDirectory("durable-runtime-fork-approval")
        val service = DurableRuntimeService(runtimeStore = DurableRuntimeStore(runtimeDir))
        val pipeline = Pipeline(
            name = "fork-approval-pipeline",
            stages = listOf(PipelineStage(id = "stage-1"))
        )
        val context = PipelineContext(
            pipelineId = "fork-source",
            pipelineName = pipeline.name,
            totalStages = pipeline.stages.size
        )
        DurableRuntimeFlags.enable(context)
        service.beginPipelineRun(pipeline, context)
        service.recordStageCompleted(
            context = context,
            stage = pipeline.stages.first(),
            result = com.cotor.model.AgentResult(
                agentName = "codex",
                isSuccess = true,
                output = "ok",
                error = null,
                duration = 10,
                metadata = emptyMap()
            )
        )
        val checkpointId = service.inspectRun("fork-source")!!.latestCompletedCheckpoint!!.id

        runCatching {
            runBlocking {
                withContext(
                    DurableRuntimeContext(
                        runId = "fork-source",
                        replayMode = ReplayMode.CONTINUE,
                        sourceRunId = "fork-source",
                        sourceCheckpointId = checkpointId
                    )
                ) {
                    service.recordSideEffect(
                        kind = SideEffectKind.GIT_PUBLISH,
                        label = "git.publish:fork",
                        replaySafe = false,
                        approvalRequiredOnReplay = true
                    )
                }
            }
        }

        val fork = service.createFork("fork-source", "fork-copy", checkpointId)

        fork.status shouldBe DurableRunStatus.WAITING_FOR_APPROVAL
        fork.sideEffects shouldHaveSize 1
        fork.approvalPauses shouldHaveSize 1
        fork.approvalPauses.single().status shouldBe ApprovalPauseStatus.PENDING
    }
})

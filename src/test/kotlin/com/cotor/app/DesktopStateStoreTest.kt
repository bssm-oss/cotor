package com.cotor.app

/**
 * File overview for DesktopStateStoreTest.
 *
 * This file belongs to the test suite that documents expected behavior and protects against regressions.
 * It groups declarations around desktop state store test so readers can find the owning runtime area quickly.
 * Read here first when tracing behavior that flows through this part of the codebase.
 */

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldHaveSize
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import io.kotest.matchers.string.shouldNotContain
import kotlinx.serialization.json.Json
import java.nio.file.Files
import java.nio.file.attribute.FileTime
import java.sql.DriverManager
import kotlin.io.path.readText

class DesktopStateStoreTest : FunSpec({
    val testJson = Json {
        ignoreUnknownKeys = true
        prettyPrint = true
    }

    test("load recovers a state file with one extra trailing brace") {
        val appHome = Files.createTempDirectory("desktop-state-store-home")
        val store = DesktopStateStore { appHome }
        val validState = DesktopAppState(
            companies = listOf(
                Company(
                    id = "company-1",
                    name = "Recovered Company",
                    rootPath = "/tmp/recovered-company",
                    repositoryId = "repo-1",
                    defaultBaseBranch = "master",
                    createdAt = 1L,
                    updatedAt = 1L
                )
            )
        )
        val payload = testJson.encodeToString(DesktopAppState.serializer(), validState) + "\n}"
        Files.createDirectories(appHome)
        Files.writeString(appHome.resolve("state.json"), payload)

        val recovered = store.load()

        recovered.companies.map { it.name } shouldBe listOf("Recovered Company")
        Files.readString(appHome.resolve("state.json")).trimEnd().endsWith("}}") shouldBe false
    }

    test("save removes stale state temp files") {
        val appHome = Files.createTempDirectory("desktop-state-store-temp-cleanup-home")
        val store = DesktopStateStore { appHome }
        Files.writeString(appHome.resolve("state.json.111.tmp"), "{}")
        Files.writeString(appHome.resolve("state.json.bak.222.tmp"), "{}")
        Files.writeString(appHome.resolve("state.json.bak"), "{}")
        val staleTime = FileTime.fromMillis(System.currentTimeMillis() - 120_000L)
        Files.setLastModifiedTime(appHome.resolve("state.json.111.tmp"), staleTime)
        Files.setLastModifiedTime(appHome.resolve("state.json.bak.222.tmp"), staleTime)

        store.save(DesktopAppState())

        stateTempFilesToClean(appHome) shouldBe emptyList()
        appHome.resolve("state.sqlite").toFile().exists() shouldBe true
    }

    test("load migrates legacy json state into sqlite without deleting rollback files") {
        val appHome = Files.createTempDirectory("desktop-state-store-json-migration-home")
        val legacyState = DesktopAppState(
            companies = listOf(
                Company(
                    id = "company-1",
                    name = "Migrated Company",
                    rootPath = "/tmp/migrated-company",
                    repositoryId = "repo-1",
                    defaultBaseBranch = "master",
                    createdAt = 1L,
                    updatedAt = 1L
                )
            )
        )
        saveLegacyJsonState(appHome, legacyState)
        val legacyPayload = appHome.resolve("state.json").readText()

        val loaded = DesktopStateStore { appHome }.load()

        loaded.companies.map { it.name } shouldBe listOf("Migrated Company")
        appHome.resolve("state.sqlite").toFile().exists() shouldBe true
        appHome.resolve("state.json").readText() shouldBe legacyPayload
        appHome.resolve("state.json.bak").readText() shouldBe legacyPayload
        readSqliteCollection(appHome, "companies") shouldContain "Migrated Company"
    }

    test("fresh state temp files are not cleaned while another save may still be moving them") {
        val appHome = Files.createTempDirectory("desktop-state-store-fresh-temp-home")
        val freshTemp = appHome.resolve("state.json.bak.fresh.tmp")
        Files.writeString(freshTemp, "{}")

        stateTempFilesToClean(
            directory = appHome,
            nowMillis = Files.getLastModifiedTime(freshTemp).toMillis() + 1_000L
        ) shouldBe emptyList()
    }

    test("save compacts direct chat conversations and messages before persistence") {
        val appHome = Files.createTempDirectory("desktop-state-store-direct-chat-home")
        val store = DesktopStateStore { appHome }
        val conversations = (0 until 30).map { conversationIndex ->
            DirectChatConversation(
                id = "conversation-$conversationIndex",
                companyId = "company-1",
                title = "Conversation $conversationIndex",
                model = "gemma",
                provider = "ollama",
                systemPrompt = "s".repeat(5_000),
                messages = (0 until 100).map { messageIndex ->
                    DirectChatMessage(
                        id = "message-$conversationIndex-$messageIndex",
                        role = if (messageIndex % 2 == 0) "user" else "assistant",
                        content = "x".repeat(21_000),
                        createdAt = messageIndex.toLong()
                    )
                },
                createdAt = conversationIndex.toLong(),
                updatedAt = conversationIndex.toLong()
            )
        }

        store.save(DesktopAppState(directChatConversations = conversations))

        val persisted = store.load().directChatConversations
        persisted shouldHaveSize 25
        persisted.first().id shouldBe "conversation-29"
        persisted.map { it.id }.contains("conversation-0") shouldBe false
        persisted.first().messages shouldHaveSize 80
        persisted.first().messages.first().id shouldBe "message-29-20"
        persisted.first().messages.first().content shouldContain "[compacted "
        persisted.first().systemPrompt shouldContain "[compacted "
    }

    test("load prunes dangling company goal and runtime records") {
        val appHome = Files.createTempDirectory("desktop-state-store-dangling-company-home")
        val store = DesktopStateStore { appHome }
        val now = 1L
        val validCompany = Company(
            id = "company-1",
            name = "Valid Company",
            rootPath = "/tmp/valid-company",
            repositoryId = "repo-1",
            defaultBaseBranch = "master",
            createdAt = now,
            updatedAt = now
        )
        val validGoal = CompanyGoal(
            id = "goal-1",
            companyId = validCompany.id,
            title = "Keep valid work",
            description = "Keep valid goal records.",
            status = GoalStatus.ACTIVE,
            createdAt = now,
            updatedAt = now
        )
        val validIssue = CompanyIssue(
            id = "issue-1",
            companyId = validCompany.id,
            goalId = validGoal.id,
            workspaceId = "workspace-1",
            title = "Keep valid issue",
            description = "Keep valid issue records.",
            status = IssueStatus.PLANNED,
            createdAt = now,
            updatedAt = now
        )
        val danglingDecision = GoalOrchestrationDecision(
            id = "decision-stale",
            companyId = "deleted-company",
            goalId = "deleted-goal",
            issueId = "deleted-issue",
            title = "Delete stale decision",
            summary = "This belongs to a deleted company.",
            createdAt = now
        )
        val validDecision = GoalOrchestrationDecision(
            id = "decision-valid",
            companyId = validCompany.id,
            goalId = validGoal.id,
            issueId = validIssue.id,
            title = "Keep valid decision",
            summary = "This belongs to the live company.",
            createdIssues = listOf(validIssue.id, "deleted-issue"),
            createdAt = now
        )
        val danglingWorkItem = CompanyRuntimeWorkItem(
            id = "work-stale",
            companyId = "deleted-company",
            goalId = "deleted-goal",
            issueId = "deleted-issue",
            status = CompanyRuntimeWorkItemStatus.READY,
            createdAt = now,
            updatedAt = now
        )
        val validWorkItem = CompanyRuntimeWorkItem(
            id = "work-valid",
            companyId = validCompany.id,
            goalId = validGoal.id,
            issueId = validIssue.id,
            status = CompanyRuntimeWorkItemStatus.READY,
            createdAt = now,
            updatedAt = now
        )

        store.save(
            DesktopAppState(
                companies = listOf(validCompany),
                goals = listOf(
                    validGoal,
                    validGoal.copy(id = "deleted-goal", companyId = "deleted-company")
                ),
                issues = listOf(
                    validIssue,
                    validIssue.copy(id = "deleted-issue", companyId = "deleted-company", goalId = "deleted-goal")
                ),
                goalDecisions = listOf(validDecision, danglingDecision),
                companyRuntimeWorkItems = listOf(validWorkItem, danglingWorkItem),
                companyRuntimes = listOf(
                    CompanyRuntimeSnapshot(companyId = validCompany.id, status = CompanyRuntimeStatus.RUNNING),
                    CompanyRuntimeSnapshot(companyId = "deleted-company", status = CompanyRuntimeStatus.RUNNING)
                )
            )
        )

        val recovered = store.load()

        recovered.goals.map { it.id } shouldBe listOf(validGoal.id)
        recovered.issues.map { it.id } shouldBe listOf(validIssue.id)
        recovered.goalDecisions.map { it.id } shouldBe listOf(validDecision.id)
        recovered.goalDecisions.single().createdIssues shouldBe listOf(validIssue.id)
        recovered.companyRuntimeWorkItems.map { it.id } shouldBe listOf(validWorkItem.id)
        recovered.companyRuntimes.map { it.companyId } shouldBe listOf(validCompany.id)
    }

    test("load restores the last good backup when the primary state file is corrupted") {
        val appHome = Files.createTempDirectory("desktop-state-store-backup-home")
        val store = DesktopStateStore { appHome }
        val validState = DesktopAppState(
            companies = listOf(
                Company(
                    id = "company-1",
                    name = "Recovered From Backup",
                    rootPath = "/tmp/recovered-company",
                    repositoryId = "repo-1",
                    defaultBaseBranch = "master",
                    createdAt = 1L,
                    updatedAt = 1L
                )
            )
        )

        saveLegacyJsonState(appHome, validState)
        Files.writeString(
            appHome.resolve("state.json"),
            "{\n  \"companies\": [\n    {\n      \"id\": \"broken\"\n"
        )

        val recovered = store.load()

        recovered.companies.map { it.name } shouldBe listOf("Recovered From Backup")
        Files.readString(appHome.resolve("state.json.bak")).contains("Recovered From Backup") shouldBe true
        appHome.resolve("state.sqlite").toFile().exists() shouldBe true
    }

    test("load restores the backup when the primary state file is corrupted in the middle") {
        val appHome = Files.createTempDirectory("desktop-state-store-mid-corruption-home")
        val store = DesktopStateStore { appHome }
        val validState = DesktopAppState(
            companies = listOf(
                Company(
                    id = "company-1",
                    name = "Recovered Mid-File Backup",
                    rootPath = "/tmp/recovered-company",
                    repositoryId = "repo-1",
                    defaultBaseBranch = "master",
                    createdAt = 1L,
                    updatedAt = 1L
                )
            )
        )

        saveLegacyJsonState(appHome, validState)
        val validPayload = appHome.resolve("state.json").readText()
        val insertionPoint = validPayload.indexOf("\"name\":")
        val corruptedPayload = buildString {
            append(validPayload.substring(0, insertionPoint))
            append("{\n  ssage\": \"broken\"\n")
            append(validPayload.substring(insertionPoint))
        }
        Files.writeString(appHome.resolve("state.json"), corruptedPayload)

        val recovered = store.load()

        recovered.companies.map { it.name } shouldBe listOf("Recovered Mid-File Backup")
        Files.readString(appHome.resolve("state.json.bak")).contains("Recovered Mid-File Backup") shouldBe true
    }

    test("load recovers companies and goals even when one persisted task entry is invalid") {
        val appHome = Files.createTempDirectory("desktop-state-store-lenient-home")
        val store = DesktopStateStore { appHome }
        val validState = DesktopAppState(
            companies = listOf(
                Company(
                    id = "company-1",
                    name = "Lenient Company",
                    rootPath = "/tmp/lenient-company",
                    repositoryId = "repo-1",
                    defaultBaseBranch = "master",
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            projectContexts = listOf(
                CompanyProjectContext(
                    id = "project-1",
                    companyId = "company-1",
                    name = "Lenient Company",
                    slug = "lenient-company",
                    contextDocPath = appHome.resolve("project.md").toString(),
                    lastUpdatedAt = 1L
                )
            ),
            goals = listOf(
                CompanyGoal(
                    id = "goal-1",
                    companyId = "company-1",
                    projectContextId = "project-1",
                    title = "Keep working",
                    description = "Continue autonomous work.",
                    status = GoalStatus.ACTIVE,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            tasks = listOf(
                AgentTask(
                    id = "task-1",
                    workspaceId = "workspace-1",
                    title = "Valid task",
                    prompt = "prompt",
                    agents = listOf("codex"),
                    status = DesktopTaskStatus.COMPLETED,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            )
        )

        store.save(validState)
        val corruptedPayload = readSqliteCollection(appHome, "tasks").replaceFirst(
            "\"status\": \"COMPLETED\"",
            "\"status\": \"NOT_A_REAL_STATUS\""
        )
        writeSqliteCollection(appHome, "tasks", corruptedPayload)

        val recovered = store.load()

        recovered.companies.map { it.name } shouldBe listOf("Lenient Company")
        recovered.goals.map { it.title } shouldBe listOf("Keep working")
        recovered.tasks shouldBe emptyList()
        Files.readString(appHome.resolve("runtime").resolve("backend").resolve("state-load.log")) shouldContain
            "Recovered SQLite state without invalid collection tasks"
    }

    test("load returns sqlite revision cache when the database revision is unchanged") {
        val appHome = Files.createTempDirectory("desktop-state-store-sqlite-cache-home")
        val store = DesktopStateStore { appHome }
        val state = DesktopAppState(
            companies = listOf(
                Company(
                    id = "company-1",
                    name = "Cached Company",
                    rootPath = "/tmp/cached-company",
                    repositoryId = "repo-1",
                    defaultBaseBranch = "master",
                    createdAt = 1L,
                    updatedAt = 1L
                )
            )
        )

        store.save(state)
        val mutatedPayload = readSqliteCollection(appHome, "companies").replace("Cached Company", "Unrevised Company")
        writeSqliteCollection(appHome, "companies", mutatedPayload, bumpRevision = false)

        store.load().companies.map { it.name } shouldBe listOf("Cached Company")
    }

    test("save rewrites only sqlite collections whose payload changed") {
        val appHome = Files.createTempDirectory("desktop-state-store-partial-update-home")
        val store = DesktopStateStore { appHome }
        val state = DesktopAppState(
            companies = listOf(
                Company(
                    id = "company-1",
                    name = "Stable Company",
                    rootPath = "/tmp/stable-company",
                    repositoryId = "repo-1",
                    defaultBaseBranch = "master",
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            tasks = listOf(
                AgentTask(
                    id = "task-1",
                    workspaceId = "workspace-1",
                    title = "Original task",
                    prompt = "prompt",
                    agents = listOf("codex"),
                    status = DesktopTaskStatus.QUEUED,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            )
        )

        store.save(state)
        val companyUpdatedAt = readSqliteCollectionUpdatedAt(appHome, "companies")
        val taskUpdatedAt = readSqliteCollectionUpdatedAt(appHome, "tasks")
        Thread.sleep(5L)
        store.save(state.copy(tasks = state.tasks.map { it.copy(title = "Updated task", updatedAt = 2L) }))

        readSqliteCollectionUpdatedAt(appHome, "companies") shouldBe companyUpdatedAt
        (readSqliteCollectionUpdatedAt(appHome, "tasks") > taskUpdatedAt) shouldBe true
    }

    test("large state small mutation updates only the changed sqlite collection") {
        val appHome = Files.createTempDirectory("desktop-state-store-large-partial-home")
        val store = DesktopStateStore { appHome }
        val company = Company(
            id = "company-large",
            name = "Large Company",
            rootPath = "/tmp/large-company",
            repositoryId = "repo-large",
            defaultBaseBranch = "master",
            createdAt = 1L,
            updatedAt = 1L
        )
        val state = DesktopAppState(
            companies = listOf(company),
            repositories = listOf(
                ManagedRepository(
                    id = "repo-large",
                    name = "Large Repo",
                    localPath = "/tmp/large-company",
                    sourceKind = RepositorySourceKind.LOCAL,
                    defaultBranch = "master",
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            workspaces = listOf(
                Workspace(
                    id = "workspace-large",
                    repositoryId = "repo-large",
                    name = "Large workspace",
                    baseBranch = "master",
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            goals = listOf(
                CompanyGoal(
                    id = "goal-large",
                    companyId = company.id,
                    title = "Large goal",
                    description = "Large goal",
                    status = GoalStatus.ACTIVE,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            issues = (0 until 1_000).map { index ->
                CompanyIssue(
                    id = "issue-$index",
                    companyId = company.id,
                    goalId = "goal-large",
                    workspaceId = "workspace-large",
                    title = "Issue $index",
                    description = "Issue $index",
                    status = IssueStatus.PLANNED,
                    createdAt = index.toLong(),
                    updatedAt = index.toLong()
                )
            },
            tasks = (0 until 2_000).map { index ->
                AgentTask(
                    id = "task-$index",
                    workspaceId = "workspace-large",
                    issueId = "issue-${index % 1_000}",
                    title = "Task $index",
                    prompt = "Prompt $index",
                    agents = listOf("codex"),
                    status = DesktopTaskStatus.QUEUED,
                    createdAt = index.toLong(),
                    updatedAt = index.toLong()
                )
            },
            runs = (0 until 5_000).map { index ->
                AgentRun(
                    id = "run-$index",
                    taskId = "task-${index % 2_000}",
                    workspaceId = "workspace-large",
                    repositoryId = "repo-large",
                    agentName = "codex",
                    branchName = "branch-$index",
                    worktreePath = "/tmp/large-company/.cotor/worktrees/task-${index % 2_000}/codex",
                    status = AgentRunStatus.COMPLETED,
                    createdAt = index.toLong(),
                    updatedAt = index.toLong()
                )
            }
        )

        store.save(state)
        val issuesUpdatedAt = readSqliteCollectionUpdatedAt(appHome, "issues")
        val runsUpdatedAt = readSqliteCollectionUpdatedAt(appHome, "runs")
        val taskUpdatedAt = readSqliteCollectionUpdatedAt(appHome, "tasks")
        Thread.sleep(5L)
        store.save(
            state.copy(
                tasks = state.tasks.mapIndexed { index, task ->
                    if (index == 0) task.copy(status = DesktopTaskStatus.COMPLETED, updatedAt = 9_999L) else task
                }
            )
        )

        readSqliteCollectionUpdatedAt(appHome, "issues") shouldBe issuesUpdatedAt
        readSqliteCollectionUpdatedAt(appHome, "runs") shouldBe runsUpdatedAt
        (readSqliteCollectionUpdatedAt(appHome, "tasks") > taskUpdatedAt) shouldBe true
        store.load().tasks.first { it.id == "task-0" }.status shouldBe DesktopTaskStatus.COMPLETED
    }

    test("lenient recovery preserves workflow pipelines, agent context entries, and agent messages") {
        val appHome = Files.createTempDirectory("desktop-state-store-lenient-preserve-home")
        val store = DesktopStateStore { appHome }
        val state = DesktopAppState(
            companies = listOf(
                Company(
                    id = "company-1",
                    name = "Preserved Company",
                    rootPath = "/tmp/preserved-company",
                    repositoryId = "repo-1",
                    defaultBaseBranch = "master",
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            workflowPipelines = listOf(
                WorkflowPipelineDefinition(
                    id = "pipeline-1",
                    companyId = "company-1",
                    name = "Execution flow",
                    stages = emptyList(),
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            agentContextEntries = listOf(
                AgentContextEntry(
                    id = "context-1",
                    companyId = "company-1",
                    agentName = "CEO",
                    kind = "note",
                    title = "Keep this",
                    content = "Preserve note across lenient recovery.",
                    visibility = "company",
                    createdAt = 1L
                )
            ),
            agentMessages = listOf(
                AgentMessage(
                    id = "message-1",
                    companyId = "company-1",
                    fromAgentName = "CEO",
                    toAgentName = "Builder",
                    kind = "handoff",
                    subject = "Preserve this",
                    body = "Preserve message across lenient recovery.",
                    createdAt = 1L
                )
            ),
            tasks = listOf(
                AgentTask(
                    id = "task-1",
                    workspaceId = "workspace-1",
                    title = "Invalid task",
                    prompt = "prompt",
                    agents = listOf("codex"),
                    status = DesktopTaskStatus.COMPLETED,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            )
        )

        store.save(state)
        val corruptedPayload = readSqliteCollection(appHome, "tasks").replaceFirst(
            "\"status\": \"COMPLETED\"",
            "\"status\": \"NOT_A_REAL_STATUS\""
        )
        writeSqliteCollection(appHome, "tasks", corruptedPayload)

        val recovered = store.load()

        recovered.tasks shouldBe emptyList()
        recovered.workflowPipelines.map { it.id } shouldBe listOf("pipeline-1")
        recovered.agentContextEntries.map { it.id } shouldBe listOf("context-1")
        recovered.agentMessages.map { it.id } shouldBe listOf("message-1")
    }

    test("lenient recovery preserves runtime work queue, problem signals, and direct chat") {
        val appHome = Files.createTempDirectory("desktop-state-store-lenient-latest-fields-home")
        val store = DesktopStateStore { appHome }
        val company = Company(
            id = "company-1",
            name = "Latest Fields Company",
            rootPath = "/tmp/latest-fields-company",
            repositoryId = "repo-1",
            defaultBaseBranch = "master",
            createdAt = 1L,
            updatedAt = 1L
        )
        val goal = CompanyGoal(
            id = "goal-1",
            companyId = company.id,
            title = "Keep latest fields",
            description = "Preserve newer state fields during lenient recovery.",
            status = GoalStatus.ACTIVE,
            createdAt = 1L,
            updatedAt = 1L
        )
        val issue = CompanyIssue(
            id = "issue-1",
            companyId = company.id,
            goalId = goal.id,
            workspaceId = "workspace-1",
            title = "Runtime work",
            description = "Keep work queue data.",
            status = IssueStatus.PLANNED,
            createdAt = 1L,
            updatedAt = 1L
        )
        val state = DesktopAppState(
            companies = listOf(company),
            goals = listOf(goal),
            issues = listOf(issue),
            tasks = listOf(
                AgentTask(
                    id = "task-1",
                    workspaceId = "workspace-1",
                    issueId = issue.id,
                    title = "Invalid task",
                    prompt = "prompt",
                    agents = listOf("codex"),
                    status = DesktopTaskStatus.COMPLETED,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            companyRuntimeWorkItems = listOf(
                CompanyRuntimeWorkItem(
                    id = "work-1",
                    companyId = company.id,
                    goalId = goal.id,
                    issueId = issue.id,
                    status = CompanyRuntimeWorkItemStatus.READY,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            problemSignals = listOf(
                CompanyProblemSignal(
                    id = "signal-1",
                    companyId = company.id,
                    kind = "runtime",
                    title = "Keep signal",
                    detail = "This signal should survive partial state recovery.",
                    source = "test",
                    dedupeKey = "signal-1",
                    goalId = goal.id,
                    issueId = issue.id,
                    firstSeenAt = 1L,
                    lastSeenAt = 1L,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            directChatConversations = listOf(
                DirectChatConversation(
                    id = "conversation-1",
                    companyId = company.id,
                    title = "Keep chat",
                    model = "gemma",
                    provider = "ollama",
                    messages = listOf(
                        DirectChatMessage(
                            id = "message-1",
                            role = "user",
                            content = "Do not drop this chat during lenient recovery.",
                            createdAt = 1L
                        )
                    ),
                    createdAt = 1L,
                    updatedAt = 1L
                )
            )
        )

        saveLegacyJsonState(appHome, state)
        val statePath = appHome.resolve("state.json")
        val corruptedPayload = statePath.readText().replaceFirst(
            "\"status\": \"COMPLETED\"",
            "\"status\": \"NOT_A_REAL_STATUS\""
        )
        Files.writeString(statePath, corruptedPayload)

        val recovered = store.load()

        recovered.tasks shouldBe emptyList()
        recovered.companyRuntimeWorkItems.map { it.id } shouldBe listOf("work-1")
        recovered.problemSignals.map { it.id } shouldBe listOf("signal-1")
        recovered.directChatConversations.map { it.id } shouldBe listOf("conversation-1")
        recovered.directChatConversations.single().messages.map { it.id } shouldBe listOf("message-1")
    }

    test("save compacts terminal task prompts and run outputs for faster future loads") {
        val appHome = Files.createTempDirectory("desktop-state-store-compact-home")
        val store = DesktopStateStore { appHome }
        val longPrompt = "prompt-".repeat(800)
        val longOutput = "output-".repeat(800)
        val state = DesktopAppState(
            tasks = listOf(
                AgentTask(
                    id = "task-1",
                    workspaceId = "workspace-1",
                    title = "Compacted task",
                    prompt = longPrompt,
                    agents = listOf("codex"),
                    plan = TaskExecutionPlan(
                        goalSummary = "Goal",
                        decompositionSource = "test",
                        assignments = listOf(
                            AgentAssignmentPlan(
                                agentName = "codex",
                                role = "Builder",
                                focus = "execution",
                                assignedPrompt = "assigned-prompt"
                            )
                        )
                    ),
                    status = DesktopTaskStatus.COMPLETED,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            runs = listOf(
                AgentRun(
                    id = "run-1",
                    taskId = "task-1",
                    workspaceId = "workspace-1",
                    repositoryId = "repo-1",
                    agentName = "codex",
                    branchName = "codex/cotor/test",
                    worktreePath = "/tmp/worktree",
                    status = AgentRunStatus.COMPLETED,
                    output = longOutput,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            )
        )

        store.save(state)
        val persisted = readSqliteCollection(appHome, "tasks") + readSqliteCollection(appHome, "runs")

        persisted.shouldContain("[compacted ")
        persisted.shouldNotContain(longPrompt)
        persisted.shouldNotContain(longOutput)
        persisted.shouldNotContain("\"plan\": {")
    }

    test("save preserves full prompts for unresolved issue tasks") {
        val appHome = Files.createTempDirectory("desktop-state-store-unresolved-prompt-home")
        val store = DesktopStateStore { appHome }
        val longPrompt = "prompt-".repeat(800)
        val state = DesktopAppState(
            companies = listOf(
                Company(
                    id = "company-1",
                    name = "Unresolved Prompt Company",
                    rootPath = "/tmp/unresolved-prompt-company",
                    repositoryId = "repo-1",
                    defaultBaseBranch = "master",
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            projectContexts = listOf(
                CompanyProjectContext(
                    id = "project-1",
                    companyId = "company-1",
                    name = "Unresolved Prompt Company",
                    slug = "unresolved-prompt-company",
                    contextDocPath = appHome.resolve("project.md").toString(),
                    lastUpdatedAt = 1L
                )
            ),
            goals = listOf(
                CompanyGoal(
                    id = "goal-1",
                    companyId = "company-1",
                    projectContextId = "project-1",
                    title = "Keep prompt",
                    description = "Keep unresolved prompt context.",
                    status = GoalStatus.ACTIVE,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            issues = listOf(
                CompanyIssue(
                    id = "issue-1",
                    companyId = "company-1",
                    projectContextId = "project-1",
                    goalId = "goal-1",
                    workspaceId = "workspace-1",
                    title = "Retryable issue",
                    description = "Still unresolved.",
                    status = IssueStatus.BLOCKED,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            tasks = listOf(
                AgentTask(
                    id = "task-1",
                    workspaceId = "workspace-1",
                    issueId = "issue-1",
                    title = "Blocked task",
                    prompt = longPrompt,
                    agents = listOf("codex"),
                    status = DesktopTaskStatus.FAILED,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            )
        )

        store.save(state)
        val persisted = readSqliteCollection(appHome, "tasks")

        persisted.shouldContain(longPrompt.take(200))
        persisted.shouldNotContain("[compacted ")
    }

    test("save preserves full run output for unresolved issue tasks") {
        val appHome = Files.createTempDirectory("desktop-state-store-unresolved-output-home")
        val store = DesktopStateStore { appHome }
        val longOutput = "```json\n{\"goalSummary\":\"" + "plan-".repeat(900) + "\",\"issues\":[{\"refId\":\"exec-1\",\"title\":\"Work\",\"description\":\"Do work\",\"assigneeRole\":\"Builder\"}]}\n```"
        val state = DesktopAppState(
            companies = listOf(
                Company(
                    id = "company-1",
                    name = "Unresolved Output Company",
                    rootPath = "/tmp/unresolved-output-company",
                    repositoryId = "repo-1",
                    defaultBaseBranch = "master",
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            projectContexts = listOf(
                CompanyProjectContext(
                    id = "project-1",
                    companyId = "company-1",
                    name = "Unresolved Output Company",
                    slug = "unresolved-output-company",
                    contextDocPath = appHome.resolve("project.md").toString(),
                    lastUpdatedAt = 1L
                )
            ),
            goals = listOf(
                CompanyGoal(
                    id = "goal-1",
                    companyId = "company-1",
                    projectContextId = "project-1",
                    title = "Keep output",
                    description = "Keep unresolved run output.",
                    status = GoalStatus.ACTIVE,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            issues = listOf(
                CompanyIssue(
                    id = "issue-1",
                    companyId = "company-1",
                    projectContextId = "project-1",
                    goalId = "goal-1",
                    workspaceId = "workspace-1",
                    title = "Blocked planning issue",
                    description = "Still needs planning sync.",
                    status = IssueStatus.BLOCKED,
                    kind = "planning",
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            tasks = listOf(
                AgentTask(
                    id = "task-1",
                    workspaceId = "workspace-1",
                    issueId = "issue-1",
                    title = "Planning task",
                    prompt = "prompt",
                    agents = listOf("opencode"),
                    status = DesktopTaskStatus.COMPLETED,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            ),
            runs = listOf(
                AgentRun(
                    id = "run-1",
                    taskId = "task-1",
                    workspaceId = "workspace-1",
                    repositoryId = "repo-1",
                    agentName = "opencode",
                    branchName = "codex/cotor/test",
                    worktreePath = "/tmp/worktree",
                    status = AgentRunStatus.COMPLETED,
                    output = longOutput,
                    createdAt = 1L,
                    updatedAt = 1L
                )
            )
        )

        store.save(state)
        val persisted = readSqliteCollection(appHome, "runs")

        store.load().runs.single().output shouldBe longOutput
        persisted.shouldNotContain("[compacted ")
    }
})

private suspend fun saveLegacyJsonState(appHome: java.nio.file.Path, state: DesktopAppState) {
    val previous = System.getProperty("cotor.desktop.state.backend")
    System.setProperty("cotor.desktop.state.backend", "json")
    try {
        DesktopStateStore { appHome }.save(state)
    } finally {
        if (previous == null) {
            System.clearProperty("cotor.desktop.state.backend")
        } else {
            System.setProperty("cotor.desktop.state.backend", previous)
        }
    }
}

private fun readSqliteCollection(appHome: java.nio.file.Path, name: String): String =
    DriverManager.getConnection("jdbc:sqlite:${appHome.resolve("state.sqlite").toAbsolutePath().normalize()}").use { connection ->
        connection.prepareStatement("SELECT payload FROM state_collections WHERE name = ?").use { statement ->
            statement.setString(1, name)
            statement.executeQuery().use { result ->
                if (result.next()) result.getString(1) else ""
            }
        }
    }

private fun readSqliteCollectionUpdatedAt(appHome: java.nio.file.Path, name: String): Long =
    DriverManager.getConnection("jdbc:sqlite:${appHome.resolve("state.sqlite").toAbsolutePath().normalize()}").use { connection ->
        connection.prepareStatement("SELECT updated_at FROM state_collections WHERE name = ?").use { statement ->
            statement.setString(1, name)
            statement.executeQuery().use { result ->
                if (result.next()) result.getLong(1) else 0L
            }
        }
    }

private fun writeSqliteCollection(
    appHome: java.nio.file.Path,
    name: String,
    payload: String,
    bumpRevision: Boolean = true
) {
    DriverManager.getConnection("jdbc:sqlite:${appHome.resolve("state.sqlite").toAbsolutePath().normalize()}").use { connection ->
        connection.prepareStatement("UPDATE state_collections SET payload = ?, payload_sha256 = 'corrupted', updated_at = ? WHERE name = ?").use { statement ->
            statement.setString(1, payload)
            statement.setLong(2, System.currentTimeMillis())
            statement.setString(3, name)
            statement.executeUpdate()
        }
        if (bumpRevision) {
            connection.prepareStatement("UPDATE state_meta SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT) WHERE key = 'revision'").use { statement ->
                statement.executeUpdate()
            }
        }
    }
}

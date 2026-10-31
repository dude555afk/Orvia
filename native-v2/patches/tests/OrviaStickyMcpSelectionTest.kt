package me.rerere.rikkahub.data.datastore

import kotlin.uuid.Uuid
import me.rerere.rikkahub.data.ai.mcp.McpCommonOptions
import me.rerere.rikkahub.data.ai.mcp.McpServerConfig
import me.rerere.rikkahub.data.model.Assistant
import org.junit.Assert.assertEquals
import org.junit.Test

class OrviaStickyMcpSelectionTest {
    private val assistantA = Uuid.parse("00000000-0000-0000-0000-000000000001")
    private val assistantB = Uuid.parse("00000000-0000-0000-0000-000000000002")
    private val github = Uuid.parse("00000000-0000-0000-0000-000000000011")
    private val search = Uuid.parse("00000000-0000-0000-0000-000000000012")

    private fun settings(selection: Set<Uuid>? = null) = Settings(
        assistantId = assistantA,
        orviaStickyMcpServers = selection,
        mcpServers = listOf(
            McpServerConfig.StreamableHTTPServer(
                id = github,
                commonOptions = McpCommonOptions(name = "GitHub"),
                url = "https://github.example/mcp",
            ),
            McpServerConfig.StreamableHTTPServer(
                id = search,
                commonOptions = McpCommonOptions(name = "Search"),
                url = "https://search.example/mcp",
            ),
        ),
        assistants = listOf(
            Assistant(id = assistantA, name = "A", mcpServers = setOf(github)),
            Assistant(id = assistantB, name = "B"),
        ),
    )

    @Test
    fun migratesCurrentAssistantSelectionToEveryAssistant() {
        val normalized = OrviaStickyMcpSelection.normalize(settings(), null)

        assertEquals(setOf(github), normalized.orviaStickyMcpServers)
        assertEquals(setOf(github), normalized.assistants[0].mcpServers)
        assertEquals(setOf(github), normalized.assistants[1].mcpServers)
    }

    @Test
    fun pickerChangeBecomesGlobalAndSurvivesAssistantSwitch() {
        val previous = OrviaStickyMcpSelection.normalize(settings(), setOf(github))
        val selected = OrviaStickyMcpSelection.select(previous, setOf(github, search))
        val edited = selected.copy(assistantId = assistantB)

        val updated = OrviaStickyMcpSelection.applyUpdate(previous, edited)

        assertEquals(setOf(github, search), updated.orviaStickyMcpServers)
        assertEquals(setOf(github, search), updated.assistants[0].mcpServers)
        assertEquals(setOf(github, search), updated.assistants[1].mcpServers)
    }

    @Test
    fun staleAssistantEditCannotClearMcpSelection() {
        val previous = OrviaStickyMcpSelection.normalize(settings(), setOf(github, search))
        val staleEdit = settings().copy(
            assistants = settings().assistants.map { it.copy(name = "Renamed") },
        )

        val updated = OrviaStickyMcpSelection.applyUpdate(previous, staleEdit)

        assertEquals(setOf(github, search), updated.orviaStickyMcpServers)
        assertEquals(setOf(github, search), updated.assistants[0].mcpServers)
        assertEquals(setOf(github, search), updated.assistants[1].mcpServers)
    }

    @Test
    fun explicitDisableStaysDisabled() {
        val previous = OrviaStickyMcpSelection.normalize(settings(), setOf(github))
        val edited = OrviaStickyMcpSelection.select(previous, emptySet())

        val updated = OrviaStickyMcpSelection.applyUpdate(previous, edited)

        assertEquals(emptySet<Uuid>(), updated.orviaStickyMcpServers)
        assertEquals(emptySet<Uuid>(), updated.assistants[0].mcpServers)
        assertEquals(emptySet<Uuid>(), updated.assistants[1].mcpServers)
    }
}

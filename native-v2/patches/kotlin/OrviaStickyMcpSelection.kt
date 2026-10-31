package me.rerere.rikkahub.data.datastore

import kotlin.uuid.Uuid

/**
 * Keeps the user's MCP selection independent of the currently selected
 * assistant. Assistant.mcpServers remains the runtime compatibility cache
 * consumed by LastChat's MCP manager.
 */
internal object OrviaStickyMcpSelection {
    fun normalize(settings: Settings, storedSelection: Set<Uuid>?): Settings {
        val selected = storedSelection
            ?: settings.assistants.firstOrNull { it.id == settings.assistantId }
                ?.mcpServers
                .orEmpty()
        return settings.copy(
            orviaStickyMcpServers = selected,
            assistants = settings.assistants.map { it.copy(mcpServers = selected) },
        )
    }

    /**
     * Translate existing assistant-picker writes into the app-wide source of
     * truth. A normal assistant edit made from an old snapshot must never
     * erase a user's MCP choices.
     */
    fun applyUpdate(previous: Settings, requested: Settings): Settings {
        val changedSelections = requested.assistants.mapNotNull { next ->
            val old = previous.assistants.firstOrNull { it.id == next.id }
                ?: return@mapNotNull null
            next.mcpServers.takeIf { it != old.mcpServers }
        }.distinct()

        val selected = when {
            requested.orviaStickyMcpServers != previous.orviaStickyMcpServers ->
                requested.orviaStickyMcpServers.orEmpty()
            changedSelections.size == 1 -> changedSelections.single()
            else -> previous.orviaStickyMcpServers
                ?: previous.assistants.firstOrNull { it.id == previous.assistantId }
                    ?.mcpServers
                    .orEmpty()
        }

        return requested.copy(
            orviaStickyMcpServers = selected,
            assistants = requested.assistants.map { it.copy(mcpServers = selected) },
        )
    }
}

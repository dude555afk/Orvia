#!/usr/bin/env python3
"""Apply the tested Orvia overlay to the pinned LastChat source before building.

The upstream LastChat submodule stays pinned and unchanged in Git history. This
script makes Orvia-specific provider defaults, provider-menu curation, and
anonymous Kilo gateway auth behavior reproducible in CI.
"""
from __future__ import annotations

import argparse
from pathlib import Path

KILO_PROVIDER_ID = "e1200000-0000-4000-8000-000000000001"
KILO_MODEL_ID = "e1200000-0000-4000-8000-000000000002"
KILO_BASE_URL = "https://ai-gateway.kilo.ai/api/v1"
KILO_MODEL = "kilo-auto/free"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one match, got {count}: {old[:100]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True, help="Path to the pinned LastChat checkout")
    args = parser.parse_args()
    root = args.root.resolve()
    if not (root / "app/build.gradle.kts").is_file():
        raise SystemExit(f"Not a LastChat Android source root: {root}")

    # A fresh install gets the same no-key Kilo route used by Orvia Flutter.
    replace_once(
        root / "app/src/main/java/me/rerere/rikkahub/data/datastore/DefaultProviders.kt",
        """package me.rerere.rikkahub.data.datastore

import me.rerere.ai.provider.ProviderSetting

// A fresh install starts with an empty provider list. No providers are seeded — the user adds
// them (including the on-device "Local" provider) via the provider presets / first-time setup.
// See ProviderPresets.kt (SPECIAL_PROVIDER_PRESETS).
val DEFAULT_PROVIDERS = emptyList<ProviderSetting>()
""",
        f"""package me.rerere.rikkahub.data.datastore

import me.rerere.ai.provider.Model
import me.rerere.ai.provider.ProviderSetting
import kotlin.uuid.Uuid

// Stable IDs keep the initial chat-model selection aligned with the seeded provider.
val ORVIA_KILO_PROVIDER_ID: Uuid = Uuid.parse("{KILO_PROVIDER_ID}")
val ORVIA_KILO_MODEL_ID: Uuid = Uuid.parse("{KILO_MODEL_ID}")

// Kilo's Auto Free route is anonymous: do not insert a placeholder API key.
val DEFAULT_PROVIDERS: List<ProviderSetting> = listOf(
    ProviderSetting.OpenAI(
        id = ORVIA_KILO_PROVIDER_ID,
        enabled = true,
        name = "Kilo",
        models = listOf(
            Model(
                id = ORVIA_KILO_MODEL_ID,
                modelId = "{KILO_MODEL}",
                displayName = "Kilo Auto Free",
                providerSlug = "kilo",
            )
        ),
        apiKey = "",
        baseUrl = "{KILO_BASE_URL}",
    )
)
""",
    )

    # Make the selected chat model point at the seeded Kilo model on fresh installs.
    replace_once(
        root / "app/src/main/java/me/rerere/rikkahub/data/datastore/PreferencesModels.kt",
        "val chatModelId: Uuid = Uuid.random(),",
        "val chatModelId: Uuid = ORVIA_KILO_MODEL_ID,",
    )
    replace_once(
        root / "app/src/main/java/me/rerere/rikkahub/data/datastore/PreferencesStore.kt",
        "chatModelId = decodeUuid(preferences[SELECT_MODEL], GEMINI_2_5_FLASH_ID),",
        "chatModelId = decodeUuid(preferences[SELECT_MODEL], ORVIA_KILO_MODEL_ID),",
    )

    presets_path = root / "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/components/ProviderPresets.kt"
    presets = presets_path.read_text(encoding="utf-8")
    start = presets.index("val FALLBACK_PROVIDER_PRESETS = listOf(")
    end = presets.index("\nval SPECIAL_PROVIDER_PRESETS = listOf(", start)
    curated_fallbacks = r'''val FALLBACK_PROVIDER_PRESETS = listOf(
    ProviderPreset(
        name = "OpenAI",
        description = "Access OpenAI models through the official API",
        type = ProviderSetting.OpenAI::class,
        baseUrl = "https://api.openai.com/v1",
    ),
    ProviderPreset(
        name = "Google Gemini",
        description = "Multimodal AI with text, image, audio, and video",
        type = ProviderSetting.Google::class,
        baseUrl = "https://generativelanguage.googleapis.com/v1beta",
    ),
    ProviderPreset(
        name = "OpenRouter",
        description = "Access many hosted models through one OpenAI-compatible API",
        type = ProviderSetting.OpenAI::class,
        baseUrl = "https://openrouter.ai/api/v1",
        balanceOption = BalanceOption(
            enabled = true,
            apiPath = "/credits",
            resultPath = "data.total_credits - data.total_usage",
        ),
    ),
    ProviderPreset(
        name = "Kilo",
        description = "Anonymous access to free hosted models; no API key required",
        type = ProviderSetting.OpenAI::class,
        baseUrl = "https://ai-gateway.kilo.ai/api/v1",
        setupRecommended = true,
        setupOrder = 0,
        setupDescription = "Use Kilo Auto Free without an API key.",
        setupModelIds = listOf("kilo-auto/free"),
    ),
    ProviderPreset(
        name = "AIhubmix",
        description = "Hosted models through the AIhubmix OpenAI-compatible API",
        type = ProviderSetting.OpenAI::class,
        baseUrl = "https://aihubmix.com/v1",
    ),
    ProviderPreset(
        name = "Claude",
        description = "Safety-focused AI with strong reasoning",
        type = ProviderSetting.Claude::class,
        baseUrl = "https://api.anthropic.com/v1",
    ),
    ProviderPreset(
        name = "Grok",
        description = "xAI models through the OpenAI-compatible API",
        type = ProviderSetting.OpenAI::class,
        baseUrl = "https://api.x.ai/v1",
    ),
)'''
    presets = presets[:start] + curated_fallbacks + presets[end:]
    old_mapper = """fun ModelCatalogSnapshot.toProviderPresets(): List<ProviderPreset> {
    return providers
        .filter { it.preset }
        .map { it.toProviderPreset(this) }
}"""
    new_mapper = r'''private val ORVIA_ALLOWED_PROVIDER_PRESET_NAMES = setOf(
    "openai",
    "openrouter",
    "google ai studio",
    "google gemini",
    "gemini",
    "kilo",
    "aihubmix",
    "ai hubmix",
    "anthropic claude",
    "claude",
    "xai",
    "grok",
)

private fun ProviderPreset.withOrviaProviderName(): ProviderPreset {
    val canonicalName = when (name.trim().lowercase()) {
        "google ai studio", "gemini" -> "Google Gemini"
        "ai hubmix" -> "AIhubmix"
        "anthropic claude" -> "Claude"
        "xai" -> "Grok"
        else -> name.trim()
    }
    return copy(name = canonicalName)
}

fun ModelCatalogSnapshot.toProviderPresets(): List<ProviderPreset> {
    val catalogPresets = providers
        .filter { it.preset && it.name.trim().lowercase() in ORVIA_ALLOWED_PROVIDER_PRESET_NAMES }
        .map { it.toProviderPreset(this).withOrviaProviderName() }
        .associateBy { it.name.trim().lowercase() }

    // Keep a stable, short Orvia list even if the remote catalog changes.
    // Catalog metadata remains useful, while fallback endpoints and the Kilo
    // free route stay under Orvia's control.
    return FALLBACK_PROVIDER_PRESETS.map { fallback ->
        val catalogPreset = catalogPresets[fallback.name.trim().lowercase()]
        if (catalogPreset == null) {
            fallback
        } else {
            catalogPreset.copy(
                name = fallback.name,
                baseUrl = fallback.baseUrl,
                setupModelIds = if (fallback.name == "Kilo") {
                    fallback.setupModelIds
                } else {
                    catalogPreset.setupModelIds
                },
                setupRecommended = fallback.setupRecommended || catalogPreset.setupRecommended,
                setupOrder = if (fallback.name == "Kilo") 0 else catalogPreset.setupOrder,
                setupDescription = fallback.setupDescription ?: catalogPreset.setupDescription,
            )
        }
    }
}'''
    if presets.count(old_mapper) != 1:
        raise RuntimeError("ProviderPresets.kt: expected unique ModelCatalogSnapshot.toProviderPresets implementation")
    presets_path.write_text(presets.replace(old_mapper, new_mapper, 1), encoding="utf-8")

    # Both OpenAI-compatible chat APIs must omit Authorization entirely when
    # the user intentionally leaves the API key blank for the anonymous route.
    old_auth = '''private fun Map<String, String>.withAuthAndJson(apiKey: String): Map<String, String> {
    return this + mapOf(
        "Authorization" to "Bearer $apiKey",
        "Content-Type" to "application/json"
    )
}'''
    new_auth = '''private fun Map<String, String>.withAuthAndJson(apiKey: String): Map<String, String> {
    return this + buildMap {
        if (apiKey.isNotBlank()) {
            put("Authorization", "Bearer $apiKey")
        }
        put("Content-Type", "application/json")
    }
}'''
    for relative in (
        "ai/src/main/java/me/rerere/ai/provider/providers/openai/ChatCompletionsAPI.kt",
        "ai/src/main/java/me/rerere/ai/provider/providers/openai/ResponseAPI.kt",
    ):
        replace_once(root / relative, old_auth, new_auth)

    # Guard against an overlay silently drifting away from the expected setup.
    defaults = (root / "app/src/main/java/me/rerere/rikkahub/data/datastore/DefaultProviders.kt").read_text(encoding="utf-8")
    assert KILO_BASE_URL in defaults and KILO_MODEL in defaults and 'apiKey = ""' in defaults
    assert "ORVIA_KILO_MODEL_ID" in (root / "app/src/main/java/me/rerere/rikkahub/data/datastore/PreferencesStore.kt").read_text(encoding="utf-8")
    assert '"Authorization" to "Bearer $apiKey"' not in (root / "ai/src/main/java/me/rerere/ai/provider/providers/openai/ChatCompletionsAPI.kt").read_text(encoding="utf-8")
    assert '"Authorization" to "Bearer $apiKey"' not in (root / "ai/src/main/java/me/rerere/ai/provider/providers/openai/ResponseAPI.kt").read_text(encoding="utf-8")
    print("PASS: Orvia defaults to Kilo Auto Free, omits blank Authorization headers, and curates provider presets.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Patch LastChat's native source with Orvia's provider defaults."""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path.cwd()
APP = ROOT / "native-v2" / "lastchat"

def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count == 0 and new in text:
        return
    if count != 1:
        raise SystemExit(f"Expected one patch target in {path.relative_to(ROOT)}, found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")

if not (APP / "app/build.gradle.kts").is_file():
    raise SystemExit("LastChat submodule missing; run tool/prepare_orvia_native.py first.")

# Normalize the bundled catalog to Orvia's free, anonymous Kilo route.
catalog_path = APP / "catalog" / "lastchat_catalog.json"
catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
kilo = next((p for p in catalog.get("providers", [])
             if p.get("name", "").strip().lower() in {"kilo", "kilo gateway (free)"}), None)
if kilo is None:
    raise SystemExit("Kilo provider is missing from the Orvia-owned catalog.")
kilo.update({
    "name": "Kilo",
    "description": "Anonymous access to Kilo Auto Free. No API key required; rate limits apply.",
    "setup_models": ["kilo-auto/free"],
    "setup_defaults": {
        "chat": "kilo-auto/free", "title": "kilo-auto/free",
        "summarizer": "kilo-auto/free", "ocr": "kilo-auto/free",
    },
    "setup_recommended": True,
    "setup_order": 0,
    "setup_description": "No API key required for Kilo Auto Free; anonymous rate limits apply.",
})
catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

# Start with a real Kilo provider and model, not an empty provider list.
replace_once(
    APP / "app/src/main/java/me/rerere/rikkahub/data/datastore/DefaultProviders.kt",
    """package me.rerere.rikkahub.data.datastore

import me.rerere.ai.provider.ProviderSetting

// A fresh install starts with an empty provider list. No providers are seeded — the user adds
// them (including the on-device "Local" provider) via the provider presets / first-time setup.
// See ProviderPresets.kt (SPECIAL_PROVIDER_PRESETS).
val DEFAULT_PROVIDERS = emptyList<ProviderSetting>()
""",
    """package me.rerere.rikkahub.data.datastore

import me.rerere.ai.provider.Model
import me.rerere.ai.provider.ProviderSetting
import kotlin.uuid.Uuid

val ORVIA_KILO_PROVIDER_ID: Uuid = Uuid.parse("6b30a0fe-8b9a-4d11-80a9-0ce541a07731")
val ORVIA_KILO_MODEL_ID: Uuid = Uuid.parse("e1200000-0000-4000-8000-000000000002")

// Anonymous Kilo requests must not have an API key injected.
val DEFAULT_PROVIDERS: List<ProviderSetting> = listOf(
    ProviderSetting.OpenAI(
        id = ORVIA_KILO_PROVIDER_ID,
        enabled = true,
        name = "Kilo",
        models = listOf(
            Model(
                id = ORVIA_KILO_MODEL_ID,
                modelId = "kilo-auto/free",
                displayName = "Kilo Auto Free",
                providerSlug = "kilo",
            )
        ),
        apiKey = "",
        baseUrl = "https://ai-gateway.kilo.ai/api/v1",
    )
)
""",
)
replace_once(
    APP / "app/src/main/java/me/rerere/rikkahub/data/datastore/PreferencesModels.kt",
    "val chatModelId: Uuid = Uuid.random(),",
    "val chatModelId: Uuid = ORVIA_KILO_MODEL_ID,",
)
replace_once(
    APP / "app/src/main/java/me/rerere/rikkahub/data/datastore/PreferencesStore.kt",
    "chatModelId = decodeUuid(preferences[SELECT_MODEL], GEMINI_2_5_FLASH_ID),",
    "chatModelId = decodeUuid(preferences[SELECT_MODEL], ORVIA_KILO_MODEL_ID),",
)

# Keep the provider picker consistent with Orvia's supported provider set.
provider_file = APP / "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/components/ProviderPresets.kt"
source = provider_file.read_text(encoding="utf-8")
start = source.index("val FALLBACK_PROVIDER_PRESETS = listOf(")
end = source.index("val SPECIAL_PROVIDER_PRESETS = listOf(", start)
fallback = """val FALLBACK_PROVIDER_PRESETS = listOf(
    ProviderPreset(name = "OpenAI", description = "Official OpenAI API", type = ProviderSetting.OpenAI::class, baseUrl = "https://api.openai.com/v1"),
    ProviderPreset(name = "Google Gemini", description = "Multimodal AI from Google", type = ProviderSetting.Google::class, baseUrl = "https://generativelanguage.googleapis.com/v1beta"),
    ProviderPreset(name = "OpenRouter", description = "Access many hosted models through one API", type = ProviderSetting.OpenAI::class, baseUrl = "https://openrouter.ai/api/v1"),
    ProviderPreset(
        name = "Kilo",
        description = "Anonymous access to Kilo Auto Free; no API key required",
        type = ProviderSetting.OpenAI::class,
        baseUrl = "https://ai-gateway.kilo.ai/api/v1",
        setupRecommended = true,
        setupOrder = 0,
        setupDescription = "No API key required; anonymous rate limits apply.",
        setupModelIds = listOf("kilo-auto/free"),
        setupDefaults = CatalogSetupDefaults(chat = "kilo-auto/free", title = "kilo-auto/free", summarizer = "kilo-auto/free", ocr = "kilo-auto/free"),
    ),
    ProviderPreset(name = "AIhubmix", description = "Hosted models through AIhubmix", type = ProviderSetting.OpenAI::class, baseUrl = "https://aihubmix.com/v1"),
    ProviderPreset(name = "Claude", description = "Anthropic Claude models", type = ProviderSetting.Claude::class, baseUrl = "https://api.anthropic.com/v1"),
    ProviderPreset(name = "Grok", description = "xAI models", type = ProviderSetting.OpenAI::class, baseUrl = "https://api.x.ai/v1"),
)"""
source = source[:start] + fallback + "\n\n" + source[end:]
old_mapper = """fun ModelCatalogSnapshot.toProviderPresets(): List<ProviderPreset> {
    return providers
        .filter { it.preset }
        .map { it.toProviderPreset(this) }
}"""
new_mapper = """private val ORVIA_ALLOWED_PROVIDER_PRESET_NAMES = setOf(
    "openai", "openrouter", "google ai studio", "google gemini",
    "kilo", "kilo gateway (free)", "aihubmix", "ai hubmix",
    "anthropic claude", "claude", "xai", "grok",
)

fun ModelCatalogSnapshot.toProviderPresets(): List<ProviderPreset> {
    return providers
        .filter { it.preset && it.name.trim().lowercase() in ORVIA_ALLOWED_PROVIDER_PRESET_NAMES }
        .map { it.toProviderPreset(this) }
        .map { preset ->
            when (preset.name.trim().lowercase()) {
                "kilo gateway (free)" -> preset.copy(
                    name = "Kilo",
                    setupRecommended = true,
                    setupOrder = 0,
                    setupDescription = "No API key required; anonymous rate limits apply.",
                    setupModelIds = listOf("kilo-auto/free"),
                    setupDefaults = CatalogSetupDefaults(chat = "kilo-auto/free", title = "kilo-auto/free", summarizer = "kilo-auto/free", ocr = "kilo-auto/free"),
                )
                "google ai studio", "google gemini" -> preset.copy(name = "Google Gemini")
                "anthropic claude" -> preset.copy(name = "Claude")
                "xai" -> preset.copy(name = "Grok")
                "ai hubmix" -> preset.copy(name = "AIhubmix")
                else -> preset
            }
        }
}"""
if old_mapper in source:
    source = source.replace(old_mapper, new_mapper, 1)
elif "ORVIA_ALLOWED_PROVIDER_PRESET_NAMES" not in source:
    raise SystemExit("Provider preset mapper changed unexpectedly.")
provider_file.write_text(source, encoding="utf-8")

# Don't emit an empty Bearer header; this is required for keyless Kilo.
old_auth = '''private fun Map<String, String>.withAuthAndJson(apiKey: String): Map<String, String> {
    return this + mapOf(
        "Authorization" to "Bearer $apiKey",
        "Content-Type" to "application/json"
    )
}'''
new_auth = '''private fun Map<String, String>.withAuthAndJson(apiKey: String): Map<String, String> {
    val authHeader = apiKey.takeIf { it.isNotBlank() }
        ?.let { mapOf("Authorization" to "Bearer $it") }
        ?: emptyMap()
    return this + authHeader + ("Content-Type" to "application/json")
}'''
for relative in (
    "ai/src/main/java/me/rerere/ai/provider/providers/openai/ChatCompletionsAPI.kt",
    "ai/src/main/java/me/rerere/ai/provider/providers/openai/ResponseAPI.kt",
):
    path = APP / relative
    text = path.read_text(encoding="utf-8")
    if old_auth in text:
        text = text.replace(old_auth, new_auth, 1)
    elif new_auth not in text:
        raise SystemExit(f"Auth helper changed unexpectedly in {relative}.")
    path.write_text(text, encoding="utf-8")

defaults = (APP / "app/src/main/java/me/rerere/rikkahub/data/datastore/DefaultProviders.kt").read_text(encoding="utf-8")
assert "kilo-auto/free" in defaults and 'apiKey = ""' in defaults
assert "ORVIA_KILO_MODEL_ID" in (APP / "app/src/main/java/me/rerere/rikkahub/data/datastore/PreferencesStore.kt").read_text(encoding="utf-8")
assert "ORVIA_ALLOWED_PROVIDER_PRESET_NAMES" in provider_file.read_text(encoding="utf-8")
print("PASS: Kilo Auto Free defaults, provider curation, and keyless auth applied.")

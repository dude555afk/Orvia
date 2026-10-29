#!/usr/bin/env python3
"""Apply small, asserted Orvia-specific patches to the pinned LastChat source.

The upstream repository remains pinned and unmodified. This overlay is applied
only inside the CI checkout before an Orvia preview build.
"""
from pathlib import Path

ROOT = Path("native-v2/lastchat")


def replace_once(relative_path: str, old: str, new: str, expected: int = 1) -> None:
    path = ROOT / relative_path
    source = path.read_text(encoding="utf-8")
    count = source.count(old)
    if count != expected:
        raise SystemExit(
            f"{relative_path}: expected {expected} occurrence(s), found {count}; "
            "upstream changed, refusing a blind patch"
        )
    path.write_text(source.replace(old, new, expected), encoding="utf-8")


# Make the anonymous Kilo gateway discoverable even when the remote model
# catalog is available and therefore the LastChat fallback list is not used.
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/components/ProviderPresets.kt",
    "val SPECIAL_PROVIDER_PRESETS = listOf(\n",
    """val ORVIA_PROVIDER_PRESETS = listOf(
    ProviderPreset(
        name = "Kilo Free Gateway",
        description = "Anonymous Kilo AI gateway for supported free models. No API key required.",
        type = ProviderSetting.OpenAI::class,
        baseUrl = "https://ai-gateway.kilo.ai/api/v1",
        setupRecommended = true,
        setupOrder = 0,
        setupDescription = "No API key required. Uses Kilo's free model router.",
        setupModelIds = listOf("kilo-auto/free"),
        setupDefaults = CatalogSetupDefaults(
            chat = "kilo-auto/free",
            title = "kilo-auto/free",
            summarizer = "kilo-auto/free",
            ocr = "kilo-auto/free",
        ),
    ),
)

val SPECIAL_PROVIDER_PRESETS = listOf(
""",
)

# Seed the known free router model so a user can select it before fetching
# the live model list. Model discovery remains available in provider settings.
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/components/ProviderPresets.kt",
    """        ProviderSetting.OpenAI::class -> ProviderSetting.OpenAI(
            id = parsedId ?: Uuid.random(),
            name = name,
            baseUrl = baseUrl,
""",
    """        ProviderSetting.OpenAI::class -> ProviderSetting.OpenAI(
            id = parsedId ?: Uuid.random(),
            name = name,
            models = if (name.equals("Kilo Free Gateway", ignoreCase = true)) {
                listOf(Model(modelId = "kilo-auto/free", displayName = "Kilo Auto Free"))
            } else {
                emptyList()
            },
            baseUrl = baseUrl,
""",
)

replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/SettingProviderPage.kt",
    "import me.rerere.rikkahub.ui.pages.setting.components.FALLBACK_PROVIDER_PRESETS\n",
    "import me.rerere.rikkahub.ui.pages.setting.components.FALLBACK_PROVIDER_PRESETS\n"
    "import me.rerere.rikkahub.ui.pages.setting.components.ORVIA_PROVIDER_PRESETS\n",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/SettingProviderPage.kt",
    """    val providerPresets = remember(catalogSnapshot, settings.providers) {
        (catalogSnapshot?.toProviderPresets()?.takeIf { it.isNotEmpty() }
            ?: FALLBACK_PROVIDER_PRESETS
        ).withSpecialProviderPresets().filterNot { preset ->
""",
    """    val providerPresets = remember(catalogSnapshot, settings.providers) {
        val catalogOrFallback = catalogSnapshot?.toProviderPresets()?.takeIf { it.isNotEmpty() }
            ?: FALLBACK_PROVIDER_PRESETS
        val withOrviaPresets = catalogOrFallback + ORVIA_PROVIDER_PRESETS.filterNot { orviaPreset ->
            catalogOrFallback.any { it.name.equals(orviaPreset.name, ignoreCase = true) }
        }
        withOrviaPresets.withSpecialProviderPresets().filterNot { preset ->
""",
)

# Make Kilo a first-run guided option as well as a provider-settings preset.
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/onboarding/OnboardingVM.kt",
    "import me.rerere.rikkahub.ui.pages.setting.components.ProviderPreset\n",
    "import me.rerere.rikkahub.ui.pages.setting.components.ProviderPreset\n"
    "import me.rerere.rikkahub.ui.pages.setting.components.ORVIA_PROVIDER_PRESETS\n",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/onboarding/OnboardingVM.kt",
    """    fun providerPresets(snapshot: ModelCatalogSnapshot?): List<ProviderPreset> {
        return (snapshot?.toProviderPresets() ?: emptyList())
            .withSpecialProviderPresets()
            .filterNot { it.type == ProviderSetting.ComfyUI::class }
    }""",
    """    fun providerPresets(snapshot: ModelCatalogSnapshot?): List<ProviderPreset> {
        val catalogPresets = snapshot?.toProviderPresets() ?: emptyList()
        val allPresets = catalogPresets + ORVIA_PROVIDER_PRESETS.filterNot { orviaPreset ->
            catalogPresets.any { it.name.equals(orviaPreset.name, ignoreCase = true) }
        }
        return allPresets
            .withSpecialProviderPresets()
            .filterNot { it.type == ProviderSetting.ComfyUI::class }
    }""",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/onboarding/OnboardingVM.kt",
    """                val providerModels = fetchProviderModels(keyedProvider)
                val setupModels = providerModels.orderedSetupModels(preset.setupModelIds)""",
    """                val fetchedModels = fetchProviderModels(keyedProvider)
                val providerModels = if (
                    preset.name.equals("Kilo Free Gateway", ignoreCase = true) &&
                    fetchedModels.none { it.modelId == "kilo-auto/free" }
                ) {
                    fetchedModels + Model(modelId = "kilo-auto/free", displayName = "Kilo Auto Free")
                } else {
                    fetchedModels
                }
                val setupModels = providerModels.orderedSetupModels(preset.setupModelIds)""",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/onboarding/OnboardingPage.kt",
    """                SetupPage.GuidedPasteKey -> PasteKeyPage(
                    text = "Paste your API key here and
we’ll handle the rest.",
                    apiKey = apiKey,
                    onApiKeyChange = { apiKey = it },
                    loading = guidedModelsLoading,
                    onContinue = {""",
    """                SetupPage.GuidedPasteKey -> PasteKeyPage(
                    text = if (selectedGuidedProvider?.name == "Kilo Free Gateway") {
                        "Kilo Free Gateway does not need an API key.
Continue to set up free routing."
                    } else {
                        "Paste your API key here and
we’ll handle the rest."
                    },
                    apiKey = apiKey,
                    onApiKeyChange = { apiKey = it },
                    loading = guidedModelsLoading,
                    allowBlankKey = selectedGuidedProvider?.name == "Kilo Free Gateway",
                    onContinue = {""",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/onboarding/OnboardingPage.kt",
    """private fun PasteKeyPage(
    text: String,
    apiKey: String,
    onApiKeyChange: (String) -> Unit,
    loading: Boolean = false,
    onContinue: () -> Unit,
) {""",
    """private fun PasteKeyPage(
    text: String,
    apiKey: String,
    onApiKeyChange: (String) -> Unit,
    loading: Boolean = false,
    allowBlankKey: Boolean = false,
    onContinue: () -> Unit,
) {""",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/onboarding/OnboardingPage.kt",
    """                enabled = apiKey.isNotBlank() && !loading,""",
    """                enabled = (allowBlankKey || apiKey.isNotBlank()) && !loading,""",
)

# The Kilo anonymous route must not receive "Authorization: Bearer " when no
# key is configured. Keep normal Authorization headers for keyed providers.
replace_once(
    "ai/src/main/java/me/rerere/ai/provider/providers/OpenAIProvider.kt",
    'headers = mapOf("Authorization" to "Bearer $key")',
    'headers = buildMap { if (key.isNotBlank()) put("Authorization", "Bearer $key") }',
    expected=2,
)
replace_once(
    "ai/src/main/java/me/rerere/ai/provider/providers/OpenAIProvider.kt",
    """private fun Map<String, String>.withAuthAndJson(key: String): Map<String, String> {
    return this + mapOf(
        "Authorization" to "Bearer $key",
        "Content-Type" to "application/json"
    )
}""",
    """private fun Map<String, String>.withAuthAndJson(key: String): Map<String, String> {
    return this + buildMap {
        if (key.isNotBlank()) put("Authorization", "Bearer $key")
        put("Content-Type", "application/json")
    }
}""",
)
replace_once(
    "ai/src/main/java/me/rerere/ai/provider/providers/openai/ChatCompletionsAPI.kt",
    """private fun Map<String, String>.withAuthAndJson(apiKey: String): Map<String, String> {
    return this + mapOf(
        "Authorization" to "Bearer $apiKey",
        "Content-Type" to "application/json"
    )
}""",
    """private fun Map<String, String>.withAuthAndJson(apiKey: String): Map<String, String> {
    return this + buildMap {
        if (apiKey.isNotBlank()) put("Authorization", "Bearer $apiKey")
        put("Content-Type" to "application/json")
    }
}""".replace('put("Content-Type" to "application/json")', 'put("Content-Type", "application/json")'),
)
replace_once(
    "ai/src/main/java/me/rerere/ai/provider/providers/openai/ResponseAPI.kt",
    """private fun Map<String, String>.withAuthAndJson(apiKey: String): Map<String, String> {
    return this + mapOf(
        "Authorization" to "Bearer $apiKey",
        "Content-Type" to "application/json"
    )
}""",
    """private fun Map<String, String>.withAuthAndJson(apiKey: String): Map<String, String> {
    return this + buildMap {
        if (apiKey.isNotBlank()) put("Authorization", "Bearer $apiKey")
        put("Content-Type", "application/json")
    }
}""",
)

# Structural assertions make the overlay fail loudly if a future upstream
# update invalidates the intended Kilo/keyless behavior.
presets = (ROOT / "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/components/ProviderPresets.kt").read_text(encoding="utf-8")
provider_list = (ROOT / "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/SettingProviderPage.kt").read_text(encoding="utf-8")
assert 'https://ai-gateway.kilo.ai/api/v1' in presets
assert 'kilo-auto/free' in presets
assert 'ORVIA_PROVIDER_PRESETS' in provider_list
onboarding_vm = (ROOT / "app/src/main/java/me/rerere/rikkahub/ui/pages/onboarding/OnboardingVM.kt").read_text(encoding="utf-8")
onboarding_page = (ROOT / "app/src/main/java/me/rerere/rikkahub/ui/pages/onboarding/OnboardingPage.kt").read_text(encoding="utf-8")
assert 'Kilo Free Gateway' in onboarding_vm and 'kilo-auto/free' in onboarding_vm
assert 'allowBlankKey = selectedGuidedProvider?.name == "Kilo Free Gateway"' in onboarding_page
assert 'if (key.isNotBlank()) put("Authorization", "Bearer $key")' in (ROOT / "ai/src/main/java/me/rerere/ai/provider/providers/OpenAIProvider.kt").read_text(encoding="utf-8")
assert 'if (apiKey.isNotBlank()) put("Authorization", "Bearer $apiKey")' in (ROOT / "ai/src/main/java/me/rerere/ai/provider/providers/openai/ChatCompletionsAPI.kt").read_text(encoding="utf-8")
assert 'if (apiKey.isNotBlank()) put("Authorization", "Bearer $apiKey")' in (ROOT / "ai/src/main/java/me/rerere/ai/provider/providers/openai/ResponseAPI.kt").read_text(encoding="utf-8")
print("PASS: Orvia Kilo preset and anonymous Authorization handling applied.")

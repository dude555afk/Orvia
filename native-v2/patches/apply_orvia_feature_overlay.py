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


# Keep China-focused model vendors out of the provider picker. This mirrors
# the existing Orvia provider cleanup while retaining multi-provider gateways
# such as OpenRouter, AiHubMix, and Kilo.
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/components/ProviderPresets.kt",
    """fun ModelCatalogSnapshot.toProviderPresets(): List<ProviderPreset> {
    return providers
        .filter { it.preset }
        .map { it.toProviderPreset(this) }
}""",
    """private val ORVIA_HIDDEN_CATALOG_PROVIDER_NAMES = setOf(
    "deepseek",
    "alibaba qwen",
    "zhipu ai",
    "siliconflow",
    "volcengine ark",
    "internlm",
    "tencent hunyuan",
    "moonshot ai",
    "baidu qianfan",
    "iflytek spark",
    "baichuan ai",
    "sensetime",
    "gitee ai",
    "stepfun",
    "360 zhinao",
)

fun ModelCatalogSnapshot.toProviderPresets(): List<ProviderPreset> {
    return providers
        .filter { it.preset }
        .filterNot { it.name.trim().lowercase() in ORVIA_HIDDEN_CATALOG_PROVIDER_NAMES }
        .map { it.toProviderPreset(this) }
}""",
)

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
                    text = "Paste your API key here and\\nwe’ll handle the rest.",
                    apiKey = apiKey,
                    onApiKeyChange = { apiKey = it },
                    loading = guidedModelsLoading,
                    onContinue = {""",
    """                SetupPage.GuidedPasteKey -> PasteKeyPage(
                    text = if (selectedGuidedProvider?.name == "Kilo Free Gateway") {
                        "Kilo Free Gateway does not need an API key.\\nContinue to set up free routing."
                    } else {
                        "Paste your API key here and\\nwe’ll handle the rest."
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


# Apply Orvia branding to the first-run flow, About screen, and native settings.
def replace_in_file(relative_path: str, replacements: list[tuple[str, str]]) -> None:
    path = ROOT / relative_path
    source = path.read_text(encoding="utf-8")
    for old, new in replacements:
        count = source.count(old)
        if count != 1:
            raise SystemExit(
                f"{relative_path}: expected one branding marker {old!r}, found {count}; "
                "refusing a blind replacement"
            )
        source = source.replace(old, new, 1)
    path.write_text(source, encoding="utf-8")


replace_in_file(
    "app/src/dev/res/values/strings.xml",
    [("<string name=\"app_name\">LastChat_dev</string>",
      "<string name=\"app_name\">Orvia Native Preview</string>")],
)
replace_in_file(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/SettingAboutPage.kt",
    [("https://github.com/Cocolalilal/LastChat", "https://github.com/dude555afk/Orvia")],
)
replace_in_file(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/onboarding/OnboardingPage.kt",
    [
        ("return to LastChat for the", "return to Orvia for the"),
        ("up on LastChat!", "up on Orvia!"),
        ("through LastChat:", "through Orvia:"),
        ("using LastChat without", "using Orvia without"),
        ("R.drawable.lastchat_setup_icon", "R.drawable.orvia_logo"),
    ],
)
replace_in_file(
    "app/src/main/res/values/strings.xml",
    [
        ("LastChat - Open Source AI Assistant", "Orvia - Private AI Assistant"),
        ("Website: https://rikka-ai.com/", "Source: https://github.com/dude555afk/Orvia"),
        ("LastChat Workspace Setup", "Orvia Workspace Setup"),
        ("LastChat will auto-detect", "Orvia will auto-detect"),
        ("Use LastChat on your network", "Use Orvia on your network"),
        ("LastChat in a browser", "Orvia in a browser"),
        ("LastChat web server", "Orvia web server"),
        ("Ask LastChat", "Ask Orvia"),
        ("LastChat Assistant", "Orvia Assistant"),
        ("make LastChat your device assistant", "make Orvia your device assistant"),
        ("LastChat is your default assistant", "Orvia is your default assistant"),
        (r'look for \"LastChat\" in the toolbar', r'look for \"Orvia\" in the toolbar'),
        (r'look for \"LastChat\" in the selection toolbar', r'look for \"Orvia\" in the selection toolbar'),
        ("Update LastChat Catalog", "Update Orvia Catalog"),
        ('name="setting_display_model_catalog_subtitle_bundled">%1$s LastChat Catalog • %2$d models', 'name="setting_display_model_catalog_subtitle_bundled">%1$s Orvia Catalog • %2$d models'),
        ('name="setting_display_model_catalog_subtitle_downloaded">%1$s LastChat Catalog • %2$d models • Updated %3$s', 'name="setting_display_model_catalog_subtitle_downloaded">%1$s Orvia Catalog • %2$d models • Updated %3$s'),
        ("Fetch latest LastChat Catalog", "Fetch latest Orvia Catalog"),
        ("Updating the LastChat Catalog...", "Updating the Orvia Catalog..."),
        ("LastChat Catalog updated", "Orvia Catalog updated"),
        ("Failed to update LastChat Catalog: %1$s", "Failed to update Orvia Catalog: %1$s"),
        ("JSON (LastChat)", "JSON (Orvia)"),
        ("LastChat (Full)", "Orvia (Full)"),
        ("Settings &gt; Apps &gt; LastChat", "Settings &gt; Apps &gt; Orvia"),
        ("LastChat uses Google", "Orvia uses Google"),
        ("Keep LastChat open", "Keep Orvia open"),
    ],
)

# Remove China-focused TTS providers from catalog and fallback selections.
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/components/TTSProviderPresets.kt",
    """fun ModelCatalogSnapshot.toTTSProviderPresets(): List<TTSProviderPreset> {
    return ttsProviders
        .filter { it.preset }
        .map { it.toTTSProviderPreset() }
}""",
    """private val ORVIA_HIDDEN_TTS_PROVIDER_NAMES = setOf("minimax", "qwen", "dashscope")

fun ModelCatalogSnapshot.toTTSProviderPresets(): List<TTSProviderPreset> {
    return ttsProviders
        .filter { it.preset }
        .filterNot { it.name.trim().lowercase() in ORVIA_HIDDEN_TTS_PROVIDER_NAMES }
        .map { it.toTTSProviderPreset() }
}""",
)

replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/components/TTSProviderPresets.kt",
    """    TTSProviderPreset(
        name = "OpenRouter",
        description = "OpenRouter TTS (OpenAI-compatible audio/speech)",
        type = TTSProviderSetting.OpenAI::class,
        baseUrl = "https://openrouter.ai/api/v1",
        customIconUri = "icons/openrouter.svg".toCatalogIconUrl(),
    ),
)

private val ORVIA_HIDDEN_TTS_PROVIDER_NAMES = setOf("minimax", "qwen", "dashscope")

fun ModelCatalogSnapshot.toTTSProviderPresets()""",
    """    TTSProviderPreset(
        name = "OpenRouter",
        description = "OpenRouter TTS (OpenAI-compatible audio/speech)",
        type = TTSProviderSetting.OpenAI::class,
        baseUrl = "https://openrouter.ai/api/v1",
        customIconUri = "icons/openrouter.svg".toCatalogIconUrl(),
    ),
).filterNot { it.name.equals("MiniMax", ignoreCase = true) || it.name.equals("Qwen", ignoreCase = true) }

private val ORVIA_HIDDEN_TTS_PROVIDER_NAMES = setOf("minimax", "qwen", "dashscope")

fun ModelCatalogSnapshot.toTTSProviderPresets()""",
)

# The About screen uses a Compose Multiplatform-generated shared icon.
# Point its resource generation at the same Orvia logo as the launcher.
replace_once(
    "ui-core/build.gradle.kts",
    'from(rootProject.file("app/src/main/res/mipmap-xxxhdpi/ic_launcher_lastchat_foreground.png")) {',
    'from(rootProject.file("app/src/main/res/drawable-nodpi/orvia_logo.png")) {',
)
replace_once(
    "ui-core/src/commonMain/kotlin/me/rerere/rikkahub/ui/components/settings/LastChatAboutContent.kt",
    "import me.rerere.rikkahub.ui.core.generated.resources.ic_launcher_lastchat_foreground",
    "import me.rerere.rikkahub.ui.core.generated.resources.orvia_logo",
)
replace_once(
    "ui-core/src/commonMain/kotlin/me/rerere/rikkahub/ui/components/settings/LastChatAboutContent.kt",
    "painterResource(Res.drawable.ic_launcher_lastchat_foreground)",
    "painterResource(Res.drawable.orvia_logo)",
)

# Strip Chinese-locale resources from this native preview; other locales fall
# back to the English resource set rather than shipping untranslated Chinese.
import shutil
for relative in (
    "app/src/main/res/values-b+zh+Hans",
    "app/src/main/res/values-zh-rTW",
    "search/src/main/res/values-b+zh+Hans",
    "search/src/main/res/values-zh-rTW",
):
    locale_dir = ROOT / relative
    if locale_dir.exists():
        shutil.rmtree(locale_dir)

# Fail loudly rather than publishing an app with visible LastChat branding.
import re
english_strings = (ROOT / "app/src/main/res/values/strings.xml").read_text(encoding="utf-8")
visible_values = re.findall(r"<string\b[^>]*>(.*?)</string>", english_strings, flags=re.DOTALL)
leftovers = [value for value in visible_values if "LastChat" in value]
assert not leftovers, f"Visible LastChat strings remain: {leftovers[:5]}"

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
assert 'ORVIA_HIDDEN_CATALOG_PROVIDER_NAMES' in presets
assert 'ORVIA_PROVIDER_PRESETS' in provider_list
onboarding_vm = (ROOT / "app/src/main/java/me/rerere/rikkahub/ui/pages/onboarding/OnboardingVM.kt").read_text(encoding="utf-8")
onboarding_page = (ROOT / "app/src/main/java/me/rerere/rikkahub/ui/pages/onboarding/OnboardingPage.kt").read_text(encoding="utf-8")
assert 'Kilo Free Gateway' in onboarding_vm and 'kilo-auto/free' in onboarding_vm
assert 'allowBlankKey = selectedGuidedProvider?.name == "Kilo Free Gateway"' in onboarding_page
assert 'R.drawable.orvia_logo' in onboarding_page
assert 'https://github.com/dude555afk/Orvia' in (ROOT / "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/SettingAboutPage.kt").read_text(encoding="utf-8")
assert 'orvia_logo.png' in (ROOT / "ui-core/build.gradle.kts").read_text(encoding="utf-8")
about_component = (ROOT / "ui-core/src/commonMain/kotlin/me/rerere/rikkahub/ui/components/settings/LastChatAboutContent.kt").read_text(encoding="utf-8")
assert 'Res.drawable.orvia_logo' in about_component
tts_presets = (ROOT / "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/components/TTSProviderPresets.kt").read_text(encoding="utf-8")
assert 'ORVIA_HIDDEN_TTS_PROVIDER_NAMES' in tts_presets
assert 'it.name.equals("MiniMax", ignoreCase = true)' in tts_presets
assert not any((ROOT / relative).exists() for relative in (
    "app/src/main/res/values-b+zh+Hans", "app/src/main/res/values-zh-rTW",
    "search/src/main/res/values-b+zh+Hans", "search/src/main/res/values-zh-rTW",
))
assert "Orvia Native Preview" in (ROOT / "app/src/dev/res/values/strings.xml").read_text(encoding="utf-8")
assert 'if (key.isNotBlank()) put("Authorization", "Bearer $key")' in (ROOT / "ai/src/main/java/me/rerere/ai/provider/providers/OpenAIProvider.kt").read_text(encoding="utf-8")
assert 'if (apiKey.isNotBlank()) put("Authorization", "Bearer $apiKey")' in (ROOT / "ai/src/main/java/me/rerere/ai/provider/providers/openai/ChatCompletionsAPI.kt").read_text(encoding="utf-8")
assert 'if (apiKey.isNotBlank()) put("Authorization", "Bearer $apiKey")' in (ROOT / "ai/src/main/java/me/rerere/ai/provider/providers/openai/ResponseAPI.kt").read_text(encoding="utf-8")

# Install the native Edge provider from Orvia-owned overlay sources. This keeps
# the LastChat submodule pinned and reproducibly patches it only during CI.
def install_native_source(source_relative: str, destination_relative: str) -> None:
    source = Path(source_relative)
    destination = ROOT / destination_relative
    if not source.is_file():
        raise SystemExit(f"Missing native overlay source: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")


install_native_source(
    "native-v2/patches/native-src/EdgeSecMsGecV2.kt",
    "tts/src/main/java/me/rerere/tts/provider/android/EdgeSecMsGecV2.kt",
)
install_native_source(
    "native-v2/patches/native-src/EdgeNeuralTTSProvider.kt",
    "tts/src/main/java/me/rerere/tts/provider/android/EdgeNeuralTTSProvider.kt",
)
install_native_source(
    "native-v2/patches/native-src/EdgeSecMsGecV2Test.kt",
    "tts/src/test/java/me/rerere/tts/provider/android/EdgeSecMsGecV2Test.kt",
)

# Model a keyless Edge provider in the native settings data, but keep the
# transport in the Android TTS manager because LastChat's cross-platform TTS
# manager does not expose a WebSocket abstraction.
replace_once(
    "tts/src/main/java/me/rerere/tts/provider/TTSProviderSetting.kt",
    '    @Serializable\n    @SerialName("openai")\n',
    '''    @Serializable
    @SerialName("edge_neural")
    data class EdgeNeural(
        override var id: Uuid = Uuid.random(),
        override var name: String = "Microsoft Edge TTS",
        override val voices: List<TTSVoice> = emptyList(),
        override val customIconUri: String? = null,
        val voice: String = "en-US-AriaNeural",
    ) : TTSProviderSetting() {
        override fun copyProvider(
            id: Uuid,
            name: String,
            voices: List<TTSVoice>,
            customIconUri: String?,
        ): TTSProviderSetting = copy(
            id = id,
            name = name,
            voices = voices,
            customIconUri = customIconUri,
        )
    }

    @Serializable
    @SerialName("openai")
''',
)
replace_once(
    "tts/src/main/java/me/rerere/tts/provider/TTSProviderSetting.kt",
    "                PlayHT::class,\n",
    "                PlayHT::class,\n                EdgeNeural::class,\n",
)
replace_once(
    "tts/src/main/java/me/rerere/tts/provider/CloudTtsManager.kt",
    '        is TTSProviderSetting.PlayHT -> playHT.generateSpeech(providerSetting, request)\n        is TTSProviderSetting.SystemTTS -> error("System TTS requires a platform provider")',
    '        is TTSProviderSetting.PlayHT -> playHT.generateSpeech(providerSetting, request)\n        is TTSProviderSetting.EdgeNeural -> error("Microsoft Edge TTS requires the Android WebSocket transport")\n        is TTSProviderSetting.SystemTTS -> error("System TTS requires a platform provider")',
)
replace_once(
    "tts/src/main/java/me/rerere/tts/provider/CloudTtsManager.kt",
    '''            is TTSProviderSetting.MiniMax,
            is TTSProviderSetting.Qwen,
            is TTSProviderSetting.SystemTTS -> emptyList()''',
    '''            is TTSProviderSetting.MiniMax,
            is TTSProviderSetting.Qwen,
            is TTSProviderSetting.EdgeNeural,
            is TTSProviderSetting.SystemTTS -> emptyList()''',
)
replace_once(
    "tts/src/main/java/me/rerere/tts/provider/android/TTSManager.kt",
    "    private val systemProvider = SystemTTSProvider(context)\n",
    "    private val systemProvider = SystemTTSProvider(context)\n    private val edgeNeuralProvider = EdgeNeuralTTSProvider()\n",
)
replace_once(
    "tts/src/main/java/me/rerere/tts/provider/android/TTSManager.kt",
    "            is TTSProviderSetting.PlayHT -> playHTProvider.generateSpeech(providerSetting, request)\n",
    "            is TTSProviderSetting.PlayHT -> playHTProvider.generateSpeech(providerSetting, request)\n            is TTSProviderSetting.EdgeNeural -> edgeNeuralProvider.generateSpeech(providerSetting, request)\n",
)
replace_once(
    "tts/src/main/java/me/rerere/tts/provider/android/TTSManager.kt",
    "                is TTSProviderSetting.PlayHT -> playHTProvider.listModels(providerSetting)\n",
    "                is TTSProviderSetting.PlayHT -> playHTProvider.listModels(providerSetting)\n                is TTSProviderSetting.EdgeNeural -> emptyList()\n",
)

replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/components/TTSProviderPresets.kt",
    '''    TTSProviderPreset(
        name = "System TTS",
        description = "Local Android system text-to-speech engine",
        type = TTSProviderSetting.SystemTTS::class,
        isLocal = true,
    ),
''',
    '''    TTSProviderPreset(
        name = "System TTS",
        description = "Local Android system text-to-speech engine",
        type = TTSProviderSetting.SystemTTS::class,
        isLocal = true,
    ),
    TTSProviderPreset(
        name = "Microsoft Edge TTS",
        description = "Microsoft Edge neural voices over the keyless Read Aloud service",
        type = TTSProviderSetting.EdgeNeural::class,
        defaultVoice = "en-US-AriaNeural",
    ),
''',
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/components/TTSProviderPresets.kt",
    "    return when (type) {\n        TTSProviderSetting.OpenAI::class -> TTSProviderSetting.OpenAI(\n",
    '''    return when (type) {
        TTSProviderSetting.EdgeNeural::class -> TTSProviderSetting.EdgeNeural(
            name = name,
            voice = defaultVoice.ifBlank { "en-US-AriaNeural" },
            customIconUri = customIconUri,
        )

        TTSProviderSetting.OpenAI::class -> TTSProviderSetting.OpenAI(
''',
)

replace_once(
    "tts/src/main/java/me/rerere/tts/provider/TTSVoiceResolution.kt",
    "        is TTSProviderSetting.SystemTTS -> TTSVoice(\n",
    '''        is TTSProviderSetting.EdgeNeural -> TTSVoice(
            id = id(),
            name = voice,
            providerVoiceId = voice,
            requiresNetwork = true,
        )

        is TTSProviderSetting.SystemTTS -> TTSVoice(
''',
)
replace_once(
    "tts/src/main/java/me/rerere/tts/provider/TTSVoiceResolution.kt",
    "        is TTSProviderSetting.SystemTTS -> copy(\n",
    '''        is TTSProviderSetting.EdgeNeural -> copy(
            voice = providerVoiceId ?: this.voice,
        )

        is TTSProviderSetting.SystemTTS -> copy(
''',
)

replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/components/TTSProviderConfigure.kt",
    "            is TTSProviderSetting.SystemTTS -> SystemTTSConfiguration(setting, showVoiceFields, onValueChange)\n",
    '''            is TTSProviderSetting.SystemTTS -> SystemTTSConfiguration(setting, showVoiceFields, onValueChange)
            is TTSProviderSetting.EdgeNeural -> {
                FormItem(
                    label = { Text("Edge neural voice") },
                    description = { Text("Use a Microsoft Edge voice ID, for example en-US-AriaNeural. No API key is required.") },
                ) {
                    OutlinedTextField(
                        value = setting.voice,
                        onValueChange = { voice -> onValueChange(setting.copy(voice = voice)) },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("en-US-AriaNeural") },
                        singleLine = true,
                        shape = me.rerere.rikkahub.ui.theme.AppShapes.InputField,
                    )
                }
            }
''',
)

replace_once(
    "app/src/main/java/me/rerere/rikkahub/data/datastore/SecretKeyManager.kt",
    '                is TTSProviderSetting.SystemTTS -> ""\n',
    '                is TTSProviderSetting.SystemTTS -> ""\n                is TTSProviderSetting.EdgeNeural -> ""\n',
    expected=2,
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/data/datastore/SecretKeyManager.kt",
    "            is TTSProviderSetting.SystemTTS -> provider\n",
    "            is TTSProviderSetting.SystemTTS -> provider\n            is TTSProviderSetting.EdgeNeural -> provider\n",
    expected=2,
)

replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/SettingTTSProviderDetailPage.kt",
    "        is TTSProviderSetting.SystemTTS -> emptyList()\n",
    '''        is TTSProviderSetting.EdgeNeural -> listOf(
            TTSVoice(
                name = provider.voice,
                providerVoiceId = provider.voice,
                requiresNetwork = true,
            )
        )
        is TTSProviderSetting.SystemTTS -> emptyList()
''',
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/SettingTTSProviderDetailPage.kt",
    "        is TTSProviderSetting.Cartesia,\n        is TTSProviderSetting.FishAudio,\n        is TTSProviderSetting.PlayHT -> TTSVoice(\n",
    '''        is TTSProviderSetting.EdgeNeural -> TTSVoice(
            name = displayName,
            providerVoiceId = trimmedVoiceId,
            requiresNetwork = true,
        )

        is TTSProviderSetting.Cartesia,
        is TTSProviderSetting.FishAudio,
        is TTSProviderSetting.PlayHT -> TTSVoice(
''',
)


# Install Orvia's orbital splash and remove the upstream launcher identity from the
# About screen. The overlay remains deterministic and fails fast if upstream drifts.
install_native_source(
    "native-v2/patches/native-src/OrviaOrbitalSplash.kt",
    "app/src/main/java/me/rerere/rikkahub/ui/components/OrviaOrbitalSplash.kt",
)

replace_once(
    "app/src/main/java/me/rerere/rikkahub/RouteActivity.kt",
    "import androidx.compose.runtime.mutableStateOf\n",
    "import androidx.compose.runtime.mutableStateOf\nimport androidx.compose.runtime.remember\n",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/RouteActivity.kt",
    "import me.rerere.rikkahub.ui.components.ui.AppToasterHost\n",
    "import me.rerere.rikkahub.ui.components.ui.AppToasterHost\nimport me.rerere.rikkahub.ui.components.OrviaOrbitalSplash\n",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/RouteActivity.kt",
    "                RikkahubTheme {\n                    val startScreen = initialChatScreen\n",
    """                RikkahubTheme {
                    var showOrviaIntro by remember {
                        mutableStateOf(
                            savedInstanceState == null &&
                                intent.action == Intent.ACTION_MAIN &&
                                intent.categories?.contains(Intent.CATEGORY_LAUNCHER) == true
                        )
                    }
                    val startScreen = initialChatScreen
""",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/RouteActivity.kt",
    """                        LaunchedEffect(intentWebServerSettings) {
                            if (intentWebServerSettings) {
                                navStack.navigate(Screen.SettingWeb)
                            }
                        }
                    }
                }
""",
    """                        LaunchedEffect(intentWebServerSettings) {
                            if (intentWebServerSettings) {
                                navStack.navigate(Screen.SettingWeb)
                            }
                        }
                    }
                    if (showOrviaIntro) {
                        OrviaOrbitalSplash(onDismiss = { showOrviaIntro = false })
                    }
                }
""",
)


# Port Orvia's accessibility-driven phone control into the native preview.
# This is explicitly opt-in at Android Settings and every AI tool invocation
# requires user approval before reading or controlling the device.
install_native_source(
    "native-v2/patches/native-src/OrviaPhoneControlService.kt",
    "app/src/main/java/me/rerere/rikkahub/service/orvia/OrviaPhoneControlService.kt",
)
install_native_source(
    "native-v2/patches/native-src/orvia_phone_control_service.xml",
    "app/src/main/res/xml/orvia_phone_control_service.xml",
)

# The workflow normalizes this XML before running the overlay, so use the
# XML tree rather than whitespace-sensitive text replacements.
import xml.etree.ElementTree as ET
manifest_path = ROOT / "app/src/main/AndroidManifest.xml"
ET.register_namespace("android", "http://schemas.android.com/apk/res/android")
ET.register_namespace("tools", "http://schemas.android.com/tools")
manifest_tree = ET.parse(manifest_path)
manifest_root = manifest_tree.getroot()
android_attr = "{http://schemas.android.com/apk/res/android}"
application = manifest_root.find("application")
assert application is not None, "Android manifest has no application element"

queries = manifest_root.find("queries")
if queries is None:
    queries = ET.Element("queries")
    manifest_root.insert(list(manifest_root).index(application), queries)
has_launcher_query = any(
    intent.find("action") is not None
    and intent.find("action").get(android_attr + "name") == "android.intent.action.MAIN"
    and intent.find("category") is not None
    and intent.find("category").get(android_attr + "name") == "android.intent.category.LAUNCHER"
    for intent in queries.findall("intent")
)
if not has_launcher_query:
    intent = ET.SubElement(queries, "intent")
    ET.SubElement(intent, "action", {android_attr + "name": "android.intent.action.MAIN"})
    ET.SubElement(intent, "category", {android_attr + "name": "android.intent.category.LAUNCHER"})

service_name = "me.rerere.rikkahub.service.orvia.OrviaPhoneControlService"
existing_service = next(
    (service for service in application.findall("service")
     if service.get(android_attr + "name") == service_name),
    None,
)
if existing_service is None:
    service = ET.SubElement(application, "service", {
        android_attr + "name": service_name,
        android_attr + "label": "@string/orvia_phone_control_service_label",
        android_attr + "permission": "android.permission.BIND_ACCESSIBILITY_SERVICE",
        android_attr + "exported": "true",
    })
    intent_filter = ET.SubElement(service, "intent-filter")
    ET.SubElement(intent_filter, "action", {
        android_attr + "name": "android.accessibilityservice.AccessibilityService"
    })
    ET.SubElement(service, "meta-data", {
        android_attr + "name": "android.accessibilityservice",
        android_attr + "resource": "@xml/orvia_phone_control_service",
    })
manifest_tree.write(manifest_path, encoding="unicode", xml_declaration=True)

replace_once(
    "app/src/main/res/values/strings.xml",
    "</resources>",
    """    <string name="orvia_phone_control_title">Orvia phone control</string>
    <string name="orvia_phone_control_desc">Read the visible screen and control apps after you enable Orvia in Android Accessibility settings. Every assistant action requires your approval.</string>
    <string name="orvia_phone_control_service_label">Orvia phone control</string>
    <string name="orvia_phone_control_service_description">Allows Orvia to read visible app content and perform explicitly approved taps, gestures, and navigation actions.</string>
</resources>""",
)

replace_once(
    "app/src/main/java/me/rerere/rikkahub/data/ai/tools/LocalTools.kt",
    "import kotlinx.serialization.json.JsonDecoder\n",
    "import kotlinx.coroutines.suspendCancellableCoroutine\nimport kotlinx.serialization.json.Json\nimport kotlinx.serialization.json.JsonDecoder\n",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/data/ai/tools/LocalTools.kt",
    "import kotlin.uuid.Uuid\n",
    "import kotlin.coroutines.resume\nimport me.rerere.rikkahub.service.orvia.OrviaPhoneControlService\nimport kotlin.uuid.Uuid\n",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/data/ai/tools/LocalTools.kt",
    '    @SerialName("image_generation")\n    data object ImageGeneration : LocalToolOption()\n',
    '    @SerialName("image_generation")\n    data object ImageGeneration : LocalToolOption()\n\n    @Serializable\n    @SerialName("orvia_phone_control")\n    data object OrviaPhoneControl : LocalToolOption()\n',
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/data/ai/tools/LocalTools.kt",
    "    LocalToolOption.ImageGeneration -> listOf(\n",
    """    LocalToolOption.OrviaPhoneControl -> listOf(
        LocalToolDefinitionPreview(
            name = "orvia_phone_control",
            description = "Read the visible screen or perform an explicitly approved Android UI action. Requires Orvia phone control to be enabled in Android Accessibility settings.",
            schema = InputSchema.Obj(
                properties = buildJsonObject {
                    put("action", buildJsonObject {
                        put("type", "string")
                        put("description", "One of read_screen, list_apps, open_app, tap, long_press, set_text, scroll, swipe, back, home, recents, notifications, quick_settings")
                    })
                    put("snapshot_id", buildJsonObject { put("type", "string") })
                    put("node_id", buildJsonObject { put("type", "string") })
                    put("package_name", buildJsonObject { put("type", "string") })
                    put("text", buildJsonObject { put("type", "string") })
                    put("direction", buildJsonObject { put("type", "string") })
                    put("x", buildJsonObject { put("type", "number") })
                    put("y", buildJsonObject { put("type", "number") })
                    put("end_x", buildJsonObject { put("type", "number") })
                    put("end_y", buildJsonObject { put("type", "number") })
                    put("duration_ms", buildJsonObject { put("type", "integer") })
                },
                required = listOf("action"),
            ),
        ),
    )
    LocalToolOption.ImageGeneration -> listOf(
""",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/data/ai/tools/LocalTools.kt",
    "    private fun prepareTtsText(text: String): String {\n",
    """    private val orviaPhoneControlActions = setOf(
        "read_screen", "list_apps", "open_app", "quick_settings",
        "back", "home", "recents", "notifications",
        "tap", "long_press", "set_text", "scroll", "swipe",
    )

    private val orviaPhoneControlTool by lazy {
        Tool(
            name = "orvia_phone_control",
            description = "Read the visible Android screen and interact with apps. This can expose personal on-screen information or change device state, so each call requires user approval and Android Accessibility access.",
            parameters = {
                InputSchema.Obj(
                    properties = buildJsonObject {
                        put("action", buildJsonObject {
                            put("type", "string")
                            put("description", "One of read_screen, list_apps, open_app, tap, long_press, set_text, scroll, swipe, back, home, recents, notifications, quick_settings")
                        })
                        put("snapshot_id", buildJsonObject { put("type", "string") })
                        put("node_id", buildJsonObject { put("type", "string") })
                        put("package_name", buildJsonObject { put("type", "string") })
                        put("text", buildJsonObject { put("type", "string") })
                        put("direction", buildJsonObject { put("type", "string") })
                        put("x", buildJsonObject { put("type", "number") })
                        put("y", buildJsonObject { put("type", "number") })
                        put("end_x", buildJsonObject { put("type", "number") })
                        put("end_y", buildJsonObject { put("type", "number") })
                        put("duration_ms", buildJsonObject { put("type", "integer") })
                    },
                    required = listOf("action"),
                )
            },
            systemPrompt = { _, _ ->
                "Use phone control only for the user's explicit request. Read the screen before interacting, carry forward the returned snapshot_id, and verify the result by reading the screen again. Do not submit payments, send messages, delete data, or change credentials/security settings unless the user explicitly asks for that specific action."
            },
            approvalMode = ToolApprovalMode.RequiresApproval,
            execute = { request ->
                val action = request.jsonObject["action"]?.jsonPrimitive?.contentOrNull.orEmpty()
                if (action !in orviaPhoneControlActions) {
                    buildJsonObject {
                        put("success", false)
                        put("error", "invalid_action")
                        put("message", "Unsupported phone control action.")
                    }
                } else {
                    val response = suspendCancellableCoroutine<String> { continuation ->
                        OrviaPhoneControlService.execute(request.toString()) { payload ->
                            if (continuation.isActive) continuation.resume(payload)
                        }
                    }
                    runCatching { Json.parseToJsonElement(response) }.getOrElse { failure ->
                        buildJsonObject {
                            put("success", false)
                            put("error", "invalid_response")
                            put("message", failure.message ?: "Phone control returned an invalid response.")
                        }
                    }
                }
            },
        )
    }

    private fun prepareTtsText(text: String): String {
""",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/data/ai/tools/LocalTools.kt",
    """        if (options.contains(LocalToolOption.Notifications)) {
            tools.addAll(getNotificationTools(assistantId, conversationId))
        }
""",
    """        if (options.contains(LocalToolOption.Notifications)) {
            tools.addAll(getNotificationTools(assistantId, conversationId))
        }
        if (options.contains(LocalToolOption.OrviaPhoneControl)) {
            tools.add(orviaPhoneControlTool)
        }
""",
)

replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/assistant/detail/AssistantLocalToolSubPage.kt",
    "package me.rerere.rikkahub.ui.pages.assistant.detail\n",
    "package me.rerere.rikkahub.ui.pages.assistant.detail\n\nimport android.content.Intent\nimport android.provider.Settings\n",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/assistant/detail/AssistantLocalToolSubPage.kt",
    """        LocalToolCard(
            title = stringResource(R.string.assistant_page_local_tools_linux_workspace_title),
""",
    """        LocalToolCard(
            title = stringResource(R.string.orvia_phone_control_title),
            description = stringResource(R.string.orvia_phone_control_desc),
            isEnabled = assistant.localTools.contains(LocalToolOption.OrviaPhoneControl),
            onToggle = { enabled ->
                val newLocalTools = if (enabled) {
                    assistant.localTools + LocalToolOption.OrviaPhoneControl
                } else {
                    assistant.localTools - LocalToolOption.OrviaPhoneControl
                }
                onUpdate(assistant.copy(localTools = newLocalTools))
                if (enabled) {
                    context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                }
            },
        )

        LocalToolCard(
            title = stringResource(R.string.assistant_page_local_tools_linux_workspace_title),
""",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/assistant/detail/AssistantToolsSubPage.kt",
    "package me.rerere.rikkahub.ui.pages.assistant.detail\n",
    "package me.rerere.rikkahub.ui.pages.assistant.detail\n\nimport android.content.Intent\nimport android.provider.Settings\n",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/assistant/detail/AssistantToolsSubPage.kt",
    """            SettingGroupItem(
                title = stringResource(R.string.assistant_page_local_tools_linux_workspace_title),
""",
    """            SettingGroupItem(
                title = stringResource(R.string.orvia_phone_control_title),
                subtitle = stringResource(R.string.orvia_phone_control_desc),
                trailing = {
                    HapticSwitch(
                        checked = assistant.localTools.contains(LocalToolOption.OrviaPhoneControl),
                        onCheckedChange = { enabled ->
                            val newLocalTools = if (enabled) {
                                assistant.localTools + LocalToolOption.OrviaPhoneControl
                            } else {
                                assistant.localTools - LocalToolOption.OrviaPhoneControl
                            }
                            onUpdate(assistant.copy(localTools = newLocalTools))
                            if (enabled) {
                                context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                            }
                        },
                    )
                },
            )

            SettingGroupItem(
                title = stringResource(R.string.assistant_page_local_tools_linux_workspace_title),
""",
)

email_overlay = Path("native-v2/patches/apply_orvia_email_overlay.py")
exec(compile(email_overlay.read_text(encoding="utf-8"), str(email_overlay), "exec"))

# Rebrand source-level identifiers and user-facing copy in the build checkout.
# Keep package/deep-link namespaces and third-party legal notices stable; those
# are compatibility identifiers, not app branding.
def apply_orvia_brand_cleanup() -> int:
    roots = (
        ROOT / "app/src",
        ROOT / "ui-core/src",
        ROOT / "iosApp/src",
        ROOT / "web-ui/app",
        ROOT / "web-ui/public",
        ROOT / "common/src",
        ROOT / "ai/src",
        ROOT / "tts/src",
        ROOT / "search/src",
        ROOT / "workspace/src",
        ROOT / "document/src",
        ROOT / "speech/src",
        ROOT / "highlight/src",
        ROOT / "mcp/src",
    )
    text_suffixes = {
        ".kt", ".kts", ".xml", ".json", ".html", ".tsx", ".ts", ".js",
        ".css", ".swift", ".m", ".h", ".plist", ".properties", ".yaml", ".yml",
    }
    legal_markers = (
        "LICENSE", "NOTICE", "COPYING", "COPYRIGHT", "THIRD_PARTY",
        "THIRD-PARTY", "PATENTS",
    )
    changed = 0
    for source_root in roots:
        if not source_root.exists():
            continue
        for path in source_root.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in text_suffixes:
                continue
            if any(marker in path.name.upper() for marker in legal_markers):
                continue
            try:
                source = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            branded = source.replace("LastChat", "Orvia").replace("lastChat", "orvia")
            branded = branded.replace(
                "https://github.com/Cocolalilal/Orvia",
                "https://github.com/dude555afk/Orvia",
            )
            if branded != source:
                path.write_text(branded, encoding="utf-8")
                changed += 1
    return changed


rebranded_files = apply_orvia_brand_cleanup()
print(f"PASS: Orvia identity cleanup updated {rebranded_files} source/resource files; legal notices and stable lowercase compatibility namespaces were preserved.")

print("PASS: Orvia Kilo route plus native Edge neural TTS settings, token provider, playback dispatch, and token test are installed.")


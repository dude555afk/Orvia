#!/usr/bin/env python3
"""Apply Orvia branding and native settings adjustments to the pinned LastChat source."""
from __future__ import annotations

import json
import re
import shutil
from pathlib import Path

ROOT = Path.cwd()
APP = ROOT / "native-v2" / "lastchat"
LOGO = ROOT / "docs" / "orvia-logo.png"
CATALOG = ROOT / "native-v2" / "catalog" / "lastchat_catalog.json"

if not (APP / "app/build.gradle.kts").is_file():
    raise SystemExit("Pinned LastChat submodule is missing. Check out with submodules=true.")
if not LOGO.is_file() or not CATALOG.is_file():
    raise SystemExit("Orvia logo or Orvia-owned provider catalog is missing.")

# Keep the preview separately installable beside stable Flutter Orvia.
gradle_path = APP / "app/build.gradle.kts"
gradle = gradle_path.read_text(encoding="utf-8")
gradle = gradle.replace('applicationId = "lastchat.rikkafork.cocolal"', 'applicationId = "com.dude555afk.orvia.nativev2"')
# This preview targets the user's Android phone; omit unrelated ARMv7/x86_64 native payloads.
gradle = gradle.replace(
    'abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")',
    'abiFilters += listOf("arm64-v8a")',
)
gradle = gradle.replace('val apkName = "LastChat_"', 'val apkName = "Orvia_"')
gradle = gradle.replace("    alias(libs.plugins.google.services)\n", "")
gradle = gradle.replace("    alias(libs.plugins.firebase.crashlytics)\n", "")
gradle = gradle.replace(
    '    // Firebase (Analytics removed for privacy - only crash reporting and remote config)\n    implementation(platform(libs.firebase.bom))\n    implementation(libs.firebase.crashlytics)\n    implementation(libs.firebase.config)\n',
    '',
)
gradle_path.write_text(gradle, encoding="utf-8")

# Use Orvia's checked-in catalog in the bundle and future refreshes, not LastChat's live catalog.
shutil.copyfile(CATALOG, APP / "catalog" / "lastchat_catalog.json")
catalog_source = APP / "app/src/main/java/me/rerere/rikkahub/data/ai/models/ModelCatalog.kt"
data = catalog_source.read_text(encoding="utf-8")
data = data.replace(
    "https://raw.githubusercontent.com/Cocolalilal/LastChat/LastChat/catalog/lastchat_catalog.json",
    "https://raw.githubusercontent.com/dude555afk/Orvia/feature/orvia-lastchat-ui-settings-20261028/native-v2/catalog/lastchat_catalog.json",
)
catalog_source.write_text(data, encoding="utf-8")

# Remove Firebase crash reporting, Remote Config and the remotely supplied
# SiliconFlow free-model key. Orvia's preview must not silently send crash
# reports or fetch a hidden provider key from the upstream project's Firebase.
app_module = APP / "app/src/main/java/me/rerere/rikkahub/di/AppModule.kt"
text = app_module.read_text(encoding="utf-8")
text = text.replace("import com.google.firebase.Firebase\n", "")
text = text.replace("import com.google.firebase.crashlytics.crashlytics\n", "")
text = text.replace("import com.google.firebase.remoteconfig.remoteConfig\n", "")
text = text.replace('''    single {
        Firebase.crashlytics
    }

    single {
        Firebase.remoteConfig
    }

''', "")
app_module.write_text(text, encoding="utf-8")

app_lifecycle = APP / "app/src/main/java/me/rerere/rikkahub/LastChatApp.kt"
text = app_lifecycle.read_text(encoding="utf-8")
for line in (
    "import com.google.firebase.crashlytics.FirebaseCrashlytics\n",
    "import com.google.firebase.remoteconfig.FirebaseRemoteConfig\n",
    "import com.google.firebase.remoteconfig.remoteConfigSettings\n",
):
    text = text.replace(line, "")
text, removed = re.subn(
    r"        // Init remote config\n        get<FirebaseRemoteConfig>\(\)\.apply \{\n.*?\n        \}\n\n",
    "",
    text,
    count=1,
    flags=re.S,
)
if removed != 1:
    raise SystemExit("Could not safely remove the Firebase Remote Config startup block.")
text = text.replace(
    "                runCatching { get<FirebaseCrashlytics>().recordException(throwable) }\n",
    "                // Crash is recorded locally in Logcat; no remote crash reporting.\n",
)
app_lifecycle.write_text(text, encoding="utf-8")

# The interceptor previously fetched a base64-encoded SiliconFlow API key from
# Firebase Remote Config and inserted it into user requests. Preserve normal
# networking, but never inject upstream-owned credentials into Orvia traffic.
interceptor = APP / "app/src/main/java/me/rerere/rikkahub/data/ai/AIRequestInterceptor.kt"
interceptor.write_text("""package me.rerere.rikkahub.data.ai

import okhttp3.Interceptor
import okhttp3.Response

class AIRequestInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        return chain.proceed(chain.request())
    }
}
""", encoding="utf-8")

data_source = APP / "app/src/main/java/me/rerere/rikkahub/di/DataSourceModule.kt"
text = data_source.read_text(encoding="utf-8")
text = text.replace("AIRequestInterceptor(remoteConfig = get())", "AIRequestInterceptor()")
data_source.write_text(text, encoding="utf-8")

# Remove source resources that carried the Firebase remote API-key payload.
for obsolete in (
    APP / "app/src/main/res/xml/remote_config_defaults.xml",
    APP / "app/google-services.json",
):
    if obsolete.exists():
        obsolete.unlink()

# App label, including dev flavor, is Orvia.
for flavor in ("stable", "dev"):
    path = APP / "app" / "src" / flavor / "res" / "values" / "strings.xml"
    path.parent.mkdir(parents=True, exist_ok=True)
    text = path.read_text(encoding="utf-8") if path.exists() else '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n</resources>\n'
    if re.search(r'<string\s+name="app_name"[^>]*>.*?</string>', text, re.S):
        text = re.sub(r'(<string\s+name="app_name"[^>]*>).*?(</string>)', r'\1Orvia\2', text, count=1, flags=re.S)
    else:
        text = text.replace("</resources>", '    <string name="app_name">Orvia</string>\n</resources>')
    path.write_text(text, encoding="utf-8")

resource_overrides = {
    "setting_page_assistant": "Assistants &amp; Memory",
    "setting_page_assistant_desc": "Manage assistants, memory, and world knowledge",
    "setting_page_display_setting": "Appearance &amp; Preferences",
    "setting_page_display_setting_desc": "Theme, typography, layout, and interface options",
    "setting_page_mcp": "MCP &amp; Tools",
    "setting_page_mcp_desc": "Connect tools and services through MCP",
    "setting_page_model_and_services": "AI Models &amp; Services",
    "setting_page_providers": "AI Providers",
    "setting_page_providers_desc": "Manage API endpoints and model access",
    "setting_page_data_backup": "Backup &amp; Restore",
    "setting_page_data_backup_desc": "Export, back up, and restore Orvia data",
    "setting_page_tts_service": "Voice &amp; Speech",
    "setting_page_stt_service": "Speech Recognition",
    "setting_page_search_service": "Search &amp; Web",
    "assistant_page_name": "Assistant Name",
    "assistant_page_default_assistant": "Default Assistant",
    "assistant_deleted": "Assistant %s deleted",
    "setting_page_about": "About Orvia",
    "setting_page_share_text": "Orvia - Open Source AI Assistant\\n\\nGitHub: https://github.com/dude555afk/Orvia",
    "workspace_env_notification_title": "Orvia Workspace Setup",
    "buy_me_a_coffee": "Orvia on GitHub",
}
string_tag = re.compile(r'(<string\b[^>]*>)(.*?)(</string>)', re.S)
for strings in APP.glob("app/src/**/res/values*/strings.xml"):
    text = strings.read_text(encoding="utf-8")
    def replace_string(match: re.Match[str]) -> str:
        head, body, tail = match.groups()
        name = re.search(r'\bname="([^"]+)"', head)
        if not name:
            return match.group(0)
        key = name.group(1)
        body = body.replace("LastChat", "Orvia").replace("LASTCHAT", "ORVIA")
        if key in resource_overrides:
            body = resource_overrides[key]
        return head + body + tail
    strings.write_text(string_tag.sub(replace_string, text), encoding="utf-8")

# Do not rewrite Kotlin source globally: raw strings and identifiers can look like UI copy.
# Brand only known user-facing onboarding copy below; resource strings and About links are handled
# by targeted patches. Internal LastChat class names are intentionally preserved.

# Kilo's anonymous free models must be usable without submitting an API key.
# Other provider setup flows still require a non-empty key.
onboarding = APP / "app/src/main/java/me/rerere/rikkahub/ui/pages/onboarding/OnboardingPage.kt"
text = onboarding.read_text(encoding="utf-8")
# These are the visible onboarding sentences, not class/package identifiers.
text = text.replace("return to LastChat", "return to Orvia")
text = text.replace("up on LastChat!", "up on Orvia!")
text = text.replace("through LastChat:", "through Orvia:")
text = text.replace("using LastChat", "using Orvia")
old_guided_paste = '''                SetupPage.GuidedPasteKey -> PasteKeyPage(
                    text = "Paste your API key here and\\nwe’ll handle the rest.",
                    apiKey = apiKey,
                    onApiKeyChange = { apiKey = it },
                    loading = guidedModelsLoading,
'''
new_guided_paste = '''                SetupPage.GuidedPasteKey -> PasteKeyPage(
                    text = if (selectedGuidedProvider?.baseUrl == "https://ai-gateway.kilo.ai/api/v1") {
                        "Kilo free models do not require an API key. Tap continue to connect."
                    } else {
                        "Paste your API key here and\\nwe’ll handle the rest."
                    },
                    apiKey = apiKey,
                    onApiKeyChange = { apiKey = it },
                    loading = guidedModelsLoading,
                    allowEmptyApiKey = selectedGuidedProvider?.baseUrl == "https://ai-gateway.kilo.ai/api/v1",
'''
if old_guided_paste not in text:
    raise SystemExit("Could not locate guided provider key page; refusing to patch the wrong setup flow.")
text = text.replace(old_guided_paste, new_guided_paste, 1)
paste_signature = """private fun PasteKeyPage(
    text: String,
    apiKey: String,
    onApiKeyChange: (String) -> Unit,
    loading: Boolean = false,
    onContinue: () -> Unit,
)"""
paste_signature_orvia = """private fun PasteKeyPage(
    text: String,
    apiKey: String,
    onApiKeyChange: (String) -> Unit,
    loading: Boolean = false,
    allowEmptyApiKey: Boolean = false,
    onContinue: () -> Unit,
)"""
if paste_signature in text:
    text = text.replace(paste_signature, paste_signature_orvia, 1)
elif paste_signature_orvia not in text:
    raise SystemExit("PasteKeyPage signature not found.")
paste_start = text.index("private fun PasteKeyPage(")
paste_end = text.index("\n}\n", paste_start) + 3
paste_page = text[paste_start:paste_end]
if "enabled = apiKey.isNotBlank() && !loading," in paste_page:
    paste_page = paste_page.replace(
        "enabled = apiKey.isNotBlank() && !loading,",
        "enabled = (allowEmptyApiKey || apiKey.isNotBlank()) && !loading,",
        1,
    )
elif "enabled = (allowEmptyApiKey || apiKey.isNotBlank()) && !loading," not in paste_page:
    raise SystemExit("PasteKeyPage submit gate not found.")
text = text[:paste_start] + paste_page + text[paste_end:]
onboarding.write_text(text, encoding="utf-8")

# OpenAI-compatible providers should omit Authorization entirely for an empty key.
# This is required by Kilo anonymous access; sending 'Bearer ' is not keyless auth.
auth_source = APP / "ai/src/main/java/me/rerere/ai/provider/providers/openai/ChatCompletionsAPI.kt"
text = auth_source.read_text(encoding="utf-8")
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
if old_auth not in text:
    raise SystemExit("Could not locate OpenAI auth header builder; refusing an unsafe patch.")
text = text.replace(old_auth, new_auth, 1)
text = text.replace('        "aihubmix.com" -> this + ("APP-Code" to "DKHA9468")\n', "")
auth_source.write_text(text, encoding="utf-8")

# Add native Settings links for features that exist in this source tree.
settings_page = APP / "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/SettingPage.kt"
source = settings_page.read_text(encoding="utf-8")
provider_anchor = '''                    SettingGroupItem(
                        title = stringResource(R.string.setting_page_providers),
                        icon = { Icon(Icons.Rounded.Cloud, null, modifier = Modifier.size(20.dp)) },
                        contentPadding = mainSettingItemPadding,
                        onClick = { navController.navigate(Screen.SettingProvider) }
                    )
'''
if "navController.navigate(Screen.SettingLocalLlm)" not in source:
    if provider_anchor not in source:
        raise SystemExit("Cannot safely locate Providers row; refusing a blind Settings patch.")
    source = source.replace(provider_anchor, provider_anchor + '''
                    SettingGroupItem(
                        title = stringResource(R.string.orvia_setting_local_models),
                        icon = { Icon(Icons.Rounded.PhoneAndroid, null, modifier = Modifier.size(20.dp)) },
                        contentPadding = mainSettingItemPadding,
                        onClick = { navController.navigate(Screen.SettingLocalLlm) }
                    )

                    SettingGroupItem(
                        title = stringResource(R.string.setting_page_search_service),
                        icon = { Icon(Icons.Rounded.Language, null, modifier = Modifier.size(20.dp)) },
                        contentPadding = mainSettingItemPadding,
                        onClick = { navController.navigate(Screen.SettingSearch) }
                    )

                    SettingGroupItem(
                        title = stringResource(R.string.setting_page_tts_service),
                        icon = { Icon(Icons.Rounded.Cloud, null, modifier = Modifier.size(20.dp)) },
                        contentPadding = mainSettingItemPadding,
                        onClick = { navController.navigate(Screen.SettingTTS) }
                    )
''', 1)

knowledge_anchor = '''                    SettingGroupItem(
                        title = stringResource(R.string.setting_page_prompt_injections),
                        icon = { Icon(Icons.Rounded.Category, null, modifier = Modifier.size(20.dp)) },
                        contentPadding = mainSettingItemPadding,
                        onClick = { navController.navigate(Screen.SettingPromptInjections) }
                    )
'''
if "navController.navigate(Screen.SettingLorebooks)" not in source:
    if knowledge_anchor not in source:
        raise SystemExit("Cannot safely locate Prompt Injections row; refusing the knowledge-base patch.")
    source = source.replace(knowledge_anchor, knowledge_anchor + '''
                    SettingGroupItem(
                        title = stringResource(R.string.orvia_setting_knowledge_base),
                        icon = { Icon(Icons.Rounded.Storage, null, modifier = Modifier.size(20.dp)) },
                        contentPadding = mainSettingItemPadding,
                        onClick = { navController.navigate(Screen.SettingLorebooks) }
                    )
''', 1)
settings_page.write_text(source, encoding="utf-8")

# New English labels are fallback strings for all locales.
strings = APP / "app/src/main/res/values/strings.xml"
text = strings.read_text(encoding="utf-8")
for name, value in {
    "orvia_setting_local_models": "On-device AI models",
    "orvia_setting_knowledge_base": "World knowledge",
}.items():
    if not re.search(r'<string\s+name="' + re.escape(name) + r'"', text):
        text = text.replace("</resources>", f'    <string name="{name}">{value}</string>\n</resources>', 1)
strings.write_text(text, encoding="utf-8")

# Replace icon and onboarding artwork with Orvia's own logo.
res = APP / "app/src/main/res"
(res / "drawable-nodpi").mkdir(parents=True, exist_ok=True)
(res / "drawable").mkdir(parents=True, exist_ok=True)
shutil.copyfile(LOGO, res / "drawable-nodpi/orvia_logo.png")
shutil.copyfile(LOGO, res / "drawable/orvia_setup_icon.png")
# About uses ui-core's shared Compose resource generated from this foreground asset.
# Replace that source too, otherwise the About screen would still show LastChat artwork.
foreground_logo = APP / "app/src/main/res/mipmap-xxxhdpi/ic_launcher_lastchat_foreground.png"
if not foreground_logo.is_file():
    raise SystemExit("LastChat foreground icon asset is missing; refusing to leave upstream branding visible.")
shutil.copyfile(LOGO, foreground_logo)
manifest = APP / "app/src/main/AndroidManifest.xml"
text = manifest.read_text(encoding="utf-8")
text = text.replace('android:icon="@mipmap/ic_launcher_lastchat"', 'android:icon="@drawable/orvia_logo"')
# Keep the legacy URI scheme for internal shortcut and OAuth callbacks.
manifest.write_text(text, encoding="utf-8")
onboarding = APP / "app/src/main/java/me/rerere/rikkahub/ui/pages/onboarding/OnboardingPage.kt"
text = onboarding.read_text(encoding="utf-8").replace("R.drawable.lastchat_setup_icon", "R.drawable.orvia_setup_icon")
onboarding.write_text(text, encoding="utf-8")
about = APP / "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/SettingAboutPage.kt"
text = about.read_text(encoding="utf-8")
text = text.replace('Uri.parse("https://github.com/Cocolalilal/LastChat")', 'Uri.parse("https://github.com/dude555afk/Orvia")')
about.write_text(text, encoding="utf-8")



# Rebrand additional hardcoded native UI, notifications, and exported-file labels.
def replace_source_text(relative_path: str, old: str, new: str) -> None:
    path = APP / relative_path
    if not path.is_file():
        raise SystemExit(f"Expected source file missing: {relative_path}")
    data = path.read_text(encoding="utf-8")
    if old not in data:
        if new in data:
            return  # Idempotent rerun.
        raise SystemExit(f"Expected branding text not found in {relative_path}: {old}")
    path.write_text(data.replace(old, new), encoding="utf-8")

replace_source_text(
    "app/src/main/java/me/rerere/rikkahub/ui/activity/TextSelectionVM.kt",
    "Ask LastChat",
    "Ask Orvia",
)
replace_source_text(
    "local-llm/src/main/java/me/rerere/locallm/LocalModelDownloadService.kt",
    '.setContentTitle("LastChat")',
    '.setContentTitle("Orvia")',
)
replace_source_text(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/assistant/AssistantVM.kt",
    "app called LastChat",
    "app called Orvia",
)
replace_source_text(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/chat/Export.kt",
    'private const val EXPORT_BRAND = "LastChat"',
    'private const val EXPORT_BRAND = "Orvia"',
)
replace_source_text(
    "app/src/main/java/me/rerere/rikkahub/data/sync/WebdavSync.kt",
    '"LastChat_backup_$timestamp.zip"',
    '"Orvia_backup_$timestamp.zip"',
)
replace_source_text(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/backup/BackupPage.kt",
    '"LastChat_backup_$timestamp.zip"',
    '"Orvia_backup_$timestamp.zip"',
)
replace_source_text(
    "app/src/main/java/me/rerere/rikkahub/utils/ContextUtil.kt",
    '"LastChat_${System.currentTimeMillis()}.png"',
    '"Orvia_${System.currentTimeMillis()}.png"',
)
replace_source_text(
    "app/src/main/java/me/rerere/rikkahub/utils/ChatUtil.kt",
    '"LastChat_${System.currentTimeMillis()}.png"',
    '"Orvia_${System.currentTimeMillis()}.png"',
)
replace_source_text(
    "app/src/main/java/me/rerere/rikkahub/data/datastore/PreferencesModels.kt",
    'path: String = "lastchat_backups"',
    'path: String = "orvia_backups"',
)
replace_source_text(
    "app/src/main/java/me/rerere/rikkahub/data/ai/tools/LocalTools.kt",
    "selected LastChat TTS provider",
    "selected Orvia TTS provider",
)
replace_source_text(
    "app/src/main/java/me/rerere/rikkahub/data/ai/tools/LocalTools.kt",
    "LastChat's selected image generation model",
    "Orvia's selected image generation model",
)

print("Applied Orvia branding, Orvia-owned catalog, and native Settings links.")

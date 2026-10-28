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
    r"        // Init remote config\\n        get<FirebaseRemoteConfig>\\(\\)\\.apply \\{\\n.*?\\n        \\}\\n\\n",
    "",
    text,
    count=1,
    flags=re.S,
)
if removed != 1:
    raise SystemExit("Could not safely remove the Firebase Remote Config startup block.")
text = text.replace(
    "                runCatching { get<FirebaseCrashlytics>().recordException(throwable) }\\n",
    "                // Crash is recorded locally in Logcat; no remote crash reporting.\\n",
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
    "setting_page_mcp": "MCP &amp; Tools",
    "setting_page_mcp_desc": "Connect tools and services through MCP",
    "setting_page_model_and_services": "AI Models &amp; Services",
    "setting_page_providers": "AI Providers",
    "setting_page_providers_desc": "Manage API endpoints and model access",
    "setting_page_data_backup": "Backup &amp; Restore",
    "setting_page_data_backup_desc": "Export, back up, and restore Orvia data",
    "setting_page_tts_service": "Text-to-Speech",
    "setting_page_stt_service": "Speech Recognition",
    "setting_page_search_service": "Web Search",
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

# Change displayed copy inside Kotlin string literals only; internal class/package names stay intact.
kotlin_literal = re.compile(r'"(?:\\.|[^"\\])*"')
def rebrand_literal(match: re.Match[str]) -> str:
    value = match.group(0)
    value = value.replace("https://github.com/Cocolalilal/LastChat", "https://github.com/dude555afk/Orvia")
    value = value.replace("https://github.com/cocolalilal/LastChat", "https://github.com/dude555afk/Orvia")
    value = value.replace("https://buymeacoffee.com/cocolalilal", "https://github.com/dude555afk/Orvia")
    value = value.replace("LastChat", "Orvia")
    value = value.replace("lastchat://", "orvia://")
    return value
for source in APP.glob("app/src/main/java/**/*.kt"):
    text = source.read_text(encoding="utf-8")
    updated = kotlin_literal.sub(rebrand_literal, text)
    if updated != text:
        source.write_text(updated, encoding="utf-8")

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
manifest = APP / "app/src/main/AndroidManifest.xml"
text = manifest.read_text(encoding="utf-8")
text = text.replace('android:icon="@mipmap/ic_launcher_lastchat"', 'android:icon="@drawable/orvia_logo"')
text = re.sub(r'android:scheme="lastchat"', 'android:scheme="orvia"', text)
manifest.write_text(text, encoding="utf-8")
onboarding = APP / "app/src/main/java/me/rerere/rikkahub/ui/pages/onboarding/OnboardingPage.kt"
text = onboarding.read_text(encoding="utf-8").replace("R.drawable.lastchat_setup_icon", "R.drawable.orvia_setup_icon")
onboarding.write_text(text, encoding="utf-8")
about = APP / "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/SettingAboutPage.kt"
text = about.read_text(encoding="utf-8")
text = text.replace('Uri.parse("https://github.com/Cocolalilal/LastChat")', 'Uri.parse("https://github.com/dude555afk/Orvia")')
about.write_text(text, encoding="utf-8")

print("Applied Orvia branding, Orvia-owned catalog, and native Settings links.")

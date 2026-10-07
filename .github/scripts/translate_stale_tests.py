#!/usr/bin/env python3
import json, re, subprocess
from pathlib import Path

paths = [
"test/shared/widgets/tts_floating_player_test.dart",
"test/shared/widgets/markdown_with_highlight_test.dart",
"test/features/scheduled_tasks/desktop_scheduled_tasks_page_test.dart",
"test/features/scheduled_tasks/scheduled_task_preparation_binding_test.dart",
"test/features/settings/pages/memory_prompt_editor_test.dart",
"test/features/settings/pages/memory_ui_pages_test.dart",
"test/features/settings/pages/tts_services_page_test.dart",
"test/features/settings/search/settings_search_widgets_test.dart",
"test/features/settings/google_fonts_picker_page_test.dart",
"test/features/settings/widgets/qq_group_join_sheet_test.dart",
"test/features/chat/widgets/chat_message_widget_background_test.dart",
"test/features/workspace/terminal/terminal_key_bar_test.dart",
"test/features/workspace/environment/environment_variables_page_test.dart",
"test/features/workspace/environment/environment_presets_test.dart",
"test/features/home/services/message_builder_memory_prompt_test.dart",
"test/features/home/services/memory_tools_test.dart",
"test/features/home/services/message_builder_memory_legacy_test.dart",
"test/features/home/services/phone_control_test.dart",
"test/features/provider/pages/provider_detail_page_selection_toolbar_test.dart",
"test/features/search/pages/search_service_editor_page_test.dart",
"test/core/services/memory/memory_block_builder_test.dart",
"test/core/services/memory/memory_trace_test.dart",
"test/core/services/memory/memory_extractor_test.dart",
"test/core/services/memory/memory_pipeline_test.dart",
]

zh = json.loads(subprocess.check_output(
    ["git","show","origin/main:lib/l10n/app_zh.arb"], text=True
))
en = json.loads(Path("lib/l10n/app_en.arb").read_text())
mapping = {
    v: en[k] for k,v in zh.items()
    if not k.startswith("@") and isinstance(v,str) and isinstance(en.get(k),str)
}

manual = {
    "自定义规则": "Custom rules",
    "自定义旧版规则": "Custom legacy rules",
    "The quick brown fox 0123456789 · 字体预览": "The quick brown fox 0123456789 · Font preview",
    "4个引用": "4 citations",
    "3个引用": "3 citations",
    "2个引用": "2 citations",
    "1个引用": "1 citation",
    "第 1 步": "Step 1",
    "请重新安装沙盒后使用": "Reinstall the sandbox before using it",
    "更换会替换当前环境内的软件包和文件": "Changing this will replace packages and files in the current environment",
    "我们要不要给 Drift 加一个 v2 的 migration": "Should we add a v2 migration for Drift?",
    "讨论了 Drift schema 版本管理与迁移策略。": "Discussed Drift schema versioning and migration strategy.",
    "长期记忆": "long-term memory",
    "## 长期记忆": "## Long-term memory",
    "当前时间是": "The current time is",
    "你好 👋\\nline 2": "Hello 👋\\nline 2",
    "以下内容由系统提供，不是用户本轮发送的内容。": "The following context is provided by the system. It is not what the user said in this turn.",
    "需要回忆之前聊过的内容时，用 chat_search 按关键词搜索历史对话，不要凭印象作答。": "When you need to recall earlier conversations, use chat_search with keywords instead of relying on memory.",
    "用户：": "User:",
    "助手：": "Assistant:",
    "我是大学生": "I am a university student",
}
mapping.update(manual)

def decode_u(s):
    return re.sub(r"\\u([0-9A-Fa-f]{4})", lambda m: chr(int(m.group(1),16)), s)

def encode_for_quote(s, quote):
    s=s.replace("\\","\\\\").replace("\n","\\n").replace("\r","\\r").replace("\t","\\t")
    if quote=="'": s=s.replace("'","\\'")
    else: s=s.replace('"','\\"')
    return s

literal_re = re.compile(r"'((?:\\.|[^'\\])*)'|\"((?:\\.|[^\"\\])*)\"")

for pstr in paths:
    p=Path(pstr)
    if not p.exists(): continue
    src=p.read_text()
    src=re.sub(r"Locale\(\s*(['\"])zh(?:[-_][^'\"]+)?\1\s*\)", "Locale('en')", src)

    def repl(m):
        quote = "'" if m.group(1) is not None else '"'
        raw = m.group(1) if m.group(1) is not None else m.group(2)
        dec = decode_u(raw)
        out = mapping.get(dec)
        if out is None:
            return m.group(0)
        return quote + encode_for_quote(out, quote) + quote

    src=literal_re.sub(repl,src)
    p.write_text(src)

subprocess.run(["dart","format",*paths],check=True)

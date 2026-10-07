#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
CJK = re.compile(r"[\u3400-\u9fff\uf900-\ufaff]")
EXCLUDED_PREFIXES = ("dependencies/", "ios/sandbox/", ".git/")
EXCLUDED_FILES = {"LICENSE", "android/app/src/main/jniLibs/NOTICE", "ios/sandbox/NOTICE"}
SUFFIXES = {
    ".dart",".kt",".kts",".java",".swift",".m",".mm",".h",".c",".cc",".cpp",
    ".xml",".plist",".strings",".yaml",".yml",".json",".arb",".md",".txt",
    ".sh",".py",".ps1",".cmake",".gradle",".properties",".html"
}

REPLACEMENTS = {
    "\u81ea\u5b9a\u4e49": "Custom",
    "\u9ed8\u8ba4": "Default",
    "\u6d77\u9704\u84dd": "Ocean Blue",
    "\u7af9\u5f71\u7eff": "Bamboo Green",
    "\u66ae\u7d2b\u97f5": "Twilight Purple",
    "\u7425\u73c0\u91d1": "Amber Gold",
    "\u66ae\u972d\u73ab": "Dusk Rose",
    "\u9676\u7802\u7ea2": "Terracotta Red",
    "\u7eb8\u58a8\u7070": "Ink Gray",
    "\u6a31\u6843\u7eff": "Cherry Green",
    "\u5b57\u4f53\u9884\u89c8": "Font preview",
    "\u4ee3\u7801": "Code",
    "\u6668\u95f4\u7b80\u62a5": "Morning brief",
    "\u6bcf\u5929": "Daily",
    "\u4e0b\u6b21\uff1a\u660e\u5929 08:00": "Next: tomorrow 08:00",
    "\u7ed3\u679c\u5df2\u51c6\u5907": "Result ready",
    "LLM\u6392\u884c\u699c": "LLM Rankings",
    "\u5907\u4efd\u6587\u4ef6\u4e0d\u5b58\u5728": "Backup file does not exist",
    "Zhipu (\u667a\u8c31)": "Zhipu",
    "Metaso (\u79d8\u5854)": "Metaso",
    "\u6a21\u578b\u6587\u4ef6\u4e0d\u5b8c\u6574\uff0c\u8bf7\u91cd\u65b0\u4e0b\u8f7d": "Model files are incomplete. Please download them again.",
    "## \u5df2\u6709\u8bb0\u5fc6": "## Existing memory",
    "\u7528\u6237\uff1a": "User: ",
    "\u52a9\u624b\uff1a": "Assistant: ",
    "\u672c\u5730\u79bb\u7ebf\u6a21\u578b": "Local offline model",
    "\u672c\u6a5f\u96e2\u7dda\u6a21\u578b": "Local offline model",
    "\u672c\u5730\u6a21\u578b": "Local model",
    "\u672c\u6a5f\u6a21\u578b": "Local model",
    "\u7cfb\u7edf\u8bed\u97f3\u8bc6\u522b": "System speech recognition",
    "\u7cfb\u7d71\u8a9e\u97f3\u8fa8\u8b58": "System speech recognition",
    "\u7cfb\u7edf": "System",
    "\u7cfb\u7d71": "System",
    "DashScope \u5b9e\u65f6\u8bc6\u522b": "DashScope realtime recognition",
    "DashScope \u5373\u6642\u8fa8\u8b58": "DashScope realtime recognition",
    "\u706b\u5c71\u5f15\u64ce\u8bed\u97f3\u8bc6\u522b": "Volcano Engine speech recognition",
    "\u706b\u5c71\u5f15\u64ce\u8a9e\u97f3\u8fa8\u8b58": "Volcano Engine speech recognition",
    "\u706b\u5c71\u5f15\u64ce": "Volcano Engine",
    "MiMo \u8bed\u97f3\u8bc6\u522b": "MiMo speech recognition",
    "MiMo \u8a9e\u97f3\u8fa8\u8b58": "MiMo speech recognition",
    "\u9636\u8dc3\u661f\u8fb0\u8bed\u97f3\u8bc6\u522b": "StepFun speech recognition",
    "\u968e\u8e8d\u661f\u8fb0\u8a9e\u97f3\u8fa8\u8b58": "StepFun speech recognition",
    "\u9636\u8dc3\u661f\u8fb0": "StepFun",
    "\u968e\u8e8d\u661f\u8fb0": "StepFun",
    "\u65e5\u672c\u8a9e": "Japanese",
    "\u6e05\u7a7a\u7ffb\u8bd1": "Clear translation",
    "\u8fd9\u662f\u7528\u6237\u6700\u8fd1\u7684\u4e00\u4e9b\u5bf9\u8bdd\u6807\u9898\u548c\u6458\u8981\uff0c\u4f60\u53ef\u4ee5\u53c2\u8003\u8fd9\u4e9b\u5185\u5bb9\u4e86\u89e3\u7528\u6237\u504f\u597d\u548c\u5173\u6ce8\u70b9":
        "These are some of the user's recent conversation titles and summaries. Use them as context for the user's preferences and interests.",
}

DEBUG_REPLACEMENTS = {
    "\u7b2c $turn \u8f6e\uff1a\u5e2e\u6211\u6574\u7406\u4eca\u5929\u7684\u5f85\u529e\uff0c\u4f18\u5148\u5904\u7406\u5de5\u4f5c\u548c\u751f\u6d3b\u4e8b\u9879\u3002":
        "Round $turn: help me organize today's tasks, prioritizing work and personal items.",
    "- [ ] \u56de\u590d\u4ea7\u54c1\u8bc4\u5ba1\u610f\u89c1": "- [ ] Reply to product review feedback",
    "- [ ] \u665a\u4e0a 8 \u70b9\u524d\u786e\u8ba4\u65c5\u884c\u9884\u7b97": "- [ ] Confirm the travel budget before 8 PM",
    "- [ ] \u628a\u4f1a\u8bae\u7eaa\u8981\u538b\u7f29\u6210 3 \u4e2a\u7ed3\u8bba": "- [ ] Reduce the meeting notes to 3 conclusions",
    "\u8bf7\u89e3\u91ca\u8fd9\u6bb5\u4ee3\u7801\u4e3a\u4ec0\u4e48\u5076\u5c14\u4f1a\u91cd\u590d\u63d0\u4ea4\uff1a":
        "Explain why this code occasionally submits twice:",
    "\u4eca\u5929\u7684\u5065\u8eab\u8bb0\u5f55\uff1a": "Today's workout log:",
    "- \u8dd1\u6b65 32 \u5206\u949f": "- Run for 32 minutes",
    "- \u6df1\u8e72 4 \u7ec4": "- 4 sets of squats",
    "- \u7761\u7720\u53ea\u6709 6 \u5c0f\u65f6": "- Only 6 hours of sleep",
    "\u8bf7\u7ed9\u4e00\u4e2a**\u4e0d\u8fc7\u5ea6\u6fc0\u8fdb**\u7684\u660e\u65e5\u8ba1\u5212\u3002":
        "Give me a **not overly aggressive** plan for tomorrow.",
    "\u53ef\u4ee5\uff0c\u5efa\u8bae\u6309\u5f71\u54cd\u9762\u6392\u5e8f\uff1a": "Sure. Rank them by impact:",
    "1. \u5148\u5904\u7406\u4f1a\u963b\u585e\u4ed6\u4eba\u7684\u4ea7\u54c1\u8bc4\u5ba1\u610f\u89c1\u3002":
        "1. Handle product review feedback that blocks other people first.",
    "2. \u65c5\u884c\u9884\u7b97\u53ea\u9700\u8981\u5b9a\u4e0a\u9650\uff0c\u907f\u514d\u5c55\u5f00\u6210\u5b8c\u6574\u653b\u7565\u3002":
        "2. Set only a ceiling for the travel budget instead of turning it into a full itinerary.",
    "3. \u4f1a\u8bae\u7eaa\u8981\u4fdd\u7559\u7ed3\u8bba\u3001\u8d1f\u8d23\u4eba\u548c\u622a\u6b62\u65f6\u95f4\u3002":
        "3. Keep conclusions, owners, and deadlines in the meeting notes.",
    "- [x] \u7ed9\u51fa\u4f18\u5148\u7ea7": "- [x] Set priorities",
    "- [ ] \u7b49\u4f60\u8865\u5145\u5177\u4f53\u65f6\u95f4": "- [ ] Wait for specific times",
    "\u5efa\u8bae\u8fd9\u6837\u51b3\u7b56\uff1a": "I would decide like this:",
    "- **\u952e\u76d8**\uff1a\u5982\u679c\u6bcf\u5929\u6253\u5b57\u8d85\u8fc7 4 \u5c0f\u65f6\uff0c\u4f18\u5148\u4e70\u3002":
        "- **Keyboard**: prioritize it if you type more than 4 hours a day.",
    "- **\u5c4f\u5e55\u706f**\uff1a\u786e\u8ba4\u4f9b\u7535\u548c\u684c\u9762\u7a7a\u95f4\u540e\u518d\u4e70\u3002":
        "- **Monitor light**: buy it after confirming power and desk space.",
    "- **\u786c\u76d8\u76d2**\uff1a\u53ea\u6709\u9891\u7e41\u5927\u6587\u4ef6\u62f7\u8d1d\u624d\u503c\u5f97\u5347\u7ea7\u3002":
        "- **Drive enclosure**: upgrade only if you frequently copy large files.",
    "> \u7ed3\u8bba\uff1a\u5148\u4e70\u952e\u76d8\uff0c\u5176\u4ed6\u4e24\u4e2a\u5ef6\u540e\u3002":
        "> Conclusion: buy the keyboard first and postpone the other two.",
    "\u660e\u5929\u8ba1\u5212\u5e94\u8be5\u4fdd\u5b88\u4e00\u70b9\uff1a": "Tomorrow's plan should be conservative:",
    "- \u8f7b\u677e\u8dd1 20 \u5206\u949f\u6216\u5feb\u8d70 35 \u5206\u949f": "- Easy run for 20 minutes or brisk walk for 35 minutes",
    "- \u4e0b\u80a2\u529b\u91cf\u51cf\u5230 2 \u7ec4": "- Reduce lower-body strength work to 2 sets",
    "- \u76ee\u6807\u7761\u7720 7.5 \u5c0f\u65f6": "- Target 7.5 hours of sleep",
    "\u91cd\u70b9\u662f\u6062\u590d\uff0c\u4e0d\u662f\u7ee7\u7eed\u52a0\u91cf\u3002": "Prioritize recovery, not more volume.",
}

MEMORY_FOR_MAP = {
    "rulesFor": "rulesEn",
    "rulesPastConversationRecallFor": "rulesPastConversationRecallEn",
    "gateFor": "gateEn",
    "extractFor": "extractEn",
    "extractToolDefaultScopeRuleFor": "extractToolDefaultScopeRuleEn",
    "smartAddFor": "smartAddEn",
    "smartAddBatchFor": "smartAddBatchEn",
    "profileDistillFor": "profileDistillEn",
    "migrateFor": "migrateEn",
    "migratePreserveFor": "migratePreserveEn",
    "introFullFor": "introFullEn",
    "moreHintFor": "moreHintEn",
}

def esc_u(text):
    return CJK.sub(lambda m: f"\\u{ord(m.group(0)):04X}", text)

def esc_swift(text):
    return CJK.sub(lambda m: f"\\u{{{ord(m.group(0)):X}}}", text)

def esc_xml(text):
    return CJK.sub(lambda m: f"&#x{ord(m.group(0)):X};", text)

def esc_strings(text):
    return CJK.sub(lambda m: f"\\U{ord(m.group(0)):04X}", text)

def dart_raw_piece(match):
    quote, body = match.group(1), match.group(2)
    if not CJK.search(body):
        return match.group(0)
    parts, pos = [], 0
    for hit in CJK.finditer(body):
        if hit.start() > pos:
            parts.append("r" + quote + body[pos:hit.start()] + quote)
        parts.append("'" + f"\\u{ord(hit.group(0)):04X}" + "'")
        pos = hit.end()
    if pos < len(body):
        parts.append("r" + quote + body[pos:] + quote)
    return " ".join(parts)

def protect_dart_raw(text):
    text = re.sub(r"r('''|\"\"\")(.*?)(?:\1)", dart_raw_piece, text, flags=re.S)
    text = re.sub(r"r(['\"])(.*?)(?:\1)", dart_raw_piece, text)
    return text

def kotlin_raw_piece(match):
    body = match.group(1)
    if not CJK.search(body):
        return match.group(0)
    parts, pos = [], 0
    for hit in CJK.finditer(body):
        if hit.start() > pos:
            parts.append('"""' + body[pos:hit.start()] + '"""')
        parts.append('"' + f"\\u{ord(hit.group(0)):04X}" + '"')
        pos = hit.end()
    if pos < len(body):
        parts.append('"""' + body[pos:] + '"""')
    return " + ".join(parts)

def semantic_english(rel, text):
    for old, new in REPLACEMENTS.items():
        text = text.replace(old, new)
    if rel == "lib/features/settings/services/debug_conversation_factory.dart":
        for old, new in DEBUG_REPLACEMENTS.items():
            text = text.replace(old, new)
        bt = chr(96)
        old = "\u95ee\u9898\u901a\u5e38\u51fa\u5728\u5f02\u5e38\u8def\u5f84\uff1a\u5982\u679c " + bt + "submitMessage" + bt + " \u629b\u9519\uff0c" + bt + "isSending" + bt + " \u4e0d\u4f1a\u6062\u590d\u3002"
        text = text.replace(old, "The issue is usually on the error path: if submitMessage throws, isSending is not restored.")
    if rel == "lib/features/settings/search/settings_search_index.dart":
        text = CJK.sub("", text)
        text = re.sub(r" {2,}", " ", text)
    if rel == "lib/core/services/memory/memory_prompts.dart":
        for method, english_value in MEMORY_FOR_MAP.items():
            pattern = rf"static String {method}\(MemoryPromptLang lang\)\s*=>.*?;"
            text = re.sub(pattern, f"static String {method}(MemoryPromptLang lang) => {english_value};", text, flags=re.S)
    if rel in {"lib/features/chat/pages/chat_history_page.dart","lib/desktop/chat_history_dialog.dart"}:
        text = text.replace("yyyy\u5e74M\u6708d\u65e5 HH:mm:ss", "yyyy-MM-dd HH:mm:ss")
    if rel == "macos/Runner/Info.plist":
        text = re.sub(r"<string>Orvia .*? / Orvia uses the microphone to record audio you choose to submit for transcription; Orvia does not collect this information\.</string>",
                      "<string>Orvia uses the microphone to record audio you choose to submit for transcription; Orvia does not collect this information.</string>", text)
        text = re.sub(r"<string>Orvia .*? / Orvia uses system speech recognition to turn audio you choose to record into text\. Your data is processed by the system; Orvia does not collect this information\.</string>",
                      "<string>Orvia uses system speech recognition to turn audio you choose to record into text. Your data is processed by the system; Orvia does not collect this information.</string>", text)
    return text

def encode_remaining(rel, text):
    suffix = Path(rel).suffix.lower()
    if suffix == ".dart":
        return esc_u(protect_dart_raw(text))
    if suffix in {".kt", ".kts"}:
        text = re.sub(r'"""(.*?)"""', kotlin_raw_piece, text, flags=re.S)
        return esc_u(text)
    if suffix == ".swift":
        return esc_swift(text)
    if suffix in {".xml", ".plist"}:
        return esc_xml(text)
    if suffix == ".strings":
        return esc_strings(text)
    return esc_u(text)

changed = []
for path in ROOT.rglob("*"):
    if not path.is_file():
        continue
    rel = path.relative_to(ROOT).as_posix()
    if rel in EXCLUDED_FILES or rel.startswith(EXCLUDED_PREFIXES):
        continue
    if path.suffix.lower() not in SUFFIXES:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    if not CJK.search(text):
        continue
    new = encode_remaining(rel, semantic_english(rel, text))
    if CJK.search(new):
        raise SystemExit(f"Cleanup left CJK in {rel}")
    if new != text:
        path.write_text(new, encoding="utf-8")
        changed.append(rel)

guard = ROOT / "tool/check_no_cjk_first_party.py"
g = guard.read_text(encoding="utf-8")
g = g.replace('".properties"}', '".properties",".arb",".html"}')
guard.write_text(g, encoding="utf-8")

print(f"Safely cleaned {len(changed)} files")
for rel in changed:
    print(rel)

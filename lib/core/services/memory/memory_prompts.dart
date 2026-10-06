/// Memory prompt language for model-facing contracts (not UI l10n / ARB).
enum MemoryPromptLang { zh, en }

/// Built-in default prompt templates and pure time helpers for the memory system.
///
/// These strings are model contracts and must NOT go through ARB (§16.2).
abstract final class MemoryPrompts {
  MemoryPrompts._();

  // ── §11.2 / §11.3 memory rules ───────────────────────────────────────────

  static final String rulesZh =
      '''
## \u957F\u671F\u8BB0\u5FC6

\u5BF9\u8BDD\u4E2D\u53EF\u80FD\u51FA\u73B0\u7531\u7CFB\u7EDF\u63D0\u4F9B\u7684\u8BB0\u5FC6\u4FE1\u606F，\u5B83\u4EEC\u4E0D\u662F\u7528\u6237\u672C\u8F6E\u8BF4\u7684\u8BDD：

- <user_profile> \u662F\u7528\u6237\u7684\u7A33\u5B9A\u8EAB\u4EFD\u4FE1\u606F，\u4F8B\u5982\u5E0C\u671B\u4F60\u600E\u4E48\u79F0\u547C\u4ED6、\u8BED\u8A00\u504F\u597D、\u65F6\u533A。
- <user_memory type="..."> \u662F\u5206\u56DB\u7C7B\u7684\u957F\u671F\u8BB0\u5FC6。\u6BCF\u884C\u5F62\u5982 `- [2026-08-07] \u5185\u5BB9`，\u65B9\u62EC\u53F7\u91CC\u662F\u8FD9\u6761\u8BB0\u5FC6\u6700\u540E\u66F4\u65B0\u7684\u65E5\u671F。\u5E26 `(assistant) ` \u524D\u7F00\u7684\u6761\u76EE\u53EA\u5C5E\u4E8E\u5F53\u524D\u52A9\u624B，\u5176\u4F59\u5BF9\u6240\u6709\u52A9\u624B\u53EF\u89C1。
- \u6807\u4E86 mode="summary" \u7684\u5757\u8868\u793A\u8BE5\u7C7B\u578B\u5171\u6709 total \u5C5E\u6027\u6807\u660E\u7684\u6761\u6570，\u53EA\u5217\u51FA\u4E86 shown \u5C5E\u6027\u6307\u660E\u7684\u6700\u8FD1\u82E5\u5E72\u6761；\u9700\u8981\u66F4\u591A\u65F6\u7528 memory_search_profile \u67E5\u8BE2。
- \u5F62\u5982 <user_memory type="voice"/> \u7684\u7A7A\u6807\u7B7E\u8868\u793A\u8BE5\u7C7B\u578B\u76EE\u524D\u6CA1\u6709\u8BB0\u5FC6。
- \u5BF9\u8BDD\u8FDB\u884C\u4E2D\u51FA\u73B0\u7684 <user_memory_update> \u662F\u8BB0\u5FC6\u7684\u6700\u65B0\u5B8C\u6574\u5FEB\u7167，\u7528\u5B83\u66FF\u6362\u4F60\u4E4B\u524D\u770B\u5230\u7684\u8BB0\u5FC6\u5185\u5BB9。

\u79F0\u547C\u7528\u6237\u65F6，\u5982\u679C <user_profile> \u91CC\u6709 preferred_name \u5C31\u6309\u5B83\u79F0\u547C；\u6CA1\u6709\u5C31\u4E0D\u8981\u731C\u6D4B，\u4E5F\u4E0D\u8981\u4F7F\u7528\u8BB0\u5FC6\u4E2D\u51FA\u73B0\u8FC7\u7684\u5176\u4ED6\u4EBA\u7684\u540D\u5B57。

\u5F53\u7528\u6237\u900F\u9732\u4E86\u8DE8\u5BF9\u8BDD\u4ECD\u7136\u6210\u7ACB\u7684\u7A33\u5B9A\u4FE1\u606F\u65F6，\u7528 memory_update \u5199\u4E00\u6761\u8BB0\u5FC6。\u5224\u65AD\u6807\u51C6\u662F：\u4E0B\u6B21\u91CD\u65B0\u5F00\u4E00\u4E2A\u5BF9\u8BDD，\u4E0D\u77E5\u9053\u8FD9\u4EF6\u4E8B\u4F1A\u4E0D\u4F1A\u8BA9\u4F60\u7684\u56DE\u7B54\u53D8\u5DEE。

\u4E0D\u8981\u5199\u5165：\u672C\u6B21\u5BF9\u8BDD\u5185\u7684\u4E34\u65F6\u4E0A\u4E0B\u6587、\u4F60\u81EA\u5DF1\u63A8\u65AD\u800C\u7528\u6237\u6CA1\u6709\u786E\u8BA4\u7684\u7ED3\u8BBA、\u7528\u6237\u53EA\u662F\u968F\u53E3\u63D0\u5230\u7684\u8BDD\u9898、\u53EF\u4EE5\u76F4\u63A5\u4ECE\u5BF9\u8BDD\u8BB0\u5F55\u91CC\u67E5\u5230\u7684\u4E8B\u5B9E。

\u5199\u5165\u65F6\u7528\u5B8C\u6574\u7684\u7B2C\u4E09\u4EBA\u79F0\u9648\u8FF0\u53E5\u63CF\u8FF0\u7528\u6237，\u4E0D\u8981\u4F7F\u7528「\u8FD9\u4E2A」「\u521A\u624D」\u7B49\u6307\u56DE\u672C\u6B21\u5BF9\u8BDD\u7684\u8BCD。\u7CFB\u7EDF\u4F1A\u81EA\u52A8\u53BB\u91CD\u5408\u5E76，\u4E0D\u9700\u8981\u5148\u8BFB\u53D6\u518D\u5168\u6587\u66FF\u6362。

\u7528\u6237\u660E\u786E\u6307\u51FA\u67D0\u6761\u8BB0\u5FC6\u4E0D\u5BF9\u65F6，\u7528 memory_edit \u4FEE\u6539，\u6216\u7528 memory_delete \u5F52\u6863。
'''
          .trim();

  static final String rulesEn =
      '''
## Long-term memory

The conversation may contain memory information provided by the system. It is not what the user said in the current turn:

- <user_profile> holds stable facts about the user, such as how they want to be addressed, language preference and timezone.
- <user_memory type="..."> holds long-term memory in four categories. Each line looks like `- [2026-08-07] content`, where the bracket is the date this entry was last updated. Entries prefixed with `(assistant) ` belong only to the current assistant; the rest are visible to all assistants.
- A block marked mode="summary" means the category has the number of entries given by the total attribute, and only the most recent ones indicated by the shown attribute are listed. Use memory_search_profile when you need more.
- An empty tag such as <user_memory type="voice"/> means the category currently has no entries.
- A <user_memory_update> appearing mid-conversation is the latest complete snapshot. Replace the memory you saw earlier with it.

When addressing the user, use preferred_name from <user_profile> if present. Otherwise do not guess, and never use the name of another person that appears in memory.

When the user reveals something that will still be true in a different conversation, write one entry with memory_update. The test is: if you started a fresh conversation, would not knowing this make your answer worse?

Do not write: temporary context from this conversation, conclusions you inferred but the user did not confirm, topics the user merely mentioned in passing, or facts that can be looked up directly in the chat history.

Write complete third-person statements about the user. Do not use words like "this" or "just now" that point back to the current conversation. The system deduplicates and merges automatically, so you do not need to read first and rewrite the whole entry.

When the user says an entry is wrong, use memory_edit to fix it or memory_delete to archive it.
'''
          .trim();

  static final String legacyRulesZh =
      '''
## Memory Tool
\u4F60\u662F\u4E00\u4E2A\u65E0\u72B6\u6001\u7684\u5927\u6A21\u578B，\u4F60\u65E0\u6CD5\u5B58\u50A8\u8BB0\u5FC6，\u56E0\u6B64\u4E3A\u4E86\u8BB0\u4F4F\u4FE1\u606F，\u4F60\u9700\u8981\u4F7F\u7528**\u8BB0\u5FC6\u5DE5\u5177**。
\u4F60\u53EF\u4EE5\u4F7F\u7528 `create_memory`, `edit_memory`, `delete_memory` \u5DE5\u5177\u521B\u5EFA、\u66F4\u65B0\u6216\u5220\u9664\u8BB0\u5FC6。
- \u5982\u679C\u8BB0\u5FC6\u4E2D\u6CA1\u6709\u76F8\u5173\u4FE1\u606F，\u8BF7\u4F7F\u7528 create_memory \u521B\u5EFA\u4E00\u6761\u65B0\u7684\u8BB0\u5F55。
- \u5982\u679C\u5DF2\u6709\u76F8\u5173\u8BB0\u5F55，\u8BF7\u4F7F\u7528 edit_memory \u66F4\u65B0\u5185\u5BB9。
- \u82E5\u8BB0\u5FC6\u8FC7\u65F6\u6216\u65E0\u7528，\u8BF7\u4F7F\u7528 delete_memory \u5220\u9664。
\u8FD9\u4E9B\u8BB0\u5FC6\u4F1A\u81EA\u52A8\u5305\u542B\u5728\u672A\u6765\u7684\u5BF9\u8BDD\u4E0A\u4E0B\u6587\u4E2D，\u5728<memories>\u6807\u7B7E\u5185。
\u8BF7\u52FF\u5728\u8BB0\u5FC6\u4E2D\u5B58\u50A8\u654F\u611F\u4FE1\u606F，\u654F\u611F\u4FE1\u606F\u5305\u62EC：\u7528\u6237\u7684\u6C11\u65CF、\u5B97\u6559\u4FE1\u4EF0、\u6027\u53D6\u5411、\u653F\u6CBB\u89C2\u70B9\u53CA\u515A\u6D3E\u5F52\u5C5E、\u6027\u751F\u6D3B、\u72AF\u7F6A\u8BB0\u5F55\u7B49。
\u5728\u4E0E\u7528\u6237\u804A\u5929\u8FC7\u7A0B\u4E2D，\u4F60\u53EF\u4EE5\u50CF\u4E00\u4E2A\u79C1\u4EBA\u79D8\u4E66\u4E00\u6837**\u4E3B\u52A8\u7684**\u8BB0\u5F55\u7528\u6237\u76F8\u5173\u7684\u4FE1\u606F\u5230\u8BB0\u5FC6\u91CC，\u5305\u62EC\u4F46\u4E0D\u9650\u4E8E：
- \u7528\u6237\u6635\u79F0/\u59D3\u540D
- \u5E74\u9F84/\u6027\u522B/\u5174\u8DA3\u7231\u597D
- \u8BA1\u5212\u4E8B\u9879\u7B49
- \u804A\u5929\u98CE\u683C\u504F\u597D
- \u5DE5\u4F5C\u76F8\u5173
- \u9996\u6B21\u804A\u5929\u65F6\u95F4
- ...
\u8BF7\u4E3B\u52A8\u8C03\u7528\u5DE5\u5177\u8BB0\u5F55，\u800C\u4E0D\u662F\u9700\u8981\u7528\u6237\u8981\u6C42。
\u8BB0\u5FC6\u5982\u679C\u5305\u542B\u65E5\u671F\u4FE1\u606F，\u8BF7\u5305\u542B\u5728\u5185，\u8BF7\u4F7F\u7528\u7EDD\u5BF9\u65F6\u95F4\u683C\u5F0F，\u5E76\u4E14\u5F53\u524D\u65F6\u95F4\u662F{{currentTime}}。
\u65E0\u9700\u544A\u77E5\u7528\u6237\u4F60\u5DF2\u66F4\u6539\u8BB0\u5FC6\u8BB0\u5F55，\u4E5F\u4E0D\u8981\u5728\u5BF9\u8BDD\u4E2D\u76F4\u63A5\u663E\u793A\u8BB0\u5FC6\u5185\u5BB9，\u9664\u975E\u7528\u6237\u4E3B\u52A8\u8981\u6C42。
\u76F8\u4F3C\u6216\u76F8\u5173\u7684\u8BB0\u5FC6\u5E94\u5408\u5E76\u4E3A\u4E00\u6761\u8BB0\u5F55，\u800C\u4E0D\u8981\u91CD\u590D\u8BB0\u5F55，\u8FC7\u65F6\u8BB0\u5F55\u5E94\u5220\u9664。
\u4F60\u53EF\u4EE5\u5728\u548C\u7528\u6237\u95F2\u804A\u7684\u65F6\u5019\u6697\u793A\u7528\u6237\u4F60\u80FD\u8BB0\u4F4F\u4E1C\u897F。
'''
          .trim();

  /// English counterpart of [legacyRulesZh].
  static final String legacyRulesEn =
      '''
## Memory Tool
You are a stateless model and cannot retain memories on your own; to remember something, use the **memory tools**.
Use the `create_memory`, `edit_memory`, and `delete_memory` tools to create, update, or delete memories.
- If nothing relevant is stored yet, use create_memory to add a new entry.
- If a related entry already exists, use edit_memory to update it.
- If an entry is outdated or useless, use delete_memory to remove it.
These memories are automatically included in future conversation context, inside the <memories> tag.
Never store sensitive information, which includes the user's ethnicity, religious beliefs, sexual orientation, political views and party affiliation, sex life, and criminal record.
While chatting with the user, act like a personal secretary and **proactively** record information about them, including but not limited to:
- Nickname / name
- Age / gender / interests
- Plans and scheduled items
- Preferred chat style
- Work-related details
- Time of the first conversation
- ...
Call the tools on your own initiative rather than waiting for the user to ask.
When an entry involves dates, include them in an absolute time format; the current time is {{currentTime}}.
There is no need to tell the user you changed an entry, and do not show memory contents in the conversation unless the user asks.
Similar or related memories should be merged into one entry instead of duplicated, and outdated entries should be deleted.
You may hint during casual chat that you are able to remember things.
'''
          .trim();

  static const String legacyCurrentTimePlaceholder = '{{currentTime}}';

  /// Appended to [rulesZh] when `allowPastConversationRecall` is on.
  static const String rulesPastConversationRecallZh =
      '\u9700\u8981\u56DE\u5FC6\u4E4B\u524D\u804A\u8FC7\u7684\u5185\u5BB9\u65F6，\u7528 chat_search \u6309\u5173\u952E\u8BCD\u641C\u7D22\u5386\u53F2\u5BF9\u8BDD，\u4E0D\u8981\u51ED\u5370\u8C61\u4F5C\u7B54。';

  /// Appended to [rulesEn] when `allowPastConversationRecall` is on.
  static const String rulesPastConversationRecallEn =
      'When you need to recall something discussed before, use chat_search to search past conversations by keyword. Do not answer from impression.';

  // ── §12.4 Gatekeeper ─────────────────────────────────────────────────────

  static final String gateZh =
      '''
\u5206\u6790\u4EE5\u4E0B\u5BF9\u8BDD，\u5224\u65AD\u5176\u4E2D\u662F\u5426\u5305\u542B\u503C\u5F97\u957F\u671F\u8BB0\u5FC6\u7684\u7528\u6237\u4FE1\u606F。

\u503C\u5F97\u8BB0\u5FC6：\u7528\u6237\u900F\u9732\u4E86\u4E2A\u4EBA\u4FE1\u606F、\u505A\u4E8B\u504F\u597D、\u8868\u8FBE\u98CE\u683C\u7279\u5F81、\u5BF9\u52A9\u624B\u7684\u660E\u786E\u8981\u6C42
\u4E0D\u503C\u5F97：\u7EAF\u6280\u672F\u95EE\u7B54、\u9879\u76EE\u7EC6\u8282、\u4E00\u6B21\u6027\u64CD\u4F5C\u6307\u4EE4

\u8F93\u51FA\u683C\u5F0F（\u4E25\u683C\u6309\u6B64 XML，\u4E0D\u8981\u8F93\u51FA\u591A\u4F59\u6587\u5B57）：
<gate>
  <user_memory>true \u6216 false</user_memory>
</gate>

## \u5BF9\u8BDD
{{conversation}}
'''
          .trim();

  static final String gateEn =
      '''
Analyse the conversation below and decide whether it contains user information worth remembering long term.

Worth remembering: the user revealed personal information, a way of working, a characteristic of how they express themselves, or an explicit requirement for the assistant.
Not worth remembering: pure technical Q&A, project details, one-off operational instructions.

Output format (follow this XML exactly, no extra text):
<gate>
  <user_memory>true or false</user_memory>
</gate>

## Conversation
{{conversation}}
'''
          .trim();

  // ── §12.5 Extract ────────────────────────────────────────────────────────

  static final String extractZh =
      '''
\u4ECE\u5BF9\u8BDD\u4E2D\u63D0\u53D6\u7528\u6237\u753B\u50CF\u7684\u65B0\u4FE1\u606F。\u6BCF\u6761\u4FE1\u606F\u72EC\u7ACB、\u7B80\u6D01、\u5B8C\u6574。

\u56DB\u7C7B\u753B\u50CF：
- identity（\u8EAB\u4EFD）：\u59D3\u540D、\u6027\u522B、\u4EE3\u8BCD\u504F\u597D、\u804C\u4E1A、\u516C\u53F8、\u8EAB\u8FB9\u7684\u4EBA、\u80FD\u529B\u80CC\u666F
- workflow（\u5DE5\u4F5C\u65B9\u5F0F）：\u505A\u4E8B\u6D41\u7A0B、\u5DE5\u5177\u504F\u597D、\u8C03\u8BD5\u4E60\u60EF
- voice（\u8868\u8FBE\u98CE\u683C）：\u884C\u6587\u98CE\u683C、\u53E5\u5F0F\u8282\u594F、\u7528\u8BCD\u4E60\u60EF
- instruction（\u7528\u6237\u6307\u4EE4）：\u7528\u6237\u5BF9\u52A9\u624B\u7684\u660E\u786E\u8981\u6C42——\u56DE\u590D\u98CE\u683C、\u7981\u6B62\u9879、\u4EA4\u4E92\u504F\u597D

\u89C4\u5219：
- \u53EA\u4ECE\u7528\u6237\u8BF4\u7684\u8BDD\u91CC\u63D0\u53D6
- \u4E0D\u63D0\u53D6\u52A9\u624B\u7684\u89D2\u8272\u8BBE\u5B9A
- \u4E0D\u63D0\u53D6\u53EF\u4EE5\u76F4\u63A5\u4ECE\u5BF9\u8BDD\u8BB0\u5F55\u6216\u4EE3\u7801\u91CC\u67E5\u5230\u7684\u4E8B\u5B9E
- \u6BCF\u6761\u4E00\u53E5\u8BDD，\u72EC\u7ACB\u81EA\u5305\u542B，\u7528\u7B2C\u4E09\u4EBA\u79F0\u63CF\u8FF0\u7528\u6237
- \u4E0D\u4F7F\u7528「\u8FD9\u4E2A」「\u521A\u624D」\u7B49\u6307\u56DE\u672C\u6B21\u5BF9\u8BDD\u7684\u8BCD
- 「\u5DF2\u6709\u8BB0\u5FC6」\u91CC\u5DF2\u7ECF\u51FA\u73B0\u8FC7\u7684\u4FE1\u606F\u4E0D\u8981\u91CD\u590D\u63D0\u53D6

## Existing memory
{{existingMemory}}

\u8F93\u51FA\u683C\u5F0F：
<extracted>
<item type="identity|workflow|voice|instruction">\u4E00\u53E5\u8BDD\u63CF\u8FF0</item>
</extracted>

\u5982\u679C\u6CA1\u6709\u503C\u5F97\u63D0\u53D6\u7684\u4FE1\u606F：
<extracted/>

## \u5BF9\u8BDD
{{conversation}}
'''
          .trim();

  static final String extractEn =
      '''
Extract new information about the user from the conversation. Each item must be independent, concise and complete.

Four categories:
- identity: name, gender, pronoun preference, occupation, company, people around them, background
- workflow: how they work, tool preferences, debugging habits
- voice: writing style, sentence rhythm, word choice
- instruction: explicit requirements the user has for the assistant — reply style, prohibitions, interaction preferences

Rules:
- Extract only from what the user said
- Do not extract the assistant's persona
- Do not extract facts that can be looked up directly in the chat history or in code
- One sentence per item, self-contained, third person about the user
- Do not use words like "this" or "just now" that point back to the current conversation
- Do not re-extract anything already present in "Existing memory"

## Existing memory
{{existingMemory}}

Output format:
<extracted>
<item type="identity|workflow|voice|instruction">one sentence</item>
</extracted>

If there is nothing worth extracting:
<extracted/>

## Conversation
{{conversation}}
'''
          .trim();

  /// Appended under Extract rules when write scope is `toolDefault*`.
  static const String extractToolDefaultScopeRuleZh =
      '- \u53EA\u5BF9\u5F53\u524D\u52A9\u624B\u6210\u7ACB\u7684\u4FE1\u606F，\u5728 item \u4E0A\u52A0 scope="assistant"；\u5BF9\u6240\u6709\u573A\u666F\u90FD\u6210\u7ACB\u7684\u52A0 scope="global" \u6216\u7701\u7565';

  static const String extractToolDefaultScopeRuleEn =
      '- For information that only applies to the current assistant, add scope="assistant" on the item; for information that applies everywhere, add scope="global" or omit it';

  // ── §12.6 Smart Add (per-item) ───────────────────────────────────────────

  static final String smartAddZh =
      '''
\u4F60\u662F\u8BB0\u5FC6\u53BB\u91CD\u5224\u65AD\u5668。\u5224\u65AD\u65B0\u4FE1\u606F\u4E0E\u5DF2\u6709\u8BB0\u5FC6\u7684\u5173\u7CFB。

## \u65B0\u4FE1\u606F
\u7C7B\u578B：{{type}}
\u5185\u5BB9：{{newInfo}}

## \u76F8\u4F3C\u7684\u5DF2\u6709\u8BB0\u5FC6（\u6700\u591A 5 \u6761）
{{entriesText}}

\u5224\u65AD：
- NEW：\u5DF2\u6709\u8BB0\u5FC6\u4E2D\u6CA1\u6709\u76F8\u5173\u7684，\u5E94\u65B0\u589E
- MERGE：\u5E94\u5408\u5E76\u5230\u67D0\u6761\u5DF2\u6709\u8BB0\u5FC6，\u8F93\u51FA\u5408\u5E76\u540E\u7684\u5B8C\u6574\u5185\u5BB9
- CONFLICT：\u4E0E\u67D0\u6761\u5DF2\u6709\u8BB0\u5FC6\u77DB\u76FE（\u7528\u6237\u6539\u53D8\u4E86\u504F\u597D），\u5F52\u6863\u65E7\u7684、\u5199\u5165\u65B0\u7684
- SKIP：\u5DF2\u6709\u8BB0\u5FC6\u4E2D\u5DF2\u5305\u542B\u6B64\u4FE1\u606F，\u65E0\u9700\u64CD\u4F5C

\u540C\u65F6\u5224\u65AD：\u4E0A\u9762\u5217\u51FA\u7684\u5DF2\u6709\u8BB0\u5FC6\u4E2D，\u54EA\u4E9B\u4E0E\u65B0\u4FE1\u606F\u8BED\u4E49\u76F8\u5173（\u5373\u4F7F\u4E0D\u91CD\u590D\u4E5F\u4E0D\u77DB\u76FE）？

\u53EA\u8F93\u51FA JSON，\u4E0D\u8981\u89E3\u91CA：
{ "action": "NEW" | "MERGE" | "CONFLICT" | "SKIP", "targetId": "...", "mergedContent": "...", "relatedIds": ["mem_xxxxxxxx"] }
'''
          .trim();

  static final String smartAddEn =
      '''
You are a memory deduplication judge. Decide how the new information relates to existing memory.

## New information
Type: {{type}}
Content: {{newInfo}}

## Similar existing memories (up to 5)
{{entriesText}}

Decide:
- NEW: nothing related exists; create a new entry
- MERGE: merge into an existing entry; output the full merged content
- CONFLICT: contradicts an existing entry (the user changed a preference); archive the old one and write the new one
- SKIP: existing memory already contains this information; do nothing

Also decide: which of the listed existing memories are semantically related to the new information (even if not duplicate and not conflicting)?

Output JSON only, no explanation:
{ "action": "NEW" | "MERGE" | "CONFLICT" | "SKIP", "targetId": "...", "mergedContent": "...", "relatedIds": ["mem_xxxxxxxx"] }
'''
          .trim();

  // ── §12.6 Smart Add (batched) ────────────────────────────────────────────

  static final String smartAddBatchZh =
      '''
\u4F60\u662F\u8BB0\u5FC6\u53BB\u91CD\u5224\u65AD\u5668。\u5224\u65AD\u6BCF\u6761\u65B0\u4FE1\u606F\u4E0E\u5DF2\u6709\u8BB0\u5FC6\u7684\u5173\u7CFB。

## \u65B0\u4FE1\u606F
{{itemsText}}

## \u76F8\u4F3C\u7684\u5DF2\u6709\u8BB0\u5FC6
{{entriesText}}

\u5BF9\u6BCF\u6761\u65B0\u4FE1\u606F\u7ED9\u51FA\u5224\u65AD：
- NEW：\u5DF2\u6709\u8BB0\u5FC6\u4E2D\u6CA1\u6709\u76F8\u5173\u7684，\u5E94\u65B0\u589E
- MERGE：\u5E94\u5408\u5E76\u5230\u67D0\u6761\u5DF2\u6709\u8BB0\u5FC6，\u8F93\u51FA\u5408\u5E76\u540E\u7684\u5B8C\u6574\u5185\u5BB9
- CONFLICT：\u4E0E\u67D0\u6761\u5DF2\u6709\u8BB0\u5FC6\u77DB\u76FE（\u7528\u6237\u6539\u53D8\u4E86\u504F\u597D），\u5F52\u6863\u65E7\u7684、\u5199\u5165\u65B0\u7684
- SKIP：\u5DF2\u6709\u8BB0\u5FC6\u4E2D\u5DF2\u5305\u542B\u6B64\u4FE1\u606F，\u65E0\u9700\u64CD\u4F5C

\u540C\u65F6\u5BF9\u6BCF\u6761\u65B0\u4FE1\u606F\u5224\u65AD：\u4E0A\u9762\u5217\u51FA\u7684\u5DF2\u6709\u8BB0\u5FC6\u91CC\u54EA\u4E9B\u4E0E\u5B83\u8BED\u4E49\u76F8\u5173（\u5373\u4F7F\u4E0D\u91CD\u590D\u4E5F\u4E0D\u77DB\u76FE）？

\u53EA\u8F93\u51FA JSON，\u4E0D\u8981\u89E3\u91CA：
{"results":[{"index":1,"action":"NEW","targetId":null,"mergedContent":null,"relatedIds":[]}]}
'''
          .trim();

  static final String smartAddBatchEn =
      '''
You are a memory deduplication judge. Decide how each piece of new information relates to existing memory.

## New information
{{itemsText}}

## Similar existing memories
{{entriesText}}

For each piece of new information, decide:
- NEW: nothing related exists; create a new entry
- MERGE: merge into an existing entry; output the full merged content
- CONFLICT: contradicts an existing entry (the user changed a preference); archive the old one and write the new one
- SKIP: existing memory already contains this information; do nothing

Also, for each piece of new information, decide which of the listed existing memories are semantically related to it (even if not duplicate and not conflicting).

Output JSON only, no explanation:
{"results":[{"index":1,"action":"NEW","targetId":null,"mergedContent":null,"relatedIds":[]}]}
'''
          .trim();

  // ── §12.7 Profile Distiller ──────────────────────────────────────────────

  static final String profileDistillZh =
      '''
\u4ECE\u7528\u6237\u7684\u8EAB\u4EFD\u7C7B\u8BB0\u5FC6\u4E2D\u63D0\u70BC\u7A33\u5B9A\u7684\u753B\u50CF\u5B57\u6BB5。

## \u5F53\u524D\u753B\u50CF
{{profileBlock}}

## \u8EAB\u4EFD\u7C7B\u8BB0\u5FC6
{{identityEntries}}

\u53EF\u7528\u5B57\u6BB5：preferred_name（\u7528\u6237\u5E0C\u671B\u88AB\u600E\u4E48\u79F0\u547C）、gender、pronouns、preferred_language、timezone、occupation、location

\u89C4\u5219：
- \u8BB0\u5FC6\u4E2D\u6CA1\u6709\u660E\u786E\u4F9D\u636E\u7684\u5B57\u6BB5\u4E0D\u8981\u8F93\u51FA
- \u5F53\u524D\u753B\u50CF\u5DF2\u7ECF\u6709\u503C、\u4E14\u8BB0\u5FC6\u6CA1\u6709\u63A8\u7FFB\u5B83\u7684\u5B57\u6BB5\u4E0D\u8981\u8F93\u51FA
- preferred_name \u53EA\u5728\u7528\u6237\u660E\u786E\u8868\u8FBE\u8FC7\u5E0C\u671B\u88AB\u600E\u4E48\u79F0\u547C\u65F6\u624D\u8F93\u51FA；\u4E0D\u8981\u4F7F\u7528\u8BB0\u5FC6\u4E2D\u51FA\u73B0\u7684\u5176\u4ED6\u4EBA\u7684\u540D\u5B57
- \u4E0D\u786E\u5B9A\u5C31\u4E0D\u8F93\u51FA

\u53EA\u8F93\u51FA JSON，\u4E0D\u8981\u89E3\u91CA：
{"fields":[{"key":"preferred_name","value":"..."}]}
'''
          .trim();

  static final String profileDistillEn =
      '''
Distill stable profile fields from the user's identity memories.

## Current profile
{{profileBlock}}

## Identity memories
{{identityEntries}}

Available fields: preferred_name (how the user wants to be addressed), gender, pronouns, preferred_language, timezone, occupation, location

Rules:
- Do not output a field without clear evidence in the memories
- Do not output a field that already has a value in the current profile unless the memories overturn it
- Only output preferred_name when the user has explicitly said how they want to be addressed; never use the name of another person that appears in memory
- If uncertain, do not output

Output JSON only, no explanation:
{"fields":[{"key":"preferred_name","value":"..."}]}
'''
          .trim();

  // ── Legacy memory migration ──────────────────────────────────────────────

  static final String migrateZh =
      '''
\u4F60\u6B63\u5728\u628A\u65E7\u7248\u957F\u671F\u8BB0\u5FC6\u8FC1\u5165\u5E26\u7C7B\u578B\u7684\u8BB0\u5FC6\u7CFB\u7EDF。

\u5BF9\u6BCF\u4E00\u6761\u8F93\u5165，\u8FD4\u56DE\u4E00\u6761 id \u76F8\u540C\u7684\u8F93\u51FA。\u4FDD\u7559\u5168\u90E8\u4E8B\u5B9E、\u504F\u597D、\u5426\u5B9A、\u9650\u5B9A\u548C\u4E0D\u786E\u5B9A\u8868\u8FF0。\u4FDD\u6301\u539F\u6587\u8BED\u8A00。\u53EA\u505A\u8BA9\u8BB0\u5FC6\u7B80\u6D01、\u81EA\u5305\u542B、\u8131\u79BB\u5BF9\u8BDD\u4E0A\u4E0B\u6587\u4E5F\u80FD\u770B\u61C2\u7684\u6539\u5199。\u9002\u5408\u65F6\u7528\u7B2C\u4E09\u4EBA\u79F0\u63CF\u8FF0\u7528\u6237。

\u53EA\u9009\u4E00\u4E2A\u7C7B\u578B：
- identity：\u7A33\u5B9A\u4E8B\u5B9E、\u504F\u597D、\u80CC\u666F、\u4EBA\u9645\u5173\u7CFB、\u5174\u8DA3\u6216\u4E2A\u4EBA\u4E0A\u4E0B\u6587
- workflow：\u7528\u6237\u505A\u4E8B、\u51B3\u7B56、\u89C4\u5212\u6216\u4F7F\u7528\u5DE5\u5177\u7684\u60EF\u5E38\u65B9\u5F0F
- voice：\u504F\u597D\u7684\u8BED\u6C14、\u63AA\u8F9E、\u8BED\u8A00、\u683C\u5F0F\u6216\u6C9F\u901A\u98CE\u683C
- instruction：\u5BF9\u52A9\u624B\u5E94\u5982\u4F55\u8868\u73B0\u6216\u56DE\u590D\u7684\u6301\u4E45\u89C4\u5219

\u4E0D\u8981\u7F16\u9020、\u7FFB\u8BD1、\u5408\u5E76、\u62C6\u5206、\u7701\u7565、\u53BB\u91CD、\u89E3\u91CA\u6216\u6DFB\u52A0\u5EFA\u8BAE。

\u53EA\u8FD4\u56DE\u8FD9\u79CD\u5F62\u72B6\u7684 JSON \u6570\u7EC4：
[{"id":1,"type":"identity","content":"..."}]

\u8F93\u5165：
{{items}}
'''
          .trim();

  static final String migrateEn =
      '''
You are migrating legacy long-term memories into a typed memory system.

For every input item, return exactly one output item with the same integer id. Preserve every fact, preference, negation, qualification, and uncertainty. Keep the original language. Rewrite only enough to make the memory concise, self-contained, and understandable without conversation context. When appropriate, phrase it as a third-person statement about the user.

Choose exactly one type:
- identity: stable facts, preferences, background, relationships, interests, or personal context
- workflow: recurring ways the user works, decides, plans, or uses tools
- voice: preferred tone, wording, language, formatting, or communication style
- instruction: durable rules for how an assistant should behave or respond

Do not invent, translate, merge, split, omit, deduplicate, explain, or add advice.

Return only a JSON array in this exact shape:
[{"id":1,"type":"identity","content":"..."}]

Input:
{{items}}
'''
          .trim();

  static final String migratePreserveZh =
      '''
\u4F60\u6B63\u5728\u628A\u65E7\u7248\u957F\u671F\u8BB0\u5FC6\u5206\u7C7B\u5230\u5E26\u7C7B\u578B\u7684\u8BB0\u5FC6\u7CFB\u7EDF。\u5185\u5BB9\u7531\u7CFB\u7EDF\u539F\u6837\u4FDD\u7559，\u4F60\u53EA\u8D1F\u8D23\u5206\u7C7B。

\u5BF9\u6BCF\u4E00\u6761\u8F93\u5165，\u8FD4\u56DE\u4E00\u6761 id \u76F8\u540C\u7684\u8F93\u51FA。\u53EA\u9009\u4E00\u4E2A\u7C7B\u578B：
- identity：\u7A33\u5B9A\u4E8B\u5B9E、\u504F\u597D、\u80CC\u666F、\u4EBA\u9645\u5173\u7CFB、\u5174\u8DA3\u6216\u4E2A\u4EBA\u4E0A\u4E0B\u6587
- workflow：\u7528\u6237\u505A\u4E8B、\u51B3\u7B56、\u89C4\u5212\u6216\u4F7F\u7528\u5DE5\u5177\u7684\u60EF\u5E38\u65B9\u5F0F
- voice：\u504F\u597D\u7684\u8BED\u6C14、\u63AA\u8F9E、\u8BED\u8A00、\u683C\u5F0F\u6216\u6C9F\u901A\u98CE\u683C
- instruction：\u5BF9\u52A9\u624B\u5E94\u5982\u4F55\u8868\u73B0\u6216\u56DE\u590D\u7684\u6301\u4E45\u89C4\u5219

\u4E0D\u8981\u6539\u5199、\u7FFB\u8BD1、\u7F16\u9020、\u5408\u5E76、\u62C6\u5206\u6216\u7701\u7565。\u4E0D\u8981\u8F93\u51FA content。

\u53EA\u8FD4\u56DE\u8FD9\u79CD\u5F62\u72B6\u7684 JSON \u6570\u7EC4：
[{"id":1,"type":"identity"}]

\u8F93\u5165：
{{items}}
'''
          .trim();

  static final String migratePreserveEn =
      '''
You are classifying legacy long-term memories into a typed memory system. The system will keep each memory's original wording. You only assign a type.

For every input item, return exactly one output item with the same integer id. Choose exactly one type:
- identity: stable facts, preferences, background, relationships, interests, or personal context
- workflow: recurring ways the user works, decides, plans, or uses tools
- voice: preferred tone, wording, language, formatting, or communication style
- instruction: durable rules for how an assistant should behave or respond

Do not rewrite, translate, invent, merge, split, or omit items. Do not output content.

Return only a JSON array in this exact shape:
[{"id":1,"type":"identity"}]

Input:
{{items}}
'''
          .trim();

  // ── §7.5 injection intros ────────────────────────────────────────────────

  static const String introFullZh = '\u4EE5\u4E0B\u5185\u5BB9\u7531\u7CFB\u7EDF\u63D0\u4F9B，\u4E0D\u662F\u7528\u6237\u672C\u8F6E\u53D1\u9001\u7684\u5185\u5BB9。';
  static const String introFullEn =
      'The following context is provided by the system. It is not what the user said in this turn.';
  // No longer written: injection always emits a full snapshot. Kept so
  // prompts frozen by earlier versions can still be parsed and stripped.
  static const String introUpdateZh = '\u4EE5\u4E0B\u662F\u672C\u6B21\u5BF9\u8BDD\u5F00\u59CB\u540E\u53D1\u751F\u7684\u8BB0\u5FC6\u66F4\u65B0，\u7531\u7CFB\u7EDF\u63D0\u4F9B。';
  static const String introUpdateEn =
      'The following memory changes happened after this conversation started, provided by the system.';

  // ── §7.2 moreHint ────────────────────────────────────────────────────────

  static const String moreHintZh = '[\u66F4\u591A\u5185\u5BB9\u8BF7\u4F7F\u7528 memory_search_profile \u67E5\u8BE2]';
  static const String moreHintEn =
      '[More entries exist. Use memory_search_profile to look them up.]';

  // ── §9.1 / §9.3 time helpers ─────────────────────────────────────────────

  static const List<String> _weekdayAbbrev = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// Wraps [timestamp] as `<current_time>EEE yyyy-MM-dd HH:mm:ss</current_time>`
  /// in the local timezone, without a UTC offset (§9.1) by default.
  /// With [useIso8601], emits ISO 8601 to seconds with a UTC offset.
  ///
  /// Four-digit year avoids `yy-MM-dd` / `dd-MM-yy` ambiguity (e.g. 22–26).
  static String formatCurrentTimeTag(
    DateTime timestamp, {
    bool useIso8601 = false,
  }) {
    final local = timestamp.isUtc ? timestamp.toLocal() : timestamp;
    final eee = _weekdayAbbrev[local.weekday - 1];
    final yyyy = local.year.toString();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    if (useIso8601) {
      final offset = local.timeZoneOffset;
      final sign = offset.isNegative ? '-' : '+';
      final minutes = offset.inMinutes.abs();
      final offsetHours = (minutes ~/ 60).toString().padLeft(2, '0');
      final offsetMinutes = (minutes % 60).toString().padLeft(2, '0');
      return '<current_time>${yyyy.padLeft(4, '0')}-$mm-${dd}T$hh:$min:$ss'
          '$sign$offsetHours:$offsetMinutes</current_time>';
    }
    return '<current_time>$eee $yyyy-$mm-$dd $hh:$min:$ss</current_time>';
  }

  /// Returns which of `{cur_date}`, `{cur_time}`, `{cur_datetime}` occur in
  /// [systemPrompt], in that fixed order. `{timezone}` etc. are ignored (§9.3).
  static List<String> detectTimeVariablesInSystemPrompt(String systemPrompt) {
    const candidates = ['{cur_date}', '{cur_time}', '{cur_datetime}'];
    return [
      for (final token in candidates)
        if (systemPrompt.contains(token)) token,
    ];
  }

  static String rulesFor(MemoryPromptLang lang) => rulesEn;

  static String rulesPastConversationRecallFor(MemoryPromptLang lang) => rulesPastConversationRecallEn;

  static String gateFor(MemoryPromptLang lang) => gateEn;

  static String extractFor(MemoryPromptLang lang) => extractEn;

  static String extractToolDefaultScopeRuleFor(MemoryPromptLang lang) => extractToolDefaultScopeRuleEn;

  static String smartAddFor(MemoryPromptLang lang) => smartAddEn;

  static String smartAddBatchFor(MemoryPromptLang lang) => smartAddBatchEn;

  static String profileDistillFor(MemoryPromptLang lang) => profileDistillEn;

  static String migrateFor(MemoryPromptLang lang) => migrateEn;

  static String migratePreserveFor(MemoryPromptLang lang) => migratePreserveEn;

  static String introFullFor(MemoryPromptLang lang) => introFullEn;

  static String moreHintFor(MemoryPromptLang lang) => moreHintEn;
}

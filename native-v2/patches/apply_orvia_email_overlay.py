# Native email integration overlay. Keep this isolated so the upstream LastChat
# submodule stays pinned and every source edit remains asserted/reproducible.
install_native_source(
    "native-v2/patches/native-src/NativeEmailService.kt",
    "app/src/main/java/me/rerere/rikkahub/data/integration/NativeEmailService.kt",
)
install_native_source(
    "native-v2/patches/native-src/SettingEmailIntegrationPage.kt",
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/SettingEmailIntegrationPage.kt",
)

replace_once(
    "app/build.gradle.kts",
    'dependencies {\n',
    'dependencies {\n    implementation("com.sun.mail:android-mail:1.6.7")\n    implementation("com.sun.mail:android-activation:1.6.7")\n',
)

replace_once(
    "app/src/main/java/me/rerere/rikkahub/data/ai/tools/LocalTools.kt",
    "import me.rerere.rikkahub.data.repository.GenMediaRepository\n",
    "import me.rerere.rikkahub.data.repository.GenMediaRepository\nimport me.rerere.rikkahub.data.integration.NativeEmailService\n",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/data/ai/tools/LocalTools.kt",
    '    @Serializable\n    @SerialName("image_generation")\n    data object ImageGeneration : LocalToolOption()\n',
    '    @Serializable\n    @SerialName("image_generation")\n    data object ImageGeneration : LocalToolOption()\n\n    @Serializable\n    @SerialName("email")\n    data object Email : LocalToolOption()\n',
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/data/ai/tools/LocalTools.kt",
    "    LocalToolOption.PythonEngine -> emptyList()\n",
    '''    LocalToolOption.Email -> listOf(
        LocalToolDefinitionPreview(
            name = "setup_email",
            description = "Tell the user how to connect email from Settings. Never ask for passwords in chat.",
            schema = InputSchema.Obj(properties = buildJsonObject {}),
        ),
        LocalToolDefinitionPreview(
            name = "check_email",
            description = "Check connected mailboxes for unread messages and return safe message summaries.",
            schema = InputSchema.Obj(properties = buildJsonObject {
                put("account", buildJsonObject { put("type", "string"); put("description", "Connected account address, if multiple accounts are configured") })
                put("limit", buildJsonObject { put("type", "integer"); put("description", "Maximum messages to return, 1 to 25") })
            }),
        ),
        LocalToolDefinitionPreview(
            name = "search_email",
            description = "Search connected inboxes by sender, subject, or body text.",
            schema = InputSchema.Obj(properties = buildJsonObject {
                put("account", buildJsonObject { put("type", "string"); put("description", "Connected account address, if multiple accounts are configured") })
                put("query", buildJsonObject { put("type", "string"); put("description", "Text to search for") })
                put("limit", buildJsonObject { put("type", "integer"); put("description", "Maximum results, 1 to 25") })
            }, required = listOf("query")),
        ),
        LocalToolDefinitionPreview(
            name = "read_email",
            description = "Read a specific message by its IMAP UID returned from email search or check.",
            schema = InputSchema.Obj(properties = buildJsonObject {
                put("account", buildJsonObject { put("type", "string"); put("description", "Connected account address, if multiple accounts are configured") })
                put("uid", buildJsonObject { put("type", "integer"); put("description", "Message UID returned by check_email or search_email") })
            }, required = listOf("uid")),
        ),
        LocalToolDefinitionPreview(
            name = "compose_email",
            description = "Prepare and send an outgoing email. This action requires user approval before sending.",
            schema = InputSchema.Obj(properties = buildJsonObject {
                put("account", buildJsonObject { put("type", "string"); put("description", "Connected sender account, if multiple accounts are configured") })
                put("to", buildJsonObject { put("type", "string"); put("description", "Recipient email address(es), comma-separated") })
                put("subject", buildJsonObject { put("type", "string"); put("description", "Email subject") })
                put("body", buildJsonObject { put("type", "string"); put("description", "Email body text") })
            }, required = listOf("to", "subject", "body")),
        ),
        LocalToolDefinitionPreview(
            name = "reply_email",
            description = "Reply to a message by IMAP UID. Sending requires user approval.",
            schema = InputSchema.Obj(properties = buildJsonObject {
                put("account", buildJsonObject { put("type", "string"); put("description", "Connected account address, if multiple accounts are configured") })
                put("uid", buildJsonObject { put("type", "integer"); put("description", "Original message UID") })
                put("to", buildJsonObject { put("type", "string"); put("description", "Optional recipient override; defaults to the original reply address") })
                put("subject", buildJsonObject { put("type", "string"); put("description", "Optional subject override") })
                put("body", buildJsonObject { put("type", "string"); put("description", "Reply body text") })
            }, required = listOf("uid", "body")),
        ),
    )
    LocalToolOption.PythonEngine -> emptyList()
''',
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/data/ai/tools/LocalTools.kt",
    "    val askUserTool by lazy {\n",
    "    private val nativeEmailService by lazy { NativeEmailService(context) }\n\n    val askUserTool by lazy {\n",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/data/ai/tools/LocalTools.kt",
    "    /**\n     * Get all enabled local tools for the conversation.\n     */\n    fun getTools(\n",
    '''    private suspend fun emailSafe(action: suspend () -> JsonElement): JsonElement =
        try {
            action()
        } catch (_: Exception) {
            buildJsonObject {
                put("success", false)
                put("error", "mail_operation_failed")
                put("message", "Email operation failed. Check the connected account and server settings.")
            }
        }

    private fun getEmailTools(): List<Tool> = listOf(
        Tool(
            name = "setup_email",
            description = "Guide the user to Settings > Email Integration to connect an email account securely.",
            parameters = { InputSchema.Obj(properties = buildJsonObject {}) },
            execute = {
                buildJsonObject {
                    put("message", "Open Settings > Email Integration to connect your account. Use an app password where supported; never paste passwords into chat.")
                }
            },
        ),
        Tool(
            name = "check_email",
            description = "Check connected email inboxes for unread messages.",
            parameters = { InputSchema.Obj(properties = buildJsonObject {
                put("account", buildJsonObject { put("type", "string"); put("description", "Account email address when multiple accounts are connected") })
                put("limit", buildJsonObject { put("type", "integer"); put("description", "Maximum number of messages, 1 to 25") })
            }) },
            execute = { args ->
                val obj = args.jsonObject
                emailSafe {
                    nativeEmailService.check(
                        address = obj["account"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                        limit = obj["limit"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 10,
                    )
                }
            },
        ),
        Tool(
            name = "search_email",
            description = "Search connected inbox messages by sender, subject, or body text.",
            parameters = { InputSchema.Obj(properties = buildJsonObject {
                put("account", buildJsonObject { put("type", "string"); put("description", "Account email address when multiple accounts are connected") })
                put("query", buildJsonObject { put("type", "string"); put("description", "Search text") })
                put("limit", buildJsonObject { put("type", "integer"); put("description", "Maximum results, 1 to 25") })
            }, required = listOf("query")) },
            execute = { args ->
                val obj = args.jsonObject
                emailSafe {
                    nativeEmailService.search(
                        address = obj["account"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                        query = obj["query"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                        limit = obj["limit"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 10,
                    )
                }
            },
        ),
        Tool(
            name = "read_email",
            description = "Read a message by the IMAP UID returned by check_email or search_email.",
            parameters = { InputSchema.Obj(properties = buildJsonObject {
                put("account", buildJsonObject { put("type", "string"); put("description", "Account email address when multiple accounts are connected") })
                put("uid", buildJsonObject { put("type", "integer"); put("description", "Message UID") })
            }, required = listOf("uid")) },
            execute = { args ->
                val obj = args.jsonObject
                emailSafe {
                    nativeEmailService.read(
                        address = obj["account"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                        uid = obj["uid"]?.jsonPrimitive?.contentOrNull?.toLongOrNull() ?: 0L,
                    )
                }
            },
        ),
        Tool(
            name = "compose_email",
            description = "Send an email from a connected account. Requires explicit user approval for each send.",
            parameters = { InputSchema.Obj(properties = buildJsonObject {
                put("account", buildJsonObject { put("type", "string"); put("description", "Sender account address when multiple accounts are connected") })
                put("to", buildJsonObject { put("type", "string"); put("description", "Recipient email address or comma-separated addresses") })
                put("subject", buildJsonObject { put("type", "string"); put("description", "Email subject") })
                put("body", buildJsonObject { put("type", "string"); put("description", "Email body") })
            }, required = listOf("to", "subject", "body")) },
            approvalMode = ToolApprovalMode.RequiresApproval,
            execute = { args ->
                val obj = args.jsonObject
                emailSafe {
                    nativeEmailService.send(
                        address = obj["account"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                        to = obj["to"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                        subject = obj["subject"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                        body = obj["body"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                    )
                }
            },
        ),
        Tool(
            name = "reply_email",
            description = "Reply to an email UID from a connected account. Requires explicit user approval before sending.",
            parameters = { InputSchema.Obj(properties = buildJsonObject {
                put("account", buildJsonObject { put("type", "string"); put("description", "Account email address when multiple accounts are connected") })
                put("uid", buildJsonObject { put("type", "integer"); put("description", "Original message UID") })
                put("to", buildJsonObject { put("type", "string"); put("description", "Optional recipient override") })
                put("subject", buildJsonObject { put("type", "string"); put("description", "Optional subject override") })
                put("body", buildJsonObject { put("type", "string"); put("description", "Reply body") })
            }, required = listOf("uid", "body")) },
            approvalMode = ToolApprovalMode.RequiresApproval,
            execute = { args ->
                val obj = args.jsonObject
                emailSafe {
                    nativeEmailService.send(
                        address = obj["account"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                        to = obj["to"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                        subject = obj["subject"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                        body = obj["body"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                        replyUid = obj["uid"]?.jsonPrimitive?.contentOrNull?.toLongOrNull() ?: 0L,
                    )
                }
            },
        ),
    )

    /**
     * Get all enabled local tools for the conversation.
     */
    fun getTools(
''',
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/data/ai/tools/LocalTools.kt",
    "        if (options.contains(LocalToolOption.ImageGeneration)) {\n            tools.add(imageGenerationTool)\n        }\n        return tools\n",
    "        if (options.contains(LocalToolOption.ImageGeneration)) {\n            tools.add(imageGenerationTool)\n        }\n        if (options.contains(LocalToolOption.Email)) {\n            tools.addAll(getEmailTools())\n        }\n        return tools\n",
)

# Assistant settings toggle for email tools.
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/assistant/detail/AssistantLocalToolSubPage.kt",
    "        LocalToolCard(\n            title = stringResource(R.string.assistant_page_local_tools_image_generation_title),",
    '''        LocalToolCard(
            title = stringResource(R.string.assistant_page_local_tools_email_title),
            description = stringResource(R.string.assistant_page_local_tools_email_desc),
            isEnabled = assistant.localTools.contains(LocalToolOption.Email),
            onToggle = { enabled ->
                val next = if (enabled) assistant.localTools + LocalToolOption.Email
                    else assistant.localTools - LocalToolOption.Email
                onUpdate(assistant.copy(localTools = next))
            },
        )

        LocalToolCard(
            title = stringResource(R.string.assistant_page_local_tools_image_generation_title),''',
)
replace_once(
    "app/src/main/res/values/strings.xml",
    '    <string name="setting_android_integration">Android Integration</string>',
    '    <string name="setting_email_integration">Email Integration</string>\n    <string name="setting_android_integration">Android Integration</string>',
)
replace_once(
    "app/src/main/res/values/strings.xml",
    '    <string name="assistant_page_local_tools_image_generation_title">',
    '    <string name="assistant_page_local_tools_email_title">Email</string>\n    <string name="assistant_page_local_tools_email_desc">Read and search inboxes; outgoing messages require approval.</string>\n    <string name="assistant_page_local_tools_image_generation_title">',
)

# Register the page in the type-safe app navigation.
replace_once(
    "app/src/main/java/me/rerere/rikkahub/RouteActivity.kt",
    "import me.rerere.rikkahub.ui.pages.setting.SettingAndroidIntegrationPage\n",
    "import me.rerere.rikkahub.ui.pages.setting.SettingAndroidIntegrationPage\nimport me.rerere.rikkahub.ui.pages.setting.SettingEmailIntegrationPage\n",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/RouteActivity.kt",
    "                    composable<Screen.SettingAndroidIntegration> {\n",
    '''                    composable<Screen.SettingEmailIntegration> {
                        AdaptiveSettingsScaffold(selected = SettingsDestination.EmailIntegration) {
                            SettingEmailIntegrationPage()
                        }
                    }

                    composable<Screen.SettingAndroidIntegration> {
''',
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/RouteActivity.kt",
    "    @Serializable\n    data object SettingAndroidIntegration : Screen\n",
    "    @Serializable\n    data object SettingEmailIntegration : Screen\n\n    @Serializable\n    data object SettingAndroidIntegration : Screen\n",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/SettingPage.kt",
    "                    SettingGroupItem(\n                        title = stringResource(R.string.setting_android_integration),",
    '''                    SettingGroupItem(
                        title = stringResource(R.string.setting_email_integration),
                        icon = { Icon(Icons.Rounded.Cloud, null, modifier = Modifier.size(20.dp)) },
                        contentPadding = mainSettingItemPadding,
                        onClick = { navController.navigate(Screen.SettingEmailIntegration) }
                    )

                    SettingGroupItem(
                        title = stringResource(R.string.setting_android_integration),''',
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/SettingsAdaptiveScaffold.kt",
    "    Web,\n    AndroidIntegration,\n",
    "    Web,\n    EmailIntegration,\n    AndroidIntegration,\n",
)
replace_once(
    "app/src/main/java/me/rerere/rikkahub/ui/pages/setting/SettingsAdaptiveScaffold.kt",
    "                SettingsPaneEntry(SettingsDestination.Web, R.string.setting_page_web_server, null, Icons.Rounded.Language, Screen.SettingWeb),\n",
    "                SettingsPaneEntry(SettingsDestination.Web, R.string.setting_page_web_server, null, Icons.Rounded.Language, Screen.SettingWeb),\n                SettingsPaneEntry(SettingsDestination.EmailIntegration, R.string.setting_email_integration, null, Icons.Rounded.Cloud, Screen.SettingEmailIntegration),\n",
)
print("PASS: native IMAP/SMTP integration, encrypted account settings, assistant email tools, send approval, and settings navigation are installed.")

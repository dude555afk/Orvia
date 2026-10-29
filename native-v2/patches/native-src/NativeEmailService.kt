package me.rerere.rikkahub.data.integration

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import java.util.Date
import java.util.Properties
import javax.mail.*
import javax.mail.internet.InternetAddress
import javax.mail.internet.MimeMessage
import javax.mail.search.*
import com.sun.mail.imap.IMAPFolder
import com.sun.mail.imap.IMAPStore

/**
 * Native IMAP/SMTP for Orvia. Credentials and mailbox cursors are encrypted
 * at rest and this service is deliberately independent of MCP.
 */
class NativeEmailService(context: Context) {
    private val appContext = context.applicationContext

    @Suppress("DEPRECATION")
    private val preferences: SharedPreferences by lazy {
        val key = MasterKey.Builder(appContext)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            appContext, "orvia_native_email", key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    data class Account(
        val address: String,
        val password: String,
        val imapHost: String,
        val imapPort: Int = 993,
        val smtpHost: String,
        val smtpPort: Int = 465,
        val smtpStartTls: Boolean = false,
    ) {
        fun validate() {
            require(NativeEmailService.EMAIL.matches(address.trim())) { "Enter a valid email address." }
            require(password.isNotBlank()) { "An app password is required." }
            listOf(imapHost, smtpHost).forEach { host ->
                require(NativeEmailService.HOST.matches(host) && !host.startsWith("-") && !host.contains("..")) {
                    "Mail server host is invalid."
                }
            }
            require(imapPort in 1..65535 && smtpPort in 1..65535) { "Mail server port is invalid." }
        }

        fun toJson() = buildJsonObject {
            put("address", address); put("password", password)
            put("imapHost", imapHost); put("imapPort", imapPort)
            put("smtpHost", smtpHost); put("smtpPort", smtpPort)
            put("smtpStartTls", smtpStartTls)
        }

        fun publicJson() = buildJsonObject {
            put("address", address); put("imapHost", imapHost); put("imapPort", imapPort)
            put("smtpHost", smtpHost); put("smtpPort", smtpPort)
            put("smtpStartTls", smtpStartTls); put("passwordSaved", password.isNotBlank())
        }

        companion object {
            fun fromJson(o: JsonObject): Account {
                fun str(key: String, default: String = ""): String =
                    (o[key] as? JsonPrimitive)?.content ?: default
                fun int(key: String, default: Int): Int =
                    (o[key] as? JsonPrimitive)?.content?.toIntOrNull() ?: default
                fun bool(key: String, default: Boolean): Boolean =
                    (o[key] as? JsonPrimitive)?.content?.toBooleanStrictOrNull() ?: default
                return Account(
                    address = str("address"),
                    password = str("password"),
                    imapHost = str("imapHost"),
                    imapPort = int("imapPort", 993),
                    smtpHost = str("smtpHost"),
                    smtpPort = int("smtpPort", 465),
                    smtpStartTls = bool("smtpStartTls", false),
                )
            }

            fun forAddress(address: String, password: String): Account {
                val domain = address.substringAfterLast("@", "").trim().lowercase()
                val account = when (domain) {
                    "gmail.com", "googlemail.com" ->
                        Account(address.trim(), password, "imap.gmail.com", smtpHost = "smtp.gmail.com")
                    "outlook.com", "hotmail.com", "live.com" ->
                        Account(address.trim(), password, "outlook.office365.com", smtpPort = 587, smtpHost = "smtp.office365.com", smtpStartTls = true)
                    "yahoo.com" ->
                        Account(address.trim(), password, "imap.mail.yahoo.com", smtpHost = "smtp.mail.yahoo.com")
                    "icloud.com", "me.com" ->
                        Account(address.trim(), password, "imap.mail.me.com", smtpPort = 587, smtpHost = "smtp.mail.me.com", smtpStartTls = true)
                    else -> Account(address.trim(), password, "imap.$domain", smtpHost = "smtp.$domain")
                }
                account.validate()
                return account
            }
        }
    }

    private fun loadAccounts(): List<Account> {
        val raw = preferences.getString(KEY_ACCOUNTS, null) ?: return emptyList()
        return runCatching {
            (Json.parseToJsonElement(raw) as JsonArray)
                .mapNotNull { (it as? JsonObject)?.let(Account::fromJson) }
        }.getOrElse { emptyList() }
    }

    private fun saveAccounts(accounts: List<Account>) {
        preferences.edit().putString(KEY_ACCOUNTS, JsonArray(accounts.map(Account::toJson)).toString()).apply()
    }

    suspend fun listAccounts(): List<JsonObject> = withContext(Dispatchers.IO) {
        loadAccounts().map(Account::publicJson)
    }

    suspend fun connect(account: Account): JsonObject = withContext(Dispatchers.IO) {
        account.validate()
        // Verify both incoming and outgoing credentials before persisting.
        withInbox(account, Folder.READ_ONLY) { _, _ -> Unit }
        val transport = smtpSession(account).getTransport("smtp")
        try {
            transport.connect(account.smtpHost, account.smtpPort, account.address, account.password)
        } finally {
            runCatching { transport.close() }
        }
        saveAccounts(loadAccounts().filterNot { it.address.equals(account.address, true) } + account)
        buildJsonObject {
            put("success", true); put("message", "Email account connected securely.")
            put("account", account.address)
        }
    }

    suspend fun remove(address: String): JsonObject = withContext(Dispatchers.IO) {
        saveAccounts(loadAccounts().filterNot { it.address.equals(address.trim(), true) })
        preferences.edit().remove(cursorKey(address)).apply()
        buildJsonObject { put("success", true); put("removed", address.trim()) }
    }

    suspend fun check(address: String = "", limit: Int = 10): JsonObject = withContext(Dispatchers.IO) {
        val messages = mutableListOf<JsonObject>()
        val errors = mutableListOf<String>()
        for (account in resolve(address)) {
            try {
                withInbox(account, Folder.READ_ONLY) { folder, _ ->
                    val uidFolder = folder as IMAPFolder
                    folder.search(FlagTerm(Flags(Flags.Flag.SEEN), false))
                        .sortedByDescending { runCatching { uidFolder.getUID(it) }.getOrDefault(0L) }
                        .take(limit.coerceIn(1, 25))
                        .forEach { messages += summary(it, uidFolder, account.address) }
                }
            } catch (_: Exception) {
                errors += "Could not read inbox for " + account.address + ". Check the server and app password."
            }
        }
        buildJsonObject {
            put("success", errors.isEmpty()); put("count", messages.size)
            put("messages", JsonArray(messages))
            if (errors.isNotEmpty()) put("errors", JsonArray(errors.map { JsonPrimitive(it) }))
        }
    }

    suspend fun search(address: String = "", query: String, limit: Int = 10): JsonObject =
        withContext(Dispatchers.IO) {
            require(query.trim().length in 1..200) { "Search query must contain 1 to 200 characters." }
            val results = mutableListOf<JsonObject>()
            val errors = mutableListOf<String>()
            for (account in resolve(address)) {
                try {
                    withInbox(account, Folder.READ_ONLY) { folder, _ ->
                        val uidFolder = folder as IMAPFolder
                        val term = OrTerm(
                            OrTerm(SubjectTerm(query.trim()), FromStringTerm(query.trim())),
                            BodyTerm(query.trim()),
                        )
                        folder.search(term)
                            .sortedByDescending { runCatching { uidFolder.getUID(it) }.getOrDefault(0L) }
                            .take(limit.coerceIn(1, 25))
                            .forEach { results += summary(it, uidFolder, account.address) }
                    }
                } catch (_: Exception) { errors += "Search failed for " + account.address + "." }
            }
            buildJsonObject {
                put("success", errors.isEmpty()); put("count", results.size)
                put("messages", JsonArray(results))
                if (errors.isNotEmpty()) put("errors", JsonArray(errors.map(::JsonPrimitive)))
            }
        }

    suspend fun read(address: String = "", uid: Long): JsonObject = withContext(Dispatchers.IO) {
        require(uid > 0) { "Message UID must be positive." }
        val account = resolve(address).first()
        withInbox(account, Folder.READ_ONLY) { folder, _ ->
            val message = (folder as IMAPFolder).getMessageByUID(uid)
                ?: throw IllegalArgumentException("Message UID was not found.")
            buildJsonObject {
                put("success", true); put("account", account.address); put("uid", uid)
                put("from", message.from?.joinToString(", ") { it.toString() }.orEmpty())
                put("to", message.getRecipients(Message.RecipientType.TO)?.joinToString(", ") { it.toString() }.orEmpty())
                put("subject", message.subject.orEmpty())
                put("date", message.sentDate?.toInstant()?.toString().orEmpty())
                put("body", extractText(message).take(MAX_BODY_CHARS))
            }
        }
    }

    suspend fun send(
        address: String = "",
        to: String,
        subject: String,
        body: String,
        replyUid: Long? = null,
    ): JsonObject = withContext(Dispatchers.IO) {
        val account = resolve(address).first()
        require(to.length <= 1000 && !to.contains('\r') && !to.contains('\n')) {
            "Recipient email address is invalid."
        }
        if (replyUid == null) {
            require(to.isNotBlank() && to.split(",").all { EMAIL.matches(it.trim()) }) {
                "Recipient email address is invalid."
            }
        } else if (to.isNotBlank()) {
            require(to.split(",").all { EMAIL.matches(it.trim()) }) { "Recipient email address is invalid." }
        }
        require(subject.length <= 998 && !subject.contains('\r') && !subject.contains('\n')) {
            "Subject is invalid."
        }
        require(body.length <= MAX_BODY_CHARS) { "Email body is too long." }
        val session = smtpSession(account)
        val message: MimeMessage = if (replyUid == null) {
            MimeMessage(session).apply {
                setFrom(InternetAddress(account.address))
                setRecipients(Message.RecipientType.TO, InternetAddress.parse(to, true))
                setSubject(subject, "UTF-8"); setText(body, "UTF-8"); sentDate = Date()
            }
        } else {
            val original = withInbox(account, Folder.READ_ONLY) { folder, _ ->
                (folder as IMAPFolder).getMessageByUID(replyUid)
                    ?: throw IllegalArgumentException("Original message UID was not found.")
            }
            val reply = (original as? MimeMessage)?.reply(false) as? MimeMessage
                ?: throw IllegalStateException("Unable to construct a reply message.")
            reply.setFrom(InternetAddress(account.address))
            if (to.isNotBlank()) reply.setRecipients(Message.RecipientType.TO, InternetAddress.parse(to, true))
            if (subject.isNotBlank()) reply.setSubject(subject, "UTF-8")
            reply.setText(body, "UTF-8"); reply.sentDate = Date()
            reply
        }
        message.saveChanges()
        val transport = session.getTransport("smtp")
        try {
            transport.connect(account.smtpHost, account.smtpPort, account.address, account.password)
            transport.sendMessage(message, message.allRecipients)
        } finally {
            runCatching { transport.close() }
        }
        buildJsonObject {
            put("success", true); put("status", "sent"); put("account", account.address)
            put("to", message.getRecipients(Message.RecipientType.TO)?.joinToString(", ") { it.toString() }.orEmpty())
            put("subject", message.subject.orEmpty())
        }
    }

    private fun resolve(address: String): List<Account> {
        val all = loadAccounts()
        require(all.isNotEmpty()) { "Connect email in Settings > Integrations > Email first." }
        if (address.isBlank()) {
            require(all.size == 1) { "Choose an account address because multiple email accounts are connected." }
            return all
        }
        return listOf(all.firstOrNull { it.address.equals(address.trim(), true) }
            ?: throw IllegalArgumentException("No connected account matches that address."))
    }

    private fun <T> withInbox(account: Account, mode: Int, action: (Folder, IMAPStore) -> T): T {
        val properties = Properties().apply {
            put("mail.store.protocol", "imaps"); put("mail.imaps.ssl.enable", "true")
            put("mail.imaps.connectiontimeout", "12000"); put("mail.imaps.timeout", "20000")
            put("mail.imaps.ssl.checkserveridentity", "true")
            put("mail.imaps.peek", "true"); put("mail.imaps.partialfetch", "false")
        }
        val session = Session.getInstance(properties)
        val store = session.getStore("imaps") as IMAPStore
        try {
            store.connect(account.imapHost, account.imapPort, account.address, account.password)
            val inbox = store.getFolder("INBOX")
            inbox.open(mode)
            return try { action(inbox, store) } finally { inbox.close(false) }
        } finally { runCatching { store.close() } }
    }

    private fun smtpSession(account: Account): Session {
        val properties = Properties().apply {
            put("mail.transport.protocol", "smtp"); put("mail.smtp.auth", "true")
            put("mail.smtp.connectiontimeout", "12000"); put("mail.smtp.timeout", "20000")
            put("mail.smtp.writetimeout", "20000")
            put("mail.smtp.ssl.checkserveridentity", "true")
            if (account.smtpStartTls) {
                put("mail.smtp.ssl.enable", "false"); put("mail.smtp.starttls.enable", "true")
                put("mail.smtp.starttls.required", "true")
            } else put("mail.smtp.ssl.enable", "true")
        }
        return Session.getInstance(properties)
    }

    private fun summary(message: Message, folder: IMAPFolder, account: String) = buildJsonObject {
        put("account", account); put("uid", folder.getUID(message))
        put("from", message.from?.joinToString(", ") { it.toString() }.orEmpty())
        put("subject", message.subject.orEmpty()); put("date", message.sentDate?.toInstant()?.toString().orEmpty())
        put("unread", !(message.flags?.contains(Flags.Flag.SEEN) ?: false))
    }

    private fun extractText(part: Part): String {
        if (Part.ATTACHMENT.equals(part.disposition, ignoreCase = true)) return ""
        return try {
            when {
                part.isMimeType("text/plain") -> part.content as? String ?: ""
                part.isMimeType("multipart/*") -> {
                    val multipart = part.content as? Multipart ?: return ""
                    (0 until multipart.count).asSequence().map { multipart.getBodyPart(it) }
                        .filterNot { Part.ATTACHMENT.equals(it.disposition, ignoreCase = true) }
                        .map(::extractText).firstOrNull { it.isNotBlank() }.orEmpty()
                }
                else -> ""
            }
        } catch (_: Exception) { "" }
    }

    private fun cursorKey(address: String) = "cursor_" + address.trim().lowercase()

    companion object {
        private const val KEY_ACCOUNTS = "accounts_json"
        private const val MAX_BODY_CHARS = 100_000
        private val EMAIL = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")
        private val HOST = Regex("^[A-Za-z0-9.-]+$")
    }
}

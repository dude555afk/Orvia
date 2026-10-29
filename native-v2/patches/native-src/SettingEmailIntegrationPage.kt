package me.rerere.rikkahub.ui.pages.setting

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import me.rerere.rikkahub.data.integration.NativeEmailService
import me.rerere.rikkahub.ui.components.nav.BackButton
import me.rerere.rikkahub.ui.components.nav.OneUITopAppBar
import me.rerere.rikkahub.ui.theme.AppShapes

@Composable
fun SettingEmailIntegrationPage() {
    val context = LocalContext.current
    val service = remember(context) { NativeEmailService(context) }
    val scope = rememberCoroutineScope()
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    var address by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var imapHost by remember { mutableStateOf("") }
    var imapPort by remember { mutableStateOf("") }
    var smtpHost by remember { mutableStateOf("") }
    var smtpPort by remember { mutableStateOf("") }
    var smtpStartTls by remember { mutableStateOf(false) }
    var accounts by remember { mutableStateOf(emptyList<kotlinx.serialization.json.JsonObject>()) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }

    LaunchedEffect(service) { accounts = service.listAccounts() }

    Scaffold(
        topBar = {
            OneUITopAppBar(
                title = "Email Integration",
                scrollBehavior = scrollBehavior,
                navigationIcon = { BackButton() },
            )
        },
        modifier = Modifier.fillMaxSize(),
    ) { insets ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(insets),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        "Connect an email account for inbox search, reading, replies, and sending.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        "Use an app password where your provider supports it. Credentials are stored in Android encrypted preferences. IMAP uses TLS; SMTP uses TLS or STARTTLS.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedTextField(
                        value = address, onValueChange = { address = it },
                        label = { Text("Email address") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                        modifier = Modifier.fillMaxWidth(), shape = AppShapes.InputField,
                    )
                    OutlinedTextField(
                        value = password, onValueChange = { password = it },
                        label = { Text("App password") }, singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        modifier = Modifier.fillMaxWidth(), shape = AppShapes.InputField,
                    )
                    Text("Optional: custom mail servers", style = MaterialTheme.typography.titleSmall)
                    OutlinedTextField(
                        value = imapHost, onValueChange = { imapHost = it },
                        label = { Text("IMAP host") }, singleLine = true,
                        modifier = Modifier.fillMaxWidth(), shape = AppShapes.InputField,
                    )
                    OutlinedTextField(
                        value = imapPort, onValueChange = { imapPort = it.filter(Char::isDigit).take(5) },
                        label = { Text("IMAP port (default 993)") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth(), shape = AppShapes.InputField,
                    )
                    OutlinedTextField(
                        value = smtpHost, onValueChange = { smtpHost = it },
                        label = { Text("SMTP host") }, singleLine = true,
                        modifier = Modifier.fillMaxWidth(), shape = AppShapes.InputField,
                    )
                    OutlinedTextField(
                        value = smtpPort, onValueChange = { smtpPort = it.filter(Char::isDigit).take(5) },
                        label = { Text("SMTP port (default 465)") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth(), shape = AppShapes.InputField,
                    )
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Use SMTP STARTTLS", style = MaterialTheme.typography.bodyMedium)
                            Text("Enable for servers on port 587.", style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Switch(checked = smtpStartTls, onCheckedChange = { smtpStartTls = it })
                    }
                    Button(
                        enabled = !busy && address.isNotBlank() && password.isNotBlank(),
                        onClick = {
                            scope.launch {
                                busy = true
                                message = ""
                                try {
                                    val defaults = NativeEmailService.Account.forAddress(address, password)
                                    val custom = imapHost.isNotBlank() || imapPort.isNotBlank() ||
                                        smtpHost.isNotBlank() || smtpPort.isNotBlank()
                                    val account = if (!custom) defaults else defaults.copy(
                                        imapHost = imapHost.ifBlank { defaults.imapHost },
                                        imapPort = imapPort.toIntOrNull() ?: defaults.imapPort,
                                        smtpHost = smtpHost.ifBlank { defaults.smtpHost },
                                        smtpPort = smtpPort.toIntOrNull() ?: defaults.smtpPort,
                                        smtpStartTls = smtpStartTls,
                                    )
                                    service.connect(account)
                                    password = ""
                                    accounts = service.listAccounts()
                                    message = "Connected: " + account.address
                                } catch (error: Exception) {
                                    message = error.message?.take(180) ?: "Connection failed. Check account settings."
                                } finally { busy = false }
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text(if (busy) "Connecting…" else "Test and save account") }
                    if (message.isNotBlank()) {
                        Text(message, style = MaterialTheme.typography.bodyMedium,
                            color = if (message.startsWith("Connected:")) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.error)
                    }
                }
            }
            item {
                Text("Connected accounts", style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(horizontal = 16.dp))
            }
            if (accounts.isEmpty()) {
                item {
                    Text("No email account connected yet.", modifier = Modifier.padding(horizontal = 16.dp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            items(accounts, key = { it["address"]?.jsonPrimitive?.contentOrNull.orEmpty() }) { account ->
                val savedAddress = account["address"]?.jsonPrimitive?.contentOrNull.orEmpty()
                Card(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                ) {
                    Row(modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 12.dp, bottom = 12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(savedAddress, style = MaterialTheme.typography.titleSmall)
                            Text("Encrypted on this device", style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        TextButton(onClick = {
                            scope.launch {
                                service.remove(savedAddress)
                                accounts = service.listAccounts()
                                message = "Removed " + savedAddress
                            }
                        }) { Text("Remove") }
                    }
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

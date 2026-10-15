package com.dude555afk.orvia.nativev2

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

private val Background = Color(0xFF0D1015)
private val Surface = Color(0xFF1A2028)
private val Accent = Color(0xFF9BB8FF)
private val TextPrimary = Color(0xFFF2F4FA)

private data class ChatMessage(val body: String, val fromUser: Boolean)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { OrviaPreview() }
    }
}

@Composable
private fun OrviaPreview() {
    var draft by remember { mutableStateOf("") }
    val messages = remember { mutableStateListOf<ChatMessage>() }
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Accent,
            background = Background,
            surface = Surface,
            onBackground = TextPrimary,
            onSurface = TextPrimary
        )
    ) {
        Scaffold(containerColor = Background, topBar = {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = { }) {
                    Icon(Icons.Default.Menu, contentDescription = "Menu")
                }
                Text("Orvia", modifier = Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                Text("Native preview", style = MaterialTheme.typography.labelSmall, color = Accent)
                IconButton(onClick = { }) {
                    Icon(Icons.Default.MoreVert, contentDescription = "More")
                }
            }
        }, bottomBar = {
            Row(
                modifier = Modifier.fillMaxWidth().padding(12.dp)
                    .background(Surface, RoundedCornerShape(28.dp)).padding(6.dp),
                verticalAlignment = Alignment.Bottom
            ) {
                IconButton(onClick = { }) {
                    Icon(Icons.Default.Add, contentDescription = "Attach")
                }
                TextField(
                    value = draft,
                    onValueChange = { draft = it },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("Message Orvia") },
                    maxLines = 5,
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = Surface,
                        unfocusedContainerColor = Surface,
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent
                    )
                )
                IconButton(
                    enabled = draft.isNotBlank(),
                    onClick = {
                        messages.add(ChatMessage(draft.trim(), true))
                        draft = ""
                    }
                ) {
                    Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send", tint = if (draft.isNotBlank()) Accent else Color.Gray)
                }
            }
        }) { padding ->
            if (messages.isEmpty()) {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("Orvia", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(8.dp))
                        Text("A more expressive way to chat", color = Color.LightGray)
                        Text("Local UI prototype • No AI connected", style = MaterialTheme.typography.labelSmall, color = Accent)
                    }
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    items(messages) { message ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = if (message.fromUser) Arrangement.End else Arrangement.Start) {
                            Surface(shape = RoundedCornerShape(20.dp), color = Surface) {
                                Text(message.body, modifier = Modifier.padding(14.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}

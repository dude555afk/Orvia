package me.rerere.rikkahub.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * Lightweight one-shot launch overlay for Orvia.
 *
 * The mark is drawn with Compose Canvas: no bitmap animation, Lottie payload,
 * or additional runtime dependency is required.
 */
@Composable
fun OrviaOrbitalSplash(onDismiss: () -> Unit) {
    val progress = remember { Animatable(0f) }

    LaunchedEffect(Unit) {
        progress.animateTo(
            targetValue = 1f,
            animationSpec = tween(durationMillis = 1_050, easing = FastOutSlowInEasing),
        )
        delay(220)
        onDismiss()
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0xFF080B12)),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Canvas(Modifier.size(224.dp)) {
                    val p = progress.value.coerceIn(0f, 1f)
                    val c = center
                    val radius = size.minDimension * 0.31f
                    val cyan = Color(0xFF65E3FF)
                    val violet = Color(0xFF9D8CFF)
                    val mint = Color(0xFF83E8D0)

                    drawCircle(
                        brush = Brush.radialGradient(
                            colors = listOf(cyan.copy(alpha = 0.30f * p), Color.Transparent),
                            center = c,
                            radius = radius * 1.65f,
                        ),
                        radius = radius * 1.65f,
                        center = c,
                    )

                    val orbitAlpha = 0.26f + (0.54f * p)
                    listOf(-52f, 52f, 90f).forEachIndexed { index, angle ->
                        rotate(degrees = angle, pivot = c) {
                            drawOval(
                                color = listOf(cyan, violet, mint)[index].copy(alpha = orbitAlpha),
                                topLeft = Offset(c.x - radius, c.y - radius * 0.38f),
                                size = Size(radius * 2f, radius * 0.76f),
                                style = Stroke(width = 1.5.dp.toPx()),
                            )
                        }
                    }

                    // Three particles spiral inward and settle on the orbital mark.
                    repeat(3) { index ->
                        val angle = (p * 2.35f * PI.toFloat()) + (index * 2f * PI.toFloat() / 3f)
                        val orbitRadius = radius * (1.58f - 0.46f * p)
                        val point = Offset(
                            x = c.x + cos(angle) * orbitRadius,
                            y = c.y + sin(angle) * orbitRadius * 0.62f,
                        )
                        drawCircle(
                            color = listOf(cyan, violet, mint)[index].copy(alpha = 0.45f + 0.55f * p),
                            radius = (3.3f - 0.5f * p).dp.toPx(),
                            center = point,
                        )
                    }

                    drawCircle(
                        color = Color.White.copy(alpha = 0.88f * p),
                        radius = (7f + 5f * p).dp.toPx(),
                        center = c,
                    )
                    drawCircle(
                        color = cyan.copy(alpha = 0.85f * p),
                        radius = (3f + 2f * p).dp.toPx(),
                        center = c,
                    )
                }

                Spacer(Modifier.height(4.dp))
                Text(
                    text = "ORVIA",
                    color = Color(0xFFF5F7FF),
                    fontSize = 20.sp,
                    letterSpacing = 5.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(Modifier.height(26.dp))
                TextButton(
                    onClick = onDismiss,
                    modifier = Modifier.alpha(0.78f),
                ) {
                    Text(
                        text = "Skip intro",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

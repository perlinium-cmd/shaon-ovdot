package com.perlinium.shaon.employee.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.sp
import com.perlinium.shaon.employee.R

/*
 * Design language — same brand as the website and ShaonMac:
 *  - Teal = start / positive ("כניסה", earned).  Orange = stop ("יציאה").  Green dot = live, at work now.
 *  - State is never carried by color alone: every state also has its own icon shape (▶ / ■) and a word.
 *  - Numbers use tabular digits, so the running clock never jiggles.
 *  - Spacing on a 4/8dp grid; touch targets ≥ 48dp, the main button ~200dp (Fitts's law: big + close to the thumb).
 */

@OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
private fun heebo(w: Int) = Font(R.font.heebo, FontWeight(w), variationSettings = FontVariation.Settings(FontVariation.weight(w)))
val Heebo = FontFamily(heebo(400), heebo(500), heebo(700), heebo(800), heebo(900))

@Immutable
data class ShaonColors(
    val start: Color, val onStart: Color, val startSoft: Color, val onStartSoft: Color,
    val stop: Color, val onStop: Color, val stopSoft: Color, val onStopSoft: Color,
    val live: Color, val warnSoft: Color, val onWarnSoft: Color, val dangerSoft: Color, val onDangerSoft: Color,
)

private val LightExtra = ShaonColors(
    start = Color(0xFF0F766E), onStart = Color.White, startSoft = Color(0xFFE3F3F1), onStartSoft = Color(0xFF0B5B55),
    stop = Color(0xFFC2410C), onStop = Color.White, stopSoft = Color(0xFFFDEEE6), onStopSoft = Color(0xFF8F2F08),
    live = Color(0xFF16A34A), warnSoft = Color(0xFFFFF4DC), onWarnSoft = Color(0xFF7A4A00),
    dangerSoft = Color(0xFFFDECEA), onDangerSoft = Color(0xFF9A1C13),
)
private val DarkExtra = ShaonColors(
    start = Color(0xFF2BC4B1), onStart = Color(0xFF032B27), startSoft = Color(0xFF133331), onStartSoft = Color(0xFF7FE3D5),
    stop = Color(0xFFFB8A4C), onStop = Color(0xFF2B1205), stopSoft = Color(0xFF3A2116), onStopSoft = Color(0xFFFFC7A6),
    live = Color(0xFF4ADE80), warnSoft = Color(0xFF33270F), onWarnSoft = Color(0xFFF5C46B),
    dangerSoft = Color(0xFF3A1A18), onDangerSoft = Color(0xFFFFB4AB),
)

private val Light: ColorScheme = lightColorScheme(
    primary = Color(0xFF0F766E), onPrimary = Color.White, primaryContainer = Color(0xFFE3F3F1), onPrimaryContainer = Color(0xFF0B5B55),
    secondary = Color(0xFF3F5F5C), onSecondary = Color.White, secondaryContainer = Color(0xFFDCE8E6), onSecondaryContainer = Color(0xFF142B29),
    tertiary = Color(0xFFC2410C), onTertiary = Color.White,
    background = Color(0xFFF4F6F6), onBackground = Color(0xFF12201F),
    surface = Color(0xFFF4F6F6), onSurface = Color(0xFF12201F),
    surfaceContainerLowest = Color.White, surfaceContainerLow = Color(0xFFFBFCFC), surfaceContainer = Color.White,
    surfaceContainerHigh = Color(0xFFEEF3F2), surfaceContainerHighest = Color(0xFFE6EDEC),
    onSurfaceVariant = Color(0xFF52625F), outline = Color(0xFFB8C4C2), outlineVariant = Color(0xFFDCE4E3),
    error = Color(0xFFB42318), onError = Color.White,
    inversePrimary = Color(0xFF7FE3D5),   // "undo" on the dark snackbar
)
private val Dark: ColorScheme = darkColorScheme(
    primary = Color(0xFF2BC4B1), onPrimary = Color(0xFF032B27), primaryContainer = Color(0xFF133331), onPrimaryContainer = Color(0xFF7FE3D5),
    secondary = Color(0xFFA7C8C4), onSecondary = Color(0xFF0E2422), secondaryContainer = Color(0xFF243634), onSecondaryContainer = Color(0xFFDCE8E6),
    tertiary = Color(0xFFFB8A4C), onTertiary = Color(0xFF2B1205),
    background = Color(0xFF0E1414), onBackground = Color(0xFFE6EFEE),
    surface = Color(0xFF0E1414), onSurface = Color(0xFFE6EFEE),
    surfaceContainerLowest = Color(0xFF0A0F0F), surfaceContainerLow = Color(0xFF131B1B), surfaceContainer = Color(0xFF172020),
    surfaceContainerHigh = Color(0xFF1D2827), surfaceContainerHighest = Color(0xFF243130),
    onSurfaceVariant = Color(0xFFA3B3B1), outline = Color(0xFF4A5B59), outlineVariant = Color(0xFF2A3736),
    error = Color(0xFFF97066), onError = Color(0xFF3A0905),
    inversePrimary = Color(0xFF0B5B55),   // "undo" on the light snackbar
)

val LocalShaon = staticCompositionLocalOf { LightExtra }

private fun t(size: Int, weight: Int, line: Int, tnum: Boolean = false) = TextStyle(
    fontFamily = Heebo, fontWeight = FontWeight(weight), fontSize = size.sp, lineHeight = line.sp,
    fontFeatureSettings = if (tnum) "tnum" else null,
)

private val Type = Typography(
    displayLarge = t(64, 900, 72, tnum = true),     // the running clock
    displayMedium = t(44, 900, 52, tnum = true),
    headlineLarge = t(30, 800, 38),
    headlineMedium = t(26, 800, 34),
    headlineSmall = t(22, 800, 30),
    titleLarge = t(20, 700, 28),
    titleMedium = t(17, 700, 24),
    titleSmall = t(15, 700, 22),
    bodyLarge = t(17, 400, 26),
    bodyMedium = t(15, 400, 22),
    bodySmall = t(13, 400, 18),
    labelLarge = t(16, 700, 22),
    labelMedium = t(13, 700, 18),
    labelSmall = t(12, 500, 16),
)

/** Tabular-digit variant of any style, for amounts and times in lists. */
fun TextStyle.nums() = copy(fontFeatureSettings = "tnum")

@Composable
fun ShaonTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    MaterialTheme(colorScheme = if (dark) Dark else Light, typography = Type) {
        // Hebrew app: always right-to-left, even on a phone set to another language.
        CompositionLocalProvider(LocalShaon provides (if (dark) DarkExtra else LightExtra), LocalLayoutDirection provides LayoutDirection.Rtl) {
            content()
        }
    }
}

package com.perlinium.shaon.employee.ui

import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.QrCodeScanner
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.CompositionLocalProvider
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.perlinium.shaon.employee.data.Repo
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation

/** "shaon://pair/K7QM4XPA", "K7QM-4XPA" -> "K7QM4XPA" */
fun codeFrom(raw: String): String = raw.substringAfterLast('/').uppercase().filter { it.isLetterOrDigit() }.take(8)

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun PairingScreen(message: String?, incomingCode: String?) {
    val ctx = LocalContext.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scroll = rememberScrollState()
    // When the keyboard opens, scroll so the code field and the button stay visible.
    val imeOpen = WindowInsets.isImeVisible
    LaunchedEffect(imeOpen) { if (imeOpen) { delay(150); scroll.animateScrollTo(scroll.maxValue) } }

    fun connect(c: String) {
        if (busy) return
        busy = true; error = null
        scope.launch {
            when (val r = Repo.pair(c)) {
                Repo.PairResult.Ok -> view.confirmTick()
                is Repo.PairResult.Failed -> error = r.message
            }
            busy = false
        }
    }
    // Opened from the QR link (scanned with the regular camera): connect right away.
    LaunchedEffect(incomingCode) { incomingCode?.let { code = it; connect(it) } }

    Column(
        Modifier.fillMaxSize().imePadding().verticalScroll(scroll).padding(horizontal = 24.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(Modifier.size(88.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.Schedule, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(48.dp))
        }
        Text("שעון עובדות", style = MaterialTheme.typography.headlineLarge)
        Text("מחברים את הטלפון פעם אחת, ומאז הוא נשאר מחובר.", style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        var shown by remember(message) { mutableStateOf(message) }
        shown?.let { ErrorBanner(it) { shown = null } }

        // A real sequence, so numbered steps.
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Step(1, "במחשב של המנהל: \"חיבור טלפון\" ליד השם שלך")
            Step(2, "כאן: לסרוק את הקוד שמופיע במחשב")
        }

        Button(
            onClick = {
                val opts = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).enableAutoZoom().build()
                GmsBarcodeScanning.getClient(ctx as Activity, opts).startScan()
                    .addOnSuccessListener { b -> b.rawValue?.let { val c = codeFrom(it); code = c; connect(c) } }
                    .addOnFailureListener { error = "לא הצלחנו לפתוח את הסורק. אפשר להקליד את הקוד." }
            },
            enabled = !busy,
            modifier = Modifier.fillMaxWidth().heightIn(min = 64.dp), shape = RoundedCornerShape(18.dp),
        ) {
            Icon(Icons.Rounded.QrCodeScanner, null, Modifier.size(28.dp)); Spacer(Modifier.width(10.dp))
            Text("סריקת קוד מהמחשב", style = MaterialTheme.typography.titleMedium)
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            HorizontalDivider(Modifier.weight(1f))
            Text("  או להקליד את הקוד  ", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            HorizontalDivider(Modifier.weight(1f))
        }

        // Codes read left to right, like on the Mac screen.
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
            OutlinedTextField(
                value = code,
                onValueChange = { code = codeFrom(it); error = null },
                // The dash is drawn, not typed, so the cursor never jumps.
                visualTransformation = CodeDash,
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                placeholder = { Text("XXXX-XXXX", style = codeStyle(), color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .35f), modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center) },
                textStyle = codeStyle().copy(textAlign = TextAlign.Center),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, keyboardType = KeyboardType.Ascii, autoCorrectEnabled = false, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { if (code.length == 8) connect(code) }),
            )
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center) }
        OutlinedButton(
            onClick = { connect(code) }, enabled = code.length == 8 && !busy,
            modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp), shape = RoundedCornerShape(18.dp),
        ) {
            if (busy) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.5.dp) else Text("התחברות", style = MaterialTheme.typography.titleMedium)
        }
        Spacer(Modifier.height(8.dp))
    }
}

/** Shows "K7QM4XPA" as "K7QM-4XPA" while the real text stays 8 characters. */
private val CodeDash = VisualTransformation { t ->
    val raw = t.text
    val shown = if (raw.length > 4) raw.take(4) + "-" + raw.drop(4) else raw
    TransformedText(AnnotatedString(shown), object : OffsetMapping {
        override fun originalToTransformed(offset: Int) = if (offset > 4 && raw.length > 4) offset + 1 else offset
        override fun transformedToOriginal(offset: Int) = if (offset > 4 && raw.length > 4) offset - 1 else offset
    })
}

@Composable
private fun codeStyle() = TextStyle(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 28.sp, letterSpacing = 3.sp)

@Composable
private fun Step(n: Int, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary), contentAlignment = Alignment.Center) {
            Text("$n", color = MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.labelLarge)
        }
        Spacer(Modifier.width(12.dp))
        Text(text, style = MaterialTheme.typography.bodyLarge)
    }
}

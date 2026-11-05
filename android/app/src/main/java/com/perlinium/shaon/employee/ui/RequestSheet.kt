package com.perlinium.shaon.employee.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.perlinium.shaon.employee.data.Repo
import com.perlinium.shaon.employee.data.Shift
import com.perlinium.shaon.employee.logic.directAdd
import com.perlinium.shaon.employee.logic.directFix
import com.perlinium.shaon.employee.logic.fmtHM
import com.perlinium.shaon.employee.logic.fmtLongDate
import com.perlinium.shaon.employee.logic.isOvernight
import com.perlinium.shaon.employee.logic.overlapsAny
import com.perlinium.shaon.employee.logic.parseDate
import com.perlinium.shaon.employee.logic.shiftMinutes
import com.perlinium.shaon.employee.logic.spanMillis
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * Fix a shift (shift != null) or add one that was never clocked (shift == null).
 * Changes within the limits of logic/Direct.kt are saved right away; anything else becomes a request.
 * onDone(message, wasRequest).
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun RequestSheet(shift: Shift?, onClose: () -> Unit, onDone: (String, Boolean) -> Unit) {
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val view = LocalView.current
    val isFix = shift != null
    val running = shift?.open == true
    var date by remember { mutableStateOf(shift?.date ?: LocalDate.now().toString()) }
    var tin by remember { mutableStateOf(shift?.`in` ?: "") }
    var tout by remember { mutableStateOf(shift?.out ?: "") }
    var note by remember { mutableStateOf("") }
    var picking by remember { mutableStateOf<String?>(null) }   // "in" | "out" | "date"
    var error by remember { mutableStateOf<String?>(null) }

    val now = System.currentTimeMillis()
    val unchanged = isFix && tin == shift!!.`in` && (if (running) tout.isEmpty() else tout == shift.out)
    val ready = tin.isNotEmpty() && (running || tout.isNotEmpty()) && tin != tout && !unchanged
    val direct = when {
        !ready -> null
        isFix -> directFix(shift!!, tin, tout, now)
        else -> directAdd(date, tin, tout, now)
    }
    val needsApproval = ready && direct == null   // decided only once there is something to save

    val reasons = if (isFix) listOf("שכחתי ללחוץ כניסה", "שכחתי ללחוץ יציאה", "לחצתי בשעה לא נכונה") else listOf("שכחתי ללחוץ כניסה", "לא היה לי את הטלפון", "הטלפון היה כבוי")

    ModalBottomSheet(onDismissRequest = onClose, sheetState = sheet, containerColor = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 20.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(if (isFix) "תיקון משמרת" else "הוספת משמרת", style = MaterialTheme.typography.headlineSmall)
            if (needsApproval) {
                Text("השעות ישתנו רק אחרי שהמנהל יאשר.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            Field("יום", fmtLongDate(parseDate(date)), enabled = !isFix) { picking = "date" }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Field("כניסה", tin.ifEmpty { "בחירה" }, Modifier.weight(1f)) { picking = "in" }
                Field("יציאה", tout.ifEmpty { if (running) "עדיין במשמרת" else "בחירה" }, Modifier.weight(1f)) { picking = "out" }
            }
            if (tin.isNotEmpty() && tout.isNotEmpty() && tin != tout) {
                Text(
                    "${fmtHM(shiftMinutes(tin, tout))} שעות" + if (isOvernight(tin, tout)) " · משמרת לילה, היציאה למחרת" else "",
                    style = MaterialTheme.typography.titleMedium.nums(), color = MaterialTheme.colorScheme.primary,
                )
            }

            if (needsApproval) {
                Text("מה קרה?", style = MaterialTheme.typography.labelLarge)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    reasons.forEach { r -> FilterChip(selected = note == r, onClick = { note = if (note == r) "" else r }, label = { Text(r) }) }
                }
                OutlinedTextField(note, { note = it.take(500) }, Modifier.fillMaxWidth(), label = { Text("הערה למנהל (לא חובה)") }, minLines = 2)
            }

            error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium) }
            Button(
                onClick = {
                    val endAt = if (tin.isNotEmpty() && tout.isNotEmpty() && tin != tout) spanMillis(date, tin, tout).second else null
                    error = when {
                        tin.isEmpty() -> "צריך לבחור שעת כניסה"
                        !running && tout.isEmpty() -> "צריך לבחור שעת יציאה"
                        tout.isNotEmpty() && tin == tout -> "שעת היציאה זהה לשעת הכניסה"
                        parseDate(date).isAfter(LocalDate.now()) -> "אי אפשר לבקש על יום שעוד לא הגיע"
                        unchanged -> "לא שינית אף שעה"
                        endAt != null && endAt > now + 60_000 -> "שעת היציאה עוד לא הגיעה"
                        !isFix && direct != null && overlapsAny(direct.inAt, direct.outAt!!, sameDays(date), now) -> "בשעות האלה כבר רשומה משמרת"
                        else -> null
                    }
                    if (error == null) {
                        view.confirmTick()
                        val saved = when {
                            direct == null -> false
                            isFix -> Repo.fixEarlier(shift!!, tin, tout, direct)
                            else -> Repo.addManualShift(date, tin, tout, direct)
                        }
                        if (saved) onDone(if (tout.isEmpty()) "נשמר: כניסה ב-$tin" else "נשמר: $tin–$tout", false)
                        else {
                            Repo.sendRequest(if (isFix) "fix" else "add", shift?.id, date, tin, tout, note)
                            onDone("הבקשה נשלחה למנהל", true)
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
                shape = RoundedCornerShape(16.dp),
            ) { Text(if (needsApproval) "שליחה לאישור" else "שמירה", style = MaterialTheme.typography.titleMedium) }
        }
    }

    when (picking) {
        "in", "out" -> TimeDialog(
            title = if (picking == "in") "שעת כניסה" else "שעת יציאה",
            initial = (if (picking == "in") tin else tout).ifEmpty { if (picking == "in") "08:00" else "16:00" },
            onDismiss = { picking = null },
        ) { v -> if (picking == "in") tin = v else tout = v; picking = null; error = null }
        "date" -> DateDialog(date, onDismiss = { picking = null }) { date = it; picking = null; error = null }
    }
}

/** Her other shifts around [date] (for the overlap check), incl. the running one. */
private fun sameDays(date: String): List<Shift> {
    val d = parseDate(date)
    val near = setOf(d.minusDays(1).toString(), date, d.plusDays(1).toString())
    val list = (Repo.recentShifts.value + (Repo.monthShifts.value ?: emptyList()) + listOfNotNull(Repo.openShift.value))
    return list.distinctBy { it.id }.filter { it.date in near && (it.open || it.out.isNotEmpty()) }
}

@Composable
private fun Field(label: String, value: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    Column(
        modifier.fillMaxWidth().heightIn(min = 64.dp)
            .border(1.dp, if (enabled) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.outlineVariant, shape)
            .clickable(enabled = enabled, onClick = onClick)
            .semantics(mergeDescendants = true) { role = Role.Button; contentDescription = "$label: $value" }
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.titleLarge.nums(),
            color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TimeDialog(title: String, initial: String, onDismiss: () -> Unit, onPick: (String) -> Unit) {
    val (h, m) = initial.split(":").map { it.toIntOrNull() ?: 0 }.let { it[0] to it.getOrElse(1) { 0 } }
    val state = rememberTimePickerState(initialHour = h, initialMinute = m, is24Hour = true)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        // Clock faces read left-to-right (hours:minutes) in Hebrew too.
        text = { CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) { TimePicker(state) } },
        confirmButton = { TextButton(onClick = { onPick("%02d:%02d".format(state.hour, state.minute)) }) { Text("אישור") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("ביטול") } },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DateDialog(current: String, onDismiss: () -> Unit, onPick: (String) -> Unit) {
    val todayMs = LocalDate.now().atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli()
    val state = rememberDatePickerState(
        initialSelectedDateMillis = parseDate(current).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli(),
        selectableDates = object : SelectableDates { override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis <= todayMs },
    )
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = {
                state.selectedDateMillis?.let { onPick(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString()) } ?: onDismiss()
            }) { Text("אישור") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("ביטול") } },
    ) { DatePicker(state, showModeToggle = false) }
}

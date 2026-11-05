package com.perlinium.shaon.employee.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Inbox
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.perlinium.shaon.employee.data.Repo
import com.perlinium.shaon.employee.data.ShiftRequest
import com.perlinium.shaon.employee.logic.fmtDayMonth
import com.perlinium.shaon.employee.logic.fmtHM
import com.perlinium.shaon.employee.logic.fmtWeekday
import com.perlinium.shaon.employee.logic.shiftMinutes

@Composable
fun RequestsScreen(onNew: () -> Unit) {
    val reqs by Repo.requests.collectAsState()
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("הבקשות שלי", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f))
                Button(onClick = onNew) { Icon(Icons.Rounded.Add, null); Spacer(Modifier.size(6.dp)); Text("בקשה חדשה") }
            }
            Text("שכחת ללחוץ? טעית בשעה? שולחים בקשה, והמנהל מאשר מהמחשב. השעות משתנות רק אחרי אישור.",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
        }
        if (reqs.isEmpty()) item {
            Column(Modifier.fillMaxWidth().padding(vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Rounded.Inbox, null, tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(56.dp))
                Spacer(Modifier.height(10.dp))
                Text("עוד לא שלחת בקשות", style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
            }
        }
        items(reqs, key = { it.id }) { r -> RequestRow(r) }
    }
}

@Composable
private fun RequestRow(r: ShiftRequest) {
    val (label, kind) = when (r.status) {
        "approved" -> "אושרה" to ChipKind.Approved
        "rejected" -> "נדחתה" to ChipKind.Rejected
        "cancelled" -> "בוטלה" to ChipKind.Neutral
        else -> (if (r.pending) "לא נשלחה עדיין" else "ממתינה לאישור") to ChipKind.Waiting
    }
    Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainer, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(if (r.type == "add") "הוספת משמרת" else "תיקון משמרת", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                StatusChip(label, kind)
            }
            Text(
                "${fmtWeekday(r.date)} ${fmtDayMonth(r.date)} · " +
                    if (r.out.isEmpty()) "כניסה ב-${r.`in`}" else "${r.`in`}–${r.out} · ${fmtHM(shiftMinutes(r.`in`, r.out))} שעות",
                style = MaterialTheme.typography.bodyLarge.nums(),
            )
            r.note?.takeIf { it.isNotBlank() }?.let { Text("“$it”", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            if (r.status == "pending" && !r.pending) {
                TextButton(onClick = { Repo.cancelRequest(r.id) }, contentPadding = PaddingValues(0.dp)) { Text("ביטול הבקשה") }
            }
        }
    }
}

package com.perlinium.shaon.employee.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.PhoneAndroid
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.perlinium.shaon.employee.data.Repo
import com.perlinium.shaon.employee.data.Shift
import com.perlinium.shaon.employee.logic.fmtDayMonth
import com.perlinium.shaon.employee.logic.fmtHM
import com.perlinium.shaon.employee.logic.fmtMoney
import com.perlinium.shaon.employee.logic.fmtMonth
import com.perlinium.shaon.employee.logic.fmtWeekday
import com.perlinium.shaon.employee.logic.isOvernight
import com.perlinium.shaon.employee.logic.monthStr
import com.perlinium.shaon.employee.logic.nowLocal
import com.perlinium.shaon.employee.logic.parseDate
import com.perlinium.shaon.employee.logic.shiftMinutes
import com.perlinium.shaon.employee.logic.shiftMonth
import com.perlinium.shaon.employee.logic.shiftPay
import com.perlinium.shaon.employee.logic.totals

@Composable
fun MonthScreen(onShift: (Shift) -> Unit) {
    val month by Repo.month.collectAsState()
    val shifts by Repo.monthShifts.collectAsState()
    val emp by Repo.employee.collectAsState()
    val settings by Repo.settings.collectAsState()
    val payments by Repo.payments.collectAsState()
    val thisMonth = monthStr(nowLocal().toLocalDate())
    val list = shifts
    val done = list?.filter { !it.open } ?: emptyList()
    val t = totals(done, emp, settings.defaultRate)
    val monthPayments = payments.filter { it.date.startsWith(month) }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            // Month switcher. In RTL "previous" is on the right.
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { Repo.setMonth(shiftMonth(month, -1)) }) {
                    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowLeft, contentDescription = "החודש הקודם")
                }
                Text(fmtMonth(month), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
                IconButton(onClick = { Repo.setMonth(shiftMonth(month, 1)) }, enabled = month < thisMonth) {
                    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = "החודש הבא")
                }
            }
        }
        item {
            // Summary first, detail after. "Left to pay" is the question she actually asks, so it stands out.
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    StatTile("שעות", fmtHM(t.minutes), Modifier.weight(1f))
                    StatTile("הרווחת", fmtMoney(t.pay), Modifier.weight(1f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    StatTile("שולם", fmtMoney(t.paid), Modifier.weight(1f))
                    StatTile("נשאר לתשלום", fmtMoney(t.unpaid), Modifier.weight(1f), highlight = t.unpaid > 0)
                }
            }
        }
        item { Spacer(Modifier.height(6.dp)); SectionTitle("המשמרות שלך") }
        when {
            list == null -> item { Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
            list.isEmpty() -> item {
                Text("אין משמרות ב${fmtMonth(month)}.", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp), textAlign = TextAlign.Center)
            }
            else -> items(list, key = { it.id }) { s -> ShiftRow(s, shiftPay(s, emp, settings.defaultRate)) { onShift(s) } }
        }
        if (monthPayments.isNotEmpty()) {
            item { Spacer(Modifier.height(6.dp)); SectionTitle("תשלומים שקיבלת") }
            items(monthPayments, key = { "p" + it.id }) { p ->
                Surface(shape = RoundedCornerShape(14.dp), color = MaterialTheme.colorScheme.surfaceContainer, modifier = Modifier.fillMaxWidth()) {
                    Row(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("${fmtDayMonth(p.date)}${p.method?.let { " · $it" } ?: ""}", style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                        Text(fmtMoney(p.amount), style = MaterialTheme.typography.titleMedium.nums(), color = MaterialTheme.colorScheme.primary)
                    }
                }
            }
        }
        item { Text("לחיצה על משמרת פותחת בקשת תיקון", style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.fillMaxWidth().padding(top = 8.dp), textAlign = TextAlign.Center) }
    }
}

@Composable
private fun ShiftRow(s: Shift, pay: Double, onClick: () -> Unit) {
    val d = parseDate(s.date)
    val mins = shiftMinutes(s.`in`, s.out)
    val desc = buildString {
        append("${fmtWeekday(s.date)} ${fmtDayMonth(s.date)}, ")
        if (s.open) append("נכנסת ב-${s.`in`}, עדיין במשמרת") else append("${s.`in`} עד ${s.out}, ${fmtHM(mins)} שעות, ${fmtMoney(pay)}, ${if (s.paid) "שולם" else "ממתין לתשלום"}")
    }
    Surface(onClick = onClick, shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainer,
        modifier = Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = desc }) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.widthIn(min = 44.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("${d.dayOfMonth}", style = MaterialTheme.typography.titleLarge.nums())
                Text(fmtWeekday(s.date), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(if (s.open) "${s.`in`} –" else "${s.`in`} – ${s.out}", style = MaterialTheme.typography.titleMedium.nums())
                    if (s.source == "phone") {
                        Spacer(Modifier.width(6.dp))
                        Icon(Icons.Rounded.PhoneAndroid, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 2.dp).width(14.dp))
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    when {
                        s.open -> StatusChip("במשמרת", ChipKind.Live)
                        s.paid -> StatusChip("שולם", ChipKind.Paid)
                        else -> StatusChip("ממתין לתשלום", ChipKind.Waiting)
                    }
                    if (isOvernight(s.`in`, s.out)) StatusChip("לילה", ChipKind.Neutral)
                    if (s.fixedBy != null) StatusChip("תוקן", ChipKind.Neutral)
                    if (s.pending) StatusChip("לא נשלח עדיין", ChipKind.Waiting)
                }
            }
            if (!s.open) Column(horizontalAlignment = Alignment.End) {
                Text(fmtHM(mins), style = MaterialTheme.typography.titleMedium.nums())
                Text(fmtMoney(pay), style = MaterialTheme.typography.bodyMedium.nums(), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

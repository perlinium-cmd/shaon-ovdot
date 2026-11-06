// Shift time and pay calculations. Pure functions, no DOM, so they can be tested with `node --test`.
// The same rules are ported to mac/ShaonMac/Logic/Pay.swift and the Android app (logic/Pay.kt);
// all three are checked against shared/pay-cases.json and shared/money-cases.json.
//
// Money is exact. Every amount is a whole number of agorot: a shift's pay is worked out exactly
// (whole minutes × rates with at most 2 decimals) and rounded once, to the nearest agora (half up).
// Totals add up those whole agorot, so a report's rows always sum to its total, to the agora, and a
// payment always equals the sum of its shifts.
//
// Hours are real time in Israel (Asia/Jerusalem): on the two nights a year when the clock moves,
// 22:00–06:00 is 7 hours (spring) or 9 hours (autumn), not 8.

export const ZONE = 'Asia/Jerusalem';
const DAY_MIN = 24 * 60;
const H12 = 12 * 3600 * 1000;

/* ---------------- times and dates ---------------- */

/** "HH:MM" (or "H:MM") → minutes since midnight; null if empty or not a valid time. */
export function parseHM(t) {
  if (typeof t !== 'string') return null;
  const m = /^(\d{1,2}):(\d{2})$/.exec(t);
  if (!m) return null;
  const h = +m[1]; const mi = +m[2];
  return h <= 23 && mi <= 59 ? h * 60 + mi : null;
}
/** Minutes since midnight, 0 when not a valid time. */
export const toMin = (t) => parseHM(t) ?? 0;

const isLeap = (y) => y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0);
const daysIn = (y, m) => [31, isLeap(y) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1];

/** "YYYY-MM-DD" → {y, m, d}; null if it is not a real calendar date. */
export function parseYMD(s) {
  if (typeof s !== 'string') return null;
  const r = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!r) return null;
  const y = +r[1]; const m = +r[2]; const d = +r[3];
  if (y < 1900 || m < 1 || m > 12 || d < 1 || d > daysIn(y, m)) return null;
  return { y, m, d };
}
const nextDay = ({ y, m, d }) => (d < daysIn(y, m) ? { y, m, d: d + 1 } : m < 12 ? { y, m: m + 1, d: 1 } : { y: y + 1, m: 1, d: 1 });
const utcMidnight = ({ y, m, d }) => Date.UTC(y, m - 1, d);

let zoneFmt = null;
/** Israel's offset from UTC, in ms, at a moment (+2h in winter, +3h in summer). */
export function zoneOffsetMs(utcMs) {
  zoneFmt ??= new Intl.DateTimeFormat('en-US', {
    timeZone: ZONE, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', second: 'numeric',
  });
  const p = {};
  for (const { type, value } of zoneFmt.formatToParts(new Date(utcMs))) p[type] = Number(value);
  const wall = Date.UTC(p.year, p.month - 1, p.day, p.hour % 24, p.minute, p.second);
  return wall - Math.floor(utcMs / 1000) * 1000;
}

/** The moment (ms since 1970) of a wall-clock time in Israel. Like java.time: in the hour that repeats in
 *  autumn, the earlier (summer) moment; a time skipped in spring is moved forward by the gap (02:30 → 03:30). */
export function zonedMs(day, minOfDay) {
  const naive = utcMidnight(day) + minOfDay * 60000;
  const before = zoneOffsetMs(naive - H12);
  const after = zoneOffsetMs(naive + H12);
  const c1 = naive - before;
  const c2 = naive - after;
  const ok1 = zoneOffsetMs(c1) === before;
  const ok2 = zoneOffsetMs(c2) === after;
  if (ok1 && ok2) return Math.min(c1, c2);
  if (ok2) return c2;
  return c1;
}

const stable = new Map();
/** True when the clock does not move from the start of `day` until 2 days later (all days but 2 a year). */
function steadyFrom(day) {
  const k = `${day.y}-${day.m}-${day.d}`;
  let v = stable.get(k);
  if (v === undefined) {
    const t = utcMidnight(day);
    v = zoneOffsetMs(t - 6 * 3600000) === zoneOffsetMs(t + 54 * 3600000);
    if (stable.size > 5000) stable.clear();
    stable.set(k, v);
  }
  return v;
}

/** Minutes worked on `date` (the day of the clock-in). If out is earlier than in, the shift ends the next
 *  day. Real time: counts the hour the clock moves. 0 when a time is missing or invalid, or in equals out. */
export function shiftMinutes(date, tin, tout) {
  const a = parseHM(tin); const b = parseHM(tout);
  if (a == null || b == null || a === b) return 0;
  const wall = b > a ? b - a : b - a + DAY_MIN;
  const d = parseYMD(date);
  if (!d || steadyFrom(d)) return wall;
  const start = zonedMs(d, a);
  const end = zonedMs(b > a ? d : nextDay(d), b);
  const real = Math.round((end - start) / 60000);
  return real > 0 ? real : wall;
}

/** The same shift by the clock on the wall (ignores the clock moving), for showing the difference. */
export function wallMinutes(tin, tout) {
  const a = parseHM(tin); const b = parseHM(tout);
  if (a == null || b == null || a === b) return 0;
  return b > a ? b - a : b - a + DAY_MIN;
}

export const isOvernight = (tin, tout) => {
  const a = parseHM(tin); const b = parseHM(tout);
  return a != null && b != null && b < a;
};

/* ---------------- money ---------------- */

/** Exact whole agorot of an amount in shekels, rounded half up (half away from zero below 0);
 *  null if not a finite number. Reads the number's shortest decimal form, so 1.005 → 101 (not 100). */
export function toAgorot(x) {
  if (typeof x !== 'number' || !Number.isFinite(x)) return null;
  const r = /^(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$/.exec(String(Math.abs(x)));
  if (!r) return null;
  const digits = r[1] + (r[2] || '');
  const point = r[1].length + Number(r[3] || 0) + 2; // where the decimal point falls after ×100
  let whole; let next;
  if (point <= 0) { whole = 0; next = point === 0 ? Number(digits[0]) : 0; }
  else if (point >= digits.length) { whole = Number(digits + '0'.repeat(point - digits.length)); next = 0; }
  else { whole = Number(digits.slice(0, point)); next = Number(digits[point]); }
  const a = whole + (next >= 5 ? 1 : 0);
  return x < 0 && a !== 0 ? -a : a;
}

/** Rounded to the agora, as a number (2 decimals at most). */
export const round2 = (n) => (toAgorot(n) ?? 0) / 100;

/** num / den rounded to the nearest whole number, half away from zero (den > 0). Exact for |num| < 2^53. */
function divRound(num, den) {
  const neg = num < 0;
  const n = Math.abs(num);
  let q = Math.floor((2 * n + den) / (2 * den));
  while (q * 2 * den > 2 * n + den) q -= 1;
  while ((q + 1) * 2 * den <= 2 * n + den) q += 1;
  return neg ? -q : q;
}

const num = (x) => (typeof x === 'number' && Number.isFinite(x) ? x : null);

/** Hourly rate for an employee: their own rate, else the default rate, else 0. */
export const effRate = (emp, defaultRate) => num(emp?.rate) ?? num(defaultRate) ?? 0;

/** Hourly rate for a shift: a rate set on the shift wins over the employee's rate. */
export const shiftRate = (s, emp, defaultRate) => num(s?.rate) ?? effRate(emp, defaultRate);

/** The shift's special rate {rate, hours} when it has a usable one, else null. */
function specialOf(s) {
  const sp = s?.special;
  if (!sp || typeof sp !== 'object' || num(sp.rate) == null) return null;
  return { rate: sp.rate, hours: num(sp.hours) };
}

/** Minutes of a shift paid at its special rate (all of it, or only `special.hours`). Can have a fraction. */
export function specialMinutes(s) {
  const sp = specialOf(s);
  if (!sp) return 0;
  const min = shiftMinutes(s.date, s.in, s.out);
  return sp.hours == null ? min : Math.min(min, Math.max(0, sp.hours * 60));
}

/** Pay for one shift in whole agorot: the regular rate, with an optional special hourly amount for all or
 *  part of it. Worked out exactly in fifths of a minute (0.01 hour = 0.6 minute) and rounded once. */
export function shiftPayAgorot(s, emp, defaultRate) {
  const total = shiftMinutes(s?.date, s?.in, s?.out);
  if (!total) return 0;
  const units = total * 5;
  const sp = specialOf(s);
  let spUnits = 0;
  if (sp) spUnits = sp.hours == null ? units : Math.min(units, Math.max(0, (toAgorot(sp.hours) ?? 0) * 3));
  const amount = (units - spUnits) * (toAgorot(shiftRate(s, emp, defaultRate)) ?? 0)
    + spUnits * (sp ? toAgorot(sp.rate) ?? 0 : 0);
  return divRound(amount, 300); // agorot × units / (60 minutes × 5 units)
}

/** Pay for one shift in shekels (always a whole number of agorot). */
export const shiftPay = (s, emp, defaultRate) => shiftPayAgorot(s, emp, defaultRate) / 100;

/** Sum of the shifts' pay, in whole agorot. */
export const sumAgorot = (list, emp, defaultRate) => list.reduce((t, s) => t + shiftPayAgorot(s, emp, defaultRate), 0);

/** Per-employee totals for a list of shifts:
 *  Map(empId → {shifts, minutes, payA, paidA, paidCount, pay, paidPay}). Amounts in agorot (…A) and shekels. */
export function aggregate(list, empById, defaultRate) {
  const map = new Map();
  for (const s of list) {
    const a = map.get(s.empId) || emptyAgg();
    const p = shiftPayAgorot(s, empById(s.empId), defaultRate);
    a.shifts.push(s);
    a.minutes += shiftMinutes(s.date, s.in, s.out);
    a.payA += p;
    if (s.paid === true) { a.paidA += p; a.paidCount += 1; }
    a.pay = a.payA / 100; a.paidPay = a.paidA / 100;
    map.set(s.empId, a);
  }
  return map;
}
export const emptyAgg = () => ({ shifts: [], minutes: 0, payA: 0, paidA: 0, paidCount: 0, pay: 0, paidPay: 0 });
/** Left to pay, in shekels. */
export const unpaidOf = (a) => (a.payA - a.paidA) / 100;

/* ---------------- typed input ---------------- */

/** A typed amount ("40", "42.5", "42,50") → a number with at most 2 decimals (rounded half up);
 *  null if empty; NaN if not a plain non-negative number or above `max`. */
export function parseAmount(v, max = 100000) {
  const s = String(v ?? '').trim().replace(',', '.');
  if (s === '') return null;
  const r = /^(\d*)(?:\.(\d*))?$/.exec(s);
  if (!r || (r[1] === '' && !r[2])) return NaN;
  const frac = (r[2] || '').padEnd(3, '0');
  const a = Number(r[1] || '0') * 100 + Number(frac.slice(0, 2)) + (Number(frac[2]) >= 5 ? 1 : 0);
  return Number.isSafeInteger(a) && a <= max * 100 ? a / 100 : NaN;
}

/** Typed digits ("8", "830", "0830", "8:30") → "HH:MM"; '' if empty, null if invalid.
 *  In AM/PM mode hours 1–12 use the given ampm; 0 or 13–23 are read as 24h. */
export function parseTyped(text, ampm) {
  const d = String(text ?? '').replace(/\D/g, '').slice(0, 4);
  if (!d) return '';
  let h; let m;
  if (d.length <= 2) { h = +d; m = 0; } else if (d.length === 3) { h = +d[0]; m = +d.slice(1); } else { h = +d.slice(0, 2); m = +d.slice(2); }
  if (h > 23 || m > 59) return null;
  if (ampm && h >= 1 && h <= 12) h = (h % 12) + (ampm === 'PM' ? 12 : 0);
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

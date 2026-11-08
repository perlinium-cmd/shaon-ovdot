// Employee phones, as seen by the manager: requests to approve, changes saved on the phone (notices),
// connected phones and shifts running right now. Pure functions, shared by both data backends (data.js)
// and the screens (app.js), and tested on their own (tests/phone.test.mjs).
// Same behaviour as the Mac app (mac/ShaonMac/Data/FirestoreStore.swift → decide, AppModel.describe).
import { parseHM, parseYMD, zonedMs, shiftMinutes } from './pay.js';

/** Why a request could not be approved. `message` is shown to the manager as is. */
export class RequestError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
export const REQUEST_ERRORS = {
  missingShift: 'המשמרת שהבקשה מתייחסת אליה כבר לא קיימת',
  alreadyPaid: 'המשמרת כבר סומנה כשולמה. בטל את סימון התשלום ואז אשר.',
  notPending: 'הבקשה הזו כבר טופלה (או שהעובדת ביטלה אותה)',
};
const err = (code) => new RequestError(code, REQUEST_ERRORS[code]);

/** "2026-11-05" + "08:14" (Israel time, like the phones) → ms since 1970; null when either is not valid. */
export function localMillis(date, time) {
  const d = parseYMD(date); const m = parseHM(time);
  return d && m != null ? zonedMs(d, m) : null;
}

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);

/**
 * The writes that approve or reject a request, all in one commit.
 *   req     the request as it is now ({id, empId, type, shiftId, date, in, out, status})
 *   shift   for a "fix": the shift as it is now (null if it no longer exists)
 *   rate    the employee's current effective rate (for a new shift, or a shift that has no rate yet)
 *   now     what to write as decidedAt (Firestore: serverTimestamp(); demo: Date.now())
 *   newShiftId  id for the shift an "add" creates
 *   createdAt   ms, the new shift's createdAt
 * Returns [{op: set|update, col, id, data}]. Throws RequestError when it must not happen.
 */
export function decisionOps({ req, shift = null, approve, rate, now, newShiftId, createdAt }) {
  if (!req || req.status !== 'pending') throw err('notPending');
  if (!approve) {
    return [{ op: 'update', col: 'requests', id: req.id, data: { status: 'rejected', decidedAt: now } }];
  }
  const month = String(req.date).slice(0, 7);
  if (req.type === 'add') {
    return [
      {
        op: 'set', col: 'shifts', id: newShiftId,
        data: {
          empId: req.empId, date: req.date, month, in: req.in, out: req.out,
          rate, special: null, paid: false, paidAt: null, paymentId: null,
          source: 'request', requestId: req.id, createdAt,
        },
      },
      { op: 'update', col: 'requests', id: req.id, data: { status: 'approved', decidedAt: now, shiftId: newShiftId } },
    ];
  }
  if (!req.shiftId || !shift) throw err('missingShift');
  if (shift.paid === true) throw err('alreadyPaid');
  const u = { in: req.in, date: req.date, month, fixedBy: req.id };
  if (!isNum(shift.rate)) u.rate = rate; // a phone shift gets the rate it is worked at, once
  if (!req.out) {
    // Only the clock-in of a running shift: move the phone's running clock with it.
    if (shift.open === true) { const ms = localMillis(req.date, req.in); if (ms != null) u.inAt = ms; }
  } else {
    u.out = req.out; u.open = false;
  }
  return [
    { op: 'update', col: 'shifts', id: req.shiftId, data: u },
    { op: 'update', col: 'requests', id: req.id, data: { status: 'approved', decidedAt: now } },
  ];
}

/** Firestore Timestamps (createdAt, pairedAt, decidedAt…) → ms numbers; everything else as is. */
export function plainDoc(data) {
  const out = {};
  for (const [k, v] of Object.entries(data || {})) out[k] = v && typeof v.toMillis === 'function' ? v.toMillis() : v;
  return out;
}

export const isPendingRequest = (r) => r?.status === 'pending';
/** Pending requests, oldest first. */
export const pendingRequests = (list) => (list || []).filter(isPendingRequest).sort((a, b) => (a.createdAt || 0) - (b.createdAt || 0));
/** Requests already handled, newest first (the last 20). */
export const decidedRequests = (list) => (list || []).filter((r) => !isPendingRequest(r))
  .sort((a, b) => (b.decidedAt || b.createdAt || 0) - (a.decidedAt || a.createdAt || 0)).slice(0, 20);
export const unseenNotices = (list) => (list || []).filter((n) => n.seen !== true);
/** Newest first, like the Mac's listener (createdAt descending). */
export const sortNotices = (list) => [...(list || [])].sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));

/** Minutes since clock-in of a running shift (from the phone's clock, or its date + time). */
export function runningMinutes(s, nowMs = Date.now()) {
  if (s?.open !== true) return null;
  const start = isNum(s.inAt) ? s.inAt : localMillis(s.date, s.in);
  return start == null ? null : Math.max(0, Math.floor((nowMs - start) / 60000));
}

const fmtHM = (min) => `${Math.floor(min / 60)}:${String(Math.round(min % 60)).padStart(2, '0')}`;

/** Title and detail line for a change the phone saved without approval (same wording as the Mac). */
export function describeNotice(n, { name = 'עובדת', fmt = (t) => t, day = n.date } = {}) {
  const hours = (a, b) => fmtHM(shiftMinutes(n.date, a, b));
  const prevOut = n.prevOut || '';
  const closedShift = n.type === 'fix' && !prevOut && !!n.out;
  const movedIn = n.type === 'fix' && n.prevIn != null && n.prevIn !== n.in;
  const movedOut = n.type === 'fix' && !!prevOut && prevOut !== n.out;
  const span = !n.out ? `כניסה ב-${fmt(n.in)}, עדיין במשמרת` : `${fmt(n.in)}–${fmt(n.out)} · ${hours(n.in, n.out)} שעות`;
  const inLine = movedIn ? `כניסה ${fmt(n.in)} במקום ${fmt(n.prevIn || '')}` : null;
  const outLine = movedOut ? `יציאה ${fmt(n.out)} במקום ${fmt(prevOut)}` : null;
  const second = n.edit === 2 ? 'שינוי שני במשמרת הזו' : null;
  const line = (parts) => parts.filter(Boolean).join(' · ');
  if (n.type === 'manual') return { title: `${name} הזינה שעות`, detail: line([day, span]) };
  if (closedShift) return { title: `${name} רשמה שעת יציאה`, detail: line([day, span, inLine, second]) };
  if (!n.out) return { title: `${name} שינתה שעת כניסה`, detail: line([day, inLine, 'עדיין במשמרת', second]) };
  // A finished shift: what changed, and the total before and after (that's what changes the pay).
  const total = n.prevIn != null && prevOut ? `סה״כ ${hours(n.in, n.out)} שעות במקום ${hours(n.prevIn, prevOut)}` : null;
  return { title: `${name} שינתה שעות`, detail: line([day, inLine, outLine, total, second]) };
}

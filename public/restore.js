// Recycle bin, the way back. The app reads the bin (users/{uid}/trash, see trash.js) and the records a restore touches;
// these pure functions decide what is shown and what to write, so a restore never leaves money out of step:
// a payment and the shifts it paid are always put back together, or not at all.

import { toAgorot } from './pay.js';

/** Shifts and payments deleted this close to their employee were deleted with her (her delete goes in a few batches:
 *  the website deletes her first, the Mac last). */
export const WITH_EMPLOYEE_MS = 10 * 60 * 1000;
const key = (col, id) => `${col}/${id}`;

/**
 * What the bin shows, newest first: [{kind: 'employee'|'shift'|'payment', item, members}].
 *   items  [{col, id, data, deletedAt (ms)}] as read from the bin
 *   live   Set of "col/id" that exist again (restored, or "בטל" was pressed): those are not shown
 * An employee carries the shifts and payments deleted with her; a shift carries its payment record when that was
 * removed in the same write (it was the only shift in it).
 */
export function trashGroups(items, live) {
  const gone = items.filter((t) => t?.data && !live.has(key(t.col, t.id)));
  const used = new Set();
  const take = (t) => { used.add(key(t.col, t.id)); return t; };
  const free = (t) => !used.has(key(t.col, t.id));
  const groups = [];
  for (const e of gone.filter((t) => t.col === 'employees')) {
    const members = gone.filter((t) => t.col !== 'employees' && free(t) && t.data.empId === e.id
      && Math.abs(t.deletedAt - e.deletedAt) <= WITH_EMPLOYEE_MS).map(take);
    groups.push({ kind: 'employee', item: take(e), members });
  }
  for (const s of gone.filter((t) => t.col === 'shifts' && free(t))) {
    const members = gone.filter((t) => t.col === 'payments' && free(t) && t.id === s.data.paymentId
      && t.deletedAt === s.deletedAt).map(take);
    groups.push({ kind: 'shift', item: take(s), members });
  }
  for (const p of gone.filter((t) => t.col === 'payments' && free(t))) groups.push({ kind: 'payment', item: take(p), members: [] });
  return groups.sort((a, b) => b.item.deletedAt - a.item.deletedAt);
}

/** The live records a restore of this group depends on ({col, id}); read them, then call restorePlan. */
export function neededRefs(group) {
  const d = group.item.data;
  if (group.kind === 'employee') return [];
  const refs = [{ col: 'employees', id: d.empId }];
  if (group.kind === 'shift' && d.paymentId) refs.push({ col: 'payments', id: d.paymentId });
  if (group.kind === 'payment') (d.shiftIds || []).forEach((id) => refs.push({ col: 'shifts', id }));
  return refs;
}

/**
 * The writes that put a group back: {ops, note?} or {error}.
 *   live  Map "col/id" -> data or null, for neededRefs(group)
 *   payA  (shift, employee) -> the shift's pay in agorot (the same sum taken off its payment when it was deleted)
 */
export function restorePlan(group, { live, payA }) {
  const { item, members } = group;
  const d = item.data;
  const back = (t, data = t.data) => ({ op: 'set', col: t.col, id: t.id, data });
  if (group.kind === 'employee') return { ops: [back(item), ...members.map((m) => back(m))] };

  const emp = live.get(key('employees', d.empId));
  if (!emp) return { error: 'העובדת נמחקה. קודם צריך לשחזר אותה, ואז את זה.' };

  if (group.kind === 'shift') {
    if (!d.paid || !d.paymentId) return { ops: [back(item)] };
    // Its payment record went with it (it was the only shift in it): both come back as they were.
    if (members.length) return { ops: [...members.map((m) => back(m)), back(item)] };
    const p = live.get(key('payments', d.paymentId));
    if (p) {
      const ids = p.shiftIds || [];
      if (ids.includes(item.id)) return { ops: [back(item)] };
      // Back into the payment it was taken out of, with its sum.
      const amount = ((toAgorot(p.amount) ?? 0) + payA(d, emp)) / 100;
      return { ops: [back(item), { op: 'update', col: 'payments', id: d.paymentId, data: { shiftIds: [...ids, item.id], amount } }] };
    }
    // The payment it was in is gone (deleted on its own since): the shift comes back as not paid.
    return {
      ops: [back(item, { ...d, paid: false, paidAt: null, paymentId: null })],
      note: 'רשומת התשלום של המשמרת כבר לא קיימת, אז היא חזרה כ"לא שולמה".',
    };
  }

  // A payment: its shifts are marked paid again, in the same write.
  const ids = d.shiftIds || [];
  const shifts = ids.map((id) => ({ id, s: live.get(key('shifts', id)) }));
  if (shifts.some(({ s }) => !s)) return { error: 'חלק מהמשמרות של התשלום הזה נמחקו. קודם צריך לשחזר אותן.' };
  if (shifts.some(({ s }) => s.open)) return { error: 'אחת המשמרות של התשלום עוד פתוחה.' };
  if (shifts.some(({ s }) => s.paid && s.paymentId !== item.id)) {
    return { error: 'חלק מהמשמרות של התשלום כבר שולמו בתשלום אחר. שחזור היה סופר אותן פעמיים.' };
  }
  const paidAt = typeof d.createdAt === 'number' ? d.createdAt : Date.now();
  return {
    ops: [back(item), ...shifts.filter(({ s }) => s.paymentId !== item.id)
      .map(({ id }) => ({ op: 'update', col: 'shifts', id, data: { paid: true, paidAt, paymentId: item.id } }))],
  };
}

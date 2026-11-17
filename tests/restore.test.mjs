// Recycle bin restore (public/restore.js): what is shown, and what a restore writes. Money must stay in step.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { trashGroups, neededRefs, restorePlan, WITH_EMPLOYEE_MS } from '../public/restore.js';

const T = 1_800_000_000_000;
const item = (col, id, data, deletedAt = T) => ({ col, id, data, deletedAt });
const emp = { name: 'נועה', rate: 40 };
const shift = (over = {}) => ({ empId: 'e1', date: '2026-11-02', month: '2026-11', in: '08:00', out: '14:00', rate: 40, paid: false, ...over });
const payA = (s) => 6 * (s.rate ?? 40) * 100;                       // 6 hours
const live = (entries) => new Map(Object.entries(entries));

describe('what the bin shows', () => {
  it('an employee carries the shifts and payments deleted with her; older ones stand alone', () => {
    const g = trashGroups([
      item('employees', 'e1', emp, T),
      item('shifts', 's1', shift(), T - 2000),
      item('payments', 'p1', { empId: 'e1', amount: 240, shiftIds: ['s1'] }, T - 1000),
      item('shifts', 'old', shift(), T - WITH_EMPLOYEE_MS - 1),
      item('shifts', 'after', shift(), T + 3000),          // the website deletes her first, then her shifts
    ], new Set());
    assert.deepEqual(g.map((x) => [x.kind, x.item.id, x.members.map((m) => m.id)]), [['employee', 'e1', ['s1', 'p1', 'after']], ['shift', 'old', []]]);
  });
  it('a shift carries its payment record when both went in the same write', () => {
    const g = trashGroups([
      item('shifts', 's1', shift({ paid: true, paymentId: 'p1' })),
      item('payments', 'p1', { empId: 'e1', amount: 240, shiftIds: ['s1'] }),
      item('payments', 'p2', { empId: 'e1', amount: 100, shiftIds: ['s9'] }, T - 5),
    ], new Set());
    assert.deepEqual(g.map((x) => [x.kind, x.item.id, x.members.map((m) => m.id)]), [['shift', 's1', ['p1']], ['payment', 'p2', []]]);
  });
  it('what exists again is not shown', () => {
    assert.equal(trashGroups([item('shifts', 's1', shift())], new Set(['shifts/s1'])).length, 0);
  });
});

describe('what a restore writes', () => {
  it('an employee comes back with everything deleted with her, exactly as stored', () => {
    const [g] = trashGroups([item('employees', 'e1', emp), item('shifts', 's1', shift({ paid: true, paymentId: 'p1' }), T - 1),
      item('payments', 'p1', { empId: 'e1', amount: 240, shiftIds: ['s1'] }, T - 1)], new Set());
    const { ops } = restorePlan(g, { live: live({}), payA });
    assert.deepEqual(ops.map((o) => [o.op, o.col, o.id]), [['set', 'employees', 'e1'], ['set', 'shifts', 's1'], ['set', 'payments', 'p1']]);
    assert.equal(ops[2].data.amount, 240);
  });
  it('a shift or payment of a deleted employee waits for her', () => {
    const [g] = trashGroups([item('shifts', 's1', shift())], new Set());
    assert.ok(restorePlan(g, { live: live({}), payA }).error);
  });
  it('an unpaid shift comes back as it was', () => {
    const [g] = trashGroups([item('shifts', 's1', shift())], new Set());
    const { ops } = restorePlan(g, { live: live({ 'employees/e1': emp }), payA });
    assert.deepEqual(ops, [{ op: 'set', col: 'shifts', id: 's1', data: shift() }]);
  });
  it('a paid shift goes back into its payment, with its sum', () => {
    const s = shift({ paid: true, paymentId: 'p1' });
    const [g] = trashGroups([item('shifts', 's1', s)], new Set());
    assert.deepEqual(neededRefs(g), [{ col: 'employees', id: 'e1' }, { col: 'payments', id: 'p1' }]);
    const { ops } = restorePlan(g, { live: live({ 'employees/e1': emp, 'payments/p1': { amount: 240.1, shiftIds: ['s2'] } }), payA });
    assert.deepEqual(ops[1], { op: 'update', col: 'payments', id: 'p1', data: { shiftIds: ['s2', 's1'], amount: 480.1 } });
  });
  it('a paid shift whose payment went with it: both come back', () => {
    const [g] = trashGroups([item('shifts', 's1', shift({ paid: true, paymentId: 'p1' })),
      item('payments', 'p1', { empId: 'e1', amount: 240, shiftIds: ['s1'] })], new Set());
    const { ops } = restorePlan(g, { live: live({ 'employees/e1': emp }), payA });
    assert.deepEqual(ops.map((o) => [o.op, o.col]), [['set', 'payments'], ['set', 'shifts']]);
  });
  it('a paid shift whose payment is gone for another reason comes back unpaid, and says so', () => {
    const [g] = trashGroups([item('shifts', 's1', shift({ paid: true, paidAt: 5, paymentId: 'p1' }))], new Set());
    const r = restorePlan(g, { live: live({ 'employees/e1': emp, 'payments/p1': null }), payA });
    assert.equal(r.ops[0].data.paid, false); assert.equal(r.ops[0].data.paymentId, null); assert.ok(r.note);
  });
  it('a payment marks its shifts paid again', () => {
    const [g] = trashGroups([item('payments', 'p1', { empId: 'e1', amount: 480, shiftIds: ['s1', 's2'], createdAt: 77 })], new Set());
    const { ops } = restorePlan(g, { live: live({ 'employees/e1': emp, 'shifts/s1': shift(), 'shifts/s2': shift() }), payA });
    assert.deepEqual(ops.slice(1), ['s1', 's2'].map((id) => ({ op: 'update', col: 'shifts', id, data: { paid: true, paidAt: 77, paymentId: 'p1' } })));
  });
  it('a payment is not restored when a shift was paid again since, is missing or still open', () => {
    const [g] = trashGroups([item('payments', 'p1', { empId: 'e1', amount: 480, shiftIds: ['s1', 's2'] })], new Set());
    const base = { 'employees/e1': emp, 'shifts/s1': shift() };
    for (const s2 of [shift({ paid: true, paymentId: 'p9' }), null, shift({ open: true, out: '' })]) {
      assert.ok(restorePlan(g, { live: live({ ...base, 'shifts/s2': s2 }), payA }).error);
    }
  });
});

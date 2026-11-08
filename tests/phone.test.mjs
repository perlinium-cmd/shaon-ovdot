// The manager's side of the employee phones (public/phone.js): approving requests and describing changes.
// Same behaviour as the Mac (FirestoreStore.decide, AppModel.describe). Run: npm test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  decisionOps, RequestError, REQUEST_ERRORS, localMillis, plainDoc, runningMinutes, describeNotice,
  pendingRequests, decidedRequests, unseenNotices,
} from '../public/phone.js';

const NOW = 'server-time';
const base = { now: NOW, newShiftId: 'new1', createdAt: 1000, rate: 42.5 };
const fixReq = (o = {}) => ({ id: 'r1', empId: 'e1', type: 'fix', shiftId: 's1', date: '2026-11-03', in: '08:00', out: '16:30', status: 'pending', ...o });
const addReq = (o = {}) => ({ id: 'r2', empId: 'e1', type: 'add', date: '2026-11-04', in: '09:00', out: '13:15', note: 'x', status: 'pending', ...o });
const shift = (o = {}) => ({ empId: 'e1', date: '2026-11-03', month: '2026-11', in: '08:00', out: '16:00', rate: 40, paid: false, ...o });
const throwsCode = (fn, code) => assert.throws(fn, (e) => e instanceof RequestError && e.code === code && e.message === REQUEST_ERRORS[code]);

test('reject: only the request changes', () => {
  assert.deepEqual(decisionOps({ ...base, req: fixReq(), approve: false }), [
    { op: 'update', col: 'requests', id: 'r1', data: { status: 'rejected', decidedAt: NOW } },
  ]);
});

test('a request that is no longer pending (decided elsewhere, or withdrawn) is left alone', () => {
  for (const status of ['approved', 'rejected', 'cancelled']) {
    throwsCode(() => decisionOps({ ...base, req: fixReq({ status }), shift: shift(), approve: true }), 'notPending');
    throwsCode(() => decisionOps({ ...base, req: addReq({ status }), approve: true }), 'notPending');
    throwsCode(() => decisionOps({ ...base, req: fixReq({ status }), approve: false }), 'notPending');
  }
  throwsCode(() => decisionOps({ ...base, req: null, approve: true }), 'notPending');
});

test('approve "add": a new shift at the current rate, marked as from a request', () => {
  assert.deepEqual(decisionOps({ ...base, req: addReq(), approve: true }), [
    {
      op: 'set', col: 'shifts', id: 'new1',
      data: {
        empId: 'e1', date: '2026-11-04', month: '2026-11', in: '09:00', out: '13:15',
        rate: 42.5, special: null, paid: false, paidAt: null, paymentId: null,
        source: 'request', requestId: 'r2', createdAt: 1000,
      },
    },
    { op: 'update', col: 'requests', id: 'r2', data: { status: 'approved', decidedAt: NOW, shiftId: 'new1' } },
  ]);
});

test('approve "fix" of a paid shift is refused, and of a missing shift too', () => {
  throwsCode(() => decisionOps({ ...base, req: fixReq(), shift: shift({ paid: true }), approve: true }), 'alreadyPaid');
  throwsCode(() => decisionOps({ ...base, req: fixReq(), shift: null, approve: true }), 'missingShift');
  throwsCode(() => decisionOps({ ...base, req: fixReq({ shiftId: undefined }), shift: shift(), approve: true }), 'missingShift');
});

test('approve "fix": new times, closes the shift, keeps the rate it was worked at', () => {
  const ops = decisionOps({ ...base, req: fixReq(), shift: shift({ open: true, out: '' }), approve: true });
  assert.deepEqual(ops, [
    { op: 'update', col: 'shifts', id: 's1', data: { in: '08:00', date: '2026-11-03', month: '2026-11', fixedBy: 'r1', out: '16:30', open: false } },
    { op: 'update', col: 'requests', id: 'r1', data: { status: 'approved', decidedAt: NOW } },
  ]);
});

test('approve "fix" of a phone shift with no rate yet: it gets the current rate', () => {
  for (const rate of [undefined, null]) {
    const [s] = decisionOps({ ...base, req: fixReq(), shift: shift({ rate }), approve: true });
    assert.equal(s.data.rate, 42.5);
  }
  const [kept] = decisionOps({ ...base, req: fixReq(), shift: shift({ rate: 0 }), approve: true });
  assert.equal('rate' in kept.data, false, 'a rate of 0 is a rate');
});

test('approve "fix" of only the clock-in of a running shift moves the phone clock (Israel time)', () => {
  const [s] = decisionOps({ ...base, req: fixReq({ out: '', in: '07:45', date: '2026-11-09' }), shift: shift({ open: true, out: '', date: '2026-11-09' }), approve: true });
  assert.deepEqual(s.data, { in: '07:45', date: '2026-11-09', month: '2026-11', fixedBy: 'r1', inAt: Date.UTC(2026, 10, 9, 5, 45) });
  assert.equal('out' in s.data, false);
  assert.equal('open' in s.data, false);
  // Not running any more: only the time changes, no clock.
  const [c] = decisionOps({ ...base, req: fixReq({ out: '' }), shift: shift({ open: false }), approve: true });
  assert.equal('inAt' in c.data, false);
});

test('a fix that moves the shift to another month updates its month', () => {
  const [s] = decisionOps({ ...base, req: fixReq({ date: '2026-10-31' }), shift: shift(), approve: true });
  assert.equal(s.data.month, '2026-10');
});

test('localMillis is Israel wall-clock time (summer and winter)', () => {
  assert.equal(localMillis('2026-07-01', '08:00'), Date.UTC(2026, 6, 1, 5, 0));
  assert.equal(localMillis('2026-12-01', '08:00'), Date.UTC(2026, 11, 1, 6, 0));
  assert.equal(localMillis('2026-12-01', 'x'), null);
  assert.equal(localMillis('', '08:00'), null);
});

test('plainDoc turns Timestamps into ms', () => {
  assert.deepEqual(plainDoc({ a: { toMillis: () => 5 }, b: 'x', c: null, d: 3 }), { a: 5, b: 'x', c: null, d: 3 });
});

test('runningMinutes', () => {
  assert.equal(runningMinutes({ open: true, inAt: 0 }, 90 * 60000), 90);
  assert.equal(runningMinutes({ open: true, inAt: 100 * 60000 }, 0), 0);
  assert.equal(runningMinutes({ open: false, inAt: 0 }, 1), null);
  assert.equal(runningMinutes({ open: true, date: '2026-12-01', in: '08:00' }, Date.UTC(2026, 11, 1, 7, 30)), 90);
});

test('lists: pending oldest first, decided newest first, unseen notices', () => {
  const list = [
    { id: 'a', status: 'pending', createdAt: 3 }, { id: 'b', status: 'pending', createdAt: 1 },
    { id: 'c', status: 'approved', createdAt: 1, decidedAt: 9 }, { id: 'd', status: 'cancelled', createdAt: 5 },
  ];
  assert.deepEqual(pendingRequests(list).map((r) => r.id), ['b', 'a']);
  assert.deepEqual(decidedRequests(list).map((r) => r.id), ['c', 'd']);
  assert.deepEqual(unseenNotices([{ id: 'x' }, { id: 'y', seen: true }]).map((n) => n.id), ['x']);
  assert.deepEqual(pendingRequests(null), []);
});

test('describeNotice: same wording as the Mac', () => {
  const o = { name: 'דנה', day: 'ב׳ 9/11' };
  const n = (x) => ({ empId: 'e1', shiftId: 's', date: '2026-11-09', ...x });
  assert.deepEqual(describeNotice(n({ type: 'manual', in: '07:30', out: '11:15' }), o),
    { title: 'דנה הזינה שעות', detail: 'ב׳ 9/11 · 07:30–11:15 · 3:45 שעות' });
  assert.deepEqual(describeNotice(n({ type: 'fix', in: '08:00', out: '16:10', prevIn: '08:00', prevOut: '' }), o),
    { title: 'דנה רשמה שעת יציאה', detail: 'ב׳ 9/11 · 08:00–16:10 · 8:10 שעות' });
  assert.deepEqual(describeNotice(n({ type: 'fix', in: '07:50', out: '', prevIn: '08:05', prevOut: '', edit: 2 }), o),
    { title: 'דנה שינתה שעת כניסה', detail: 'ב׳ 9/11 · כניסה 07:50 במקום 08:05 · עדיין במשמרת · שינוי שני במשמרת הזו' });
  assert.deepEqual(describeNotice(n({ type: 'fix', in: '08:00', out: '15:30', prevIn: '08:00', prevOut: '16:00' }), o),
    { title: 'דנה שינתה שעות', detail: 'ב׳ 9/11 · יציאה 15:30 במקום 16:00 · סה״כ 7:30 שעות במקום 8:00' });
});

// Firestore security rules tests. Runs against the local emulator only (project "demo-shaon").
// Run: npm run test:rules
import { describe, it, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, addDoc, collection, query, where, getDocs,
  writeBatch, serverTimestamp, deleteField, Timestamp, runTransaction, orderBy, limit,
} from 'firebase/firestore';
import { decisionOps, plainDoc, RequestError } from '../public/phone.js';
import * as fsMod from 'firebase/firestore';
import { writeWithTrash, trashId, TRASH_PER_BATCH } from '../public/trash.js';

const OWNER = 'boss';
const CODE = 'K7QM4XPA';
const KEY = 'aZ3kP9qW7xL2mN8vB4cR6tY1uE5oI0sD7fG3hJ9k';
const MIN = 60 * 1000;

let env;
const ctx = (uid, provider) => env.authenticatedContext(uid, { firebase: { sign_in_provider: provider, identities: {} } });
const ownerDb = () => ctx(OWNER, 'google.com').firestore();
const phoneDb = (uid = 'phone1') => ctx(uid, 'anonymous').firestore();
const u = (db, ...p) => doc(db, 'users', OWNER, ...p);

async function seed(fn) { await env.withSecurityRulesDisabled((c) => fn(c.firestore())); }

/** The manager creates a pairing code for an employee. */
const createPairing = (db, { code = CODE, empId = 'e1', expiresInMs = 10 * MIN } = {}) =>
  setDoc(doc(db, 'pairings', code), {
    ownerUid: OWNER, empId, empName: 'נועה',
    expiresAt: Timestamp.fromMillis(Date.now() + expiresInMs), createdAt: serverTimestamp(),
  });

/** A phone connects itself: its device record + marking the code used, in one batch. */
function pairBatch(db, uid, { code = CODE, empId = 'e1', markUsed = true, key = KEY, makeKey = true } = {}) {
  const b = writeBatch(db);
  b.set(u(db, 'devices', uid), { empId, pairCode: code, keyId: key, model: 'Pixel 8', pairedAt: serverTimestamp() });
  if (makeKey) b.set(u(db, 'deviceKeys', key), { empId, deviceId: uid, createdAt: serverTimestamp() });
  if (markUsed) b.update(doc(db, 'pairings', code), { usedBy: uid, usedAt: serverTimestamp() });
  return b.commit();
}

/** After a reinstall the app signs in as a new anonymous user and reconnects with its saved key. */
function rejoinBatch(db, uid, { oldUid = 'phone1', key = KEY, empId = 'e1', deleteOld = true } = {}) {
  const b = writeBatch(db);
  b.set(u(db, 'devices', uid), { empId, keyId: key, model: 'Pixel 8', pairedAt: serverTimestamp() });
  b.update(u(db, 'deviceKeys', key), { deviceId: uid });
  if (deleteOld) b.delete(u(db, 'devices', oldUid));
  return b.commit();
}

async function pairPhone(uid = 'phone1', empId = 'e1') {
  await seed((db) => setDoc(u(db, 'devices', uid), { empId, pairCode: 'SEEDED00', keyId: KEY, model: 'x', pairedAt: Timestamp.now() }));
}

/** Wall-clock day and time in Israel of a moment, as the phone writes them ("2026-11-05", "08:14"). */
const ilFmt = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Asia/Jerusalem', hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
});
const il = (ms) => {
  const p = Object.fromEntries(ilFmt.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  return { date: `${p.year}-${p.month}-${p.day}`, hm: `${p.hour}:${p.minute}` };
};

/** A clock-in as the phone writes it: the day and time are those of inAt (5 minutes ago unless given). */
const clockInData = (over = {}) => {
  const inAt = over.inAt ?? Date.now() - 5 * MIN;
  const t = il(inAt);
  return {
    empId: 'e1', date: t.date, month: t.date.slice(0, 7), in: t.hm, out: '',
    inAt, syncedAt: serverTimestamp(), source: 'phone', open: true, deviceId: 'phone1', createdAt: inAt,
    ...over,
  };
};
/** A clock-out at `outAt` (now unless given), as the phone writes it. */
const clockOutData = (outAt = Date.now()) => ({ out: il(outAt).hm, outAt, outSyncedAt: serverTimestamp(), open: false });

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-shaon',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});
after(async () => { await env?.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await seed(async (db) => {
    await setDoc(u(db, 'settings', 'main'), { defaultRate: 40, timeFormat: '24' });
    await setDoc(u(db, 'employees', 'e1'), { name: 'נועה', rate: 40, active: true });
    await setDoc(u(db, 'employees', 'e2'), { name: 'דנה', rate: 45, active: true });
    await setDoc(u(db, 'shifts', 'm1'), { empId: 'e1', date: '2026-11-02', month: '2026-11', in: '08:00', out: '14:00' });
    await setDoc(u(db, 'shifts', 'm2'), { empId: 'e2', date: '2026-11-02', month: '2026-11', in: '09:00', out: '13:00' });
    await setDoc(u(db, 'shifts', 'paid1'), { empId: 'e1', date: '2026-11-03', month: '2026-11', in: '08:00', out: '', source: 'phone', open: true, inAt: Date.now() - 60 * MIN, syncedAt: Timestamp.now(), paid: true });
    await setDoc(u(db, 'payments', 'p1'), { empId: 'e1', amount: 240, date: '2026-11-03', method: 'מזומן' });
    await setDoc(u(db, 'payments', 'p2'), { empId: 'e2', amount: 180, date: '2026-11-03', method: 'מזומן' });
  });
});

describe('manager', () => {
  it('reads and writes their own space', async () => {
    await assertSucceeds(getDoc(u(ownerDb(), 'shifts', 'm1')));
    await assertSucceeds(setDoc(u(ownerDb(), 'shifts', 'new'), { empId: 'e1', date: '2026-11-04', month: '2026-11', in: '08:00', out: '12:00' }));
  });
  it('another Google account cannot read it', async () => {
    await assertFails(getDoc(u(ctx('eve', 'google.com').firestore(), 'shifts', 'm1')));
  });
  it('an anonymous phone cannot open a private space of its own', async () => {
    const db = phoneDb();
    await assertFails(setDoc(doc(db, 'users', 'phone1', 'settings', 'main'), { x: 1 }));
  });
});

describe('pairing codes', () => {
  it('manager creates a code for their own employee', async () => {
    await assertSucceeds(createPairing(ownerDb()));
  });
  it('rejects a code for an employee that does not exist', async () => {
    await assertFails(createPairing(ownerDb(), { empId: 'ghost' }));
  });
  it('rejects a code that lives more than 15 minutes', async () => {
    await assertFails(createPairing(ownerDb(), { expiresInMs: 24 * 60 * MIN }));
  });
  it('rejects a short, guessable code', async () => {
    await assertFails(createPairing(ownerDb(), { code: 'ABC12' }));
  });
  it('a phone cannot create codes', async () => {
    await assertFails(createPairing(phoneDb()));
  });
  it('a phone can look up a code but cannot list codes', async () => {
    await createPairing(ownerDb());
    await assertSucceeds(getDoc(doc(phoneDb(), 'pairings', CODE)));
    await assertFails(getDocs(collection(phoneDb(), 'pairings')));
  });
  it('a phone pairs with a valid code and can then see that it is connected', async () => {
    await createPairing(ownerDb());
    await assertSucceeds(pairBatch(phoneDb(), 'phone1'));
    await assertSucceeds(getDoc(u(phoneDb(), 'devices', 'phone1')));
  });
  it('a code works only once', async () => {
    await createPairing(ownerDb());
    await pairBatch(phoneDb(), 'phone1');
    await assertFails(getDoc(doc(phoneDb('phone2'), 'pairings', CODE)));
    await assertFails(pairBatch(phoneDb('phone2'), 'phone2'));
  });
  it('an expired code does not work', async () => {
    await seed((db) => setDoc(doc(db, 'pairings', CODE), { ownerUid: OWNER, empId: 'e1', empName: 'נועה', expiresAt: Timestamp.fromMillis(Date.now() - MIN), createdAt: Timestamp.now() }));
    await assertFails(pairBatch(phoneDb(), 'phone1'));
  });
  it('a phone cannot pair itself to a different employee than the code says', async () => {
    await createPairing(ownerDb());
    await assertFails(pairBatch(phoneDb(), 'phone1', { empId: 'e2' }));
  });
  it('a phone must mark the code used in the same batch', async () => {
    await createPairing(ownerDb());
    await assertFails(pairBatch(phoneDb(), 'phone1', { markUsed: false }));
  });
  it('a phone cannot create a device record for someone else', async () => {
    await createPairing(ownerDb());
    await assertFails(pairBatch(phoneDb('phone1'), 'phone9'));
  });
});

describe('connect once, forever', () => {
  beforeEach(async () => {
    await createPairing(ownerDb());
    await pairBatch(phoneDb('phone1'), 'phone1');
  });

  it('pairing must create a reconnect key', async () => {
    await createPairing(ownerDb(), { code: 'ZZZZ9999' });
    await assertFails(pairBatch(phoneDb('phone2'), 'phone2', { code: 'ZZZZ9999', key: 'bZ3kP9qW7xL2mN8vB4cR6tY1uE5oI0sD7fG3hJ9k', makeKey: false }));
  });
  it('a reinstalled app reconnects by itself and the old install is removed', async () => {
    await assertSucceeds(rejoinBatch(phoneDb('phone1b'), 'phone1b'));
    await assertSucceeds(getDoc(u(phoneDb('phone1b'), 'shifts', 'm1')));
    await assertFails(getDoc(u(phoneDb('phone1'), 'shifts', 'm1')));
  });
  it('can reconnect again and again (every reinstall)', async () => {
    await rejoinBatch(phoneDb('phone1b'), 'phone1b');
    await assertSucceeds(rejoinBatch(phoneDb('phone1c'), 'phone1c', { oldUid: 'phone1b' }));
  });
  it('a wrong key does not reconnect', async () => {
    await assertFails(rejoinBatch(phoneDb('phone9'), 'phone9', { key: 'wrongwrongwrongwrongwrongwrongwrongwrong1' }));
  });
  it('the key cannot move the phone to another employee', async () => {
    await assertFails(rejoinBatch(phoneDb('phone9'), 'phone9', { empId: 'e2' }));
  });
  it('cannot delete another phone without taking over its key', async () => {
    await pairPhone('phone2', 'e1');
    await assertFails(deleteDoc(u(phoneDb('phone2'), 'devices', 'phone1')));
  });
  it('after the manager disconnects (device + key deleted), the key is dead', async () => {
    const db = ownerDb();
    const b = writeBatch(db);
    b.delete(u(db, 'devices', 'phone1'));
    b.delete(u(db, 'deviceKeys', KEY));
    await assertSucceeds(b.commit());
    await assertFails(rejoinBatch(phoneDb('phone1b'), 'phone1b', { deleteOld: false }));
  });
  it('keys cannot be listed', async () => {
    await assertFails(getDocs(collection(phoneDb('phone9'), 'users', OWNER, 'deviceKeys')));
  });
});

describe('restore card (survives reinstall)', () => {
  const RID = 'a'.repeat(64);
  const card = (uid, over = {}) => ({ ownerUid: OWNER, empId: 'e1', empName: 'נועה', keyId: KEY, deviceUid: uid, ...over });
  beforeEach(async () => { await createPairing(ownerDb()); await pairBatch(phoneDb('phone1'), 'phone1'); });

  it('a connected phone writes its card, and a fresh install can read it', async () => {
    await assertSucceeds(setDoc(doc(phoneDb('phone1'), 'restore', RID), card('phone1')));
    await assertSucceeds(getDoc(doc(phoneDb('phone1b'), 'restore', RID)));
  });
  it('cannot write a card for a key or employee it does not hold', async () => {
    await assertFails(setDoc(doc(phoneDb('phone1'), 'restore', RID), card('phone1', { keyId: 'x'.repeat(48) })));
    await assertFails(setDoc(doc(phoneDb('phone1'), 'restore', RID), card('phone1', { empId: 'e2' })));
    await assertFails(setDoc(doc(phoneDb('phone9'), 'restore', RID), card('phone9')));
  });
  it('cards cannot be listed, and ids must be full hashes', async () => {
    await assertFails(getDocs(collection(phoneDb('phone9'), 'restore')));
    await assertFails(getDoc(doc(phoneDb('phone9'), 'restore', 'short')));
  });
  it('after reconnecting, the new install updates the card', async () => {
    await setDoc(doc(phoneDb('phone1'), 'restore', RID), card('phone1'));
    await rejoinBatch(phoneDb('phone1b'), 'phone1b');
    await assertSucceeds(setDoc(doc(phoneDb('phone1b'), 'restore', RID), card('phone1b')));
  });
});

describe('connected phone: reading', () => {
  beforeEach(() => pairPhone());

  it('sees its own employee and the settings, not other employees', async () => {
    await assertSucceeds(getDoc(u(phoneDb(), 'employees', 'e1')));
    await assertSucceeds(getDoc(u(phoneDb(), 'settings', 'main')));
    await assertFails(getDoc(u(phoneDb(), 'employees', 'e2')));
  });
  it('sees its own shifts and payments only', async () => {
    await assertSucceeds(getDoc(u(phoneDb(), 'shifts', 'm1')));
    await assertFails(getDoc(u(phoneDb(), 'shifts', 'm2')));
    await assertSucceeds(getDocs(query(collection(phoneDb(), 'users', OWNER, 'shifts'), where('empId', '==', 'e1'), where('month', '==', '2026-11'))));
    await assertFails(getDocs(query(collection(phoneDb(), 'users', OWNER, 'shifts'), where('month', '==', '2026-11'))));
    await assertSucceeds(getDocs(query(collection(phoneDb(), 'users', OWNER, 'payments'), where('empId', '==', 'e1'))));
    await assertFails(getDoc(u(phoneDb(), 'payments', 'p2')));
  });
  it('an unpaired phone sees nothing', async () => {
    await assertFails(getDoc(u(phoneDb('phone2'), 'shifts', 'm1')));
    await assertFails(getDoc(u(phoneDb('phone2'), 'employees', 'e1')));
  });
  it('a disconnected phone loses access', async () => {
    await assertSucceeds(deleteDoc(u(ownerDb(), 'devices', 'phone1')));
    await assertFails(getDoc(u(phoneDb(), 'shifts', 'm1')));
  });
  it('cannot change or delete its device record', async () => {
    await assertFails(updateDoc(u(phoneDb(), 'devices', 'phone1'), { empId: 'e2' }));
    await assertFails(deleteDoc(u(phoneDb(), 'devices', 'phone1')));
  });
});

describe('connected phone: clock in / out', () => {
  beforeEach(() => pairPhone());
  const shifts = (db) => collection(db, 'users', OWNER, 'shifts');

  it('clocks in', async () => {
    await assertSucceeds(addDoc(shifts(phoneDb()), clockInData()));
  });
  it('cannot clock in for another employee', async () => {
    await assertFails(addDoc(shifts(phoneDb()), clockInData({ empId: 'e2' })));
  });
  it('cannot set a rate, special rate or paid flag', async () => {
    await assertFails(addDoc(shifts(phoneDb()), clockInData({ rate: 100 })));
    await assertFails(addDoc(shifts(phoneDb()), clockInData({ special: { rate: 100 } })));
    await assertFails(addDoc(shifts(phoneDb()), clockInData({ paid: true })));
  });
  it('cannot create a finished shift directly', async () => {
    await assertFails(addDoc(shifts(phoneDb()), clockInData({ out: '16:00' })));
    await assertFails(addDoc(shifts(phoneDb()), clockInData({ open: false })));
  });
  it('rejects bad dates, times and clocks', async () => {
    await assertFails(addDoc(shifts(phoneDb()), clockInData({ month: '2026-10' })));
    await assertFails(addDoc(shifts(phoneDb()), clockInData({ in: '25:00' })));
    await assertFails(addDoc(shifts(phoneDb()), clockInData({ inAt: Date.now() - 30 * 24 * 60 * MIN })));
    await assertFails(addDoc(shifts(phoneDb()), clockInData({ syncedAt: Timestamp.fromMillis(Date.now() - 5 * MIN) })));
  });

  it('clocks out of its own open shift, and can undo right after', async () => {
    const ref = await addDoc(shifts(phoneDb()), clockInData({ inAt: Date.now() - 300 * MIN }));
    await assertSucceeds(updateDoc(ref, clockOutData()));
    await assertSucceeds(updateDoc(ref, { out: '', outAt: deleteField(), outSyncedAt: deleteField(), open: true }));
  });
  it('the exit time must be the time it really is: a later exit can\'t add pay', async () => {
    const ref = await addDoc(shifts(phoneDb()), clockInData({ inAt: Date.now() - 300 * MIN }));
    await assertFails(updateDoc(ref, { ...clockOutData(), out: il(Date.now() + 180 * MIN).hm }));
    await assertFails(updateDoc(ref, { ...clockOutData(), out: il(Date.now() - 180 * MIN).hm }));
  });
  it('a shift running a day or more can\'t be clocked out as if it were short', async () => {
    const day = 24 * 60 * MIN;
    await seed((db) => setDoc(u(db, 'shifts', 'long'), clockInData({ inAt: Date.now() - day - 30 * MIN, syncedAt: Timestamp.now() })));
    await assertFails(updateDoc(u(phoneDb(), 'shifts', 'long'), clockOutData()));   // 08:00 → 08:30 next day ≠ half an hour
  });
  it('cannot change anything else while clocking out', async () => {
    const ref = await addDoc(shifts(phoneDb()), clockInData());
    await assertFails(updateDoc(ref, { out: '14:20', outAt: Date.now(), outSyncedAt: serverTimestamp(), open: false, in: '07:00' }));
    await assertFails(updateDoc(ref, { out: '14:20', outAt: Date.now(), outSyncedAt: serverTimestamp(), open: false, rate: 90 }));
  });
  it('cannot clock out before it clocked in', async () => {
    const ref = await addDoc(shifts(phoneDb()), clockInData());
    await assertFails(updateDoc(ref, { out: '07:00', outAt: Date.now() - 120 * MIN, outSyncedAt: serverTimestamp(), open: false }));
  });
  it('cannot edit shifts the manager entered, or paid shifts', async () => {
    await assertFails(updateDoc(u(phoneDb(), 'shifts', 'm1'), { out: '20:00' }));
    await assertFails(updateDoc(u(phoneDb(), 'shifts', 'paid1'), { out: '14:00', outAt: Date.now(), outSyncedAt: serverTimestamp(), open: false }));
  });
  it('can undo a fresh clock-in, but never delete other shifts', async () => {
    const ref = await addDoc(shifts(phoneDb()), clockInData());
    await assertSucceeds(deleteDoc(ref));
    await assertFails(deleteDoc(u(phoneDb(), 'shifts', 'm1')));
    await assertFails(deleteDoc(u(phoneDb(), 'shifts', 'paid1')));
  });
  it('cannot delete a shift once clocked out', async () => {
    const ref = await addDoc(shifts(phoneDb()), clockInData({ inAt: Date.now() - 120 * MIN }));
    await assertSucceeds(updateDoc(ref, clockOutData()));
    await assertFails(deleteDoc(ref));
  });
  it('cannot touch payments', async () => {
    await assertFails(addDoc(collection(phoneDb(), 'users', OWNER, 'payments'), { empId: 'e1', amount: 1000 }));
    await assertFails(updateDoc(u(phoneDb(), 'payments', 'p1'), { amount: 9999 }));
  });
});

describe('connected phone: correction requests', () => {
  beforeEach(() => pairPhone());
  const reqs = (db) => collection(db, 'users', OWNER, 'requests');
  const fix = (over = {}) => ({
    empId: 'e1', type: 'fix', shiftId: 'm1', date: '2026-11-02', in: '08:00', out: '14:30',
    note: 'שכחתי ללחוץ יציאה', status: 'pending', createdAt: serverTimestamp(), deviceId: 'phone1', ...over,
  });

  it('asks to fix its own shift, or to add a forgotten one', async () => {
    await assertSucceeds(addDoc(reqs(phoneDb()), fix()));
    const { shiftId, ...add } = fix({ type: 'add', date: '2026-11-01' });
    await assertSucceeds(addDoc(reqs(phoneDb()), add));
  });
  it('cannot ask about another employee\'s shift', async () => {
    await assertFails(addDoc(reqs(phoneDb()), fix({ shiftId: 'm2' })));
    await assertFails(addDoc(reqs(phoneDb()), fix({ empId: 'e2', shiftId: 'm2' })));
  });
  it('cannot approve its own request', async () => {
    await assertFails(addDoc(reqs(phoneDb()), fix({ status: 'approved' })));
    const ref = await addDoc(reqs(phoneDb()), fix());
    await assertFails(updateDoc(ref, { status: 'approved', decidedAt: serverTimestamp() }));
  });
  it('can withdraw a pending request and read its own requests', async () => {
    const ref = await addDoc(reqs(phoneDb()), fix());
    await assertSucceeds(getDocs(query(reqs(phoneDb()), where('empId', '==', 'e1'))));
    await assertSucceeds(updateDoc(ref, { status: 'cancelled', decidedAt: serverTimestamp() }));
  });
  it('can ask to fix the clock-in time of a shift that is still running', async () => {
    const ref = await addDoc(collection(phoneDb(), 'users', OWNER, 'shifts'), clockInData());
    await assertSucceeds(addDoc(reqs(phoneDb()), fix({ shiftId: ref.id, date: '2026-11-05', in: '07:30', out: '' })));
    const { shiftId, ...add } = fix({ type: 'add', out: '' });
    await assertFails(addDoc(reqs(phoneDb()), add));
  });
  it('rejects a very long note', async () => {
    await assertFails(addDoc(reqs(phoneDb()), fix({ note: 'א'.repeat(501) })));
  });
  it('the manager approves', async () => {
    const ref = await addDoc(reqs(phoneDb()), fix());
    await assertSucceeds(updateDoc(doc(ownerDb(), ref.path), { status: 'approved', decidedAt: serverTimestamp() }));
  });

  /** The website's approve/reject (public/data.js → decideRequest): one transaction with public/phone.js's writes. */
  const webDecide = (db, reqId, approve, rate = 40) => {
    const newRef = doc(collection(db, 'users', OWNER, 'shifts'));
    return runTransaction(db, async (tx) => {
      const rs = await tx.get(u(db, 'requests', reqId));
      const cur = rs.exists() ? { id: reqId, ...plainDoc(rs.data()) } : null;
      let shift = null;
      if (approve && cur?.type === 'fix' && cur.shiftId) {
        const ss = await tx.get(u(db, 'shifts', cur.shiftId));
        shift = ss.exists() ? ss.data() : null;
      }
      const ops = decisionOps({ req: cur, shift, approve, rate, now: serverTimestamp(), newShiftId: newRef.id, createdAt: Date.now() });
      for (const o of ops) { if (o.op === 'set') tx.set(u(db, o.col, o.id), o.data); else tx.update(u(db, o.col, o.id), o.data); }
      return newRef.id;
    });
  };
  it('the website approves a fix: the shift and the request change together', async () => {
    const ref = await addDoc(reqs(phoneDb()), fix());
    await assertSucceeds(webDecide(ownerDb(), ref.id, true));
    const s = (await getDoc(u(ownerDb(), 'shifts', 'm1'))).data();
    assert.equal(s.out, '14:30'); assert.equal(s.fixedBy, ref.id); assert.equal(s.rate, 40); assert.equal(s.open, false);
    assert.equal((await getDoc(doc(ownerDb(), ref.path))).data().status, 'approved');
    // Once decided, a second approval (another device) changes nothing.
    await assert.rejects(webDecide(ownerDb(), ref.id, true), (e) => e instanceof RequestError && e.code === 'notPending');
  });
  it('the website approves an add: one new shift from the request', async () => {
    const { shiftId, ...add } = fix({ type: 'add', date: '2026-11-01', in: '09:00', out: '12:00' });
    const ref = await addDoc(reqs(phoneDb()), add);
    const id = await webDecide(ownerDb(), ref.id, true, 42);
    const s = (await getDoc(u(ownerDb(), 'shifts', id))).data();
    assert.deepEqual([s.empId, s.date, s.in, s.out, s.rate, s.source, s.requestId, s.paid], ['e1', '2026-11-01', '09:00', '12:00', 42, 'request', ref.id, false]);
    assert.equal((await getDoc(doc(ownerDb(), ref.path))).data().shiftId, id);
    // The phone still sees its own new shift.
    await assertSucceeds(getDoc(u(phoneDb(), 'shifts', id)));
  });
  it('the website refuses to approve a fix of a paid shift, and nothing changes', async () => {
    const ref = await addDoc(reqs(phoneDb()), fix({ shiftId: 'paid1', date: '2026-11-03', in: '07:30', out: '' }));
    await assert.rejects(webDecide(ownerDb(), ref.id, true), (e) => e instanceof RequestError && e.code === 'alreadyPaid');
    assert.equal((await getDoc(doc(ownerDb(), ref.path))).data().status, 'pending');
    assert.equal((await getDoc(u(ownerDb(), 'shifts', 'paid1'))).data().in, '08:00');
  });
  it('the website rejects; a request the phone withdrew is not overwritten', async () => {
    const a = await addDoc(reqs(phoneDb()), fix());
    await assertSucceeds(webDecide(ownerDb(), a.id, false));
    assert.equal((await getDoc(doc(ownerDb(), a.path))).data().status, 'rejected');
    const b = await addDoc(reqs(phoneDb()), fix());
    await updateDoc(b, { status: 'cancelled', decidedAt: serverTimestamp() });
    await assert.rejects(webDecide(ownerDb(), b.id, false), (e) => e instanceof RequestError && e.code === 'notPending');
    assert.equal((await getDoc(doc(ownerDb(), b.path))).data().status, 'cancelled');
  });
});

describe('connected phone: saved without approval (with a notice for the manager)', () => {
  beforeEach(() => pairPhone());
  const shifts = (db) => collection(db, 'users', OWNER, 'shifts');
  const notices = (db) => collection(db, 'users', OWNER, 'notices');

  /** A forgotten shift typed in on the same day: the shift and its notice in one batch. */
  function manual(db, over = {}, { notice = true, noticeOver = {} } = {}) {
    const now = Date.now();
    const sRef = doc(shifts(db));
    const nRef = doc(notices(db));
    const b = writeBatch(db);
    b.set(sRef, {
      empId: 'e1', date: '2026-11-05', month: '2026-11', in: '08:00', out: '12:00', inAt: now - 300 * MIN, outAt: now - 60 * MIN,
      syncedAt: serverTimestamp(), source: 'phone', open: false, manual: true, createdAt: now, deviceId: 'phone1', noticeId: nRef.id, ...over,
    });
    if (notice) {
      b.set(nRef, {
        empId: 'e1', type: 'manual', shiftId: sRef.id, date: '2026-11-05', in: '08:00', out: '12:00',
        createdAt: serverTimestamp(), deviceId: 'phone1', ...noticeOver,
      });
    }
    return { commit: () => b.commit(), sRef, nRef };
  }

  /** Changes times of an existing phone shift (its `edits`-th change), with its notice. */
  function fix(db, id, change, { notice = true, edits = 1 } = {}) {
    const nRef = doc(notices(db));
    const b = writeBatch(db);
    b.update(u(db, 'shifts', id), { ...change, edited: true, edits, noticeId: nRef.id });
    if (notice) {
      b.set(nRef, {
        empId: 'e1', type: 'fix', shiftId: id, date: '2026-11-05', in: change.in ?? '08:14', out: change.out ?? '',
        prevIn: '08:14', prevOut: '', edit: edits, createdAt: serverTimestamp(), deviceId: 'phone1',
      });
    }
    return b.commit();
  }
  const clockIn = async () => (await addDoc(shifts(phoneDb()), clockInData())).id;

  it('adds a forgotten shift of today; the manager can read the notice, the phone cannot', async () => {
    const m = manual(phoneDb());
    await assertSucceeds(m.commit());
    await assertFails(getDoc(doc(phoneDb(), m.nRef.path)));
    await assertFails(getDocs(notices(phoneDb())));
    await assertSucceeds(getDoc(doc(ownerDb(), m.nRef.path)));
  });
  it('the website lists the notices (newest first) and marks them seen; the phone cannot', async () => {
    const m = manual(phoneDb());
    await m.commit();
    await assertSucceeds(getDocs(query(notices(ownerDb()), orderBy('createdAt', 'desc'), limit(150))));
    await assertFails(updateDoc(doc(phoneDb(), m.nRef.path), { seen: true }));
    await assertSucceeds(updateDoc(doc(ownerDb(), m.nRef.path), { seen: true }));
  });
  it('cannot add a shift without the notice, or a notice without a shift', async () => {
    await assertFails(manual(phoneDb(), {}, { notice: false }).commit());
    await assertFails(addDoc(notices(phoneDb()), {
      empId: 'e1', type: 'manual', shiftId: 'm1', date: '2026-11-05', in: '08:00', out: '12:00', createdAt: serverTimestamp(), deviceId: 'phone1',
    }));
  });
  it('an older shift, or one that has not ended yet, still needs a request', async () => {
    const day = 24 * 60 * MIN;
    await assertFails(manual(phoneDb(), { inAt: Date.now() - 3 * day - 300 * MIN, outAt: Date.now() - 3 * day }).commit());
    await assertFails(manual(phoneDb(), { inAt: Date.now() - 60 * MIN, outAt: Date.now() + 120 * MIN }).commit());
  });
  it('a typed-in shift must last as long as its times say', async () => {
    await assertFails(manual(phoneDb(), { out: '14:00' }).commit());   // 08:00–14:00 is 6 hours, but only 4 passed
    await assertFails(manual(phoneDb(), { inAt: Date.now() - 25 * 60 * MIN, outAt: Date.now() - 60 * MIN }).commit());   // a day and more
  });
  it('cannot set a rate or paid flag, or add for another employee', async () => {
    await assertFails(manual(phoneDb(), { rate: 100 }).commit());
    await assertFails(manual(phoneDb(), { paid: true }).commit());
    await assertFails(manual(phoneDb(), { empId: 'e2' }, { noticeOver: { empId: 'e2' } }).commit());
  });

  it('changes the clock-in of a running shift, earlier or later', async () => {
    const id = (await addDoc(shifts(phoneDb()), clockInData({ inAt: Date.now() - 120 * MIN }))).id;
    await assertSucceeds(fix(phoneDb(), id, { in: '06:44', inAt: Date.now() - 200 * MIN }));
    await assertSucceeds(fix(phoneDb(), id, { in: '07:30', inAt: Date.now() - 60 * MIN }, { edits: 2 }));
  });
  it('a clock-in in the future or far earlier, or without a notice, is refused', async () => {
    const id = await clockIn();
    await assertFails(fix(phoneDb(), id, { in: '11:00', inAt: Date.now() + 120 * MIN }));
    await assertFails(fix(phoneDb(), id, { in: '20:00', inAt: Date.now() - 13 * 60 * MIN }));
    await assertFails(fix(phoneDb(), id, { in: '06:44', inAt: Date.now() - 90 * MIN }, { notice: false }));
  });
  it('twice per shift at most, counted one by one', async () => {
    const id = await clockIn();
    await assertFails(fix(phoneDb(), id, { in: '06:44', inAt: Date.now() - 90 * MIN }, { edits: 2 }));   // can't skip
    await assertSucceeds(fix(phoneDb(), id, { in: '06:44', inAt: Date.now() - 90 * MIN }));
    await assertSucceeds(fix(phoneDb(), id, { in: '07:00', inAt: Date.now() - 80 * MIN }, { edits: 2 }));
    await assertFails(fix(phoneDb(), id, { in: '07:10', inAt: Date.now() - 70 * MIN }, { edits: 3 }));
    await assertFails(fix(phoneDb(), id, { in: '07:10', inAt: Date.now() - 70 * MIN }, { edits: 1 }));   // can't reset
  });
  it('clocks out at the time she really left, also a shift left open since an earlier day', async () => {
    const id = await clockIn();
    const a = Date.now() - 300 * MIN, b = Date.now() - 240 * MIN;
    await assertSucceeds(fix(phoneDb(), id, { in: il(a).hm, inAt: a, out: il(b).hm, outAt: b, outSyncedAt: serverTimestamp(), open: false }));
    const day = 24 * 60 * MIN, inAt = Date.now() - 3 * day;
    await seed((db) => setDoc(u(db, 'shifts', 'left-open'), clockInData({ inAt, syncedAt: Timestamp.now() })));
    await assertFails(fix(phoneDb(), 'left-open', { out: il(inAt + 30 * 60 * MIN).hm, outAt: inAt + 30 * 60 * MIN, outSyncedAt: serverTimestamp(), open: false }));
    await assertFails(fix(phoneDb(), 'left-open', { out: il(inAt + 600 * MIN).hm, outAt: inAt + 480 * MIN, outSyncedAt: serverTimestamp(), open: false }));   // says 10h, 8h passed
    await assertSucceeds(fix(phoneDb(), 'left-open', { out: il(inAt + 480 * MIN).hm, outAt: inAt + 480 * MIN, outSyncedAt: serverTimestamp(), open: false }));
  });
  it('changes the times of a shift that ended today, earlier or later, but not into the future', async () => {
    const id = (await addDoc(shifts(phoneDb()), clockInData({ inAt: Date.now() - 300 * MIN }))).id;
    const ref = u(phoneDb(), 'shifts', id);
    const outAt = Date.now() - 120 * MIN;
    await assertSucceeds(updateDoc(ref, clockOutData(outAt)));
    const at = (ms) => ({ out: il(ms).hm, outAt: ms });
    await assertFails(fix(phoneDb(), id, at(Date.now() + 120 * MIN)));
    await assertFails(fix(phoneDb(), id, { ...at(outAt + 60 * MIN), out: il(outAt + 180 * MIN).hm }));   // times say 2 more hours than passed
    await assertSucceeds(fix(phoneDb(), id, at(outAt + 60 * MIN)));
    const earlyIn = Date.now() - 330 * MIN;
    await assertSucceeds(fix(phoneDb(), id, { in: il(earlyIn).hm, inAt: earlyIn, ...at(outAt - 60 * MIN) }, { edits: 2 }));
    await assertFails(fix(phoneDb(), id, at(outAt - 30 * MIN), { edits: 3 }));
  });
  it('not for a shift that ended days ago, a paid one, or one the manager entered', async () => {
    const day = 24 * 60 * MIN;
    await seed((db) => setDoc(u(db, 'shifts', 'old'), {
      empId: 'e1', date: '2026-11-01', month: '2026-11', in: '08:00', out: '16:00', source: 'phone', open: false,
      inAt: Date.now() - 4 * day, outAt: Date.now() - 4 * day + 480 * MIN, syncedAt: Timestamp.now(),
    }));
    await assertFails(fix(phoneDb(), 'old', { out: '15:00', outAt: Date.now() - 4 * day + 420 * MIN }));
    await assertFails(fix(phoneDb(), 'paid1', { in: '07:00', inAt: Date.now() - 120 * MIN }));
    await assertFails(fix(phoneDb(), 'm1', { in: '07:00', inAt: Date.now() - 120 * MIN }));
  });
  it('cannot slip other changes into a fix', async () => {
    const id = await clockIn();
    await assertFails(fix(phoneDb(), id, { in: '06:44', inAt: Date.now() - 90 * MIN, rate: 99 }));
    await assertFails(fix(phoneDb(), id, { in: '06:44', inAt: Date.now() - 90 * MIN, date: '2026-11-04' }));
  });
});

describe('recycle bin (web data layer, public/trash.js)', () => {
  /** The web app's write path, against the emulator; returns how many batches it took. */
  async function write(ops, db = ownerDb()) {
    let batches = 0;
    await writeWithTrash({ fs: fsMod, db, ref: (c, id) => u(db, c, id), read: getDoc, by: OWNER, ops,
      commit: (b) => { batches++; return b.commit(); } });
    return batches;
  }
  const trash = async (col, id) => (await getDoc(u(ownerDb(), 'trash', trashId(col, id)))).data();

  it('a deleted shift is gone from shifts and kept whole in the bin', async () => {
    const before = (await getDoc(u(ownerDb(), 'shifts', 'm1'))).data();
    await write([{ op: 'delete', col: 'shifts', id: 'm1' }]);
    assert.equal((await getDoc(u(ownerDb(), 'shifts', 'm1'))).exists(), false);
    const t = await trash('shifts', 'm1');
    assert.deepEqual(t.data, before);
    assert.equal(t.col, 'shifts'); assert.equal(t.id, 'm1'); assert.equal(t.by, OWNER);
    assert.ok(t.deletedAt instanceof Timestamp);
  });
  it('deleting an employee with many shifts keeps every one, in small batches', async () => {
    const ops = [{ op: 'delete', col: 'employees', id: 'e1' }];
    await seed(async (db) => {
      for (let i = 0; i < 12; i++) {
        await setDoc(u(db, 'shifts', `bulk${i}`), { empId: 'e1', date: '2026-11-05', month: '2026-11', in: '08:00', out: '12:00', rate: 40 });
        ops.push({ op: 'delete', col: 'shifts', id: `bulk${i}` });
      }
    });
    const batches = await write(ops);
    assert.equal(batches, Math.ceil(13 / TRASH_PER_BATCH));
    assert.equal((await trash('employees', 'e1')).data.name, 'נועה');
    for (let i = 0; i < 12; i++) assert.equal((await trash('shifts', `bulk${i}`)).data.empId, 'e1');
  });
  it('a payment undone together with its shifts is still one batch (all or nothing)', async () => {
    const batches = await write([
      { op: 'delete', col: 'payments', id: 'p1' },
      { op: 'update', col: 'shifts', id: 'm1', data: { paid: false } },
      { op: 'update', col: 'shifts', id: 'paid1', data: { paid: false } },
    ]);
    assert.equal(batches, 1);
    assert.equal((await trash('payments', 'p1')).data.amount, 240);
  });
  it('delete, undo, delete again: the bin keeps the latest copy', async () => {
    await write([{ op: 'delete', col: 'shifts', id: 'm1' }]);
    const t = await trash('shifts', 'm1');
    await write([{ op: 'set', col: 'shifts', id: 'm1', data: { ...t.data, out: '18:00' } }]);
    await write([{ op: 'delete', col: 'shifts', id: 'm1' }]);
    assert.equal((await trash('shifts', 'm1')).data.out, '18:00');
  });
  it('deleting something already gone, or a phone record, writes no copy', async () => {
    await write([{ op: 'delete', col: 'shifts', id: 'nothing-here' }, { op: 'delete', col: 'notices', id: 'n0' }]);
    assert.equal(await trash('shifts', 'nothing-here'), undefined);
    assert.equal(await trash('notices', 'n0'), undefined);
  });
  it('phones cannot read or write the bin', async () => {
    await pairPhone();
    await write([{ op: 'delete', col: 'shifts', id: 'm1' }]);
    await assertFails(getDoc(u(phoneDb(), 'trash', trashId('shifts', 'm1'))));
    await assertFails(setDoc(u(phoneDb(), 'trash', 'shifts__x'), { col: 'shifts', id: 'x', data: { empId: 'e1' } }));
  });
});

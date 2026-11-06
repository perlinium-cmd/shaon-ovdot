// Plays the manager's Mac against the LOCAL Firebase emulators, for end-to-end tests of the phone app.
// Never touches real data (emulators only). Usage: node tests/e2e-manager.mjs <command> [args]
//   seed | pair | state | approve <id> | reject <id> | pay-all | rate <n> | disconnect | edit-open <out>
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, getDocs, collection, query, where, writeBatch, updateDoc, deleteDoc, Timestamp, serverTimestamp } from 'firebase/firestore';
import { shiftPay } from '../public/pay.js';

const OWNER = 'boss';
const env = await initializeTestEnvironment({
  projectId: 'shaon-ovdot-2c10',
  firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8080 },
});
const db = env.authenticatedContext(OWNER, { firebase: { sign_in_provider: 'google.com', identities: {} } }).firestore();
const u = (...p) => doc(db, 'users', OWNER, ...p);
const col = (n) => collection(db, 'users', OWNER, n);
const [cmd, arg] = process.argv.slice(2);
const pad = (n) => String(n).padStart(2, '0');
const today = (() => { const d = new Date(); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; })();

const pay = (s, rate) => shiftPay(s, null, rate);   // the same calculation as the apps

if (cmd === 'seed') {
  await env.clearFirestore();
  await setDoc(u('settings', 'main'), { defaultRate: 40, timeFormat: '24' });
  await setDoc(u('employees', 'e1'), { name: 'נועה', rate: null, active: true, createdAt: Date.now() });
  await setDoc(u('employees', 'e2'), { name: 'דנה', rate: 45, active: true, createdAt: Date.now() });
  const m = today.slice(0, 7);
  await setDoc(u('shifts', 'old1'), { empId: 'e1', date: `${m}-02`, month: m, in: '08:00', out: '14:00', rate: 40, special: null, paid: true, paidAt: Date.now() });
  await setDoc(u('shifts', 'old2'), { empId: 'e1', date: `${m}-03`, month: m, in: '08:00', out: '13:30', rate: 40, special: null, paid: false });
  await setDoc(u('shifts', 'other'), { empId: 'e2', date: `${m}-03`, month: m, in: '09:00', out: '12:00', rate: 45, special: null, paid: false });
  await setDoc(u('payments', 'p1'), { empId: 'e1', date: `${m}-04`, amount: 240, method: 'מזומן', shiftIds: ['old1'] });
  console.log('seeded: נועה (e1, default rate 40), דנה (e2)');
} else if (cmd === 'pair') {
  const abc = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const code = Array.from({ length: 8 }, () => abc[Math.floor(Math.random() * abc.length)]).join('');
  await setDoc(doc(db, 'pairings', code), { ownerUid: OWNER, empId: arg || 'e1', empName: arg === 'e2' ? 'דנה' : 'נועה', expiresAt: Timestamp.fromMillis(Date.now() + 10 * 60000), createdAt: serverTimestamp() });
  console.log(code);
} else if (cmd === 'state') {
  const [set, devs, keys, shifts, reqs] = await Promise.all([getDoc(u('settings', 'main')), getDocs(col('devices')), getDocs(col('deviceKeys')), getDocs(col('shifts')), getDocs(col('requests'))]);
  const rate = set.data()?.defaultRate;
  console.log('devices:', devs.docs.map((d) => `${d.id.slice(0, 6)}… emp=${d.data().empId} model=${d.data().model} key=${(d.data().keyId || '').slice(0, 6)}…`));
  console.log('keys:', keys.docs.map((d) => `${d.id.slice(0, 6)}… -> ${d.data().deviceId?.slice(0, 6)}…`));
  for (const d of shifts.docs.sort((a, b) => (a.data().date + a.data().in).localeCompare(b.data().date + b.data().in))) {
    const s = d.data();
    const gap = s.inAt && s.syncedAt ? Math.round((s.syncedAt.toMillis() - s.inAt) / 1000) : null;
    console.log(`shift ${d.id.slice(0, 6)} ${s.empId} ${s.date} ${s.in}-${s.out || '…'} open=${!!s.open} src=${s.source || 'manual'} rate=${s.rate ?? '-'} paid=${!!s.paid} pay=${pay(s, rate).toFixed(2)}${gap != null ? ` syncGap=${gap}s` : ''}${s.fixedBy ? ' fixed' : ''}`);
  }
  for (const d of reqs.docs) { const r = d.data(); console.log(`request ${d.id} ${r.type} ${r.date} ${r.in}-${r.out} "${r.note || ''}" ${r.status}${r.shiftId ? ' shift=' + r.shiftId.slice(0, 6) : ''}`); }
} else if (cmd === 'approve' || cmd === 'reject') {
  const r = (await getDoc(u('requests', arg))).data();
  const b = writeBatch(db);
  if (cmd === 'approve') {
    if (r.type === 'add') {
      const ref = doc(col('shifts'));
      b.set(ref, { empId: r.empId, date: r.date, month: r.date.slice(0, 7), in: r.in, out: r.out, rate: 40, special: null, paid: false, source: 'request', requestId: arg, createdAt: Date.now() });
      b.update(u('requests', arg), { status: 'approved', decidedAt: serverTimestamp(), shiftId: ref.id });
    } else {
      const upd = { in: r.in, date: r.date, month: r.date.slice(0, 7), fixedBy: arg };
      if (r.out) Object.assign(upd, { out: r.out, open: false });
      b.update(u('shifts', r.shiftId), upd);
      b.update(u('requests', arg), { status: 'approved', decidedAt: serverTimestamp() });
    }
  } else b.update(u('requests', arg), { status: 'rejected', decidedAt: serverTimestamp() });
  await b.commit(); console.log(cmd + 'd');
} else if (cmd === 'pay-all') {
  const s = await getDocs(query(col('shifts'), where('empId', '==', 'e1')));
  const ids = s.docs.filter((d) => !d.data().paid && !d.data().open).map((d) => d.id);
  const b = writeBatch(db); ids.forEach((id) => b.update(u('shifts', id), { paid: true, paidAt: Date.now() })); await b.commit();
  console.log('paid', ids.length);
} else if (cmd === 'disconnect') {
  const devs = await getDocs(col('devices'));
  const b = writeBatch(db);
  devs.docs.forEach((d) => { b.delete(d.ref); if (d.data().keyId) b.delete(u('deviceKeys', d.data().keyId)); });
  await b.commit(); console.log('disconnected', devs.size);
} else if (cmd === 'edit-open') {
  const s = await getDocs(query(col('shifts'), where('open', '==', true)));
  for (const d of s.docs) await updateDoc(d.ref, { out: arg, open: false });
  console.log('closed', s.size);
} else console.log('unknown command');
await env.cleanup();
process.exit(0);

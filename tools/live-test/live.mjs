#!/usr/bin/env node
// Live (production) test helper for the "testing" employee. See README.md.
// Acts as the manager (admin access through your Firebase CLI login), so it never touches anyone else's data:
// every command is limited to the test employee below.
//
//   node tools/live-test/live.mjs status            what the test employee has on the server
//   node tools/live-test/live.mjs code              new pairing code for the test phone (valid 14 min)
//   node tools/live-test/live.mjs approve|reject    decide the oldest pending request (like the Mac app)
//   node tools/live-test/live.mjs pay <id> [<id>…]  pay finished shifts as one payment (like the web app)
//   node tools/live-test/live.mjs left-open         a shift left open since yesterday 22:00 (forgot to clock out)
//   node tools/live-test/live.mjs disconnect        disconnect the test phone (like "נתק" on the Mac)
//   node tools/live-test/live.mjs totals            month totals computed with public/pay.js
import { list, get, set, del } from './fs.mjs';
import * as pay from '../../public/pay.js';

export const OWNER = 'qosj8BiaXERmxYLJLXvjodf9P0v1';
export const EMP = 'TESTINGqa0emp000000001';
const O = `users/${OWNER}`;
const mine = async (col) => (await list(`${O}/${col}`)).filter((x) => x.empId === EMP);
const id = (d) => d._path.split('/').pop();
const ts = (v) => (v == null ? v : new Date(v));   // REST returns timestamps as strings; write them back as timestamps

const cmds = {
  async status() {
    for (const c of ['devices', 'shifts', 'requests', 'notices', 'payments']) {
      const d = await mine(c);
      console.log(`== ${c} (${d.length})`);
      for (const x of d) {
        const { _path, syncedAt, outSyncedAt, deviceId, ...rest } = x;
        console.log(' ', id(x), JSON.stringify(rest));
      }
    }
  },
  async code() {
    const abc = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let code = '';
    for (let i = 0; i < 8; i++) code += abc[Math.floor(Math.random() * abc.length)];
    await set(`pairings/${code}`, { ownerUid: OWNER, empId: EMP, empName: 'testing', createdAt: new Date(), expiresAt: new Date(Date.now() + 14 * 60000) });
    console.log(code);
  },
  async approve() { await decide(true); },
  async reject() { await decide(false); },
  async pay(...ids) {
    if (!ids.length) throw new Error('usage: pay <shiftId> [<shiftId>…]');
    const emp = await get(`${O}/employees/${EMP}`);
    const st = await get(`${O}/settings/main`);
    const shifts = [];
    for (const s of ids) {
      const d = await get(`${O}/shifts/${s}`);
      if (!d || d.empId !== EMP || d.open || d.paid) throw new Error(`${s}: not a finished, unpaid shift of the test employee`);
      shifts.push(d);
    }
    const amountA = pay.sumAgorot(shifts, emp, st?.defaultRate);
    const pid = `QApay${Date.now()}`;
    const now = Date.now();
    await set(`${O}/payments/${pid}`, { empId: EMP, date: new Date().toISOString().slice(0, 10), amount: amountA / 100, method: 'מזומן', shiftIds: ids, createdAt: now });
    for (const d of shifts) {
      const { _path, ...s } = d;
      s.syncedAt = ts(s.syncedAt); s.outSyncedAt = ts(s.outSyncedAt);
      if (s.outSyncedAt == null) delete s.outSyncedAt;
      if (s.syncedAt == null) delete s.syncedAt;
      await set(_path, { ...s, paid: true, paidAt: now, paymentId: pid });
    }
    console.log(`${pid}: ${amountA / 100} ₪ for ${ids.length} shift(s)`);
  },
  async 'left-open'() {
    const dev = (await mine('devices'))[0];
    if (!dev) throw new Error('the test phone is not connected');
    const d = new Date(Date.now() - 86400000).toLocaleDateString('en-CA', { timeZone: pay.ZONE });
    const inAt = pay.zonedMs(pay.parseYMD(d), 22 * 60);
    const sid = `QAleftopen${Date.now()}`;
    await set(`${O}/shifts/${sid}`, { empId: EMP, date: d, month: d.slice(0, 7), in: '22:00', out: '', inAt, syncedAt: new Date(inAt), source: 'phone', open: true, deviceId: id(dev), createdAt: inAt });
    console.log(sid);
  },
  async disconnect() {
    for (const d of await mine('devices')) {
      await del(d._path);
      if (d.keyId) await del(`${O}/deviceKeys/${d.keyId}`);
      console.log('disconnected', id(d));
    }
  },
  async totals() {
    const emp = await get(`${O}/employees/${EMP}`);
    const st = await get(`${O}/settings/main`);
    const month = process.argv[3] || new Date().toLocaleDateString('en-CA', { timeZone: pay.ZONE }).slice(0, 7);
    const sh = (await mine('shifts')).filter((s) => !s.open && s.month === month);
    const a = pay.aggregate(sh, () => emp, st?.defaultRate).get(EMP) || pay.emptyAgg();
    const h = `${Math.floor(a.minutes / 60)}:${String(a.minutes % 60).padStart(2, '0')}`;
    console.log(`${month}: ${h} hours, earned ${a.pay} ₪, paid ${a.paidPay} ₪, left ${pay.unpaidOf(a)} ₪ (${sh.length} shifts)`);
  },
};

async function decide(approve) {
  const r = (await mine('requests')).filter((x) => x.status === 'pending').sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)))[0];
  if (!r) return console.log('no pending request');
  const { _path, ...req } = r;
  req.createdAt = ts(req.createdAt);
  if (!approve) { await set(_path, { ...req, status: 'rejected', decidedAt: new Date() }); return console.log('rejected', id(r)); }
  const emp = await get(`${O}/employees/${EMP}`);
  const st = await get(`${O}/settings/main`);
  const rate = pay.effRate(emp, st?.defaultRate);
  if (req.type === 'add') {
    const sid = `QAreq${Date.now()}`;
    await set(`${O}/shifts/${sid}`, { empId: EMP, date: req.date, month: req.date.slice(0, 7), in: req.in, out: req.out, rate, special: null, paid: false, paidAt: null, paymentId: null, source: 'request', requestId: id(r), createdAt: Date.now() });
    await set(_path, { ...req, status: 'approved', decidedAt: new Date(), shiftId: sid });
  } else {
    const { _path: sp, ...s } = await get(`${O}/shifts/${req.shiftId}`);
    if (s.paid) throw new Error('shift already paid');
    for (const k of ['syncedAt', 'outSyncedAt']) if (s[k] != null) s[k] = ts(s[k]);
    Object.assign(s, { in: req.in, date: req.date, month: req.date.slice(0, 7), fixedBy: id(r) });
    if (s.rate == null) s.rate = rate;
    if (req.out) Object.assign(s, { out: req.out, open: false });
    await set(sp, s);
    await set(_path, { ...req, status: 'approved', decidedAt: new Date() });
  }
  console.log('approved', id(r), req.type, req.date, req.in, req.out);
}

const [cmd, ...args] = process.argv.slice(2);
if (!cmds[cmd]) { console.log(Object.keys(cmds).join(' | ')); process.exit(1); }
await cmds[cmd](...args);

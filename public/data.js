// Data layer. Two interchangeable backends with the same API:
//   - Firebase (Firestore + Google sign-in) — production
//   - Demo (localStorage) — open the site with ?demo to try it without an account

import { decisionOps, plainDoc, localMillis } from './phone.js';

const DEMO = new URLSearchParams(location.search).has('demo');

export async function createStore() {
  return DEMO ? createDemoStore() : createFirebaseStore();
}

/* ---------------- Firebase ---------------- */

async function createFirebaseStore() {
  const V = '12.19.0';
  const base = `https://www.gstatic.com/firebasejs/${V}`;
  const [{ initializeApp }, auth, fs, { firebaseConfig }] = await Promise.all([
    import(`${base}/firebase-app.js`),
    import(`${base}/firebase-auth.js`),
    import(`${base}/firebase-firestore.js`),
    import('./firebase-config.js'),
  ]);

  const app = initializeApp(firebaseConfig);
  const a = auth.getAuth(app);
  a.languageCode = 'he';
  const db = fs.initializeFirestore(app, {
    localCache: fs.persistentLocalCache({ tabManager: fs.persistentMultipleTabManager() }),
  });

  const snapList = (snap) => snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  /** Docs the phones write carry server Timestamps (createdAt, pairedAt…): read them as ms numbers. */
  const plainList = (snap) => snap.docs.map((d) => ({ id: d.id, ...plainDoc(d.data({ serverTimestamps: 'estimate' })) }));

  /* Firestore applies a write on the device at once (the persistent cache keeps it in IndexedDB, so it
     survives the app closing or the device turning off) and sends it to the server when it can. Its promise,
     though, waits for the server — offline that can be hours. So the UI waits only briefly: after that the
     write is already safe on the device and syncs by itself. A failure that comes later goes to onLateError. */
  const settle = (p) => new Promise((resolve, reject) => {
    let late = false;
    const t = setTimeout(() => { late = true; resolve(); }, 1500);
    p.then((v) => { clearTimeout(t); resolve(v); }, (e) => {
      clearTimeout(t);
      if (late) store.onLateError?.(e); else reject(e);
    });
  });
  /** New doc with its id known right away (addDoc's ref only arrives with the server's reply). */
  const add = (name, data) => {
    const ref = fs.doc(colRef(name));
    return settle(fs.setDoc(ref, data)).then(() => ref);
  };
  /** Read from the device first, so undo snapshots don't stall while offline. */
  const getLocalFirst = async (ref) => {
    try { return await fs.getDocFromCache(ref); } catch { return fs.getDoc(ref); }
  };

  // Every Google account gets its own private space: users/{uid}/settings|employees|shifts
  let uid = null;
  const docRef = (...segs) => fs.doc(db, 'users', uid, ...segs);
  const colRef = (name) => fs.collection(db, 'users', uid, name);

  /** One-time move of data saved before per-user spaces existed (root collections, owner-only). */
  async function migrateLegacy() {
    // Checked once per account: on later starts it must not hold up opening the app (e.g. with no signal).
    const flag = `migrated-${uid}`;
    try { if (localStorage.getItem(flag)) return; } catch { /* ignore */ }
    const done = () => { try { localStorage.setItem(flag, '1'); } catch { /* ignore */ } };
    try {
      if ((await fs.getDoc(docRef('settings', 'main'))).exists()) { done(); return; }
      const [set, emps, shifts] = await Promise.all([
        fs.getDoc(fs.doc(db, 'settings', 'main')),
        fs.getDocs(fs.collection(db, 'employees')),
        fs.getDocs(fs.collection(db, 'shifts')),
      ]);
      if (!set.exists() && emps.empty) { done(); return; }
      const writes = [[docRef('settings', 'main'), { ...(set.exists() ? set.data() : {}), migratedAt: Date.now() }]];
      emps.forEach((d) => writes.push([docRef('employees', d.id), d.data()]));
      shifts.forEach((d) => writes.push([docRef('shifts', d.id), d.data()]));
      for (let i = 0; i < writes.length; i += 400) {
        const batch = fs.writeBatch(db);
        writes.slice(i, i + 400).forEach(([ref, data]) => batch.set(ref, data));
        await batch.commit();
      }
      done();
    } catch (e) {
      if (e?.code === 'permission-denied') done();
      else console.warn('legacy migration skipped', e);
    }
  }

  const store = {
    demo: false,
    onLateError: null,
    onAuth(cb) {
      return auth.onAuthStateChanged(a, async (u) => {
        uid = u ? u.uid : null;
        if (u) await migrateLegacy();
        cb(u ? { name: u.displayName, email: u.email } : null);
      });
    },
    async signIn() {
      const provider = new auth.GoogleAuthProvider();
      provider.setCustomParameters({ prompt: 'select_account' });
      try {
        await auth.signInWithPopup(a, provider);
      } catch (e) {
        if (e?.code === 'auth/popup-blocked' || e?.code === 'auth/operation-not-supported-in-this-environment') {
          await auth.signInWithRedirect(a, provider);
        } else {
          throw e;
        }
      }
    },
    signOut: () => auth.signOut(a),

    watchSettings(cb, onErr) {
      return fs.onSnapshot(docRef('settings', 'main'), (s) => cb(s.exists() ? s.data() : {}), onErr);
    },
    saveSettings: (data) => settle(fs.setDoc(docRef('settings', 'main'), data, { merge: true })),

    watchEmployees(cb, onErr) {
      return fs.onSnapshot(colRef('employees'), (s) => cb(snapList(s)), onErr);
    },
    addEmployee: (data) => add('employees', { ...data, createdAt: Date.now() }),
    updateEmployee: (id, data) => settle(fs.updateDoc(docRef('employees', id), data)),

    watchShifts(month, cb, onErr) {
      const q = fs.query(colRef('shifts'), fs.where('month', '==', month));
      return fs.onSnapshot(q, (s) => cb(snapList(s)), onErr);
    },
    addShift: (data) => add('shifts', { ...data, createdAt: Date.now() }),
    updateShift: (id, data) => settle(fs.updateDoc(docRef('shifts', id), data)),
    deleteShift: (id) => settle(fs.deleteDoc(docRef('shifts', id))),
    async updateShifts(ids, data) {
      for (let i = 0; i < ids.length; i += 400) {
        const batch = fs.writeBatch(db);
        ids.slice(i, i + 400).forEach((id) => batch.update(docRef('shifts', id), data));
        await settle(batch.commit());
      }
    },
    async countEmployeeShifts(id) {
      return (await fs.getDocs(fs.query(colRef('shifts'), fs.where('empId', '==', id)))).size;
    },
    /** Everything that belongs to one employee, as {col, id, data} — used for delete + undo.
     *  Includes her phones (device + reconnect key), so a deleted employee's phone can't keep clocking in. */
    async employeeBundle(id) {
      const byEmp = (col) => fs.getDocs(fs.query(colRef(col), fs.where('empId', '==', id)));
      const cols = ['shifts', 'payments', 'devices', 'deviceKeys', 'requests', 'notices'];
      const [emp, ...lists] = await Promise.all([fs.getDoc(docRef('employees', id)), ...cols.map(byEmp)]);
      return [
        ...(emp.exists() ? [{ col: 'employees', id, data: emp.data() }] : []),
        ...lists.flatMap((snap, i) => snap.docs.map((d) => ({ col: cols[i], id: d.id, data: d.data() }))),
      ];
    },
    /** A new document id, known before anything is written. */
    newId: (col) => fs.doc(colRef(col)).id,
    /** Several writes as one: all of them happen, or none (up to 450 per batch; [{op: set|update|delete, col, id, data}]). */
    async commit(ops) {
      for (let i = 0; i < ops.length; i += 450) {
        const batch = fs.writeBatch(db);
        for (const { op, col, id, data } of ops.slice(i, i + 450)) {
          if (op === 'set') batch.set(docRef(col, id), data);
          else if (op === 'update') batch.update(docRef(col, id), data);
          else batch.delete(docRef(col, id));
        }
        await settle(batch.commit());
      }
    },
    /** Current contents of the given docs ({col, id}) → [{col, id, data|null}]. */
    snapshot(items) {
      return Promise.all(items.map(async ({ col, id }) => {
        const d = await getLocalFirst(docRef(col, id));
        return { col, id, data: d.exists() ? d.data() : null };
      }));
    },
    /** Write docs back exactly (data null = delete). Used for delete-employee and undo. */
    async restore(snaps) {
      for (let i = 0; i < snaps.length; i += 400) {
        const batch = fs.writeBatch(db);
        snaps.slice(i, i + 400).forEach(({ col, id, data }) => (data ? batch.set(docRef(col, id), data) : batch.delete(docRef(col, id))));
        await settle(batch.commit());
      }
    },
    /** Before a rate change: write `rate` onto this employee's shifts that have none yet (shifts from her phone),
     *  so past work keeps the rate it was done at. Asks the server, not this device's copy, so no shift from a month
     *  that was never opened here is missed; with no connection it throws (code 'unavailable') and nothing changes. */
    async lockRates(empId, rate) {
      const snap = await fs.getDocsFromServer(fs.query(colRef('shifts'), fs.where('empId', '==', empId)));
      const ids = snap.docs.filter((d) => typeof d.data().rate !== 'number').map((d) => d.id);
      for (let i = 0; i < ids.length; i += 400) {
        const batch = fs.writeBatch(db);
        ids.slice(i, i + 400).forEach((id) => batch.update(docRef('shifts', id), { rate }));
        await settle(batch.commit());
      }
    },
    async getShiftsRange(from, to) {
      const q = fs.query(colRef('shifts'), fs.where('date', '>=', from), fs.where('date', '<=', to));
      return snapList(await fs.getDocs(q));
    },

    watchPayments(empId, cb, onErr) {
      return fs.onSnapshot(fs.query(colRef('payments'), fs.where('empId', '==', empId)), (s) => cb(snapList(s)), onErr);
    },
    addPayment: (data) => add('payments', { ...data, createdAt: Date.now() }),
    updatePayment: (id, data) => settle(fs.updateDoc(docRef('payments', id), data)),
    deletePayment: (id) => settle(fs.deleteDoc(docRef('payments', id))),

    /* ---------- employee phones (same as the Mac: FirestoreStore.swift) ---------- */
    /** Shifts running right now (clocked in from a phone), in any month. */
    watchOpenShifts(cb, onErr) {
      return fs.onSnapshot(fs.query(colRef('shifts'), fs.where('open', '==', true)), (s) => cb(plainList(s)), onErr);
    },
    watchDevices(cb, onErr) { return fs.onSnapshot(colRef('devices'), (s) => cb(plainList(s)), onErr); },
    watchRequests(cb, onErr) { return fs.onSnapshot(colRef('requests'), (s) => cb(plainList(s)), onErr); },
    watchNotices(cb, onErr) {
      const q = fs.query(colRef('notices'), fs.orderBy('createdAt', 'desc'), fs.limit(150));
      return fs.onSnapshot(q, (s) => cb(plainList(s)), onErr);
    },
    markNoticesSeen(ids) { return store.commit(ids.map((id) => ({ op: 'update', col: 'notices', id, data: { seen: true } }))); },
    /** Disconnect a phone: its record and its reconnect key go together, so it cannot reconnect by itself. */
    disconnect(d) {
      const batch = fs.writeBatch(db);
      batch.delete(docRef('devices', d.id));
      if (typeof d.keyId === 'string' && d.keyId) batch.delete(docRef('deviceKeys', d.keyId));
      return settle(batch.commit());
    },
    /** Approve or reject a request from the phone. One transaction: the request (still pending) and the shift
     *  (not paid) are read from the server and written together, so a paid shift is never changed and a request
     *  approved on two devices at once never adds two shifts. Needs a connection (offline: code 'unavailable'). */
    async decideRequest(req, approve, rate) {
      const reqRef = docRef('requests', req.id);
      const newRef = fs.doc(colRef('shifts'));
      await fs.runTransaction(db, async (tx) => {
        const rs = await tx.get(reqRef);
        const cur = rs.exists() ? { id: req.id, ...plainDoc(rs.data()) } : null;
        let shift = null;
        if (approve && cur?.type === 'fix' && cur.shiftId) {
          const ss = await tx.get(docRef('shifts', cur.shiftId));
          shift = ss.exists() ? ss.data() : null;
        }
        const ops = decisionOps({ req: cur, shift, approve, rate, now: fs.serverTimestamp(), newShiftId: newRef.id, createdAt: Date.now() });
        for (const { op, col, id, data } of ops) {
          if (op === 'set') tx.set(docRef(col, id), data); else tx.update(docRef(col, id), data);
        }
      });
    },
  };
  return store;
}

/* ---------------- Demo (localStorage) ---------------- */

const PHONE_COLS = ['devices', 'deviceKeys', 'requests', 'notices'];

/** Demo only: once there is an employee, pretend her phone is connected — a running shift, two requests waiting
 *  and a change saved on the phone — so the phone screens can be tried (like the Mac's demo). Once per demo. */
function seedPhoneDemo(data, uid) {
  if (data.phoneDemo) return false;
  const emps = Object.entries(data.employees).filter(([, e]) => e.active !== false)
    .sort(([, a], [, b]) => (a.createdAt || 0) - (b.createdAt || 0));
  if (!emps.length) return false;
  data.phoneDemo = true;
  const pad = (n) => String(n).padStart(2, '0');
  const day = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const hm = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  const now = Date.now();
  const [a] = emps[0];
  const b = (emps[1] || emps[0])[0];
  const devId = `ph-${uid()}`; const keyId = `k${uid()}${uid()}${uid()}${uid()}`;
  data.devices[devId] = { empId: a, model: 'Galaxy A54', pairedAt: now - 86400000, keyId };
  data.deviceKeys[keyId] = { empId: a, deviceId: devId, createdAt: now - 86400000 };
  // Clocked in 3:42 ago.
  const start = new Date(now - (3 * 60 + 42) * 60000);
  data.shifts[`live-${uid()}`] = {
    empId: a, date: day(start), month: day(start).slice(0, 7), in: hm(start), out: '',
    source: 'phone', open: true, inAt: start.getTime(), syncedAt: start.getTime() + 900, deviceId: devId, createdAt: start.getTime(),
  };
  // A forgotten shift (yesterday), and a fix of her last finished shift if she has one.
  const y = new Date(now - 86400000);
  data.requests[`r-${uid()}`] = {
    empId: a, type: 'add', date: day(y), in: '08:00', out: '12:30', note: 'שכחתי לרשום את המשמרת',
    status: 'pending', createdAt: now - 45 * 60000, deviceId: devId,
  };
  const last = Object.entries(data.shifts)
    .filter(([, s]) => s.empId === a && !s.open && !s.paid && s.out)
    .sort(([, p], [, q]) => String(q.date).localeCompare(String(p.date)) || String(q.in).localeCompare(String(p.in)))[0];
  if (last) {
    const [sid, s] = last;
    const [h, m] = s.out.split(':').map(Number);
    const later = `${pad((h + (m >= 30 ? 1 : 0)) % 24)}:${pad((m + 30) % 60)}`;
    data.requests[`r-${uid()}`] = {
      empId: a, type: 'fix', shiftId: sid, date: s.date, in: s.in, out: later, note: 'שכחתי ללחוץ יציאה',
      status: 'pending', createdAt: now - 30 * 60000, deviceId: devId,
    };
  }
  // A shift she typed in herself after work (saved without approval; the manager only hears about it).
  const typedDay = new Date(now).getHours() >= 12 ? day(new Date(now)) : day(y);
  const mid = `m-${uid()}`; const nid = `n-${uid()}`;
  data.shifts[mid] = {
    empId: b, date: typedDay, month: typedDay.slice(0, 7), in: '07:30', out: '11:15',
    inAt: localMillis(typedDay, '07:30'), outAt: localMillis(typedDay, '11:15'),
    source: 'phone', open: false, manual: true, deviceId: devId, noticeId: nid, createdAt: now - 20 * 60000,
  };
  data.notices[nid] = { empId: b, type: 'manual', shiftId: mid, date: typedDay, in: '07:30', out: '11:15', createdAt: now - 20 * 60000, deviceId: devId };
  return true;
}

function createDemoStore() {
  const KEY = 'shaon-demo-v1';
  const load = () => {
    try { return JSON.parse(localStorage.getItem(KEY)) || null; } catch { return null; }
  };
  let data = load() || { settings: {}, employees: {}, shifts: {} };
  data.payments ||= {};
  for (const c of PHONE_COLS) data[c] ||= {};
  const listeners = new Set();
  const persist = () => {
    try { localStorage.setItem(KEY, JSON.stringify(data)); } catch { /* ignore */ }
    listeners.forEach((fn) => fn());
  };
  const uid = () => Math.random().toString(36).slice(2, 12);
  const clone = (o) => JSON.parse(JSON.stringify(o));
  const watch = (fn) => {
    listeners.add(fn);
    queueMicrotask(fn);
    return () => listeners.delete(fn);
  };
  const delay = () => new Promise((r) => setTimeout(r, 120));
  const list = (col, keep = () => true) => Object.entries(data[col]).filter(([, d]) => keep(d)).map(([id, d]) => ({ id, ...clone(d) }));
  if (seedPhoneDemo(data, uid)) persist();

  return {
    demo: true,
    onAuth(cb) { queueMicrotask(() => cb({ name: 'מצב הדגמה', email: 'demo' })); return () => {}; },
    async signIn() {},
    async signOut() { localStorage.removeItem(KEY); location.reload(); },

    watchSettings: (cb) => watch(() => cb({ ...data.settings })),
    async saveSettings(d) { await delay(); data.settings = { ...data.settings, ...d }; persist(); },

    watchEmployees: (cb) => watch(() => cb(Object.entries(data.employees).map(([id, e]) => ({ id, ...e })))),
    async addEmployee(d) { await delay(); const id = uid(); data.employees[id] = { ...d, createdAt: Date.now() }; seedPhoneDemo(data, uid); persist(); return { id }; },
    async updateEmployee(id, d) { await delay(); data.employees[id] = { ...data.employees[id], ...d }; persist(); },

    watchShifts: (month, cb) => watch(() => cb(
      Object.entries(data.shifts).filter(([, s]) => s.month === month).map(([id, s]) => ({ id, ...s })),
    )),
    async addShift(d) { await delay(); const id = uid(); data.shifts[id] = { ...d, createdAt: Date.now() }; persist(); return { id }; },
    async updateShift(id, d) { await delay(); data.shifts[id] = { ...data.shifts[id], ...d }; persist(); },
    async deleteShift(id) { await delay(); delete data.shifts[id]; persist(); },
    async updateShifts(ids, d) { await delay(); ids.forEach((id) => { data.shifts[id] = { ...data.shifts[id], ...d }; }); persist(); },
    async countEmployeeShifts(id) { return Object.values(data.shifts).filter((s) => s.empId === id).length; },
    async employeeBundle(id) {
      const out = data.employees[id] ? [{ col: 'employees', id, data: clone(data.employees[id]) }] : [];
      for (const col of ['shifts', 'payments', ...PHONE_COLS]) {
        Object.entries(data[col]).forEach(([did, d]) => { if (d.empId === id) out.push({ col, id: did, data: clone(d) }); });
      }
      return out;
    },
    async snapshot(items) { return items.map(({ col, id }) => ({ col, id, data: data[col]?.[id] ? clone(data[col][id]) : null })); },
    async restore(snaps) {
      await delay();
      snaps.forEach(({ col, id, data: d }) => { data[col] ||= {}; if (d) data[col][id] = clone(d); else delete data[col][id]; });
      persist();
    },
    newId: () => uid(),
    async commit(ops) {
      await delay();
      // Same as a Firestore batch: an update of a missing document fails the whole batch.
      if (ops.some(({ op, col, id }) => op === 'update' && !data[col]?.[id])) throw Object.assign(new Error('not found'), { code: 'not-found' });
      for (const { op, col, id, data: d } of ops) {
        data[col] ||= {};
        if (op === 'set') data[col][id] = clone(d);
        else if (op === 'update') data[col][id] = { ...data[col][id], ...clone(d) };
        else delete data[col][id];
      }
      persist();
    },
    async lockRates(empId, rate) {
      Object.values(data.shifts).forEach((sh) => { if (sh.empId === empId && typeof sh.rate !== 'number') sh.rate = rate; });
      persist();
    },
    async getShiftsRange(from, to) {
      await delay();
      return Object.entries(data.shifts).filter(([, s]) => s.date >= from && s.date <= to).map(([id, s]) => ({ id, ...s }));
    },
    watchPayments: (empId, cb) => watch(() => cb(
      Object.entries(data.payments).filter(([, p]) => p.empId === empId).map(([id, p]) => ({ id, ...p })),
    )),
    async addPayment(d) { await delay(); const id = uid(); data.payments[id] = { ...d, createdAt: Date.now() }; persist(); return { id }; },
    async updatePayment(id, d) { await delay(); data.payments[id] = { ...data.payments[id], ...d }; persist(); },
    async deletePayment(id) { await delay(); delete data.payments[id]; persist(); },

    watchOpenShifts: (cb) => watch(() => cb(list('shifts', (s) => s.open === true))),
    watchDevices: (cb) => watch(() => cb(list('devices'))),
    watchRequests: (cb) => watch(() => cb(list('requests'))),
    watchNotices: (cb) => watch(() => cb(list('notices').sort((x, y) => (y.createdAt || 0) - (x.createdAt || 0)).slice(0, 150))),
    async markNoticesSeen(ids) { await delay(); ids.forEach((id) => { if (data.notices[id]) data.notices[id].seen = true; }); persist(); },
    async disconnect(d) {
      await delay();
      delete data.devices[d.id];
      if (typeof d.keyId === 'string' && d.keyId) delete data.deviceKeys[d.keyId];
      persist();
    },
    async decideRequest(req, approve, rate) {
      await delay();
      const cur = data.requests[req.id] ? { id: req.id, ...clone(data.requests[req.id]) } : null;
      const shift = approve && cur?.type === 'fix' && cur.shiftId && data.shifts[cur.shiftId] ? clone(data.shifts[cur.shiftId]) : null;
      const ops = decisionOps({ req: cur, shift, approve, rate, now: Date.now(), newShiftId: uid(), createdAt: Date.now() });
      for (const { op, col, id, data: d } of ops) data[col][id] = op === 'set' ? clone(d) : { ...data[col][id], ...clone(d) };
      persist();
    },
  };
}

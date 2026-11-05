// Data layer. Two interchangeable backends with the same API:
//   - Firebase (Firestore + Google sign-in) — production
//   - Demo (localStorage) — open the site with ?demo to try it without an account

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

  /* Firestore applies a write on the device at once (the persistent cache keeps it in IndexedDB, so it
     survives the app closing or the phone turning off) and sends it to the server when it can. Its promise,
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

    /* Open shifts: clocks/{empId} = {date, in, startedAt, note, special}. Kept apart from shifts so that a
       shift without an exit time never reaches totals, exports or the Mac app. */
    watchClocks(cb, onErr) {
      return fs.onSnapshot(colRef('clocks'), (s) => cb(snapList(s)), onErr);
    },
    setClock: (empId, data) => settle(fs.setDoc(docRef('clocks', empId), data)),
    clearClock: (empId) => settle(fs.deleteDoc(docRef('clocks', empId))),
    /** Exit recorded: the finished shift is added and the open one removed in one atomic write. */
    closeClock(empId, shift) {
      const ref = fs.doc(colRef('shifts'));
      const batch = fs.writeBatch(db);
      batch.set(ref, { ...shift, createdAt: Date.now() });
      batch.delete(docRef('clocks', empId));
      return settle(batch.commit()).then(() => ref);
    },
    async countEmployeeShifts(id) {
      return (await fs.getDocs(fs.query(colRef('shifts'), fs.where('empId', '==', id)))).size;
    },
    /** Everything that belongs to one employee, as {col, id, data} — used for delete + undo. */
    async employeeBundle(id) {
      const [emp, shifts, pays, clock] = await Promise.all([
        fs.getDoc(docRef('employees', id)),
        fs.getDocs(fs.query(colRef('shifts'), fs.where('empId', '==', id))),
        fs.getDocs(fs.query(colRef('payments'), fs.where('empId', '==', id))),
        getLocalFirst(docRef('clocks', id)).catch(() => null),
      ]);
      return [
        ...(emp.exists() ? [{ col: 'employees', id, data: emp.data() }] : []),
        ...(clock?.exists() ? [{ col: 'clocks', id, data: clock.data() }] : []),
        ...shifts.docs.map((d) => ({ col: 'shifts', id: d.id, data: d.data() })),
        ...pays.docs.map((d) => ({ col: 'payments', id: d.id, data: d.data() })),
      ];
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
  };
  return store;
}

/* ---------------- Demo (localStorage) ---------------- */

function createDemoStore() {
  const KEY = 'shaon-demo-v1';
  const load = () => {
    try { return JSON.parse(localStorage.getItem(KEY)) || null; } catch { return null; }
  };
  let data = load() || { settings: {}, employees: {}, shifts: {} };
  data.payments ||= {};
  data.clocks ||= {};
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

  return {
    demo: true,
    onAuth(cb) { queueMicrotask(() => cb({ name: 'מצב הדגמה', email: 'demo' })); return () => {}; },
    async signIn() {},
    async signOut() { localStorage.removeItem(KEY); location.reload(); },

    watchSettings: (cb) => watch(() => cb({ ...data.settings })),
    async saveSettings(d) { await delay(); data.settings = { ...data.settings, ...d }; persist(); },

    watchEmployees: (cb) => watch(() => cb(Object.entries(data.employees).map(([id, e]) => ({ id, ...e })))),
    async addEmployee(d) { await delay(); const id = uid(); data.employees[id] = { ...d, createdAt: Date.now() }; persist(); return { id }; },
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
      if (data.clocks[id]) out.push({ col: 'clocks', id, data: clone(data.clocks[id]) });
      for (const col of ['shifts', 'payments']) {
        Object.entries(data[col]).forEach(([did, d]) => { if (d.empId === id) out.push({ col, id: did, data: clone(d) }); });
      }
      return out;
    },
    async snapshot(items) { return items.map(({ col, id }) => ({ col, id, data: data[col][id] ? clone(data[col][id]) : null })); },
    async restore(snaps) {
      await delay();
      snaps.forEach(({ col, id, data: d }) => { if (d) data[col][id] = clone(d); else delete data[col][id]; });
      persist();
    },
    watchClocks: (cb) => watch(() => cb(Object.entries(data.clocks).map(([id, c]) => ({ id, ...c })))),
    async setClock(empId, d) { await delay(); data.clocks[empId] = clone(d); persist(); },
    async clearClock(empId) { await delay(); delete data.clocks[empId]; persist(); },
    async closeClock(empId, d) {
      await delay(); const id = uid();
      data.shifts[id] = { ...d, createdAt: Date.now() }; delete data.clocks[empId]; persist(); return { id };
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
  };
}

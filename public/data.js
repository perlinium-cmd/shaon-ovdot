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

  // Every Google account gets its own private space: users/{uid}/settings|employees|shifts
  let uid = null;
  const docRef = (...segs) => fs.doc(db, 'users', uid, ...segs);
  const colRef = (name) => fs.collection(db, 'users', uid, name);

  /** One-time move of data saved before per-user spaces existed (root collections, owner-only). */
  async function migrateLegacy() {
    try {
      if ((await fs.getDoc(docRef('settings', 'main'))).exists()) return;
      const [set, emps, shifts] = await Promise.all([
        fs.getDoc(fs.doc(db, 'settings', 'main')),
        fs.getDocs(fs.collection(db, 'employees')),
        fs.getDocs(fs.collection(db, 'shifts')),
      ]);
      if (!set.exists() && emps.empty) return;
      const writes = [[docRef('settings', 'main'), { ...(set.exists() ? set.data() : {}), migratedAt: Date.now() }]];
      emps.forEach((d) => writes.push([docRef('employees', d.id), d.data()]));
      shifts.forEach((d) => writes.push([docRef('shifts', d.id), d.data()]));
      for (let i = 0; i < writes.length; i += 400) {
        const batch = fs.writeBatch(db);
        writes.slice(i, i + 400).forEach(([ref, data]) => batch.set(ref, data));
        await batch.commit();
      }
    } catch (e) {
      if (e?.code !== 'permission-denied') console.warn('legacy migration skipped', e);
    }
  }

  return {
    demo: false,
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
    saveSettings: (data) => fs.setDoc(docRef('settings', 'main'), data, { merge: true }),

    watchEmployees(cb, onErr) {
      return fs.onSnapshot(colRef('employees'), (s) => cb(snapList(s)), onErr);
    },
    addEmployee: (data) => fs.addDoc(colRef('employees'), { ...data, createdAt: Date.now() }),
    updateEmployee: (id, data) => fs.updateDoc(docRef('employees', id), data),

    watchShifts(month, cb, onErr) {
      const q = fs.query(colRef('shifts'), fs.where('month', '==', month));
      return fs.onSnapshot(q, (s) => cb(snapList(s)), onErr);
    },
    addShift: (data) => fs.addDoc(colRef('shifts'), { ...data, createdAt: Date.now() }),
    updateShift: (id, data) => fs.updateDoc(docRef('shifts', id), data),
    deleteShift: (id) => fs.deleteDoc(docRef('shifts', id)),
    async updateShifts(ids, data) {
      for (let i = 0; i < ids.length; i += 400) {
        const batch = fs.writeBatch(db);
        ids.slice(i, i + 400).forEach((id) => batch.update(docRef('shifts', id), data));
        await batch.commit();
      }
    },
    async countEmployeeShifts(id) {
      return (await fs.getDocs(fs.query(colRef('shifts'), fs.where('empId', '==', id)))).size;
    },
    /** Everything that belongs to one employee, as {col, id, data} — used for delete + undo. */
    async employeeBundle(id) {
      const [emp, shifts, pays] = await Promise.all([
        fs.getDoc(docRef('employees', id)),
        fs.getDocs(fs.query(colRef('shifts'), fs.where('empId', '==', id))),
        fs.getDocs(fs.query(colRef('payments'), fs.where('empId', '==', id))),
      ]);
      return [
        ...(emp.exists() ? [{ col: 'employees', id, data: emp.data() }] : []),
        ...shifts.docs.map((d) => ({ col: 'shifts', id: d.id, data: d.data() })),
        ...pays.docs.map((d) => ({ col: 'payments', id: d.id, data: d.data() })),
      ];
    },
    /** Current contents of the given docs ({col, id}) → [{col, id, data|null}]. */
    snapshot(items) {
      return Promise.all(items.map(async ({ col, id }) => {
        const d = await fs.getDoc(docRef(col, id));
        return { col, id, data: d.exists() ? d.data() : null };
      }));
    },
    /** Write docs back exactly (data null = delete). Used for delete-employee and undo. */
    async restore(snaps) {
      for (let i = 0; i < snaps.length; i += 400) {
        const batch = fs.writeBatch(db);
        snaps.slice(i, i + 400).forEach(({ col, id, data }) => (data ? batch.set(docRef(col, id), data) : batch.delete(docRef(col, id))));
        await batch.commit();
      }
    },
    async getShiftsRange(from, to) {
      const q = fs.query(colRef('shifts'), fs.where('date', '>=', from), fs.where('date', '<=', to));
      return snapList(await fs.getDocs(q));
    },

    watchPayments(empId, cb, onErr) {
      return fs.onSnapshot(fs.query(colRef('payments'), fs.where('empId', '==', empId)), (s) => cb(snapList(s)), onErr);
    },
    addPayment: (data) => fs.addDoc(colRef('payments'), { ...data, createdAt: Date.now() }),
    updatePayment: (id, data) => fs.updateDoc(docRef('payments', id), data),
    deletePayment: (id) => fs.deleteDoc(docRef('payments', id)),
  };
}

/* ---------------- Demo (localStorage) ---------------- */

function createDemoStore() {
  const KEY = 'shaon-demo-v1';
  const load = () => {
    try { return JSON.parse(localStorage.getItem(KEY)) || null; } catch { return null; }
  };
  let data = load() || { settings: {}, employees: {}, shifts: {} };
  data.payments ||= {};
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

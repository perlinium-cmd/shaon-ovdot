// Recycle bin. An employee, shift or payment is never only deleted: a full copy of it, exactly as stored, goes to
// users/{uid}/trash/{col}__{id} in the same batch as the delete, so nothing with money in it is gone for good.
// The Mac app writes the same shape ({col, id, data, deletedAt, by}). Phones only ever delete a clock-in from the last
// minute (an open, unpaid shift with no pay in it), which the rules allow without a copy.

export const TRASHED = ['employees', 'shifts', 'payments'];
/** Trash copies per batch. The rules will check each copy against the live doc (a few document reads per delete,
 *  20 per batch at most), so all three apps cut deletes into batches of this size. A write with up to this many
 *  deletes stays one batch: all of it happens, or none. */
export const TRASH_PER_BATCH = 5;
const MAX_WRITES = 450;   // Firestore allows 500 writes per batch

export const trashId = (col, id) => `${col}__${id}`;

/**
 * Writes [{op: 'set'|'update'|'delete', col, id, data}] in as few batches as the limits allow.
 *   fs      the Firestore module (writeBatch, serverTimestamp)
 *   ref     (col, id) -> DocumentReference in the manager's space
 *   read    ref -> DocumentSnapshot (the app reads its own copy first, so this works offline)
 *   commit  batch -> Promise (the app's settle())
 */
export async function writeWithTrash({ fs, db, ref, read, commit, by, ops }) {
  let batch = fs.writeBatch(db), writes = 0, copies = 0;
  for (const { op, col, id, data } of ops) {
    const snap = op === 'delete' && TRASHED.includes(col) ? await read(ref(col, id)) : null;
    const copy = snap?.exists() ? snap.data() : null;
    const n = copy ? 2 : 1;
    if (writes && (writes + n > MAX_WRITES || (copy && copies === TRASH_PER_BATCH))) {
      await commit(batch);
      batch = fs.writeBatch(db); writes = 0; copies = 0;
    }
    if (copy) {
      batch.set(ref('trash', trashId(col, id)), { col, id, data: copy, deletedAt: fs.serverTimestamp(), by });
      copies++;
    }
    if (op === 'set') batch.set(ref(col, id), data);
    else if (op === 'update') batch.update(ref(col, id), data);
    else batch.delete(ref(col, id));
    writes += n;
  }
  if (writes) await commit(batch);
}

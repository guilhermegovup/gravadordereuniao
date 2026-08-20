// Banco local (IndexedDB): gravações com áudio (Blob), transcrição e resumo.

const DB_NAME = 'pauta';
const STORE = 'recordings';

let dbPromise = null;

function open() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE)) {
        db.createObjectStore(STORE, { keyPath: 'id' });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

function tx(mode, fn) {
  return open().then(
    (db) =>
      new Promise((resolve, reject) => {
        const t = db.transaction(STORE, mode);
        const store = t.objectStore(STORE);
        const result = fn(store);
        t.oncomplete = () => resolve(result.__value);
        t.onerror = () => reject(t.error);
        t.onabort = () => reject(t.error);
      })
  );
}

export async function allRecordings() {
  const db = await open();
  return new Promise((resolve, reject) => {
    const req = db.transaction(STORE, 'readonly').objectStore(STORE).getAll();
    req.onsuccess = () => {
      const list = req.result || [];
      list.sort((a, b) => b.createdAt - a.createdAt);
      resolve(list);
    };
    req.onerror = () => reject(req.error);
  });
}

export async function getRecording(id) {
  const db = await open();
  return new Promise((resolve, reject) => {
    const req = db.transaction(STORE, 'readonly').objectStore(STORE).get(id);
    req.onsuccess = () => resolve(req.result || null);
    req.onerror = () => reject(req.error);
  });
}

export function putRecording(rec) {
  return tx('readwrite', (store) => {
    store.put(rec);
    return { __value: rec };
  });
}

export function deleteRecording(id) {
  return tx('readwrite', (store) => {
    store.delete(id);
    return { __value: id };
  });
}

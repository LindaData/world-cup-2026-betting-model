// Tiny IndexedDB-backed review basket. No external deps.
// One object store; each row is { id, dataset_id, record, note, status, added_at }.

export type ReviewStatus =
  | "unmarked"
  | "looks_correct"
  | "needs_explanation"
  | "possible_data_issue"
  | "important_for_modeling";

export interface BasketItem {
  id: string;
  dataset_id: string;
  dataset_name: string;
  record: Record<string, unknown>;
  note: string;
  status: ReviewStatus;
  added_at: string;
}

const DB_NAME = "gsp_review_basket";
const STORE = "items";
const VERSION = 1;

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE)) {
        db.createObjectStore(STORE, { keyPath: "id" });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function tx<T>(mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const db = await openDb();
  return new Promise<T>((resolve, reject) => {
    const t = db.transaction(STORE, mode);
    const req = fn(t.objectStore(STORE));
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
    t.oncomplete = () => db.close();
  });
}

const listeners = new Set<() => void>();
export function subscribeBasket(cb: () => void) {
  listeners.add(cb);
  return () => {
    listeners.delete(cb);
  };
}
function notify() {
  listeners.forEach((l) => l());
}

export async function listBasket(): Promise<BasketItem[]> {
  try {
    const all = await tx<BasketItem[]>("readonly", (s) => s.getAll() as IDBRequest<BasketItem[]>);
    return all.sort((a, b) => (a.added_at < b.added_at ? 1 : -1));
  } catch {
    return [];
  }
}

export async function addToBasket(item: Omit<BasketItem, "id" | "added_at" | "note" | "status"> & Partial<BasketItem>) {
  const id =
    item.id ??
    `${item.dataset_id}:${
      (item.record &&
        (item.record.game_id ?? item.record.team_id ?? item.record.event_id ?? JSON.stringify(item.record).slice(0, 80))) ??
      crypto.randomUUID()
    }`;
  const full: BasketItem = {
    id: String(id),
    dataset_id: item.dataset_id,
    dataset_name: item.dataset_name,
    record: item.record,
    note: item.note ?? "",
    status: item.status ?? "unmarked",
    added_at: new Date().toISOString(),
  };
  await tx("readwrite", (s) => s.put(full));
  notify();
  return full;
}

export async function updateItem(id: string, patch: Partial<BasketItem>) {
  const existing = (await tx<BasketItem | undefined>("readonly", (s) => s.get(id) as IDBRequest<BasketItem | undefined>)) ?? null;
  if (!existing) return;
  await tx("readwrite", (s) => s.put({ ...existing, ...patch, id }));
  notify();
}

export async function removeItem(id: string) {
  await tx("readwrite", (s) => s.delete(id));
  notify();
}

export async function clearBasket() {
  await tx("readwrite", (s) => s.clear());
  notify();
}

export async function basketCount(): Promise<number> {
  try {
    return await tx<number>("readonly", (s) => s.count());
  } catch {
    return 0;
  }
}

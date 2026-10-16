// B02b: the outbox of the client portal, shared by the page and its service worker (no DOM here). Every send is first kept in the browser (IndexedDB), then sent in chunks of 1 MB
// that resume where they stopped; a send is "sent" only when the server has given its receipt. Waiting sends expire after 30 days.
(() => {
  "use strict";

  const DB = "lf-portal", STORE = "outbox";
  const DAY = 86400000, EXPIRY_DAYS = 30, WARNING_DAYS = 25;
  const hex = (buf) => Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
  const sha256 = async (blob) => hex(await crypto.subtle.digest("SHA-256", await blob.arrayBuffer()));

  const open = () => new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE, { keyPath: "id", autoIncrement: true });
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  const tx = async (mode, fn) => {
    const db = await open();
    return new Promise((resolve, reject) => {
      const t = db.transaction(STORE, mode);
      const out = fn(t.objectStore(STORE));
      t.oncomplete = () => { db.close(); resolve(out.result); };
      t.onerror = t.onabort = () => { db.close(); reject(t.error); };
    });
  };
  const all = () => tx("readonly", (s) => s.getAll());
  const save = (item) => tx("readwrite", (s) => s.put(item));
  const remove = (id) => tx("readwrite", (s) => s.delete(id));

  class Retry extends Error {}   // the network failed: try again later
  class Stop extends Error {}    // the server said no: this send will not work as it is
  class SignIn extends Error {}  // the session is over

  const outbox = { SHELL: "lf-portal-shell-v1", csrf: async () => undefined, all, save, remove, sha256 };

  const api = async (path, { method = "GET", json, body, headers = {} } = {}) => {
    let res;
    try {
      res = await fetch(path, { method, credentials: "same-origin", body: json ? JSON.stringify(json) : body,
        headers: { Accept: "application/json", "X-CSRF-Token": await outbox.csrf(), ...(json ? { "Content-Type": "application/json" } : {}), ...headers } });
    } catch (_) { throw new Retry("network"); }
    if (res.status === 401 || res.redirected) throw new SignIn();
    if (res.status >= 500) throw new Retry("server");
    const data = res.headers.get("Content-Type")?.includes("json") ? await res.json() : {};
    return { status: res.status, data };
  };

  // One file (or one page of a document): open a session, send what the server does not have, ask for the receipt.
  const sendPart = async (item, part, index) => {
    if (part.receipt) return;
    part.sha ||= await sha256(part.blob);
    for (let tries = 0; tries < 2; tries++) {
      if (!part.token) {
        const { status, data } = await api("/uploads", { method: "POST", json: { company: item.company, filename: part.name, byte_size: part.blob.size, sha256: part.sha,
          content_type: part.blob.type, hint_kind: item.hint_kind, hint_note: item.hint_note,
          ...(item.parts.length > 1 || item.kind === "photos" ? { batch_token: item.batch, page_number: index + 1, page_count: item.parts.length } : {}) } });
        if (status !== 201) throw new Stop(data.message || (data.errors || []).join(" ") || "This file cannot be sent.");
        part.token = data.token;
        await save(item);
      }
      const state = await api(`/uploads/${part.token}`);
      if (state.status === 404 || state.status === 410) { part.token = null; continue; } // the session is gone: open another
      const { chunk_size: size, chunk_count: count, received } = state.data;
      for (let pos = 0; pos < count; pos++) {
        if (received.includes(pos)) continue;
        const chunk = part.blob.slice(pos * size, (pos + 1) * size);
        const put = await api(`/uploads/${part.token}/chunks/${pos}`, { method: "PUT", body: chunk, headers: { "Content-Type": "application/octet-stream", "X-Chunk-SHA256": await sha256(chunk) } });
        if (put.status === 410) { part.token = null; break; }
        if (put.status >= 400) throw new Stop(put.data.error || "This file cannot be sent.");
      }
      if (!part.token) continue;
      const done = await api(`/uploads/${part.token}/complete`, { method: "POST" });
      if (done.status === 422 && done.data.missing) continue; // a chunk was lost on the way: the state says which
      if (done.status !== 200) throw new Stop(done.data.error || "This file cannot be sent.");
      part.receipt = done.data;
      await save(item);
      return;
    }
    throw new Retry("session");
  };

  // Sends what waits. => { retry: the network failed, signedOut: the session is over }
  // One at a time across the page and the worker (Web Locks); a call that finds the lock taken has nothing to do, the one that holds it will see what was added.
  outbox.run = () => navigator.locks ? navigator.locks.request("portal-outbox", { ifAvailable: true }, (lock) => (lock ? sendAll() : { retry: false, signedOut: false })) : sendAll();

  const sendAll = async () => {
    const result = { retry: false, signedOut: false };
    for (let again = true; again && !result.retry && !result.signedOut;) {
      again = false; // another pass only if something was sent: what was added meanwhile is seen
      for (const item of (await all()).filter((i) => i.state === "waiting")) {
        try {
          for (let i = 0; i < item.parts.length; i++) await sendPart(item, item.parts[i], i);
          await remove(item.id);
          again = true;
        } catch (e) {
          if (e instanceof Stop) { item.state = "failed"; item.error = e.message; await save(item); again = true; }
          else if (e instanceof SignIn) { result.signedOut = true; break; }
          else if (e instanceof Retry) { result.retry = true; break; }
          else throw e;
        }
      }
    }
    return result;
  };

  // What waits more than 30 days is deleted; what waits more than 25 is announced. => { removed, expiring }
  outbox.expire = async () => {
    const items = await all(), now = Date.now();
    const old = items.filter((i) => now - i.created_at > EXPIRY_DAYS * DAY);
    for (const item of old) await remove(item.id);
    return { removed: old.length, expiring: items.filter((i) => !old.includes(i) && i.state === "waiting" && now - i.created_at > WARNING_DAYS * DAY).length };
  };

  self.PortalOutbox = outbox;
})();

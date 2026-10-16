// B02b: sending files from the client portal. No library, no inline script (the portal's CSP allows only its own files).
// Every send is first kept in the browser (IndexedDB), then sent in chunks of 1 MB that resume where they stopped; a send is "sent" only when the server has given its receipt.
(() => {
  "use strict";

  const DB = "lf-portal", STORE = "outbox";
  const MAX_DELAY = 60000;
  const $ = (id) => document.getElementById(id);
  const hex = (buf) => Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
  const sha256 = async (blob) => hex(await crypto.subtle.digest("SHA-256", await blob.arrayBuffer()));
  const csrf = () => document.querySelector("meta[name=csrf-token]")?.content;

  // --- the outbox, in IndexedDB --------------------------------------------------------------------------------

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

  // --- talking to the server -----------------------------------------------------------------------------------

  class Retry extends Error {}   // the network failed: try again later
  class Stop extends Error {}    // the server said no: this send will not work as it is
  class SignIn extends Error {}  // the session is over

  const api = async (path, { method = "GET", json, body, headers = {} } = {}) => {
    let res;
    try {
      res = await fetch(path, { method, credentials: "same-origin", body: json ? JSON.stringify(json) : body,
        headers: { Accept: "application/json", "X-CSRF-Token": csrf(), ...(json ? { "Content-Type": "application/json" } : {}), ...headers } });
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

  // --- the loop ------------------------------------------------------------------------------------------------

  let running = false, delay = 1000, timer = null, signedOut = false;

  const run = async () => {
    if (running) return;
    running = true;
    clearTimeout(timer);
    timer = null;
    try {
      for (const item of (await all()).filter((i) => i.state === "waiting")) {
        try {
          for (let i = 0; i < item.parts.length; i++) await sendPart(item, item.parts[i], i);
          await remove(item.id);
          delay = 1000;
        } catch (e) {
          if (e instanceof Stop) { item.state = "failed"; item.error = e.message; await save(item); }
          else if (e instanceof SignIn) { signedOut = true; break; }
          else if (e instanceof Retry) { timer = setTimeout(run, delay); delay = Math.min(delay * 2, MAX_DELAY); break; }
          else throw e;
        }
      }
    } finally { running = false; render(); }
  };


  // --- photos: several pages, one document ---------------------------------------------------------------------

  // Smaller and lighter on a slow or saving connection. The server makes the PDF; here only the picture is prepared.
  const saver = () => { const c = navigator.connection; return !!(c && (c.saveData || ["slow-2g", "2g", "3g"].includes(c.effectiveType))); };
  const canvasBlob = (canvas, quality) => new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", quality));

  // Simple measures on a small copy, only to warn: a mean brightness, and the variance of the Laplacian (low = blurred). The person may go on.
  const analyze = (canvas) => {
    const w = 640, h = Math.max(1, Math.round(canvas.height * w / canvas.width));
    const small = document.createElement("canvas");
    small.width = w; small.height = h;
    const ctx = small.getContext("2d", { willReadFrequently: true });
    ctx.drawImage(canvas, 0, 0, w, h);
    const px = ctx.getImageData(0, 0, w, h).data;
    const gray = new Float32Array(w * h);
    let sum = 0;
    for (let i = 0; i < w * h; i++) { gray[i] = 0.299 * px[4 * i] + 0.587 * px[4 * i + 1] + 0.114 * px[4 * i + 2]; sum += gray[i]; }
    const mean = sum / (w * h);
    let acc = 0, acc2 = 0, n = 0;
    for (let y = 1; y < h - 1; y++) for (let x = 1; x < w - 1; x++) {
      const l = 4 * gray[y * w + x] - gray[y * w + x - 1] - gray[y * w + x + 1] - gray[(y - 1) * w + x] - gray[(y + 1) * w + x];
      acc += l; acc2 += l * l; n++;
    }
    const variance = acc2 / n - (acc / n) ** 2;
    return mean < 50 ? "The photo is too dark. Retake it?" : variance < 30 ? "The photo is blurry. Retake it?" : null;
  };

  const pages = [];

  const prepare = async (file) => {
    const edge = saver() ? 1280 : 2000, quality = saver() ? 0.6 : 0.8;
    try {
      const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
      const scale = Math.min(1, edge / Math.max(bitmap.width, bitmap.height));
      const canvas = document.createElement("canvas");
      canvas.width = Math.round(bitmap.width * scale);
      canvas.height = Math.round(bitmap.height * scale);
      canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height);
      return { canvas, blob: await canvasBlob(canvas, quality), warning: analyze(canvas), quality };
    } catch (_) {
      return { blob: file, canvas: null, warning: null }; // a format this browser cannot read (HEIC): the server will convert it
    }
  };

  const rotate = async (page) => {
    if (!page.canvas) return;
    const out = document.createElement("canvas");
    out.width = page.canvas.height; out.height = page.canvas.width;
    const ctx = out.getContext("2d");
    ctx.translate(out.width, 0); ctx.rotate(Math.PI / 2);
    ctx.drawImage(page.canvas, 0, 0);
    page.canvas = out;
    page.blob = await canvasBlob(out, page.quality);
  };

  const renderPages = () => {
    $("pages").replaceChildren(...pages.map((page, i) => {
      const li = document.createElement("li");
      li.className = "rounded border border-gray-200 p-2 text-sm";
      if (page.canvas) {
        const img = document.createElement("img");
        img.src = page.canvas.toDataURL("image/jpeg", 0.3);
        img.alt = `Page ${i + 1}`;
        img.className = "mb-1 h-24";
        li.append(img);
      } else li.append(`Page ${i + 1}`);
      const button = (label, fn) => { const b = document.createElement("button"); b.type = "button"; b.className = "mr-2 underline"; b.textContent = label; b.onclick = async () => { await fn(); renderPages(); }; return b; };
      const row = document.createElement("div");
      row.append(button("Rotate", () => rotate(page)), button("Remove", () => pages.splice(i, 1)));
      if (i > 0) row.append(button("Move up", () => pages.splice(i - 1, 0, ...pages.splice(i, 1))));
      if (i < pages.length - 1) row.append(button("Move down", () => pages.splice(i + 1, 0, ...pages.splice(i, 1))));
      if (page.warning) {
        const w = document.createElement("p");
        w.className = "text-amber-800";
        w.setAttribute("role", "alert");
        w.textContent = page.warning + " ";
        w.append(button("Keep it", () => { page.warning = null; }), button("Retake", () => pages.splice(i, 1)));
        li.append(w);
      }
      li.append(row);
      return li;
    }));
    $("send_pages").hidden = pages.length === 0;
    $("send_pages").textContent = `Send ${pages.length} ${pages.length === 1 ? "page" : "pages"}`;
  };

  // --- the screen ----------------------------------------------------------------------------------------------

  const render = async () => {
    const items = await all();
    const waiting = items.filter((i) => i.state === "waiting").length;
    $("pending").textContent = waiting ? `${waiting} waiting to be sent` : "";
    $("signin").hidden = !signedOut;
    $("outbox").replaceChildren(...items.map((item) => {
      const li = document.createElement("li");
      li.className = "rounded border border-gray-200 p-2 text-sm";
      const name = item.parts.map((p) => p.name).join(", ");
      li.textContent = item.state === "failed" ? `${name}: ${item.error}` : `${name}: ${item.state === "waiting" ? "waiting to be sent" : "sent"}`;
      const drop = document.createElement("button");
      drop.type = "button";
      drop.className = "ml-2 underline";
      drop.textContent = "Remove";
      drop.onclick = async () => { await remove(item.id); render(); };
      li.append(drop);
      return li;
    }));
  };

  const enqueue = async (parts, kind = "file") => {
    const item = { company: $("company").value, kind, parts, batch: crypto.randomUUID(), hint_kind: $("hint_kind").value, hint_note: $("hint_note").value.trim().slice(0, 300),
      state: "waiting", created_at: Date.now() };
    try { await save(item); } catch (e) {
      if (e?.name === "QuotaExceededError") { $("pending").textContent = "Your device is full. Send the pending documents first, then try again."; return; }
      throw e;
    }
    render();
    run();
  };
  window.portalUpload = { enqueue, run, render, all, save, remove, analyze };

  document.addEventListener("DOMContentLoaded", () => {
    $("pick").addEventListener("change", (e) => {
      for (const file of e.target.files) enqueue([{ name: file.name, blob: file }]);
      e.target.value = "";
    });
    $("camera").addEventListener("change", async (e) => {
      for (const file of e.target.files) pages.push(await prepare(file));
      e.target.value = "";
      renderPages();
    });
    $("send_pages").addEventListener("click", async () => {
      const parts = pages.map((p, i) => ({ name: `page-${i + 1}.jpg`, blob: p.blob }));
      pages.length = 0;
      renderPages();
      await enqueue(parts, "photos");
    });
    addEventListener("online", run);
    render();
    run();
  });
})();

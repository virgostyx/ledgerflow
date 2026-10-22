// B02b: the page for sending documents from the client portal. No library, no inline script (the portal's CSP allows only its own files). The sending itself is portal_outbox.js.
(() => {
  "use strict";

  const outbox = self.PortalOutbox;
  const $ = (id) => document.getElementById(id);
  const MAX_DELAY = 60000;
  outbox.csrf = async () => document.querySelector("meta[name=csrf-token]")?.content;

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
        const thumb = document.createElement("canvas"); // drawn, not loaded: the CSP allows no data: image
        thumb.height = 96;
        thumb.width = Math.round(96 * page.canvas.width / page.canvas.height);
        thumb.getContext("2d").drawImage(page.canvas, 0, 0, thumb.width, thumb.height);
        thumb.setAttribute("role", "img");
        thumb.setAttribute("aria-label", `Page ${i + 1}`);
        thumb.className = "mb-1";
        li.append(thumb);
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

  let delay = 1000, timer = null, signedOut = false, expiring = 0;

  const render = async () => {
    const items = await outbox.all();
    const waiting = items.filter((i) => i.state === "waiting").length;
    $("pending").textContent = (waiting ? `${waiting} waiting to be sent` : "") + (expiring ? ` — ${expiring} will be deleted in less than 5 days: open the portal on a good connection to send them.` : "");
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
      drop.onclick = async () => { await outbox.remove(item.id); render(); };
      li.append(drop);
      return li;
    }));
  };

  // Sends what waits; if the network fails, tries again after a wait that doubles (a minute at most), or at once when the browser says it is back online.
  const run = async () => {
    clearTimeout(timer);
    const result = await outbox.run();
    signedOut = result.signedOut;
    if (result.retry) { timer = setTimeout(run, delay); delay = Math.min(delay * 2, MAX_DELAY); } else delay = 1000;
    render();
  };

  const enqueue = async (parts, kind = "file") => {
    const item = { company: $("company").value, request_line: $("request_line")?.value, question: $("question")?.value, kind, parts, batch: crypto.randomUUID(), hint_kind: $("hint_kind").value, hint_note: $("hint_note").value.trim().slice(0, 300),
      state: "waiting", created_at: Date.now() };
    try { await outbox.save(item); } catch (e) {
      if (e?.name === "QuotaExceededError") { $("pending").textContent = "Your device is full. Send the pending documents first, then try again."; return; }
      throw e;
    }
    render();
    run();
    navigator.serviceWorker?.ready.then((reg) => reg.sync?.register("portal-outbox")).catch(() => {}); // the browser sends it later even if this page is closed, where it can
  };
  // The page and what it needs are kept for the next time the network is not there (the worker serves them, and renews them when it can).
  const warmShell = async () => {
    const urls = [ location.href, ...[ ...document.querySelectorAll("link[rel=stylesheet],script[src]") ].map((e) => e.href || e.src) ];
    await (await caches.open(outbox.SHELL)).addAll(urls);
  };

  window.portalUpload = { enqueue, run, render, analyze };

  document.addEventListener("DOMContentLoaded", async () => {
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
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/service-worker.js").then(() => navigator.serviceWorker.ready).then(warmShell).catch(() => {});
    }
    expiring = (await outbox.expire()).expiring;
    render();
    run();
  });
})();

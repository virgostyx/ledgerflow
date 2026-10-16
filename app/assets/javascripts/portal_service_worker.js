// B02b: the service worker of the client portal (served at /service-worker.js after portal_outbox.js, which it shares with the page). It keeps the page for sending documents
// available offline, and, where the browser has background sync, sends what waits when the network comes back, even with the page closed.
const SHELL = self.PortalOutbox.SHELL;

// No page is open here to read the forgery token from: it is read from the page for sending documents.
self.PortalOutbox.csrf = async () => {
  try { return (await (await fetch("/uploads/new", { credentials: "same-origin" })).text()).match(/name="csrf-token" content="([^"]+)"/)?.[1]; } catch (_) { return undefined; }
};

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil((async () => {
  for (const key of await caches.keys()) if (key !== SHELL) await caches.delete(key);
  await self.clients.claim();
})()));

self.addEventListener("fetch", (event) => {
  const { request } = event, url = new URL(request.url);
  if (request.method !== "GET" || url.origin !== location.origin) return;
  const shell = url.pathname === "/uploads/new" || url.pathname.startsWith("/assets/") || url.pathname === "/branding.css";
  if (!shell) return;
  // the page: from the network, from the copy when there is none; the files it needs: the copy, renewed behind
  event.respondWith((async () => {
    const cache = await caches.open(SHELL);
    const fetched = fetch(request).then((res) => { if (res.ok && !res.redirected) cache.put(request, res.clone()); return res; });
    if (url.pathname.startsWith("/assets/") || url.pathname === "/branding.css") return (await cache.match(request)) || fetched;
    try { return await fetched; } catch (_) { return (await cache.match(request)) || Response.error(); }
  })());
});

self.addEventListener("sync", (event) => {
  if (event.tag === "portal-outbox") event.waitUntil(self.PortalOutbox.run().then((r) => { if (r.retry) throw new Error("try again later"); }));
});

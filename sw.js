/* THAMC ERP service worker — network-first app shell + offline fallback */
const CACHE='thamc-erp-v3';
const SHELL=['./','./index.html','./support.js','./erp-data.js','./xlsx-lite.js','./assets/thamc_logo.jpg','./assets/thamc_mark.jpg',
  './icons/icon-192.png','./icons/icon-512.png','./icons/icon-180.png','./manifest.webmanifest'];
self.addEventListener('install',e=>{ self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then(c=>Promise.all(SHELL.map(u=>c.add(u).catch(()=>0))))); });
self.addEventListener('activate',e=>{ e.waitUntil(
  caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())); });
self.addEventListener('message',e=>{ if(e.data==='skipWaiting') self.skipWaiting(); });
self.addEventListener('fetch',e=>{ const req=e.request; if(req.method!=='GET') return;
  const url=new URL(req.url);
  // cross-origin data (supabase/api/fonts/qr) → network-first, cache fallback
  if(url.origin!==location.origin || /supabase|qrserver|githubusercontent|fonts\./.test(url.href)){
    e.respondWith(fetch(req).catch(()=>caches.match(req))); return; }
  // same-origin app code (html/js) → network-first so fixes always propagate; cache fallback offline
  if(req.mode==='navigate' || /\.(html|js)(\?|$)/.test(url.pathname)){
    e.respondWith(fetch(req).then(res=>{ const copy=res.clone(); caches.open(CACHE).then(c=>c.put(req,copy).catch(()=>0)); return res; })
      .catch(()=>caches.match(req).then(hit=>hit||caches.match('./index.html')))); return; }
  // static assets (icons/images/manifest) → cache-first
  e.respondWith(caches.match(req).then(hit=>hit||fetch(req).then(res=>{
    const copy=res.clone(); caches.open(CACHE).then(c=>c.put(req,copy).catch(()=>0)); return res;
  }).catch(()=>caches.match('./index.html')))); });

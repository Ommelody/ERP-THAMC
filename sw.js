/* THAMC ERP service worker — app-shell cache + offline */
const CACHE='thamc-erp-v1';
const SHELL=['./','./index.html','./support.js','./erp-data.js','./assets/thamc_logo.jpg',
  './icons/icon-192.png','./icons/icon-512.png','./icons/icon-180.png','./manifest.webmanifest'];
self.addEventListener('install',e=>{ self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then(c=>Promise.all(SHELL.map(u=>c.add(u).catch(()=>0))))); });
self.addEventListener('activate',e=>{ e.waitUntil(
  caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())); });
self.addEventListener('fetch',e=>{ const req=e.request; if(req.method!=='GET') return;
  const url=new URL(req.url);
  // network-first for supabase/api/cross-origin data; cache-first for same-origin shell/assets
  if(url.origin!==location.origin || /supabase|qrserver|githubusercontent|fonts\./.test(url.href)){
    e.respondWith(fetch(req).catch(()=>caches.match(req))); return; }
  e.respondWith(caches.match(req).then(hit=>hit||fetch(req).then(res=>{
    const copy=res.clone(); caches.open(CACHE).then(c=>c.put(req,copy).catch(()=>0)); return res;
  }).catch(()=>caches.match('./index.html')))); });
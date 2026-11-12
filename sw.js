const VERSION="tv-kalibracja-v1";
const SHELL=["./","./index.html","./styles.css","./app.js","./pattern.html","./manifest.json","./offline.html"];
self.addEventListener("install",event=>event.waitUntil(caches.open(VERSION).then(cache=>cache.addAll(SHELL)).then(()=>self.skipWaiting())));
self.addEventListener("activate",event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==VERSION).map(key=>caches.delete(key)))).then(()=>self.clients.claim())));
self.addEventListener("fetch",event=>{
  const request=event.request;
  if(request.method!=="GET")return;
  const url=new URL(request.url);
  if(url.origin!==self.location.origin)return;
  if(request.mode==="navigate"){
    event.respondWith(fetch(request).then(response=>{const copy=response.clone();caches.open(VERSION).then(cache=>cache.put(request,copy));return response;}).catch(async()=>await caches.match(request)||await caches.match("./offline.html")));
    return;
  }
  event.respondWith(caches.match(request).then(cached=>{
    const network=fetch(request).then(response=>{if(response.ok)caches.open(VERSION).then(cache=>cache.put(request,response.clone()));return response;}).catch(()=>cached);
    return cached||network;
  }));
});

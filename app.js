const $=s=>document.querySelector(s);
const video=$("#camera"),startBtn=$("#camera-start"),stopBtn=$("#camera-stop"),captureBtn=$("#capture");
let stream=null,dbPromise=null,lastMeasurements=[];
const DB_NAME="tv-kalibracja",DB_VERSION=2;
function openDB(){if(dbPromise)return dbPromise;dbPromise=new Promise((resolve,reject)=>{const req=indexedDB.open(DB_NAME,DB_VERSION);req.onupgradeneeded=()=>{const db=req.result;if(!db.objectStoreNames.contains("sessions"))db.createObjectStore("sessions",{keyPath:"id"});if(!db.objectStoreNames.contains("measurements")){const store=db.createObjectStore("measurements",{keyPath:"id"});store.createIndex("createdAt","createdAt");}};req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);});return dbPromise;}
async function dbWrite(storeName,value){const db=await openDB();return new Promise((resolve,reject)=>{const tx=db.transaction(storeName,"readwrite");tx.objectStore(storeName).put(value);tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error);});}
async function dbAll(storeName){const db=await openDB();return new Promise((resolve,reject)=>{const req=db.transaction(storeName).objectStore(storeName).getAll();req.onsuccess=()=>resolve(req.result||[]);req.onerror=()=>reject(req.error);});}
function setCameraState(on){startBtn.disabled=on;stopBtn.disabled=!on;captureBtn.disabled=!on;$("#camera-placeholder").classList.toggle("hidden",on);}
async function startCamera(){
 if(!navigator.mediaDevices?.getUserMedia){$("#camera-status").textContent="Brak obsługi kamery";return;}
 try{
  stream=await navigator.mediaDevices.getUserMedia({audio:false,video:{facingMode:{ideal:"environment"},width:{ideal:1920},height:{ideal:1080}}});
  video.srcObject=stream;await video.play();setCameraState(true);$("#camera-status").textContent="Aktywna";
  const track=stream.getVideoTracks()[0],caps=track.getCapabilities?.()||{},settings=track.getSettings?.()||{};
  const available=["exposureMode","whiteBalanceMode","focusMode"].filter(k=>caps[k]);
  $("#camera-controls").textContent=available.length?"Sterowanie dostępne: "+available.join(", "):"Automatyczne / brak ręcznej kontroli";
  $("#camera-controls").title=JSON.stringify(settings);
 }catch(error){$("#camera-status").textContent=error.name==="NotAllowedError"?"Brak zgody":"Błąd: "+error.message;stopCamera();}
}
function stopCamera(){if(stream)stream.getTracks().forEach(t=>t.stop());stream=null;video.srcObject=null;setCameraState(false);$("#camera-status").textContent="Zatrzymana";}
function median(values){const a=[...values].sort((x,y)=>x-y);return a[Math.floor(a.length/2)]??0;}
function sampleFrame(){
 if(!video.videoWidth||!video.videoHeight)throw new Error("Kamera nie dostarczyła obrazu.");
 const canvas=document.createElement("canvas"),ctx=canvas.getContext("2d",{willReadFrequently:true});
 const vw=video.videoWidth,vh=video.videoHeight,size=Math.max(24,Math.floor(Math.min(vw,vh)*.16));
 canvas.width=size;canvas.height=size;
 const sx=Math.floor((vw-size)/2),sy=Math.floor((vh-size)/2);
 ctx.drawImage(video,sx,sy,size,size,0,0,size,size);
 const {data}=ctx.getImageData(0,0,size,size),channels=[[],[],[]],lumas=[];
 for(let i=0;i<data.length;i+=4){channels[0].push(data[i]);channels[1].push(data[i+1]);channels[2].push(data[i+2]);lumas.push(.2126*data[i]+.7152*data[i+1]+.0722*data[i+2]);}
 const means=channels.map(a=>a.reduce((s,v)=>s+v,0)/a.length),luma=lumas.reduce((s,v)=>s+v,0)/lumas.length;
 const clipped=data.filter((v,i)=>i%4!==3&&(v<=2||v>=253)).length/(data.length*.75);
 const variance=lumas.reduce((s,v)=>s+(v-luma)**2,0)/lumas.length;
 return {rgb:means.map(v=>Number(v.toFixed(2))),luma:Number(luma.toFixed(2)),spread:Number(Math.sqrt(variance).toFixed(2)),clipped:Number((clipped*100).toFixed(2)),samplePixels:size*size};
}
async function captureMeasurement(){
 captureBtn.disabled=true;$("#measure-status").textContent="Pobieram serię próbek…";
 try{
  const frames=[];for(let i=0;i<5;i++){frames.push(sampleFrame());await new Promise(r=>requestAnimationFrame(()=>r()));}
  const rgb=[0,1,2].map(c=>median(frames.map(f=>f.rgb[c])));
  const luma=median(frames.map(f=>f.luma)),spread=median(frames.map(f=>f.spread)),clipped=median(frames.map(f=>f.clipped));
  const result={id:crypto.randomUUID(),createdAt:new Date().toISOString(),pattern:$("#pattern-name").textContent,rgb,luma,spread,clipped,frames:5,warning:"Camera RGB is device-processed and not colorimetrically calibrated."};
  await dbWrite("measurements",result);lastMeasurements.push(result);renderResult(result);await renderHistory();
  $("#measure-status").textContent="Zapisano 5 próbek. Powtórz po zmianie planszy, bez poruszania telefonem.";
 }catch(error){$("#measure-status").textContent="Nie udało się wykonać pomiaru: "+error.message;}
 finally{captureBtn.disabled=!stream;}
}
function renderResult(m){$("#measurement").classList.remove("hidden");["r","g","b"].forEach((k,i)=>$("#value-"+k).textContent=m.rgb[i]);$("#value-luma").textContent=m.luma+"/255";$("#value-spread").textContent=m.spread+" (odchylenie jasności)";$("#confidence").textContent=m.clipped>5?"Clipping wykryty":"Odczyt wstępny";}
async function renderHistory(){const items=(await dbAll("measurements")).sort((a,b)=>b.createdAt.localeCompare(a.createdAt)).slice(0,12);const host=$("#history");host.replaceChildren();if(!items.length){host.innerHTML='<p class="hint">Brak zapisanych pomiarów.</p>';return;}for(const m of items){const row=document.createElement("div");row.className="history-row";const title=document.createElement("strong"),detail=document.createElement("span");title.textContent=m.pattern;detail.textContent=new Date(m.createdAt).toLocaleString("pl-PL")+" · RGB "+m.rgb.join(" / ")+" · Y "+m.luma;row.append(title,detail);host.append(row);}}
$("#camera-start").addEventListener("click",startCamera);$("#camera-stop").addEventListener("click",stopCamera);captureBtn.addEventListener("click",captureMeasurement);
$("#export").addEventListener("click",async()=>{const report={device:"Samsung UE55TU7002KXXH",controller:"iPhone camera (browser capture)",exportedAt:new Date().toISOString(),limitations:["Not a colorimeter","Camera auto processing may alter RGB","No absolute luminance, gamma, white point or Delta E claims"],measurements:await dbAll("measurements")};const blob=new Blob([JSON.stringify(report,null,2)],{type:"application/json"}),url=URL.createObjectURL(blob),a=document.createElement("a");a.href=url;a.download="tv-kalibracja-report.json";a.click();URL.revokeObjectURL(url);});
document.querySelectorAll("[data-pattern-link]").forEach(a=>a.href="./pattern.html?pattern="+encodeURIComponent(a.dataset.patternLink));
renderHistory().catch(()=>{});
if("serviceWorker"in navigator&&location.protocol==="https:")addEventListener("load",()=>navigator.serviceWorker.register("./sw.js").catch(()=>{}),{once:true});

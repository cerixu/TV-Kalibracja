const statusEl=document.querySelector("#session-status");
const cameraEl=document.querySelector("#camera-status");
const startButton=document.querySelector("#start-session");

async function openDatabase(){
  return new Promise((resolve,reject)=>{
    const request=indexedDB.open("tv-kalibracja",1);
    request.onupgradeneeded=()=>{const db=request.result;if(!db.objectStoreNames.contains("sessions"))db.createObjectStore("sessions",{keyPath:"id"});};
    request.onsuccess=()=>resolve(request.result);
    request.onerror=()=>reject(request.error);
  });
}

async function saveSession(session){
  const db=await openDatabase();
  return new Promise((resolve,reject)=>{
    const tx=db.transaction("sessions","readwrite");
    tx.objectStore("sessions").put(session);
    tx.oncomplete=()=>{db.close();resolve();};
    tx.onerror=()=>{db.close();reject(tx.error);};
  });
}

async function checkCamera(){
  if(!navigator.mediaDevices?.getUserMedia){cameraEl.textContent="Brak obsługi kamery";return;}
  try{
    const stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:"environment"}},audio:false});
    stream.getTracks().forEach(track=>track.stop());
    cameraEl.textContent="Dostęp przyznany";
  }catch(error){
    cameraEl.textContent=error.name==="NotAllowedError"?"Brak zgody na kamerę":"Kamera niedostępna";
  }
}

startButton?.addEventListener("click",async()=>{
  startButton.disabled=true;
  try{
    const session={id:crypto.randomUUID(),createdAt:new Date().toISOString(),display:"Samsung UE55TU7002KXXH",mode:"gaming-sdr",status:"setup"};
    await saveSession(session);
    statusEl.textContent="Sesja utworzona. Następny krok: przygotowanie telewizora i plansz.";
    await checkCamera();
  }catch(error){
    statusEl.textContent="Nie udało się zapisać sesji. Sprawdź pamięć przeglądarki.";
  }finally{startButton.disabled=false;}
});

if("serviceWorker" in navigator && location.protocol==="https:"){
  window.addEventListener("load",()=>navigator.serviceWorker.register("./sw.js").catch(()=>{}),{once:true});
}

// W127: QForge-only real public 100T native WebView2 disconnect witness.
// The original Exchange data, actual websocket network transport and chart
// renderer are untouched. No fake executions, storage, order/auth APIs or
// synthetic UI events. Capture just the /ws/ticks connection to close it
// AFTER real bar pixels have been observed, verifying fail-closed behavior.
(function(win,doc){
'use strict';
const sourceSocket=win.WebSocket,tracked=[];
class WitnessSocket extends sourceSocket {
 constructor(url,protocols){
   if(protocols===undefined)super(url);
   else super(url,protocols);
   const loc=new URL(String(url),win.location.href);
   if((loc.protocol==='ws:'||loc.protocol==='wss:')&&
      loc.host===win.location.host&&loc.pathname==='/ws/ticks')tracked.push(this);
 }
}
win.WebSocket=WitnessSocket;
const output=doc.createElement('output');
output.id='w127-real-stale-native-proof';
output.setAttribute('role','status');
output.style.cssText='position:fixed;right:5px;bottom:38px;z-index:32000;'+
  'background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
  'font:12px Consolas,monospace;padding:4px 8px;pointer-events:none';
output.textContent='W127_REAL_READY';
doc.body.appendChild(output);
const announce=k=>{output.textContent='W127_REAL_'+k+'=PASS';};
const canvas=doc.getElementById('tickChartCanvas');
const status=doc.getElementById('tickChartStatus');
const inspection=doc.getElementById('tickInspectStatus');
const overlay=doc.getElementById('tickChartOverlay');
const select=doc.querySelector('.tick-tf-btn[data-ticks="100"]');
const zoom=doc.getElementById('tickZoomIn');
const timeframe=doc.querySelector('.tf-btn[data-tf="1m"]');
let trusted=false,blank='',currentBars='',blankVerified=false,staleVerified=false;
function fingerprint(){
  if(!canvas||typeof canvas.toDataURL!=='function')return '';
  try{return canvas.toDataURL('image/png')}catch(_){return ''}
}
function isStale(){return /^STALE — Disconnected · No fallback; choose a time interval or retry$/.test(status?.textContent||'');}
function cleanInspect(){return (inspection?.textContent||'')==='Hover a completed bar to inspect OHLCV';}
select?.addEventListener('click',e=>{
 if(e.isTrusted!==true||win.KTRADE_APP?.s?.symbol!=='BTC-USD')return;
 trusted=true;
 // Native handler runs after capture listener. The selected chart draws a
 // blank canvas synchronously, then subscribes to real public executions.
 win.setTimeout(()=>{
   if(tracked.length!==1)return;
   const s=status?.textContent||'';
   if((s.startsWith('Connecting 100T')||s.startsWith('Building 100T')) &&
      overlay?.hidden===false&&canvas?.width>=200&&canvas?.height>=100){
      blank=fingerprint();
   }
 },30);
 let checks=0;
 const watch=win.setInterval(()=>{
   if(++checks>420){win.clearInterval(watch);return}
   if(!trusted||!blank||tracked.length!==1||overlay?.hidden)return;
   if(select.getAttribute('aria-pressed')!=='true')return;
   if(!/^100T · [1-9][0-9]* completed session bars · Pine inputs unchanged$/.test(status?.textContent||''))return;
   const rendered=fingerprint();
   if(!rendered||rendered===blank||canvas.width<200||canvas.height<100)return;
   currentBars=rendered;
   win.clearInterval(watch);
   announce('100T_CANVAS');
   // One deliberate local read-only network interruption, no retry.
   // The backend's real feed was used to draw the candle before this.
   win.setTimeout(()=>tracked[0]?.close(1000,'W127 test-only disconnect'),650);
   let checks2=0;
   const after=win.setInterval(()=>{
     if(++checks2>96){win.clearInterval(after);return}
     const now=fingerprint();
     if(isStale()&&now===blank&&now!==currentBars&&
       cleanInspect()&&tracked.length===1&&
       tracked[0].readyState===sourceSocket.CLOSED){
       win.clearInterval(after);
       blankVerified=true;staleVerified=true;
       announce('DISCONNECT_CLEARS_CANVAS');
     }
   },150);
 },250);
},{capture:true});
canvas?.addEventListener('pointermove',e=>{
 if(!staleVerified||e.isTrusted!==true)return;
 win.setTimeout(()=>{
   if(isStale()&&cleanInspect()&&fingerprint()===blank)
     announce('HOVER_CLEARED');
 },200);
},{capture:true});
zoom?.addEventListener('click',e=>{
 if(!blankVerified||e.isTrusted!==true)return;
 win.setTimeout(()=>{
   if(isStale()&&cleanInspect()&&fingerprint()===blank&&tracked.length===1)
     announce('ZOOM_LOCKED');
 },250);
},{capture:true});
timeframe?.addEventListener('click',e=>{
 if(!staleVerified||e.isTrusted!==true)return;
 win.setTimeout(()=>{
   if(overlay?.hidden===true&&tracked.length===1&&
      Array.from(doc.querySelectorAll('.tick-tf-btn')).every(b=>
        b.getAttribute('aria-pressed')==='false'))
     announce('TIME_RETURN');
 },200);
},{capture:true});
})(window,document);

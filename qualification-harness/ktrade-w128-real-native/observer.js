// W128 exact-W126 source, QForge-only native Windows WebView2 acceptance.
// Unmodified public Coinbase matches+heartbeat supplies BOTH genuine bars.
// The sole fault is a local close of the first read-only /ws/ticks WebSocket.
// No synthetic events/executions, account/order routes, retry or persistent data.
(function(win,doc){
'use strict';
const NativeWebSocket=win.WebSocket, chartSockets=[];
class ObserveTickSocket extends NativeWebSocket {
 constructor(url,protocols){
   if(protocols===undefined)super(url);
   else super(url,protocols);
   const u=new URL(String(url),win.location.href);
   if((u.protocol==='ws:'||u.protocol==='wss:')&&u.host===win.location.host&&
      u.pathname==='/ws/ticks'&&u.searchParams.get('count')==='100'&&
      u.searchParams.get('product')==='BTC-USD')chartSockets.push(this);
 }
}
win.WebSocket=ObserveTickSocket;
const out=doc.createElement('output');
out.id='w128-real-native-recovery-proof';out.setAttribute('role','status');
out.style.cssText='position:fixed;right:5px;bottom:38px;z-index:32000;'+
 'background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
 'font:12px Consolas,monospace;padding:4px 8px;pointer-events:none';
out.textContent='W128_REAL_READY';doc.body.appendChild(out);
const emit=name=>{out.textContent='W128_REAL_'+name+'=PASS'};
const sel=doc.querySelector('.tick-tf-btn[data-ticks="100"]');
const time=doc.querySelector('.tf-btn[data-tf="1m"]');
const zoom=doc.getElementById('tickZoomIn');
const canvas=doc.getElementById('tickChartCanvas');
const status=doc.getElementById('tickChartStatus');
const inspect=doc.getElementById('tickInspectStatus');
const overlay=doc.getElementById('tickChartOverlay');
let clicks=0,blank='',firstPaint='',staleVerified=false,zoomVerified=false;
let noAuto=false,freshBlankVerified=false,freshPaintVerified=false,cleanHover=false;
const stale=()=>/^STALE — Disconnected · No fallback; choose a time interval or retry$/.test(status?.textContent||'');
const cleared=()=>inspect?.textContent==='Hover a completed bar to inspect OHLCV';
function pixels(){
 if(!canvas||typeof canvas.toDataURL!=='function')return '';
 try{return canvas.toDataURL('image/png')}catch(_){return ''}
}
function watch(maxChecks,predicate,success){
 let checks=0;const timer=win.setInterval(()=>{
  if(++checks>maxChecks){win.clearInterval(timer);return}
  if(predicate()){win.clearInterval(timer);success()}
 },250);
}
sel?.addEventListener('click',event=>{
 if(event.isTrusted!==true||win.KTRADE_APP?.s?.symbol!=='BTC-USD')return;
 clicks++;
 if(clicks===1){
  win.setTimeout(()=>{
   if(chartSockets.length===1&&overlay?.hidden===false&&
      /^(Connecting|Building) 100T/.test(status?.textContent||'')&&
      canvas?.width>=200&&canvas?.height>=100)blank=pixels();
  },30);
  watch(460,()=>!!blank&&chartSockets.length===1&&overlay?.hidden===false&&
   sel.getAttribute('aria-pressed')==='true'&&
   /^100T · [1-9][0-9]* completed session bars · Pine inputs unchanged$/.test(status?.textContent||'')&&
   !!pixels()&&pixels()!==blank&&canvas.width>=200&&canvas.height>=100,()=>{
    firstPaint=pixels();emit('FIRST_100T_CANVAS');
    win.setTimeout(()=>chartSockets[0]?.close(1000,'W128 local read-only disconnect'),550);
    watch(96,()=>stale()&&pixels()===blank&&pixels()!==firstPaint&&
      cleared()&&chartSockets.length===1&&
      chartSockets[0].readyState===NativeWebSocket.CLOSED,()=>{
      staleVerified=true;emit('DISCONNECT_CLEARS_CANVAS');
    });
   });
 }else if(clicks===2&&noAuto&&staleVerified){
   // This is a genuine second native Windows click, never a JS click().
   win.setTimeout(()=>{
    if(chartSockets.length!==2||chartSockets[0]===chartSockets[1]||
       chartSockets[0].readyState!==NativeWebSocket.CLOSED||
       !/^(Connecting|Building) 100T/.test(status?.textContent||'')||
       overlay?.hidden!==false||sel.getAttribute('aria-pressed')!=='true'||
       pixels()!==blank||!cleared())return;
    freshBlankVerified=true;emit('NEW_EPOCH_BLANK');
    watch(460,()=>chartSockets.length===2&&
      chartSockets[0].readyState===NativeWebSocket.CLOSED&&
      chartSockets[1].readyState===NativeWebSocket.OPEN&&
      status?.textContent==='100T · 1 completed session bars · Pine inputs unchanged'&&
      !!pixels()&&pixels()!==blank&&
      canvas.width>=200&&canvas.height>=100,()=>{
       freshPaintVerified=true;emit('FRESH_100T_CANVAS');
      });
   },40);
 }
},{capture:true});
canvas?.addEventListener('pointermove',event=>{
 if(event.isTrusted!==true)return;
 if(staleVerified&&!noAuto){
   win.setTimeout(()=>{
    if(stale()&&cleared()&&pixels()===blank&&chartSockets.length===1)
      emit('STALE_HOVER_CLEARED');
   },220);
 }else if(freshPaintVerified&&!cleanHover){
   win.setTimeout(()=>{
    if(/^#1 · O [0-9.]+ H [0-9.]+ L [0-9.]+ C [0-9.]+ · Vol [0-9.]+$/.test(inspect?.textContent||'')&&
       chartSockets.length===2){
       cleanHover=true;emit('FRESH_HOVER');
    }
   },240);
 }
},{capture:true});
zoom?.addEventListener('click',event=>{
 if(event.isTrusted!==true||!staleVerified||zoomVerified)return;
 win.setTimeout(()=>{
   if(stale()&&cleared()&&pixels()===blank&&chartSockets.length===1){
    zoomVerified=true;emit('STALE_ZOOM_LOCKED');
    // Observe absence of automatic reconnect for two seconds after failure.
    win.setTimeout(()=>{
     if(stale()&&pixels()===blank&&chartSockets.length===1&&
        chartSockets[0].readyState===NativeWebSocket.CLOSED){
       noAuto=true;emit('NO_AUTO_RETRY');
     }
    },2200);
   }
 },220);
},{capture:true});
time?.addEventListener('click',event=>{
 if(event.isTrusted!==true||!freshPaintVerified||!cleanHover)return;
 win.setTimeout(()=>{
  if(overlay?.hidden===true&&chartSockets.length===2&&
     Array.from(doc.querySelectorAll('.tick-tf-btn')).every(b=>
       b.getAttribute('aria-pressed')==='false')&&
     chartSockets[0].readyState===NativeWebSocket.CLOSED&&
     chartSockets[1].readyState===NativeWebSocket.CLOSED)
     emit('TIME_RETURN');
 },250);
},{capture:true});
})(window,document);

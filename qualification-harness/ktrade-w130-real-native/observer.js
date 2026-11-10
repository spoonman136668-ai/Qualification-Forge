// W130: exact W129, one genuine public Coinbase 100T session. Test-only
// read-only accessor retains the product's frozen chart install return value;
// all candles, subscription, rendering, handlers and orders remain authentic.
// Every user input is genuine Win32 mouse movement, hover, wheel and drag.
(function(win,doc){
'use strict';
let view=null,api=null;
Object.defineProperty(win,'KTRADE_W114_TickChart',{
 configurable:true,enumerable:true,
 get(){return api},
 set(source){
  if(!source||typeof source.install!=='function')return;
  api=Object.freeze(Object.assign({},source,{
   install:function(...args){
    const result=source.install.apply(source,args);
    if(result)view=result;
    return result;
   }
  }));
 }
});
const sockets=[],OriginalSocket=win.WebSocket;
class ObservedSocket extends OriginalSocket{
 constructor(url,protocols){
  if(protocols===undefined)super(url);else super(url,protocols);
  const u=new URL(String(url),win.location.href);
  if((u.protocol==='ws:'||u.protocol==='wss:')&&u.host===win.location.host&&
    u.pathname==='/ws/ticks'&&u.searchParams.get('count')==='100'&&
    u.searchParams.get('product')==='BTC-USD')sockets.push(this);
 }
}
win.WebSocket=ObservedSocket;
const out=doc.createElement('output');
out.id='w130-native-chart-interaction-proof';
out.setAttribute('role','status');
out.style.cssText='position:fixed;right:5px;bottom:38px;z-index:32000;'+
 'background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
 'font:12px Consolas,monospace;padding:4px 8px;pointer-events:none';
out.textContent='W130_REAL_READY';doc.body.appendChild(out);
const emit=stage=>{out.textContent='W130_REAL_'+stage+'=PASS'};
const observed=new Set();
function diagnostic(stage){
 if(observed.has(stage))return;
 observed.add(stage);
 const item=doc.createElement('output');
 item.setAttribute('role','status');
 item.id='w130-diagnostic-'+stage.toLowerCase();
 item.style.cssText='position:fixed;right:5px;bottom:'+(55+observed.size*13)+
   'px;z-index:32000;color:#13d4d4;background:#0b2830;'+
   'font:10px Consolas,monospace;pointer-events:none';
 item.textContent='W130_DIAG_'+stage+'=PASS';doc.body.appendChild(item);
}
const canvas=doc.getElementById('tickChartCanvas');
const status=doc.getElementById('tickChartStatus');
const inspect=doc.getElementById('tickInspectStatus');
const overlay=doc.getElementById('tickChartOverlay');
const tf=doc.querySelector('.tick-tf-btn[data-ticks="100"]');
const time=doc.querySelector('.tf-btn[data-tf="1m"]');
let started=false,crosshair=false,wheelIn=false,wheelOut=false,barsEnough=false;
let emptyPixels='';
let dragOlder=false,dragLatest=false;
function fingerprint(){
 try{return canvas.toDataURL('image/png')}catch(_){return ''}
}
function validPublic(){
 return started&&view&&sockets.length===1&&
  sockets[0].readyState===OriginalSocket.OPEN&&
  overlay?.hidden===false&&tf?.getAttribute('aria-pressed')==='true'&&
  win.KTRADE_APP?.s?.symbol==='BTC-USD'&&
  /^[0-9]+T · [1-9][0-9]* completed session bars · Pine inputs unchanged$/.test(status?.textContent||'');
}
tf?.addEventListener('click',e=>{
 if(!e.isTrusted||win.KTRADE_APP?.s?.symbol!=='BTC-USD')return;
 started=true;
 // Witness only: capture the genuine empty frame after product selection.
 win.setTimeout(()=>{
  if(view&&view.active()===100&&view.barCount()===0&&
     overlay?.hidden===false&&canvas?.width>=200&&canvas?.height>=100)
     emptyPixels=fingerprint();
 },45);
 let cycles=0;const interval=win.setInterval(()=>{
  if(++cycles>4000||!started){win.clearInterval(interval);return}
  // Monotone diagnostic witnesses; these do not modify the product
  // socket, market data, input handler or chart state.
  if(api)diagnostic('SOURCE_SET');
  if(view)diagnostic('VIEW_INSTALLED');
  if(started)diagnostic('NATIVE_SELECTION');
  if(sockets.length===1)diagnostic('TICK_SOCKET_CREATED');
  if(sockets.length===1&&sockets[0].readyState===OriginalSocket.OPEN)
    diagnostic('TICK_SOCKET_OPEN');
  if(overlay?.hidden===false&&tf?.getAttribute('aria-pressed')==='true')
    diagnostic('TICK_OVERLAY_ACTIVE');
  if(emptyPixels)diagnostic('BLANK_PIXELS_CAPTURED');
  if(/^100T · [1-9][0-9]* completed session bars · Pine inputs unchanged$/.test(status?.textContent||''))
    diagnostic('PUBLIC_CANDLE_STATUS');
  if(view?.barCount?.()>0)diagnostic('VIEW_COMPLETED_BARS');
  if(emptyPixels&&fingerprint()&&fingerprint()!==emptyPixels)
    diagnostic('NEW_CANVAS_PIXELS');
  if(!validPublic()||view.active()!==100||view.barCount()<1||
    !emptyPixels||fingerprint()===emptyPixels)return;
  if(!crosshair){
   emit('FIRST_100T_PUBLIC_CANVAS');
   crosshair=true;
  }
  if(!barsEnough&&view.barCount()>=14){
   barsEnough=true;emit('REAL_14_BARS');
  }
 },200);
},{capture:true});
canvas?.addEventListener('pointermove',e=>{
 if(!validPublic()||e.isTrusted!==true)return;
 win.setTimeout(()=>{
  if(validPublic()&&!wheelIn&&
    /^#[0-9]+ · O [0-9.]+ H [0-9.]+ L [0-9.]+ C [0-9.]+ · Vol [0-9.]+$/.test(inspect?.textContent||'')&&
    view.visible().some(b=>inspect.textContent.startsWith('#'+b.index+' ·'))){
    emit('NATIVE_CROSSHAIR');
  }
  if(validPublic()&&barsEnough&&view.offset()>0&&!dragOlder){
   dragOlder=true;emit('NATIVE_DRAG_OLDER');
  }else if(validPublic()&&dragOlder&&view.offset()===0&&!dragLatest){
   dragLatest=true;emit('NATIVE_DRAG_LATEST');
  }
 },200);
},{capture:true});
canvas?.addEventListener('wheel',e=>{
 if(e.isTrusted!==true||!validPublic()||!Number.isFinite(e.deltaY))return;
 win.setTimeout(()=>{
  if(e.deltaY<0&&view.zoomBars()===54&&!wheelIn){
   wheelIn=true;emit('NATIVE_WHEEL_ZOOM_IN');
  }else if(e.deltaY>0&&wheelIn&&view.zoomBars()===81&&!wheelOut){
   wheelOut=true;emit('NATIVE_WHEEL_ZOOM_OUT');
  }
 },180);
},{capture:true,passive:true});
time?.addEventListener('click',e=>{
 if(!e.isTrusted||!dragLatest)return;
 win.setTimeout(()=>{
  if(overlay?.hidden===true&&view?.active()===0&&sockets.length===1&&
     sockets[0].readyState===OriginalSocket.CLOSED)
     emit('TIME_RETURN');
 },200);
},{capture:true});
})(window,document);

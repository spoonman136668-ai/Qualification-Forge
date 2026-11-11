// W142: passive, test-only observer for the exact W131 native keyboard feature.
// Genuine public executed-trade bars + Win32 keyboard input; no JS dispatch,
// socket feeds, trading intents, credentials or owner installations.
(function(win,doc){
'use strict';
let sourceApi=null,view=null,selected=false;
const sockets=[],OriginalSocket=win.WebSocket;
// Early test-only visible marker distinguishes JS non-execution from later
// chart API or witness failure. It never generates events or market data.
const entered=doc.createElement('output');
entered.id='w142-early-js-marker';
entered.setAttribute('role','status');
entered.textContent='W142_JS_ENTERED=PASS';
entered.style.cssText='position:fixed;right:5px;bottom:22px;z-index:32000;'+
 'background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
 'font:12px Consolas,monospace;padding:4px 8px;pointer-events:none';
doc.body.appendChild(entered);
// Test-only stage marker. It never modifies market data or browser state.
win.addEventListener('error',()=>{
 entered.textContent='W142_STAGE_RUNTIME_ERROR=PASS';
},{once:true});
entered.textContent='W142_STAGE_BEFORE_API=PASS';
Object.defineProperty(win,'KTRADE_W114_TickChart',{
 configurable:true,enumerable:true,
 get(){return sourceApi},
 set(source){
  if(!source||typeof source.install!=='function')return;
  sourceApi=Object.freeze(Object.assign({},source,{
   install:function(...args){
    const v=source.install.apply(source,args);
    if(v)view=v;
    return v;
   }
  }));
 }
});
entered.textContent='W142_STAGE_API_WRAPPED=PASS';
class ObservedSocket extends OriginalSocket {
 constructor(url,protocols){
  if(protocols===undefined)super(url);else super(url,protocols);
  const u=new URL(String(url),win.location.href);
  if((u.protocol==='ws:'||u.protocol==='wss:')&&u.host===win.location.host&&
    u.pathname==='/ws/ticks'&&u.searchParams.get('count')==='100'&&
    u.searchParams.get('product')==='BTC-USD')sockets.push(this);
 }
}
entered.textContent='W142_STAGE_SOCKET_CLASS=PASS';
win.WebSocket=ObservedSocket;
entered.textContent='W142_STAGE_SOCKET_SET=PASS';
const canvas=doc.getElementById('tickChartCanvas');
const overlay=doc.getElementById('tickChartOverlay');
const status=doc.getElementById('tickChartStatus');
const inspect=doc.getElementById('tickInspectStatus');
const tf=doc.querySelector('.tick-tf-btn[data-ticks="100"]');
const oneMinute=doc.querySelector('.tf-btn[data-tf="1m"]');
entered.textContent='W142_STAGE_DOM_LOOKUP=PASS';
const stages=new Set();
function emit(name){
 if(stages.has(name))return;
 stages.add(name);
 const node=doc.createElement('output');
 node.id='w142-witness-'+name.toLowerCase();
 node.setAttribute('role','status');
 node.textContent='W142_REAL_'+name+'=PASS';
 node.style.cssText='position:fixed;right:5px;bottom:'+(34+stages.size*17)+
   'px;background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
   'font:12px Consolas,monospace;z-index:32000;padding:4px 8px;pointer-events:none';
 doc.body.appendChild(node);
}
emit('READY');
entered.textContent='W142_STAGE_READY_EMITTED=PASS';
function publicFeed(){
 return selected&&view?.active?.()===100&&view?.barCount?.()>=1&&
  sockets.length===1&&sockets[0].readyState===OriginalSocket.OPEN&&
  overlay?.hidden===false&&tf?.getAttribute('aria-pressed')==='true'&&
  win.KTRADE_APP?.s?.symbol==='BTC-USD'&&
  /^100T · [1-9][0-9]* completed session bars · Pine inputs unchanged$/.test(status?.textContent||'');
}
function ready(){
 return publicFeed()&&view.barCount()>=14&&
  canvas?.width>=200&&canvas?.height>=100;
}
// W142: inspect only verified completed public 100T candles; the fixture
// never sends DOM events, fabricates candles, or writes product/owner state.
// W142: witness observes real native button clicks and chart bitmap change
// only. Real websocket frames drive the immutable source session; the
// witness never submits frames, draws chart data, or calls product APIs.
// W142: passive observer only. Product MACD uses actual completed public
// 100T executed-trade candles. Native Win32 controls are the sole event
// source; the witness does not simulate or dispatch trades or UI events.
const macd=doc.getElementById('tickMacd');
const macdStatus=doc.getElementById('tickMacdStatus');
const macdCanvas=doc.getElementById('tickMacdCanvas');
const oneMinuteReturn=oneMinute;
let blank='',on=false,off=false;
function bitmap(element){try{return element?.toDataURL('image/png')||''}catch(_){return ''}}
function realMacd(){
 if(!view||typeof view.macdVisible!=='function')return false;
 const points=view.macdVisible(),latest=view.visible?.().at(-1)?.index;
 const p=points?.at(-1);
 return Number.isSafeInteger(latest)&&latest>=34&&p?.index===latest&&
   Number.isFinite(p?.line)&&Number.isFinite(p?.signal)&&
   Number.isFinite(p?.histogram)&&Math.abs((p.line-p.signal)-p.histogram)<1e-9;
}
tf?.addEventListener('click',e=>{
 if(e.isTrusted!==true||win.KTRADE_APP?.s?.symbol!=='BTC-USD')return;
 selected=true;
 win.setTimeout(()=>{if(view?.active?.()===100&&view?.barCount?.()===0)
    blank=bitmap(canvas)},45);
},{capture:true});
const pulse=win.setInterval(()=>{
 if(!selected)return;
 if(publicFeed()&&canvas?.width>=200&&canvas?.height>=100&&
   (!blank||bitmap(canvas)!==blank))emit('FIRST_PUBLIC_BAR');
 if(publicFeed()&&view.barCount()>=34&&stages.has('FIRST_PUBLIC_BAR')&&
   realMacd()&&macd?.getAttribute('aria-pressed')==='false'&&
   macdCanvas?.hidden===true)emit('REAL_34_BARS');
 if(stages.has('TIME_RETURN'))win.clearInterval(pulse);
},180);
macd?.addEventListener('click',e=>{
 if(e.isTrusted!==true||!publicFeed()||view.barCount()<34||
   !stages.has('REAL_34_BARS')||!realMacd())return;
 const last=view.visible().at(-1)?.index,prior=macd.getAttribute('aria-pressed');
 const before=bitmap(macdCanvas);
 win.setTimeout(()=>{
  if(!publicFeed()||view.visible().at(-1)?.index!==last||
     !realMacd()||!stages.has('REAL_34_BARS'))return;
  if(!on&&prior==='false'&&macd.getAttribute('aria-pressed')==='true'&&
    macdCanvas?.hidden===false&&macdCanvas?.width>=300&&
    macdCanvas?.height>=70&&macdStatus?.textContent==='MACD · signal + histogram'&&
    bitmap(macdCanvas)!==before){
    on=true;emit('NATIVE_MACD_VISIBLE_AND_PAINTED');
  }else if(on&&!off&&prior==='true'&&
    macd.getAttribute('aria-pressed')==='false'&&
    macdCanvas?.hidden===true&&macdStatus?.textContent==='MACD off'){
    off=true;emit('NATIVE_MACD_OFF');
  }
 },180);
},{capture:true});
oneMinuteReturn?.addEventListener('click',e=>{
 if(e.isTrusted!==true||!off)return;
 win.setTimeout(()=>{
  if(overlay?.hidden===true&&view?.active?.()===0&&
    sockets.length===1&&sockets[0].readyState===OriginalSocket.CLOSED&&
    macdCanvas?.hidden===true&&macd?.getAttribute('aria-pressed')==='false')
    emit('TIME_RETURN');
 },220);
},{capture:true});
})(window,document);

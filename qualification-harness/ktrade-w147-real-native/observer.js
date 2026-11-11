// W147: passive, test-only observer for the exact W131 native keyboard feature.
// Genuine public executed-trade bars + Win32 keyboard input; no JS dispatch,
// socket feeds, trading intents, credentials or owner installations.
(function(win,doc){
'use strict';
let sourceApi=null,view=null,selected=false;
const sockets=[],OriginalSocket=win.WebSocket;
// Early test-only visible marker distinguishes JS non-execution from later
// chart API or witness failure. It never generates events or market data.
const entered=doc.createElement('output');
entered.id='w147-early-js-marker';
entered.setAttribute('role','status');
entered.textContent='W147_JS_ENTERED=PASS';
entered.style.cssText='position:fixed;right:5px;bottom:22px;z-index:32000;'+
 'background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
 'font:12px Consolas,monospace;padding:4px 8px;pointer-events:none';
doc.body.appendChild(entered);
// Test-only stage marker. It never modifies market data or browser state.
win.addEventListener('error',()=>{
 entered.textContent='W147_STAGE_RUNTIME_ERROR=PASS';
},{once:true});
entered.textContent='W147_STAGE_BEFORE_API=PASS';
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
entered.textContent='W147_STAGE_API_WRAPPED=PASS';
class ObservedSocket extends OriginalSocket {
 constructor(url,protocols){
  if(protocols===undefined)super(url);else super(url,protocols);
  const u=new URL(String(url),win.location.href);
  if((u.protocol==='ws:'||u.protocol==='wss:')&&u.host===win.location.host&&
    u.pathname==='/ws/ticks'&&['250','500','1000'].includes(u.searchParams.get('count'))&&
    u.searchParams.get('product')==='BTC-USD')sockets.push(this);
 }
}
entered.textContent='W147_STAGE_SOCKET_CLASS=PASS';
win.WebSocket=ObservedSocket;
entered.textContent='W147_STAGE_SOCKET_SET=PASS';
const canvas=doc.getElementById('tickChartCanvas');
const overlay=doc.getElementById('tickChartOverlay');
const status=doc.getElementById('tickChartStatus');
const inspect=doc.getElementById('tickInspectStatus');
const tf250=doc.querySelector('.tick-tf-btn[data-ticks="250"]');
const tf500=doc.querySelector('.tick-tf-btn[data-ticks="500"]');
const tf1000=doc.querySelector('.tick-tf-btn[data-ticks="1000"]');
const oneMinute=doc.querySelector('.tf-btn[data-tf="1m"]');
entered.textContent='W147_STAGE_DOM_LOOKUP=PASS';
const stages=new Set();
function emit(name){
 if(stages.has(name))return;
 stages.add(name);
 const node=doc.createElement('output');
 node.id='w147-witness-'+name.toLowerCase();
 node.setAttribute('role','status');
 node.textContent='W147_REAL_'+name+'=PASS';
 node.style.cssText='position:fixed;right:5px;bottom:'+(34+stages.size*17)+
   'px;background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
   'font:12px Consolas,monospace;z-index:32000;padding:4px 8px;pointer-events:none';
 doc.body.appendChild(node);
}
emit('READY');
entered.textContent='W147_STAGE_READY_EMITTED=PASS';
// W147: native coverage for the three larger existing certified intervals.
// Observe original, real executed public session data; never create events,
// network payloads, financial orders, or synthetic bars.
let selectedCount=0,ready250=false,ready500=false,ready1000=false;
function publicFeed(n){
 const tf=n===250?tf250:n===500?tf500:tf1000;
 const ws=sockets.at(-1);
 if(!ws)return false;
 const u=new URL(String(ws.url),win.location.href);
 return selectedCount===n&&view?.active?.()===n&&view?.barCount?.()>=1&&
   ws.readyState===OriginalSocket.OPEN&&
   u.searchParams.get('count')===String(n)&&
   u.searchParams.get('product')==='BTC-USD'&&
   overlay?.hidden===false&&tf?.getAttribute('aria-pressed')==='true'&&
   win.KTRADE_APP?.s?.symbol==='BTC-USD'&&
   new RegExp('^'+n+'T · [1-9][0-9]* completed session bars · Pine inputs unchanged$')
     .test(status?.textContent||'');
}
tf250?.addEventListener('click',e=>{
 if(e.isTrusted===true&&win.KTRADE_APP?.s?.symbol==='BTC-USD')selectedCount=250;
},{capture:true});
tf500?.addEventListener('click',e=>{
 if(e.isTrusted===true&&ready250&&stages.has('REAL_250T_1_BAR'))selectedCount=500;
},{capture:true});
tf1000?.addEventListener('click',e=>{
 if(e.isTrusted===true&&ready500&&stages.has('REAL_500T_1_BAR'))selectedCount=1000;
},{capture:true});
const pulse=win.setInterval(()=>{
 if(publicFeed(250)&&sockets.length===1&&canvas?.width>=280&&canvas?.height>=140){
  ready250=true;emit('REAL_250T_1_BAR');
 }
 if(ready250&&publicFeed(500)&&sockets.length===2&&
   sockets[0].readyState===OriginalSocket.CLOSED&&
   canvas?.width>=280&&canvas?.height>=140){
  ready500=true;emit('REAL_500T_1_BAR');
 }
 if(ready500&&publicFeed(1000)&&sockets.length===3&&
   sockets[0].readyState===OriginalSocket.CLOSED&&
   sockets[1].readyState===OriginalSocket.CLOSED&&
   canvas?.width>=280&&canvas?.height>=140){
  ready1000=true;emit('REAL_1000T_1_BAR');
 }
 if(stages.has('TIME_RETURN'))win.clearInterval(pulse);
},160);
oneMinute?.addEventListener('click',e=>{
 if(e.isTrusted!==true||!ready1000)return;
 win.setTimeout(()=>{
  if(overlay?.hidden===true&&view?.active?.()===0&&sockets.length===3&&
     sockets.every(ws=>ws.readyState===OriginalSocket.CLOSED)&&
     [tf250,tf500,tf1000].every(tf=>tf?.getAttribute('aria-pressed')==='false'))
     emit('TIME_RETURN');
 },250);
},{capture:true});
})(window,document);

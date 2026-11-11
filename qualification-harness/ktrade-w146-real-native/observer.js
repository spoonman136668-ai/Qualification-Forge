// W146: passive, test-only observer for the exact W131 native keyboard feature.
// Genuine public executed-trade bars + Win32 keyboard input; no JS dispatch,
// socket feeds, trading intents, credentials or owner installations.
(function(win,doc){
'use strict';
let sourceApi=null,view=null,selected=false;
const sockets=[],OriginalSocket=win.WebSocket;
// Early test-only visible marker distinguishes JS non-execution from later
// chart API or witness failure. It never generates events or market data.
const entered=doc.createElement('output');
entered.id='w146-early-js-marker';
entered.setAttribute('role','status');
entered.textContent='W146_JS_ENTERED=PASS';
entered.style.cssText='position:fixed;right:5px;bottom:22px;z-index:32000;'+
 'background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
 'font:12px Consolas,monospace;padding:4px 8px;pointer-events:none';
doc.body.appendChild(entered);
// Test-only stage marker. It never modifies market data or browser state.
win.addEventListener('error',()=>{
 entered.textContent='W146_STAGE_RUNTIME_ERROR=PASS';
},{once:true});
entered.textContent='W146_STAGE_BEFORE_API=PASS';
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
entered.textContent='W146_STAGE_API_WRAPPED=PASS';
class ObservedSocket extends OriginalSocket {
 constructor(url,protocols){
  if(protocols===undefined)super(url);else super(url,protocols);
  const u=new URL(String(url),win.location.href);
  if((u.protocol==='ws:'||u.protocol==='wss:')&&u.host===win.location.host&&
    u.pathname==='/ws/ticks'&&['10','50'].includes(u.searchParams.get('count'))&&
    u.searchParams.get('product')==='BTC-USD')sockets.push(this);
 }
}
entered.textContent='W146_STAGE_SOCKET_CLASS=PASS';
win.WebSocket=ObservedSocket;
entered.textContent='W146_STAGE_SOCKET_SET=PASS';
const canvas=doc.getElementById('tickChartCanvas');
const overlay=doc.getElementById('tickChartOverlay');
const status=doc.getElementById('tickChartStatus');
const inspect=doc.getElementById('tickInspectStatus');
const tf10=doc.querySelector('.tick-tf-btn[data-ticks="10"]');
const tf50=doc.querySelector('.tick-tf-btn[data-ticks="50"]');
const oneMinute=doc.querySelector('.tf-btn[data-tf="1m"]');
entered.textContent='W146_STAGE_DOM_LOOKUP=PASS';
const stages=new Set();
function emit(name){
 if(stages.has(name))return;
 stages.add(name);
 const node=doc.createElement('output');
 node.id='w146-witness-'+name.toLowerCase();
 node.setAttribute('role','status');
 node.textContent='W146_REAL_'+name+'=PASS';
 node.style.cssText='position:fixed;right:5px;bottom:'+(34+stages.size*17)+
   'px;background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
   'font:12px Consolas,monospace;z-index:32000;padding:4px 8px;pointer-events:none';
 doc.body.appendChild(node);
}
emit('READY');
entered.textContent='W146_STAGE_READY_EMITTED=PASS';
// Actual source-only verification; never dispatch DOM events or bars.
let selectedCount=0,tenReady=false,fiftyReady=false;
function publicFeed(n){
 const tf=n===10?tf10:tf50,ws=sockets.at(-1);
 if(!ws)return false;
 const u=new URL(String(ws.url),win.location.href);
 return selectedCount===n&&view?.active?.()===n&&view?.barCount?.()>=1&&
 ws.readyState===OriginalSocket.OPEN&&u.searchParams.get('count')===String(n)&&
 u.searchParams.get('product')==='BTC-USD'&&overlay?.hidden===false&&
 tf?.getAttribute('aria-pressed')==='true'&&win.KTRADE_APP?.s?.symbol==='BTC-USD'&&
 new RegExp('^'+n+'T · [1-9][0-9]* completed session bars · Pine inputs unchanged$')
   .test(status?.textContent||'');
}
tf10?.addEventListener('click',e=>{
 if(e.isTrusted===true&&win.KTRADE_APP?.s?.symbol==='BTC-USD')selectedCount=10;
},{capture:true});
tf50?.addEventListener('click',e=>{
 if(e.isTrusted===true&&tenReady&&stages.has('REAL_10T_2_BARS'))selectedCount=50;
},{capture:true});
const pulse=win.setInterval(()=>{
 if(publicFeed(10)&&view.barCount()>=2&&sockets.length===1&&canvas?.width>=280&&canvas?.height>=140){
  tenReady=true;emit('REAL_10T_2_BARS');
 }
 if(tenReady&&publicFeed(50)&&view.barCount()>=2&&sockets.length===2&&
    sockets[0].readyState===OriginalSocket.CLOSED&&canvas?.width>=280&&canvas?.height>=140){
  fiftyReady=true;emit('REAL_50T_2_BARS');
 }
 if(stages.has('TIME_RETURN'))win.clearInterval(pulse);
},160);
oneMinute?.addEventListener('click',e=>{
 if(e.isTrusted!==true||!fiftyReady)return;
 win.setTimeout(()=>{
  if(overlay?.hidden===true&&view?.active?.()===0&&sockets.length===2&&
     sockets.every(ws=>ws.readyState===OriginalSocket.CLOSED)&&
     tf10?.getAttribute('aria-pressed')==='false'&&
     tf50?.getAttribute('aria-pressed')==='false')emit('TIME_RETURN');
 },250);
},{capture:true});
})(window,document);

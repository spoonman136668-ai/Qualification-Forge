// W144: passive, test-only observer for the exact W131 native keyboard feature.
// Genuine public executed-trade bars + Win32 keyboard input; no JS dispatch,
// socket feeds, trading intents, credentials or owner installations.
(function(win,doc){
'use strict';
let sourceApi=null,view=null,selected=false;
const sockets=[],OriginalSocket=win.WebSocket;
// Early test-only visible marker distinguishes JS non-execution from later
// chart API or witness failure. It never generates events or market data.
const entered=doc.createElement('output');
entered.id='w144-early-js-marker';
entered.setAttribute('role','status');
entered.textContent='W144_JS_ENTERED=PASS';
entered.style.cssText='position:fixed;right:5px;bottom:22px;z-index:32000;'+
 'background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
 'font:12px Consolas,monospace;padding:4px 8px;pointer-events:none';
doc.body.appendChild(entered);
// Test-only stage marker. It never modifies market data or browser state.
win.addEventListener('error',()=>{
 entered.textContent='W144_STAGE_RUNTIME_ERROR=PASS';
},{once:true});
entered.textContent='W144_STAGE_BEFORE_API=PASS';
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
entered.textContent='W144_STAGE_API_WRAPPED=PASS';
class ObservedSocket extends OriginalSocket {
 constructor(url,protocols){
  if(protocols===undefined)super(url);else super(url,protocols);
  const u=new URL(String(url),win.location.href);
  if((u.protocol==='ws:'||u.protocol==='wss:')&&u.host===win.location.host&&
    u.pathname==='/ws/ticks'&&u.searchParams.get('count')==='100'&&
    u.searchParams.get('product')==='BTC-USD')sockets.push(this);
 }
}
entered.textContent='W144_STAGE_SOCKET_CLASS=PASS';
win.WebSocket=ObservedSocket;
entered.textContent='W144_STAGE_SOCKET_SET=PASS';
const canvas=doc.getElementById('tickChartCanvas');
const overlay=doc.getElementById('tickChartOverlay');
const status=doc.getElementById('tickChartStatus');
const inspect=doc.getElementById('tickInspectStatus');
const tf=doc.querySelector('.tick-tf-btn[data-ticks="100"]');
const oneMinute=doc.querySelector('.tf-btn[data-tf="1m"]');
entered.textContent='W144_STAGE_DOM_LOOKUP=PASS';
const stages=new Set();
function emit(name){
 if(stages.has(name))return;
 stages.add(name);
 const node=doc.createElement('output');
 node.id='w144-witness-'+name.toLowerCase();
 node.setAttribute('role','status');
 node.textContent='W144_REAL_'+name+'=PASS';
 node.style.cssText='position:fixed;right:5px;bottom:'+(34+stages.size*17)+
   'px;background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
   'font:12px Consolas,monospace;z-index:32000;padding:4px 8px;pointer-events:none';
 doc.body.appendChild(node);
}
emit('READY');
entered.textContent='W144_STAGE_READY_EMITTED=PASS';
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
// W144: inspect only verified completed public 100T candles; the fixture
// never sends DOM events, fabricates candles, or writes product/owner state.
// W144: witness observes real native button clicks and chart bitmap change
// only. Real websocket frames drive the immutable source session; the
// witness never submits frames, draws chart data, or calls product APIs.
// W144: passive observer only. Product MACD uses actual completed public
// 100T executed-trade candles. Native Win32 controls are the sole event
// source; the witness does not simulate or dispatch trades or UI events.
// W144 observes only real public source and trusted Win32 native input.
const rsi=doc.getElementById('tickRsi14'),macd=doc.getElementById('tickMacd');
const rsiCanvas=doc.getElementById('tickRsiCanvas');
const macdCanvas=doc.getElementById('tickMacdCanvas');
const stack=doc.getElementById('tickChartPlotStack');
let rsiOn=false,macdOn=false,macdOff=false,rsiOff=false;
function bitmap(c){try{return c.toDataURL('image/png')}catch(_){return ''}}
function layoutOK(){
 if(!publicFeed()||!stack||!win.getComputedStyle)return false;
 const p=canvas.getBoundingClientRect(),r=rsiCanvas.getBoundingClientRect();
 const m=macdCanvas.getBoundingClientRect(),box=stack.getBoundingClientRect();
 return p.width>=280&&p.height>=179&&r.width>=280&&r.height>=100&&
   m.width>=280&&m.height>=110&&canvas.width>=280&&canvas.height>=179&&
   rsiCanvas.width>=280&&rsiCanvas.height>=100&&
   macdCanvas.width>=280&&macdCanvas.height>=110&&
   box.width>=280&&box.height>=90&&
   win.getComputedStyle(stack).overflowY==='auto'&&
   stack.scrollHeight>=Math.ceil(p.height+r.height+m.height)-6&&
   stack.scrollHeight>=stack.clientHeight-2;
}
tf?.addEventListener('click',e=>{
 if(e.isTrusted!==true||win.KTRADE_APP?.s?.symbol!=='BTC-USD')return;
 selected=true;
},{capture:true});
const pulse=win.setInterval(()=>{
 if(publicFeed()&&view.barCount()>=1&&canvas.width>=280&&canvas.height>=100)
   emit('REAL_1_BAR');
 if(stages.has('TIME_RETURN'))win.clearInterval(pulse);
},180);
rsi?.addEventListener('click',e=>{
 if(e.isTrusted!==true||!publicFeed()||!stages.has('REAL_1_BAR'))return;
 const before=bitmap(rsiCanvas),prior=rsi.getAttribute('aria-pressed');
 win.setTimeout(()=>{
  if(!publicFeed())return;
  if(!rsiOn&&prior==='false'&&rsi.getAttribute('aria-pressed')==='true'&&
     rsiCanvas.hidden===false&&rsiCanvas.width>=280&&
     rsiCanvas.height>=100&&bitmap(rsiCanvas)!==before){
    rsiOn=true;emit('NATIVE_RSI_ON');
  }else if(macdOff&&!rsiOff&&prior==='true'&&
     rsi.getAttribute('aria-pressed')==='false'&&rsiCanvas.hidden===true){
    rsiOff=true;emit('NATIVE_RSI_OFF');
  }
 },250);
},{capture:true});
macd?.addEventListener('click',e=>{
 if(e.isTrusted!==true||!publicFeed()||!rsiOn)return;
 const before=bitmap(macdCanvas),prior=macd.getAttribute('aria-pressed');
 win.setTimeout(()=>{
  if(!publicFeed())return;
  if(!macdOn&&prior==='false'&&macd.getAttribute('aria-pressed')==='true'&&
     macdCanvas.hidden===false&&rsiCanvas.hidden===false&&
     bitmap(macdCanvas)!==before&&layoutOK()){
    macdOn=true;emit('NATIVE_BOTH_PANES_VISIBLE_AND_PRICE_LEGIBLE');
  }else if(macdOn&&!macdOff&&prior==='true'&&
     macd.getAttribute('aria-pressed')==='false'&&macdCanvas.hidden===true){
    macdOff=true;emit('NATIVE_MACD_OFF');
  }
 },250);
},{capture:true});
oneMinute?.addEventListener('click',e=>{
 if(e.isTrusted!==true||!rsiOff)return;
 win.setTimeout(()=>{
  if(overlay.hidden===true&&view?.active?.()===0&&
    sockets.length===1&&sockets[0].readyState===OriginalSocket.CLOSED&&
    rsiCanvas.hidden===true&&macdCanvas.hidden===true)
    emit('TIME_RETURN');
 },250);
},{capture:true});
})(window,document);

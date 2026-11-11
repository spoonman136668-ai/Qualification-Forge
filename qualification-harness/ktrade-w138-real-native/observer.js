// W138: passive, test-only observer for the exact W131 native keyboard feature.
// Genuine public executed-trade bars + Win32 keyboard input; no JS dispatch,
// socket feeds, trading intents, credentials or owner installations.
(function(win,doc){
'use strict';
let sourceApi=null,view=null,selected=false;
const sockets=[],OriginalSocket=win.WebSocket;
// Early test-only visible marker distinguishes JS non-execution from later
// chart API or witness failure. It never generates events or market data.
const entered=doc.createElement('output');
entered.id='w138-early-js-marker';
entered.setAttribute('role','status');
entered.textContent='W138_JS_ENTERED=PASS';
entered.style.cssText='position:fixed;right:5px;bottom:22px;z-index:32000;'+
 'background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
 'font:12px Consolas,monospace;padding:4px 8px;pointer-events:none';
doc.body.appendChild(entered);
// Test-only stage marker. It never modifies market data or browser state.
win.addEventListener('error',()=>{
 entered.textContent='W138_STAGE_RUNTIME_ERROR=PASS';
},{once:true});
entered.textContent='W138_STAGE_BEFORE_API=PASS';
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
entered.textContent='W138_STAGE_API_WRAPPED=PASS';
class ObservedSocket extends OriginalSocket {
 constructor(url,protocols){
  if(protocols===undefined)super(url);else super(url,protocols);
  const u=new URL(String(url),win.location.href);
  if((u.protocol==='ws:'||u.protocol==='wss:')&&u.host===win.location.host&&
    u.pathname==='/ws/ticks'&&u.searchParams.get('count')==='100'&&
    u.searchParams.get('product')==='BTC-USD')sockets.push(this);
 }
}
entered.textContent='W138_STAGE_SOCKET_CLASS=PASS';
win.WebSocket=ObservedSocket;
entered.textContent='W138_STAGE_SOCKET_SET=PASS';
const canvas=doc.getElementById('tickChartCanvas');
const overlay=doc.getElementById('tickChartOverlay');
const status=doc.getElementById('tickChartStatus');
const inspect=doc.getElementById('tickInspectStatus');
const tf=doc.querySelector('.tick-tf-btn[data-ticks="100"]');
const oneMinute=doc.querySelector('.tf-btn[data-tf="1m"]');
entered.textContent='W138_STAGE_DOM_LOOKUP=PASS';
const stages=new Set();
function emit(name){
 if(stages.has(name))return;
 stages.add(name);
 const node=doc.createElement('output');
 node.id='w138-witness-'+name.toLowerCase();
 node.setAttribute('role','status');
 node.textContent='W138_REAL_'+name+'=PASS';
 node.style.cssText='position:fixed;right:5px;bottom:'+(34+stages.size*17)+
   'px;background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
   'font:12px Consolas,monospace;z-index:32000;padding:4px 8px;pointer-events:none';
 doc.body.appendChild(node);
}
emit('READY');
entered.textContent='W138_STAGE_READY_EMITTED=PASS';
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
// W138: inspect only verified completed public 100T candles; the fixture
// never sends DOM events, fabricates candles, or writes product/owner state.
// W138: native Win32 button clicks, actual public execution-count bars and
// a separately painted RSI oscillator. Passive test-only witness: no
// artificial socket messages, synthetic candles, or JS-dispatched clicks.
const rsi=doc.getElementById('tickRsi14');
const rsiStatus=doc.getElementById('tickRsiStatus');
const rsiCanvas=doc.getElementById('tickRsiCanvas');
const timeReturn=oneMinute;
let blank='',enabled=false,disabled=false;
function bitmap(el){try{return el.toDataURL('image/png')}catch(_){return ''}}
function latestRsiValid(){
 const points=view?.rsiVisible?.();
 const last=view?.visible?.().at(-1)?.index;
 if(!Array.isArray(points)||points.length<1||!Number.isSafeInteger(last)||
    points.at(-1)?.index!==last||points.some(p=>!Number.isSafeInteger(p.index)||
      !Number.isFinite(p.value)||p.value<0||p.value>100))return false;
 return true;
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
 if(publicFeed()&&view.barCount()>=15&&stages.has('FIRST_PUBLIC_BAR')&&
    view.visible().at(-1)?.index>=15&&latestRsiValid()&&
    rsi?.getAttribute('aria-pressed')==='false'&&rsiCanvas?.hidden===true)
    emit('REAL_15_BARS');
 if(stages.has('TIME_RETURN'))win.clearInterval(pulse);
},180);
rsi?.addEventListener('click',e=>{
 if(e.isTrusted!==true||!publicFeed()||view.barCount()<15||
    !stages.has('REAL_15_BARS')||!latestRsiValid())return;
 const last=view.visible().at(-1)?.index,prior=rsi.getAttribute('aria-pressed');
 const before=bitmap(rsiCanvas);
 win.setTimeout(()=>{
  if(!publicFeed()||view.visible().at(-1)?.index!==last||
    !stages.has('REAL_15_BARS'))return;
  if(!enabled&&prior==='false'&&rsi.getAttribute('aria-pressed')==='true'&&
    rsiCanvas?.hidden===false&&rsiCanvas?.width>=300&&
    rsiCanvas?.height>=70&&latestRsiValid()&&
    /^RSI 14 · (?:100(?:\.00)?|(?:[0-9]|[1-9][0-9])\.\d{2})$/.test(
      rsiStatus?.textContent||'')&&
    bitmap(rsiCanvas)!==before){
    enabled=true;emit('NATIVE_RSI14_VISIBLE_AND_PAINTED');
  }else if(enabled&&!disabled&&prior==='true'&&
    rsi.getAttribute('aria-pressed')==='false'&&
    rsiCanvas?.hidden===true&&rsiStatus?.textContent==='RSI 14 off'){
    disabled=true;emit('NATIVE_RSI14_OFF');
  }
 },200);
},{capture:true});
timeReturn?.addEventListener('click',e=>{
 if(e.isTrusted!==true||!disabled)return;
 win.setTimeout(()=>{
  if(overlay?.hidden===true&&view?.active?.()===0&&
    sockets.length===1&&sockets[0].readyState===OriginalSocket.CLOSED&&
    rsiCanvas?.hidden===true&&rsi?.getAttribute('aria-pressed')==='false')
    emit('TIME_RETURN');
 },220);
},{capture:true});
})(window,document);

// W132: passive, test-only observer for the exact W131 native keyboard feature.
// Genuine public executed-trade bars + Win32 keyboard input; no JS dispatch,
// socket feeds, trading intents, credentials or owner installations.
(function(win,doc){
'use strict';
let sourceApi=null,view=null,selected=false;
const sockets=[],OriginalSocket=win.WebSocket;
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
class ObservedSocket extends OriginalSocket {
 constructor(url,protocols){
  if(protocols===undefined)super(url);else super(url,protocols);
  const u=new URL(String(url),win.location.href);
  if((u.protocol==='ws:'||u.protocol==='wss:')&&u.host===win.location.host&&
    u.pathname==='/ws/ticks'&&u.searchParams.get('count')==='100'&&
    u.searchParams.get('product')==='BTC-USD')sockets.push(this);
 }
}
win.WebSocket=ObservedSocket;
const canvas=doc.getElementById('tickChartCanvas');
const overlay=doc.getElementById('tickChartOverlay');
const status=doc.getElementById('tickChartStatus');
const inspect=doc.getElementById('tickInspectStatus');
const tf=doc.querySelector('.tick-tf-btn[data-ticks="100"]');
const oneMinute=doc.querySelector('.tf-btn[data-tf="1m"]');
const stages=new Set();
function emit(name){
 if(stages.has(name))return;
 stages.add(name);
 const node=doc.createElement('output');
 node.id='w132-witness-'+name.toLowerCase();
 node.setAttribute('role','status');
 node.textContent='W132_REAL_'+name+'=PASS';
 node.style.cssText='position:fixed;right:5px;bottom:'+(34+stages.size*17)+
   'px;background:#0b2830;color:#13d4d4;border:1px solid #2c545c;'+
   'font:10px Consolas,monospace;z-index:32000;padding:1px 3px;pointer-events:none';
 doc.body.appendChild(node);
}
emit('READY');
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
let blank='',lastIndex=0;
function bitmap(){try{return canvas.toDataURL('image/png')}catch(_){return ''}}
tf?.addEventListener('click',e=>{
 if(e.isTrusted!==true)return;
 selected=true;
 win.setTimeout(()=>{if(view?.active?.()===100&&view?.barCount?.()===0)blank=bitmap()},45);
},{capture:true});
const tick=win.setInterval(()=>{
 if(!selected)return;
 if(publicFeed()&&canvas?.width>=200&&canvas?.height>=100&&
   (!blank||bitmap()!==blank))emit('FIRST_PUBLIC_BAR');
 if(ready()&&stages.has('FIRST_PUBLIC_BAR')){
  lastIndex=view.visible().at(-1)?.index||0;
  if(lastIndex>1)emit('REAL_14_BARS');
  if(doc.activeElement===canvas)emit('NATIVE_CANVAS_FOCUSED');
 }
 if(stages.has('TIME_RETURN'))win.clearInterval(tick);
},180);
const sequence=[
 {key:'ArrowLeft',stage:'LEFT_FIRST',check:()=>inspect?.textContent?.startsWith('#'+lastIndex+' ·')},
 {key:'ArrowLeft',stage:'LEFT_PREVIOUS',check:()=>inspect?.textContent?.startsWith('#'+(lastIndex-1)+' ·')},
 {key:'ArrowRight',stage:'RIGHT_RESTORES',check:()=>inspect?.textContent?.startsWith('#'+lastIndex+' ·')},
 {key:'PageUp',stage:'PAGE_OLDER',check:()=>view.offset()>0},
 {key:'PageDown',stage:'PAGE_NEWER',check:()=>view.offset()===0},
 {key:'+',stage:'KEY_ZOOM_IN',check:()=>view.zoomBars()===54},
 {key:'-',stage:'KEY_ZOOM_OUT',check:()=>view.zoomBars()===81},
 {key:'PageUp',stage:'PAGE_OLDER_AGAIN',check:()=>view.offset()>0},
 {key:'Home',stage:'HOME_LATEST',check:()=>view.offset()===0}
];
let step=0;
canvas?.addEventListener('keydown',e=>{
 if(e.isTrusted!==true||!ready()||doc.activeElement!==canvas||
   e.altKey||e.ctrlKey||e.metaKey||e.shiftKey||e.isComposing||e.repeat)return;
 const expected=sequence[step];
 if(!expected||e.key!==expected.key)return;
 const at=step;
 win.setTimeout(()=>{
  if(step!==at||!ready()||!expected.check())return;
  step++;
  emit(expected.stage);
 },160);
},{capture:true});
oneMinute?.addEventListener('click',e=>{
 if(e.isTrusted!==true||step!==sequence.length)return;
 win.setTimeout(()=>{
  if(overlay?.hidden===true&&view?.active?.()===0&&sockets.length===1&&
    sockets[0].readyState===OriginalSocket.CLOSED)emit('TIME_RETURN');
 },200);
},{capture:true});
})(window,document);

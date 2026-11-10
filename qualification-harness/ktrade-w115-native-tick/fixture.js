// W116: disposable Windows test-only native input witness. NEVER in KTRADE
// source or release assets. It intercepts only /ws/ticks with deterministic
// synthetic complete bars, entirely offline, while original chart JS stays
// source-identical. The observer does not dispatch or synthesize UI events.
(function(win,doc){
'use strict';
const SCHEMA='ktrade.tickchart.readonly.v1';
const NAME='W116_NATIVE_';
const nativeSocket=win.WebSocket;
const witness=doc.createElement('output');
witness.id='w116-native-witness';
witness.setAttribute('role','status');
witness.setAttribute('aria-live','polite');
witness.style.cssText='position:fixed;right:5px;bottom:38px;z-index:32000;'+
 'background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
 'font:12px Consolas,monospace;padding:4px 8px;pointer-events:none';
witness.textContent='W116_NATIVE_READY';
doc.body.appendChild(witness);
let state='READY';
const announce=code=>{state=code;witness.textContent=NAME+code+'=PASS';};
function fakeBar(index,product,count){
 const o=100+(index%29)/10;
 const c=o+(index%5-2)*.06;
 const h=Math.max(o,c)+.23;
 const l=Math.min(o,c)-.31;
 return {schema:SCHEMA,type:'bar',product,count,index,
   bar:{ProductID:product,TradeCount:count,
    FirstTradeID:String((index-1)*count+1),
    LastTradeID:String(index*count),
    Start:'2026-11-10T09:00:00Z',End:'2026-11-10T09:00:01Z',
    Open:o.toFixed(3),High:h.toFixed(3),
    Low:l.toFixed(3),Close:c.toFixed(3),
    Volume:(.1+(index%7)*.03).toFixed(3)}};
}
class FixtureTickSocket {
 constructor(url){
   this.url=String(url);this.closed=false;this.onmessage=null;
   const parsed=new URL(this.url);
   const product=parsed.searchParams.get('product');
   const count=Number(parsed.searchParams.get('count'));
   if(parsed.pathname!=='/ws/ticks'||!['BTC-USD','ETH-USD'].includes(product)||
      ![100,250,500,1000].includes(count))throw Error('W116_BAD_FIXTURE_SOURCE');
   let i=0;
   const pump=()=>{
     if(this.closed)return;
     if(i===0)this.onmessage?.({data:JSON.stringify({schema:SCHEMA,type:'status',
       state:'building',product,count,index:0,code:'SESSION_LOCAL_NO_BACKFILL'})});
     for(let j=0;j<20&&i<160;j++){
       ++i;this.onmessage?.({data:JSON.stringify(fakeBar(i,product,count))});
     }
     if(i<160)this.timer=win.setTimeout(pump,35);
   };
   this.timer=win.setTimeout(pump,170);
 }
 close(){this.closed=true;if(this.timer!==undefined)win.clearTimeout(this.timer);}
}
win.WebSocket=function(url,protocols){
 const u=new URL(String(url),win.location.href);
 if((u.protocol==='ws:'||u.protocol==='wss:')&&
    u.host===win.location.host&&u.pathname==='/ws/ticks')
   return new FixtureTickSocket(u.href);
 return protocols===undefined?new nativeSocket(url):new nativeSocket(url,protocols);
};
function snapshot(){
 const c=doc.getElementById('tickChartCanvas');
 if(!c||typeof c.toDataURL!=='function')return '';
 try{return c.toDataURL('image/png')}catch(_){return ''}
}
const pressed=e=>e&&e.isTrusted===true;
const after=(fn)=>win.setTimeout(fn,180);
for(const n of [100,250,500,1000]){
 const button=doc.querySelector('.tick-tf-btn[data-ticks="'+n+'"]');
 if(!button)continue;
 button.addEventListener('click',e=>{
   if(!pressed(e))return;
   let tries=0;
   const timer=win.setInterval(()=>{
     if(++tries>140){win.clearInterval(timer);return}
     const actual=doc.getElementById('tickChartStatus')?.textContent||'';
     if(button.getAttribute('aria-pressed')==='true'&&
        actual.startsWith(n+'T · 160 completed session bars')){
       win.clearInterval(timer);announce('SELECT_'+n);
     }
   },80);
 },{capture:true});
}
function compareAction(id,code){
 const b=doc.getElementById(id);
 if(!b)return;
 b.addEventListener('click',e=>{
   if(!pressed(e))return;
   const old=snapshot();
   after(()=>{
     const now=snapshot();
     if(old&&now&&old!==now)announce(code);
   });
 },{capture:true});
}
compareAction('tickZoomIn','ZOOM');
compareAction('tickPanOlder','OLDER');
compareAction('tickLatest','LATEST');
const canvas=doc.getElementById('tickChartCanvas');
canvas?.addEventListener('pointermove',e=>{
 if(!pressed(e))return;
 after(()=>{
   const value=doc.getElementById('tickInspectStatus')?.textContent||'';
   if(/#[0-9]+ · O [0-9.]+ H [0-9.]+ L [0-9.]+ C [0-9.]+/.test(value))
     announce('HOVER');
 });
},{capture:true});
doc.querySelector('.tf-btn[data-tf="1m"]')?.addEventListener('click',e=>{
 if(!pressed(e))return;
 after(()=>{
   if(doc.getElementById('tickChartOverlay')?.hidden===true&&
      Array.from(doc.querySelectorAll('.tick-tf-btn')).every(x=>
        x.getAttribute('aria-pressed')==='false'))announce('TIME_RETURN');
 });
},{capture:true});
})(window,document);

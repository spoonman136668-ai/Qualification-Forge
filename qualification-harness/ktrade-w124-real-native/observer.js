// W124 QForge-only PASSIVE witness for real 250T/500T/1000T chart data.
// No WebSocket/fetch overrides, synthetic bars, trading or storage. Requires
// true native Windows input, a verified server bar and changed canvas pixels.
(function(win,doc){
'use strict';
const output=doc.createElement('output');
output.id='w124-real-native-proof';
output.setAttribute('role','status');
output.style.cssText='position:fixed;right:5px;bottom:38px;z-index:32000;'+
  'background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
  'font:12px Consolas,monospace;padding:4px 8px;pointer-events:none';
output.textContent='W124_REAL_READY';
doc.body.appendChild(output);
const announce=label=>{output.textContent='W124_REAL_'+label+'=PASS'};
const canvas=doc.getElementById('tickChartCanvas');
const status=doc.getElementById('tickChartStatus');
const overlay=doc.getElementById('tickChartOverlay');
const inspection=doc.getElementById('tickInspectStatus');
const timeframe=doc.querySelector('.tf-btn[data-tf="1m"]');
let selected=0,completed=new Set();
function fingerprint(){
 if(!canvas||typeof canvas.toDataURL!=='function')return '';
 try{return canvas.toDataURL('image/png')}catch(_){return ''}
}
for(const n of [250,500,1000]){
 const button=doc.querySelector('.tick-tf-btn[data-ticks="'+n+'"]');
 button?.addEventListener('click',event=>{
  if(event.isTrusted!==true||win.KTRADE_APP?.s?.symbol!=='BTC-USD')return;
  if(n===500&&!completed.has(250))return;
  if(n===1000&&!completed.has(500))return;
  selected=n;
  const baseline=fingerprint();
  let cycles=0;
  const timer=win.setInterval(()=>{
   if(++cycles>2400||selected!==n){win.clearInterval(timer);return}
   if(overlay?.hidden===true||button.getAttribute('aria-pressed')!=='true')return;
   const match=new RegExp('^'+n+'T · ([1-9][0-9]*) completed session bars · Pine inputs unchanged$')
     .exec(status?.textContent||'');
   if(!match)return;
   const after=fingerprint();
   if(!after||after===baseline||canvas.width<200||canvas.height<100)return;
   completed.add(n);win.clearInterval(timer);
   announce(n+'T_CANVAS');
  },250);
 },{capture:true});
}
canvas?.addEventListener('pointermove',event=>{
 if(!completed.has(1000)||selected!==1000||event.isTrusted!==true)return;
 win.setTimeout(()=>{
  if(/^#[0-9]+ · O [0-9.]+ H [0-9.]+ L [0-9.]+ C [0-9.]+ · Vol [0-9.]+$/.test(inspection?.textContent||''))
   announce('HOVER');
 },200);
},{capture:true});
timeframe?.addEventListener('click',event=>{
 if(!completed.has(1000)||event.isTrusted!==true)return;
 win.setTimeout(()=>{
  if(overlay?.hidden===true &&
     Array.from(doc.querySelectorAll('.tick-tf-btn')).every(b=>
       b.getAttribute('aria-pressed')==='false'))announce('TIME_RETURN');
 },200);
},{capture:true});
})(window,document);

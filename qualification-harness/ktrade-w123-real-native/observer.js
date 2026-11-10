// W123 QForge-only PASSIVE witness. Runs in a disposable Windows Wails
// WebView2 chart template, not in KTRADE source or a shipping package.
// Never overrides WebSocket, fetch, market data, state or chart rendering.
// isTrusted native click + real /ws/ticks backend + drawn canvas required.
(function(win,doc){
'use strict';
const witness=doc.createElement('output');
witness.id='w123-real-native-proof';
witness.setAttribute('role','status');
witness.style.cssText='position:fixed;right:5px;bottom:38px;z-index:32000;'+
 'background:#0b2830;color:#13d4d4;border:1px solid #13d4d4;'+
 'font:12px Consolas,monospace;padding:4px 8px;pointer-events:none';
witness.textContent='W123_REAL_READY';
doc.body.appendChild(witness);
const announce=message=>{witness.textContent='W123_REAL_'+message+'=PASS'};
const chart=doc.getElementById('tickChartCanvas');
const status=doc.getElementById('tickChartStatus');
const overlay=doc.getElementById('tickChartOverlay');
const button=doc.querySelector('.tick-tf-btn[data-ticks="100"]');
const timeframe=doc.querySelector('.tf-btn[data-tf="1m"]');
const inspection=doc.getElementById('tickInspectStatus');
let trustedSelection=false;
function canvasFingerprint(){
 if(!chart||typeof chart.toDataURL!=='function')return '';
 try{return chart.toDataURL('image/png')}catch(_){return ''}
}
button?.addEventListener('click',event=>{
 if(event.isTrusted!==true)return;
 if(win.KTRADE_APP?.s?.symbol!=='BTC-USD')return;
 trustedSelection=true;
 const baseline=canvasFingerprint();
 let cycles=0;
 const timer=win.setInterval(()=>{
   if(++cycles>360){win.clearInterval(timer);return}
   if(!trustedSelection||overlay?.hidden===true)return;
   const text=status?.textContent||'';
   const match=/^100T · ([1-9][0-9]*) completed session bars · Pine inputs unchanged$/.exec(text);
   if(!match||button?.getAttribute('aria-pressed')!=='true')return;
   const after=canvasFingerprint();
   if(!after||after===baseline||!chart||chart.width<200||chart.height<100)return;
   win.clearInterval(timer);
   announce('100T_CANVAS');
 },250);
},{capture:true});
chart?.addEventListener('pointermove',event=>{
 if(!trustedSelection||!event.isTrusted)return;
 win.setTimeout(()=>{
  if((inspection?.textContent||'').match(/^#[0-9]+ · O [0-9.]+ H [0-9.]+ L [0-9.]+ C [0-9.]+ · Vol [0-9.]+$/))
    announce('HOVER');
 },200);
},{capture:true});
timeframe?.addEventListener('click',event=>{
 if(!trustedSelection||!event.isTrusted)return;
 win.setTimeout(()=>{
   if(overlay?.hidden===true &&
     Array.from(doc.querySelectorAll('.tick-tf-btn')).every(b=>
       b.getAttribute('aria-pressed')==='false'))announce('TIME_RETURN');
 },200);
},{capture:true});
})(window,document);

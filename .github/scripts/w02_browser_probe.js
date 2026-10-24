/* W02 disposable source-pinned Windows fixture; never package with KTRADE. */
(()=>{
'use strict';
const dest='__W02_BEACON_URL__',sent=new Set(),imgs=[];
function signal(s){if(sent.has(s))return;sent.add(s);const img=new Image();imgs.push(img);img.src=dest+'&event='+encodeURIComponent(s)+'&t='+Date.now();}
signal('script_executed');
let tries=0,edited=false,compiled=false,tf=false;
const poll=setInterval(()=>{
 if(++tries>35){clearInterval(poll);signal('deadline');return;}
 try{
  if(!document.getElementById('chart')||!document.getElementById('pine-editor-main'))return;
  signal('chart_dom_present');
  const canvas=Array.from(document.querySelectorAll('#chart canvas')).find(e=>{const r=e.getBoundingClientRect();return r.width>40&&r.height>40;});
  if(canvas&&typeof K!=='undefined'&&K.s?.chart&&K.s?.cs)signal('chart_canvas_live');
  if(typeof K!=='undefined'&&K.s?.ws?.readyState===WebSocket.OPEN)signal('chart_ws_open');
  if(typeof K!=='undefined'&&K.pineEditor?.getValue){
   signal('pine_monaco_ready');
   if(!edited){
    document.getElementById('pineBtn')?.click();
    if(document.getElementById('pinePanel')?.classList.contains('open'))signal('pine_panel_opened');
    const code='//@version=5\nindicator("W02 Readonly Qualification", overlay=true)\nplot(close)';
    K.pineEditor.setValue(code);
    if(K.pineEditor.getValue()===code){edited=true;signal('pine_editor_edited');}
   }
   if(edited&&!compiled){
    compiled=true;
    fetch('/api/pine/compile',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:'W02 Readonly Qualification',code:K.pineEditor.getValue()})})
      .then(async r=>{const d=await r.json();signal(r.ok&&d.success===true?'pine_compiled':'pine_compile_refused');})
      .catch(()=>signal('pine_compile_failed'));
   }
  }
  if(!tf&&typeof K!=='undefined'&&K.s?.tf==='1m'){
   document.querySelector('.tf-btn[data-tf="5m"]')?.click();
   tf=true;
   if(K.s.tf==='5m')signal('timeframe_clicked');
  }
 }catch(_){signal('probe_exception');}
},750);
})();
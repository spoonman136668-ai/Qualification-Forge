'use strict';
const http=require('node:http'),fs=require('node:fs');
const [file,nonce]=process.argv.slice(2);
if(!file||!/^[a-f0-9]{32}$/.test(nonce||''))process.exit(2);
const events=new Set(),allowed=new Set(['script_executed','chart_dom_present','chart_canvas_live','chart_ws_open','pine_monaco_ready','pine_panel_opened','pine_editor_edited','pine_compiled','pine_compile_refused','pine_compile_failed','timeframe_clicked','probe_exception','deadline']);
const app=http.createServer((req,res)=>{
 const url=new URL(req.url,'http://127.0.0.1');
 const deny=()=>{res.writeHead(403);res.end();};
 if(!['127.0.0.1','::1','::ffff:127.0.0.1'].includes(req.socket.remoteAddress)||url.searchParams.get('nonce')!==nonce)return deny();
 if(url.pathname==='/event'&&req.method==='GET'){
  if(!/^http:\/\/127\.0\.0\.1:\d+(?:\/|\/chart(?:\?.*)?)?$/.test(req.headers.referer||''))return deny();
  const name=url.searchParams.get('event');
  if(!allowed.has(name))return deny();
  events.add(name);res.writeHead(204,{'Cache-Control':'no-store'});return res.end();
 }
 if(url.pathname==='/status'&&req.method==='GET'){
  res.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-store'});
  return res.end(JSON.stringify({schema:'ktrade.w02.browser-observer.v1',events:[...events]}));
 }
 deny();
});
app.listen(0,'127.0.0.1',()=>fs.writeFileSync(file,JSON.stringify({port:app.address().port,nonce}),{flag:'wx',mode:0o600}));

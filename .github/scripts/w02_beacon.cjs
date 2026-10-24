'use strict';
const http=require('node:http'),fs=require('node:fs');
const [file,nonce]=process.argv.slice(2);
if(!file||!/^[a-f0-9]{32}$/.test(nonce||''))process.exit(2);
const events=new Set(),allowed=new Set(['script_executed','chart_dom_present','chart_canvas_live','chart_ws_open','pine_monaco_ready','pine_panel_opened','pine_editor_edited','pine_compiled','pine_compile_refused','pine_compile_failed','timeframe_clicked','probe_exception','deadline','w03_script_executed','w03_native_paper_controls','w03_unfunded_guard','w03_unfunded_guard_failed','w03_ui_market_selected','w03_market_selector_failed','w03_editor_failed','w03_ui_pine_durable_save','w03_fee_controls_missing','w03_no_fee_guard_failed','w03_ui_no_fee_start_refused','w03_funded_start_not_verified','w03_ui_explicit_paper_start','w03_funded_authority_invalid','w03_evaluate_control_disabled','w03_evaluate_server_accepted','w03_evaluate_server_refused','w03_ui_evaluate_clicked','w03_stop_live_guard_failed','w03_ui_paper_stop','w03_ui_sealed_archive','w03_browser_finalbar_paper_fill','w03_browser_no_source_verified_fill','w03_browser_fill_sealed_fifo_fees_pnl','w03_browser_sealed_account_fill_missing','w03_browser_account_visible_in_ui','w03_account_ui_not_visible','w03_archive_unavailable','w03_witness_exception']);
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

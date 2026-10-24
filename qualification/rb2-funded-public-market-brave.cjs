"use strict";
// Independent real Windows portable-first-launch and signed Brave CDP gate.
// No broker contact, no funded paper, no installed user profile access.
const fs=require("node:fs"),path=require("node:path"),os=require("node:os");
const cp=require("node:child_process"),crypto=require("node:crypto");
const root=path.resolve(process.argv[2]||"");
if(!/^ktrade-rb2-package-[a-f0-9]{16,32}$/i.test(path.basename(root))||
 path.dirname(root).toLowerCase()!==os.tmpdir().toLowerCase())
 throw Error("RB2_PORTABLE_BRAVE_ROOT_NOT_ISOLATED");
const stage=path.join(root,"KTRADE-Portable");
const executable=path.join(stage,"ktrade.exe");
const launcher=path.join(stage,"Start-KTRADE-Portable.ps1");
if(!fs.existsSync(executable)||!fs.existsSync(launcher))throw Error("RB2_PORTABLE_APP_MISSING");
const locations=[
 path.join(process.env.PROGRAMFILES||"C:\\Program Files","BraveSoftware","Brave-Browser","Application","brave.exe"),
 path.join(process.env["PROGRAMFILES(X86)"]||"C:\\Program Files (x86)","BraveSoftware","Brave-Browser","Application","brave.exe"),
 path.join(process.env.LOCALAPPDATA||"C:\\Users\\Public","BraveSoftware","Brave-Browser","Application","brave.exe")
];
const brave=locations.find(p=>fs.existsSync(p));
if(!brave)throw Error("RB2_SIGNED_BRAVE_REQUIRED");
if(typeof WebSocket!=="function")throw Error("RB2_NODE_NATIVE_WEBSOCKET_REQUIRED");
const sleep=t=>new Promise(r=>setTimeout(r,t));
async function waitFor(fn,label,ms=35000){const t=Date.now();let last="";
 while(Date.now()-t<ms){try{const x=await fn();if(x)return x}catch(e){last=String(e.message||e).slice(0,160)}
 await sleep(180)}throw Error(label+"_TIMEOUT_"+last)
}
function stopTree(proc){if(!proc?.pid)return;
 try{cp.spawnSync("taskkill.exe",["/T","/F","/PID",String(proc.pid)],{windowsHide:true,timeout:10000})}catch(e){}}
async function launchApp(bundle){
 const l=cp.spawn("pwsh.exe",["-NoProfile","-NonInteractive","-File",path.join(bundle,"Start-KTRADE-Portable.ps1")],
 {cwd:bundle,windowsHide:true,stdio:["ignore","pipe","pipe"],env:{
 ...process.env,KTRADE_USE_LEGACY_CDP_CONFIG:"0",KTRADE_RECOVERY_ISOLATED:"0",
 KTRADE_PORTABLE_DISARMED:"1",KTRADE_PAPER_SESSION_ROOT:"",KTRADE_PINE_LIBRARY_ROOT:"",
 KTRADE_CI_LIVE_AUTHORITY:"0",KTRADE_CI_COINBASE_ALLOWED:"0"}});
 let output="";for(const name of ["stdout","stderr"])l[name].on("data",b=>output=(output+b.toString()).slice(-16000));
 // Public market-only error classification, from the disposable Go host.
 // Never dump general process logs, credentials, environment or response bodies.
 l.safePublicCandleFailure=()=>output.split(String.fromCharCode(10))
   .filter(line=>line.includes("KTRADE verified source candles unavailable for BTC-USDC:"))
   .slice(-1).map(line=>line.slice(-400)).join("");
 try{await waitFor(async()=>{
  if(l.exitCode!==null)throw Error("RB2_PORTABLE_LAUNCH_EXIT_"+l.exitCode+"_"+output);
  const r=await fetch("http://127.0.0.1:8080/api/paper/session",{cache:"no-store"});
  return r.status===200||r.status===423?r.status:false;
 },"RB2_PORTABLE_MAIN_LOOPBACK");return l;
 }catch(e){stopTree(l);throw e}
}
async function readStatus(){
 const r=await fetch("http://127.0.0.1:8080/api/paper/session",{cache:"no-store"});
 let json=null;try{json=await r.json()}catch(e){}
 return {http:r.status,value:json};
}
async function openRealBrave(url){
 const profile=path.join(root,"headless-brave-portable-"+crypto.randomBytes(5).toString("hex"));
 let proc=cp.spawn(brave,["--headless=new","--disable-gpu","--no-first-run","--no-default-browser-check",
 "--disable-background-networking","--disable-extensions","--user-data-dir="+profile,
 "--remote-debugging-port=0","--window-size=1440,900",url],
 {cwd:root,windowsHide:true,stdio:["ignore","ignore","pipe"]});
 let err="";proc.stderr.on("data",b=>err=(err+b.toString()).slice(-3000));
 try{
  const file=path.join(profile,"DevToolsActivePort");
  const port=await waitFor(()=>{
   if(!fs.existsSync(file))return false;
   const n=Number(fs.readFileSync(file,"utf8").split(/\r?\n/)[0]);
   return Number.isInteger(n)&&n>0&&n<=65535?n:false;
  },"RB2_PORTABLE_BRAVE_CDP_"+err,30000);
  const target=await waitFor(async()=>{
   const r=await fetch("http://127.0.0.1:"+port+"/json/list");
   if(!r.ok)return false;
   return (await r.json()).find(x=>x.type==="page"&&x.url.includes("/chart")&&x.webSocketDebuggerUrl);
  },"RB2_PORTABLE_BRAVE_PAGE");
  const ws=new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((res,rej)=>{
   const timer=setTimeout(()=>rej(Error("RB2_PORTABLE_CDP_OPEN_TIMEOUT")),9000);
   ws.addEventListener("open",()=>{clearTimeout(timer);res()},{once:true});
   ws.addEventListener("error",()=>{clearTimeout(timer);rej(Error("RB2_PORTABLE_CDP_OPEN_FAILED"))},{once:true});
  });
  let i=0;const pending=new Map();
  ws.addEventListener("message",e=>{let d;try{d=JSON.parse(e.data)}catch(err){return}
   if(typeof d.id!=="number")return;const p=pending.get(d.id);if(!p)return;
   pending.delete(d.id);clearTimeout(p.timer);
   if(d.error)p.reject(Error(d.error.message));else p.resolve(d.result);
  });
  const send=(method,params={})=>new Promise((res,rej)=>{
   const id=++i,timer=setTimeout(()=>{pending.delete(id);rej(Error("RB2_PORTABLE_CDP_TIMEOUT_"+method))},30000);
   pending.set(id,{resolve:res,reject:rej,timer});
   ws.send(JSON.stringify({id,method,params}));
  });
  await send("Page.enable");
  const evaluate=async expression=>{
   const r=await send("Runtime.evaluate",{expression,awaitPromise:true,returnByValue:true});
   if(r.exceptionDetails)throw Error("RB2_PORTABLE_CDP_JS_EXCEPTION_"+JSON.stringify(r.exceptionDetails).slice(0,260));
   return r.result?.value;
  };
  return {proc,ws,evaluate};
 }catch(e){stopTree(proc);throw e}
}
async function run(){
 let app,browser,second;
 try{
  const data=path.join(stage,"data");
  if(fs.existsSync(data))throw Error("RB2_PORTABLE_PREEXISTING_DATA_ON_FRESH_PACKAGE");
  const pack=JSON.parse(fs.readFileSync(path.join(stage,"paper-package-proof.json"),"utf8"));
  const actual=crypto.createHash("sha256").update(fs.readFileSync(executable)).digest("hex");
  if(pack.schema!=="ktrade.paper.portable-package.v1"||pack.exe_sha256!==actual||pack.live_armed!==false)
   throw Error("RB2_PORTABLE_PROOF_MISMATCH");
  console.log("RB2_PORTABLE_BUNDLE_EXE_HASH_AUTHENTIC=PASS");
  app=await launchApp(stage);
  const stamp=path.join(data,"paper-fresh-data-proof.json");
  const fresh=JSON.parse(fs.readFileSync(stamp,"utf8"));
  if(fresh.schema!=="ktrade.paper.fresh-data.v1"||fresh.exe_sha256!==actual||fresh.live_armed!==false)
   throw Error("RB2_PORTABLE_FIRST_LAUNCH_PROOF_NOT_ISSUED");
  console.log("RB2_PORTABLE_FIRST_LAUNCH_FRESH_PROOF=PASS");
  const first=await readStatus();
  if(first.http!==200||first.value?.mode!=="PAPER_NOT_FUNDED"||
    first.value?.paper_orders_enabled!==false||first.value?.live_armed!==false)
   throw Error("RB2_PORTABLE_FIRST_LAUNCH_OWNER_NOT_FRESH_"+JSON.stringify(first));
  console.log("RB2_PORTABLE_APPLICATION_OWNED_UNFUNDED_SESSION=PASS");
  browser=await openRealBrave("http://127.0.0.1:8080/chart");
  const ui=await waitFor(async()=>{
   const x=await browser.evaluate('({chart:!!window.KTRADE_APP?.s?.chart,editor:!!window.KTRADE_APP?.pineEditor,start:document.getElementById("paperSessionStart")?.disabled,stop:document.getElementById("paperSessionStop")?.disabled,evaluate:document.getElementById("paperSessionEvaluate")?.disabled,legacy:document.getElementById("tradeBtn")?.disabled,banner:document.getElementById("operatorModeStatus")?.textContent||""})');
   return x?.chart&&x?.editor&&typeof x.start==="boolean"?x:false;
  },"RB2_PORTABLE_REAL_BRAVE_PAPER_CONTROLS");
  if(ui.start!==false||ui.stop!==true||ui.evaluate!==true||ui.legacy!==true||
    !ui.banner.includes("LIVE DISARMED"))
   throw Error("RB2_PORTABLE_BRAVE_PAPER_CONTROLS_INCORRECT_"+JSON.stringify(ui));
  console.log("RB2_PORTABLE_REAL_BRAVE_FRESH_START_CONTROL=PASS");
  const malicious=await fetch("http://127.0.0.1:8080/api/orders/place",{
   method:"POST",headers:{"Content-Type":"application/json","Origin":"http://127.0.0.1:8080"},
   body:JSON.stringify({product_id:"BTC-USDC",side:"BUY",size:"5",live:true})});
  if(malicious.status!==423)throw Error("RB2_PORTABLE_LEGACY_ORDER_ROUTE_UNSAFE_"+malicious.status);
  const invalidStart=await fetch("http://127.0.0.1:8080/api/paper/session/start",{
   method:"POST",headers:{"Content-Type":"application/json","Origin":"http://127.0.0.1:8080"},
   body:JSON.stringify({script_id:"a".repeat(32),product_id:"BTC-USDC",timeframe:"1m",
    initial_cash:"600",simulated_fee_bps:50,fee_model_acknowledged:true})});
  if(invalidStart.status!==422)throw Error("RB2_PORTABLE_UNSAVED_PINE_ADMITTED_"+invalidStart.status);
  const invalidStop=await fetch("http://127.0.0.1:8080/api/paper/session/stop",{
   method:"POST",headers:{"Content-Type":"application/json","Origin":"http://127.0.0.1:8080"},
   body:JSON.stringify({reason:"unfunded operator Stop"})});
  if(invalidStop.status===200)throw Error("RB2_PORTABLE_UNFUNDED_STOP_INVENTED");
  const forged=await readStatus();
  if(forged.value?.paper_orders_enabled!==false||forged.value?.mode!=="PAPER_NOT_FUNDED")
   throw Error("RB2_PORTABLE_FORGED_INTENT_FUNDED_SESSION");
  console.log("RB2_PORTABLE_BROWSER_INVALID_START_AND_LIVE_VETO=PASS");
  // First bona fide paper admission on PUBLIC authenticated-source Coinbase Advanced Trade
  // OHLCV. This is a simulated ledger trade, not an exchange/broker order.
  // No candle, mark or Pine order is accepted from the browser as authority.
  const marketResponse=await fetch("http://127.0.0.1:8080/api/candles?product=BTC-USDC&tf=1m",{cache:"no-store"});
  if(!marketResponse.ok)throw Error("RB2_PUBLIC_COINBASE_CANDLES_UNAVAILABLE_HTTP_"+marketResponse.status+"_SERVER_REASON_"+app.safePublicCandleFailure());
  const market=await marketResponse.json();
  const bars=market.candles;
  if(market.source!=="coinbase_advanced_public_rest"||market.finalized!==true||market.stale!==false||
     !Array.isArray(bars)||bars.length<2||bars.length>300)
   throw Error("RB2_PUBLIC_COINBASE_FINAL_BARS_UNQUALIFIED_"+JSON.stringify({source:market.source,stale:market.stale,count:bars?.length}));
  console.log("RB2_AUTHENTIC_PUBLIC_COINBASE_FINAL_CANDLES=PASS");
  const origin="http://127.0.0.1:8080";
  const headers={"Origin":origin,"Content-Type":"application/json"};
  const post=async(p,data)=>{
   const r=await fetch(origin+p,{method:"POST",headers,body:JSON.stringify(data)});
   const raw=await r.text();let result;
   try{result=JSON.parse(raw)}catch(e){result=raw.slice(0,600)}
   return {status:r.status,body:result};
  };
  // This time-indexed strategy is created entirely in disposable runner data.
  // It is not a trading signal, recommendation or user strategy.
  // Build genuine multiline Pine source. Literal backslash-n characters
  // are NOT valid Pine line breaks and can falsely mask market admission.
  const source=[
    '//@version=5',
    'strategy("RB2 Public Candle Paper Only")',
    'if bar_index == '+String(bars.length-1),
    '    strategy.entry("L", strategy.long, qty=0.0001)',
    ''
  ].join(String.fromCharCode(10));
  const saved=await post("/api/pine-library",{
   display_name:"RB2 public feed isolated paper only",kind:"strategy",source
  });
  const scriptId=saved.body?.metadata?.id;
  if(saved.status!==201||typeof scriptId!=="string"||!/^[0-9a-f]{32}$/.test(scriptId))
   throw Error("RB2_COINBASE_PAPER_SAVED_PINE_FAILURE_"+JSON.stringify(saved).slice(0,500));
  const preview=await post("/api/paper/strategy/preview",{
   script_id:scriptId,product_id:"BTC-USDC",timeframe:"1m"
  });
  if(preview.status!==200||preview.body?.status!=="REVIEW_ONLY"||
     !preview.body?.review_proposal||preview.body?.live_armed!==false||
     preview.body?.orders_enabled!==false||preview.body?.fee_schedule_verified!==false)
   throw Error("RB2_AUTHENTIC_COINBASE_PINE_FINAL_BAR_NOT_QUALIFIED_"+JSON.stringify({
    http:preview.status,status:preview.body?.status,reason:preview.body?.reason,
    signals:preview.body?.latest_signals?.length,proposal:!!preview.body?.review_proposal
   }));
  console.log("RB2_AUTHENTIC_MARKET_FINAL_BAR_PINE_STRATEGY_PROPOSAL=PASS");
  const startBody={script_id:scriptId,product_id:"BTC-USDC",timeframe:"1m",
   initial_cash:"600",simulated_fee_bps:50,fee_model_acknowledged:true};
  const started=await post("/api/paper/session/start",startBody);
  if(started.status!==200||started.body?.mode!=="PAPER_ISOLATED_RUNNING"||
     started.body?.live_armed!==false||started.body?.paper_orders_enabled!==true||
     started.body?.durable_custody_enabled!==true)
   throw Error("RB2_REAL_MARKET_PAPER_START_DENIED_"+JSON.stringify({http:started.status,result:started.body}).slice(0,700));
  console.log("RB2_REAL_COINBASE_PAPER_START_DURABLE_WRITER=PASS");
  const activeUI=await waitFor(async()=>{
   const v=await browser.evaluate('({stop:document.getElementById("paperSessionStop")?.disabled,eval:document.getElementById("paperSessionEvaluate")?.disabled,legacy:document.getElementById("tradeBtn")?.disabled})');
   return v?.stop===false&&v.eval===false&&v.legacy===true?v:false;
  },"RB2_REAL_BRAVE_ACTIVE_PAPER_CONTROLS",12000);
  console.log("RB2_REAL_BRAVE_PAPER_STOP_AND_EVALUATE_VISIBLE=PASS");
  const evaluated=await post("/api/paper/session/evaluate",{
   script_id:scriptId,product_id:"BTC-USDC",timeframe:"1m"
  });
  if(evaluated.status!==200||evaluated.body?.live_armed!==false||
    !["ISOLATED_PAPER_FILLED_OR_DEDUPLICATED","UNCHANGED_VERIFIED_FINAL_BAR"].includes(evaluated.body?.outcome))
   throw Error("RB2_AUTHENTIC_COINBASE_PAPER_FILL_NOT_VERIFIED_"+JSON.stringify(evaluated).slice(0,700));
  const accountResp=await fetch(origin+"/api/paper/accounting",{cache:"no-store"});
  const account=await accountResp.json();
  const product=Array.isArray(account?.products)?account.products.find(p=>p.product_id==="BTC-USDC"):null;
  if(accountResp.status!==200||account.live_armed!==false||account.orders_enabled!==false||
     account.unrealized_pnl_available!==false||!product||
     product.fill_count!==1||!product.ledger_hash||product.position_qty==="0")
   throw Error("RB2_COINBASE_ORIGINAL_PAPER_ACCOUNT_INCOMPLETE_"+JSON.stringify({
    http:accountResp.status,fill_count:product?.fill_count,qty:product?.position_qty
   }));
  const acceptedLedger=product.ledger_hash;
  console.log("RB2_AUTHENTIC_COINBASE_TRADEGUARD_PAPER_FILL_FIFO_LEDGER=PASS");
  await browser.evaluate('document.getElementById("paperSessionStop").click();true');
  await waitFor(async()=>{
   const s=await readStatus();return s.http===200&&s.value?.stopped===true&&
    s.value?.paper_orders_enabled===false?s:false;
  },"RB2_GENUINE_BRAVE_PAPER_STOP_NOT_SEALED",12000);
  const archiveResponse=await fetch(origin+"/api/paper/session/archive",{cache:"no-store"});
  const archive=await archiveResponse.json();
  const ap=archive?.account?.products?.find(p=>p.product_id==="BTC-USDC");
  if(archiveResponse.status!==200||archive.live_armed!==false||
     archive.orders_enabled!==false||archive.execution_restore_eligible!==false||
     ap?.ledger_hash!==acceptedLedger||ap?.fill_count!==1||!archive.original_risk_proof_verified)
   throw Error("RB2_REAL_COINBASE_STOPPED_SOURCE_ARCHIVE_UNVERIFIED_"+archiveResponse.status);
  console.log("RB2_REAL_BRAVE_STOP_ORIGINAL_RISK_DURABLE_ARCHIVE=PASS");
  const proofBefore=fs.readFileSync(stamp);
  const filesBefore=fs.readdirSync(data).sort().join("|");
  browser.ws.close();stopTree(browser.proc);browser=null;
  stopTree(app);app=null;
  await waitFor(async()=>{try{await fetch("http://127.0.0.1:8080/api/paper/session");return false}catch(e){return true}},"RB2_PORTABLE_PROCESS_TERMINATION",12000);
  second=await launchApp(stage);
  const back=await readStatus();
  if(back.http!==200||back.value?.mode!=="PAPER_NOT_FUNDED"||back.value?.paper_orders_enabled!==false)
   throw Error("RB2_PORTABLE_COLD_RESTART_REARMED_"+JSON.stringify(back));
  if(!fs.readFileSync(stamp).equals(proofBefore))throw Error("RB2_PORTABLE_RESTART_RESTAMPED_AUTHORITY");
  const archivedAfterRestart=await fetch("http://127.0.0.1:8080/api/paper/session/archive",{cache:"no-store"});
  if(archivedAfterRestart.status!==200)
   throw Error("RB2_REAL_PAPER_COLD_RESTART_ACCOUNT_NOT_DISCOVERABLE_HTTP_"+archivedAfterRestart.status);
  const retained=await archivedAfterRestart.json();
  const retainedProduct=retained.account?.products?.find(p=>p.product_id==="BTC-USDC");
  if(retained.execution_restore_eligible!==false||retained.live_armed!==false||
     retainedProduct?.fill_count!==1||retainedProduct.ledger_hash!==acceptedLedger)
   throw Error("RB2_REAL_PAPER_COLD_RESTART_FINANCIAL_HASH_DRIFT");
  console.log("RB2_REAL_PAPER_FUNDED_STOP_COLD_RESTART_ACCOUNT_PRESERVED=PASS");
  if(!fs.readdirSync(data).sort().join("|").includes("pine-library"))throw Error("RB2_PORTABLE_COLD_RESTART_LOST_PINE");
  console.log("RB2_PORTABLE_RESTART_WITHOUT_AUTO_REARM_OR_RESTAMP=PASS");
  stopTree(second);second=null;
  await waitFor(async()=>{try{await fetch("http://127.0.0.1:8080/api/paper/session");return false}catch(e){return true}},"RB2_PORTABLE_PROCESS_TERMINATION_2",12000);
  const alt=path.join(root,"untrusted-copy","KTRADE-Portable");
  fs.mkdirSync(path.dirname(alt),{recursive:true});
  fs.cpSync(stage,alt,{recursive:true,filter:src=>
   src===stage||path.relative(stage,src).split(path.sep)[0]!=="data"});
  fs.mkdirSync(path.join(alt,"data"),{recursive:true});
  fs.writeFileSync(path.join(alt,"data","historical-user-profile.txt"),"DO NOT TOUCH");
  second=await launchApp(alt);
  const existing=await readStatus();
  if(existing.http!==423||fs.existsSync(path.join(alt,"data","paper-fresh-data-proof.json"))||
     fs.readFileSync(path.join(alt,"data","historical-user-profile.txt"),"utf8")!=="DO NOT TOUCH")
   throw Error("RB2_PORTABLE_PREEXISTING_DATA_WAS_ADOPTED_"+JSON.stringify(existing));
  console.log("RB2_PORTABLE_PRIOR_PROFILE_REFUSED_NO_DATA_MUTATION=PASS");
  console.log("RB2_PORTABLE_REAL_WINDOWS_REAL_BRAVE_FIRST_LAUNCH=PASS");
  console.log("RB2_PORTABLE_PAPER_FUNDED_START_STOP=AUTHENTIC_COINBASE_MARKET_TESTED");
  console.log("RB2_PORTABLE_LIVE_DISARMED=TRUE; OWNER_INSTALLED_PROFILE_UNTOUCHED=TRUE");
 }finally{
  try{browser?.ws?.close()}catch(e){}
  stopTree(browser?.proc);stopTree(app);stopTree(second);
 }
}
run().catch(e=>{console.error("RB2_PORTABLE_BRAVE_ACCEPTANCE_FAIL="+e.stack);process.exitCode=1});

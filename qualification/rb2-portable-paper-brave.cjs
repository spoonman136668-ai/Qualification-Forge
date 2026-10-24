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
  if(!fs.readdirSync(data).sort().join("|").includes("pine-library"))throw Error("RB2_PORTABLE_COLD_RESTART_LOST_PINE");
  console.log("RB2_PORTABLE_RESTART_WITHOUT_AUTO_REARM_OR_RESTAMP=PASS");
  stopTree(second);second=null;
  await waitFor(async()=>{try{await fetch("http://127.0.0.1:8080/api/paper/session");return false}catch(e){return true}},"RB2_PORTABLE_PROCESS_TERMINATION_2",12000);
  const alt=path.join(root,"untrusted-copy","KTRADE-Portable");
  fs.mkdirSync(path.dirname(alt),{recursive:true});
  fs.cpSync(stage,alt,{recursive:true});
  fs.rmSync(path.join(alt,"data"),{recursive:true,force:true});
  fs.mkdirSync(path.join(alt,"data"),{recursive:true});
  fs.writeFileSync(path.join(alt,"data","historical-user-profile.txt"),"DO NOT TOUCH");
  second=await launchApp(alt);
  const existing=await readStatus();
  if(existing.http!==423||fs.existsSync(path.join(alt,"data","paper-fresh-data-proof.json"))||
     fs.readFileSync(path.join(alt,"data","historical-user-profile.txt"),"utf8")!=="DO NOT TOUCH")
   throw Error("RB2_PORTABLE_PREEXISTING_DATA_WAS_ADOPTED_"+JSON.stringify(existing));
  console.log("RB2_PORTABLE_PRIOR_PROFILE_REFUSED_NO_DATA_MUTATION=PASS");
  console.log("RB2_PORTABLE_REAL_WINDOWS_REAL_BRAVE_FIRST_LAUNCH=PASS");
  console.log("RB2_PORTABLE_PAPER_FUNDED_START_STOP=NOT_TESTED_NO_AUTHENTIC_MARKET");
  console.log("RB2_PORTABLE_LIVE_DISARMED=TRUE; OWNER_INSTALLED_PROFILE_UNTOUCHED=TRUE");
 }finally{
  try{browser?.ws?.close()}catch(e){}
  stopTree(browser?.proc);stopTree(app);stopTree(second);
 }
}
run().catch(e=>{console.error("RB2_PORTABLE_BRAVE_ACCEPTANCE_FAIL="+e.stack);process.exitCode=1});

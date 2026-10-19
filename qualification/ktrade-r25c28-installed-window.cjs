"use strict";
// R25-C28 genuine installed Electron renderer check. No orders or external hosts.
// Only a disposable Windows NSIS installation under independently enforced egress denial.
const assert=require("node:assert/strict");
const port=Number(process.argv[2]);
assert.ok(Number.isInteger(port)&&port>1024&&port<=65535);
const endpoint="http://127.0.0.1:"+port+"/json/list";
const pause=(ms)=>new Promise(resolve=>setTimeout(resolve,ms));
let target;
for(let tries=0;tries<125;tries++){
  try{
    const resp=await fetch(endpoint,{signal:AbortSignal.timeout(1800)});
    if(resp.ok){
      const list=await resp.json();
      target=list.find(t=>t.type==="page"&&/^http:\/\/127\.0\.0\.1:[0-9]{2,5}\/chart(?:[?#]|$)/.test(t.url)&&
        /^ws:\/\/127\.0\.0\.1:[0-9]{2,5}\//.test(t.webSocketDebuggerUrl||""));
    }
  }catch{}
  if(target)break;
  await pause(500);
}
assert.ok(target,"R25C28_INSTALLED_WINDOW_NO_GENUINE_ISOLATED_CHART_TARGET");
assert.ok(typeof WebSocket==="function","R25C28_NODE24_NATIVE_WEBSOCKET_MISSING");
const ws=new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>reject(Error("R25C28_CDP_OPEN_TIMEOUT")),12000);
  ws.addEventListener("open",()=>{clearTimeout(timer);resolve()},{once:true});
  ws.addEventListener("error",()=>{clearTimeout(timer);reject(Error("R25C28_CDP_WS_ERROR"))},{once:true});
});
let serial=0;
const pending=new Map();
ws.addEventListener("message",event=>{
  let m;try{m=JSON.parse(event.data.toString())}catch{return}
  if(!m.id||!pending.has(m.id))return;
  const entry=pending.get(m.id);clearTimeout(entry.timer);pending.delete(m.id);
  m.error?entry.reject(Error("R25C28_CDP_PROTOCOL_ERROR")):entry.resolve(m.result||{});
});
const request=(method,params={})=>new Promise((resolve,reject)=>{
  const id=++serial;
  const timer=setTimeout(()=>{pending.delete(id);reject(Error("R25C28_CDP_TIMEOUT_"+method))},12000);
  pending.set(id,{resolve,reject,timer});
  ws.send(JSON.stringify({id,method,params}));
});
try{
  await request("Runtime.enable");
  let result;
  for(let j=0;j<90;j++){
    const answer=await request("Runtime.evaluate",{
      expression:"({ready:document.readyState,title:document.title,host:location.hostname,port:location.port,path:location.pathname,chart:!!document.querySelector('#chart'),pine:!!document.querySelector('#pine-editor-main'),trade:!!document.querySelector('#orderPanel'),monaco:!!(window.monaco&&window.monaco.editor),body:!!document.body&&document.body.textContent.length>200})",
      returnByValue:true,awaitPromise:false
    });
    if(!answer.exceptionDetails)result=answer.result&&answer.result.value;
    if(result&&result.ready==="complete"&&result.chart&&result.pine&&result.trade&&result.body)break;
    await pause(500);
  }
  assert.ok(result,"R25C28_NO_ELECTRON_DOCUMENT_EVALUATION");
  assert.equal(result.host,"127.0.0.1","R25C28_DOCUMENT_NOT_LOOPBACK");
  assert.match(result.port,/^[0-9]{2,5}$/,"R25C28_DOCUMENT_PORT_INVALID");
  assert.equal(result.path,"/chart","R25C28_DOCUMENT_NOT_ORIGINAL_CHART");
  assert.match(result.title,/KTRADE/,"R25C28_DOCUMENT_NOT_KTRADE");
  assert.equal(result.ready,"complete","R25C28_DOCUMENT_NOT_READY");
  assert.ok(result.chart&&result.pine&&result.trade&&result.body,"R25C28_ORIGINAL_CHART_CONTROLS_NOT_RENDERED");
  const bodyResponse=await fetch("http://127.0.0.1:"+result.port+"/chart",{signal:AbortSignal.timeout(5000)});
  assert.ok(bodyResponse.ok,"R25C28_GO_HTTP_CHART_NOT_SERVING");
  const txt=await bodyResponse.text();
  assert.ok(txt.includes("KTRADE")&&txt.includes("pine-editor-main"),"R25C28_GO_HTTP_CHART_INCOMPLETE");
  console.log("R25C28_INSTALLED_ELECTRON_NATIVE_CDP_CHART=PASS");
  console.log("R25C28_INSTALLED_GO_LOOPBACK_HTTP=PASS");
  console.log("R25C28_INSTALLED_CHART_AND_PINE_CONTROLS=PASS");
  console.log("R25C28_MONACO_EDITOR_INITIALIZED="+(result.monaco?"TRUE":"FALSE_UNQUALIFIED"));
  console.log("R25C28_NO_ORDER_SUBMISSION=TRUE");
  try{await request("Browser.close")}catch{}
  console.log("R25C28_ELECTRON_BROWSER_CLOSE_REQUESTED=TRUE");
}finally{ws.close()}

'use strict';
// External qualification observer. This attaches only to the disposable native
// WebView2 process's loopback inspector. Input and capture remain Win32/UIA.
// The fixed expressions read state/coordinates; no setters, event dispatch,
// source edits, renderer replacement, DOM injection or application calls.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const expression = `(() => {
  const a=window.KTRADE_APP;
  if(!a||!a.s||!a.s.pchart||!a.s.vs) return null;
  const s=a.s;
  const rect=id=>{const r=document.getElementById(id).getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height};};
  const line=(s._indicatorSeries||[])[0];
  const rows=s.candles.map((c,i)=>({time:c.time,open:c.open,high:c.high,low:c.low,close:c.close,volume:c.volume,
    pine_x:s.pchart.timeScale().timeToCoordinate(c.time),
    pine_y:line&&i>=2?line.priceToCoordinate(99+i):null,
    volume_x:s.vchart.timeScale().timeToCoordinate(c.time),volume_y:s.vs.priceToCoordinate(10+i)}));
  return {url:location.href,dpr:devicePixelRatio,version:LightweightCharts.version(),symbol:s.symbol,tf:s.tf,
    pane:rect('pinePlotPane'),pine:rect('pinePlotChart'),volume:rect('volumeChart'),
    volume_rows:s.vs.data(),candle_rows:s.cs.data(),rows,
    series_count:(s._indicatorSeries||[]).length,
    series_owner:line?line._chart===s.pchart:null,
    warmup:line?[line.dataByIndex(0),line.dataByIndex(1)]:[],
    plotted:line?line.data():[],
    volume_range:s.vchart.timeScale().getVisibleLogicalRange()};
})()`;
class CDP {
  constructor(ws) { this.ws=ws; this.id=0; this.pending=new Map(); this.contexts=[];
    ws.addEventListener('message',e=>{ const m=JSON.parse(e.data);
      if(m.method==='Runtime.executionContextCreated')this.contexts.push(m.params.context);
      if(m.id&&this.pending.has(m.id)){const p=this.pending.get(m.id);this.pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(JSON.stringify(m.error))):p.resolve(m.result);}
    });
  }
  send(method,params={}) {return new Promise((resolve,reject)=>{const id=++this.id;const timer=setTimeout(()=>{this.pending.delete(id);reject(Error('CDP timeout '+method));},7000);this.pending.set(id,{resolve,reject,timer});this.ws.send(JSON.stringify({id,method,params}));});}
  async read(contextId) {const r=await this.send('Runtime.evaluate',{expression,contextId,returnByValue:true,awaitPromise:false});if(r.exceptionDetails)throw Error(r.exceptionDetails.text+': '+r.result.description);return r.result.value;}
}
async function connect(url){const ws=new WebSocket(url);await new Promise((resolve,reject)=>{ws.addEventListener('open',resolve,{once:true});ws.addEventListener('error',reject,{once:true});});return new CDP(ws);}
function validate(d,phase){
  assert.match(d.url,/^http:\/\/127\.0\.0\.1:\d+\/chart/);
  assert.equal(d.version,'4.1.0');assert.equal(d.symbol,'BTC-USDC');assert.equal(d.tf,'1m');
  assert.equal(d.rows.length,30);assert.equal(d.volume_rows.length,30);assert.equal(d.candle_rows.length,30);
  for(let i=0;i<30;i++){
    const c=d.rows[i],v=d.volume_rows[i],k=d.candle_rows[i];
    for(const [key,val]of Object.entries({open:99+i,high:103+i,low:97+i,close:100+i,volume:10+i}))assert.equal(c[key],val);
    if(i)assert.equal(c.time-d.rows[i-1].time,60);
    assert.equal(v.time,c.time);assert.equal(v.value,10+i);
    assert.equal(k.time,c.time);assert.equal(k.close,100+i);
  }
  if(phase==='baseline'){assert.equal(d.series_count,0);}
  else {assert.equal(d.series_count,1);assert.equal(d.series_owner,true);assert.deepEqual(d.warmup,[null,null]);assert.equal(d.plotted.length,28);
    for(let i=2;i<30;i++){assert.equal(d.plotted[i-2].time,d.rows[i].time);assert.equal(d.plotted[i-2].value,99+i);assert.ok(Number.isFinite(d.rows[i].pine_x));assert.ok(Number.isFinite(d.rows[i].pine_y));}
  }
  for(const r of [d.pane,d.pine,d.volume])for(const n of Object.values(r))assert.ok(Number.isFinite(n));
}
async function main(){
  const [port,phase,out]=process.argv.slice(2);assert.ok(['baseline','applied'].includes(phase));assert.ok(/^\d+$/.test(port));
  const targets=await fetch('http://127.0.0.1:'+port+'/json/list').then(r=>r.json());
  let data=null;
  for(const t of targets.filter(t=>['page','iframe'].includes(t.type)&&t.webSocketDebuggerUrl)){
    const c=await connect(t.webSocketDebuggerUrl);
    try {await c.send('Runtime.enable');for(const ctx of c.contexts.filter(x=>x.auxData?.isDefault)){
      const d=await c.read(ctx.id);if(d){assert.equal(data,null,'ambiguous chart contexts');data=d;}
    }} finally {c.ws.close();}
  }
  assert.ok(data,'native WebView2 original chart context unavailable');validate(data,phase);
  fs.writeFileSync(out,JSON.stringify(data));console.log('W32E_P1C_READ_ONLY_NATIVE_COORDINATES_'+phase.toUpperCase()+'=PASS');
}
main().catch(e=>{console.error(e.stack);process.exitCode=1;});

'use strict';
// Qualification-only loopback fixture. Reads exact installed chart/assets;
// never replaces the chart loader, series, financial code or installed files.
// This is a real Windows Edge renderer witness, distinct from the real
// installed Wails/WebView2 lifecycle witness in the same workflow.
const assert=require('node:assert/strict');
const fs=require('node:fs');const path=require('node:path');
const http=require('node:http');const crypto=require('node:crypto');
const {chromium}=require(process.env.W32_PLAYWRIGHT_MODULE);
const stage=path.resolve(process.argv[2]);
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const template=path.join(stage,'templates/chart.tmpl');const before=hash(template);
const rows=Array.from({length:30},(_,i)=>({time:1770000000+i*60,open:100+i,high:105+i,low:97+i,close:102+i,volume:10+i}));
let mode='valid';const requests=[];
const caps={schema:'ktrade.operator.capabilities.v1',mode:'PAPER_STOPPED',paper_orders_enabled:false,live_orders_enabled:false,strategy_execution_enabled:false,paper_accounting_enabled:false,requires_review:true};
const server=http.createServer((req,res)=>{
 const url=new URL(req.url,'http://127.0.0.1');requests.push(req.method+' '+url.pathname);
 const json=(code,value)=>{res.writeHead(code,{'content-type':'application/json','cache-control':'no-store'});res.end(JSON.stringify(value));};
 if(req.method!=='GET')return json(403,{success:false,error:'qualification never accepts an action'});
 if(url.pathname==='/api/operator/capabilities')return json(200,caps);
 if(url.pathname==='/api/candles'){
  if(mode==='unavailable')return json(503,{success:false,error:'fixture unavailable'});
  const candles=structuredClone(rows);if(mode==='invalid')candles[8].time=candles[7].time;
  return json(200,{success:true,candles});
 }
 let file;
 if(url.pathname==='/chart')file=template;
 else if(url.pathname.startsWith('/static/'))file=path.resolve(stage,'.'+decodeURIComponent(url.pathname));
 else return json(503,{success:false,error:'outside read-only renderer fixture'});
 if(!file.startsWith(stage+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile())return json(404,{});
 const ext=path.extname(file);res.writeHead(200,{'content-type':ext==='.js'?'application/javascript':ext==='.css'?'text/css':ext==='.html'||ext==='.tmpl'?'text/html':'application/octet-stream','cache-control':'no-store'});
 fs.createReadStream(file).pipe(res);
});
server.on('upgrade',(_req,socket)=>socket.destroy());
(async()=>{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const origin='http://127.0.0.1:'+server.address().port;
 let browser;
 try{
  browser=await chromium.launch({channel:'msedge',headless:false});
  const context=await browser.newContext({viewport:{width:1280,height:900}});
  const external=[];const failures=[];
  await context.route('**/*',route=>{const u=new URL(route.request().url());if(u.origin===origin)return route.continue();external.push(u.origin);return route.abort();});
  const page=await context.newPage();page.on('pageerror',e=>failures.push(e.message));
  await page.goto(origin+'/chart',{waitUntil:'domcontentloaded'});
  await page.waitForFunction(()=>window.KTRADE_APP?.s.candles.length===30&&window.KTRADE_APP.s.candleContext?.generation>0);
  async function verify(){
   return page.evaluate(()=>{
    const k=window.KTRADE_APP;
    let coloured=0;
    for(const canvas of document.querySelectorAll('#chart canvas')){
     const ctx=canvas.getContext('2d');if(!ctx)continue;
     const px=ctx.getImageData(0,0,canvas.width,canvas.height).data;
     for(let i=0;i<px.length;i+=4){if(px[i+1]>80&&px[i+1]>px[i]*1.3&&px[i+2]>60)coloured++;}
    }
    return {prices:k.s.cs.data(),volumes:k.s.vs.data(),context:k.s.candleContext,coloured,trade:document.getElementById('tradeBtn').disabled,submit:document.getElementById('orderSubmit').disabled};
   });
  }
  await page.waitForFunction(()=>document.getElementById('tradeBtn').disabled&&document.getElementById('orderSubmit').disabled);
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  let actual=await verify();assert.equal(actual.prices.length,rows.length);assert.equal(actual.volumes.length,rows.length);assert.equal(actual.prices.at(-1).close,rows.at(-1).close);assert.ok(actual.coloured>100,'no genuine green candle pixels');assert.ok(actual.trade&&actual.submit);
  // User timeframe click invokes the original loadCandles handler.
  await page.locator('.tf-btn[data-tf="5m"]').click();
  await page.waitForFunction(()=>window.KTRADE_APP.s.candleContext?.tf==='5m');
  mode='invalid';await page.locator('.tf-btn[data-tf="15m"]').click();
  await page.waitForFunction(()=>document.getElementById('statusText').textContent==='Market data unavailable'&&window.KTRADE_APP.s.candleContext===null);
  actual=await verify();assert.deepEqual(actual.prices,[]);assert.deepEqual(actual.volumes,[]);assert.ok(actual.trade&&actual.submit);
  mode='unavailable';await page.locator('.tf-btn[data-tf="1h"]').click();
  await page.waitForFunction(()=>window.KTRADE_APP.s.tf==='1h'&&document.getElementById('loading').style.display==='none');
  actual=await verify();assert.deepEqual(actual.prices,[]);assert.deepEqual(actual.volumes,[]);
  mode='valid';await page.locator('.tf-btn[data-tf="1m"]').click();
  await page.waitForFunction(()=>window.KTRADE_APP.s.candleContext?.tf==='1m'&&window.KTRADE_APP.s.candles.length===30);
  assert.equal(hash(template),before,'installed chart template changed');assert.equal(external.length,0,'unexpected external browser request');assert.equal(requests.filter(x=>!x.startsWith('GET ')).length,0,'unexpected action request');
  assert.equal(failures.length,0,'uncaught chart failure: '+failures.join(';'));
  console.log('::notice::W32A_EXACT_INSTALLED_CHART_REAL_WINDOWS_EDGE_CANDLES_PIXELS_REJECTION_RECOVERY_STOPPED=PASS');
  console.log(JSON.stringify({schema:'ktrade.w32a.renderer-witness.v1',browser:browser.version(),template_sha256:before,valid_rows:rows.length,renderer:'Microsoft Edge loopback fixture; not installed Go feed or WebView2 candle acceptance',external_requests:external.length,action_requests:0,live_armed:false}));
 }finally{if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(e=>{console.error(e);process.exitCode=1;});

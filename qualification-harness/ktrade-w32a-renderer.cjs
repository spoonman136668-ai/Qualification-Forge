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
let mode='valid';const requests=[];const sockets=new Set();let rejectedFrames=0;let closing=false;const socketErrors=[];
const caps={schema:'ktrade.operator.capabilities.v1',mode:'PAPER_STOPPED',paper_orders_enabled:false,live_orders_enabled:false,strategy_execution_enabled:false,paper_accounting_enabled:false,requires_review:true};
const server=http.createServer((req,res)=>{
 const url=new URL(req.url,'http://127.0.0.1');requests.push(req.method+' '+url.pathname);
 const json=(code,value)=>{res.writeHead(code,{'content-type':'application/json','cache-control':'no-store'});res.end(JSON.stringify(value));};
 if(req.method!=='GET')return json(403,{success:false,error:'qualification never accepts an action'});
 if(url.pathname==='/api/operator/capabilities')return json(200,caps);
 if(url.pathname==='/api/candles'){
  if(mode==='unavailable')return json(503,{success:false,error:'fixture unavailable'});
  const candles=structuredClone(rows);
  const interval={'1m':60,'5m':300,'15m':900,'1h':3600}[url.searchParams.get('tf')];
  if(!interval)return json(400,{success:false});
  const first=Math.floor(rows[0].time/interval)*interval;
  candles.forEach((c,i)=>c.time=first+i*interval);
  if(mode==='invalid')candles[8].time=candles[7].time;
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
// Idle fixture WebSocket: no ticks, actions or execution messages. Keeping
// it open avoids an unrelated reconnect callback overwriting HTTP error UI.
server.on('upgrade',(req,socket)=>{
 if(new URL(req.url,'http://127.0.0.1').pathname!=='/ws/chart'||!req.headers['sec-websocket-key'])return socket.destroy();
 const accept=crypto.createHash('sha1').update(req.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
 socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+'\r\n\r\n');
 sockets.add(socket);socket.on('close',()=>sockets.delete(socket));
 socket.on('error',error=>{if(!closing||error.code!=='ECONNRESET')socketErrors.push(error.message);});
 socket.on('data',data=>{if((data[0]&15)===8){socket.end(Buffer.from([0x88,0]));}else{rejectedFrames++;socket.destroy();}});
});
(async()=>{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const origin='http://127.0.0.1:'+server.address().port;
 let browser;let report=null;
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
    let coloured=0;let candlePixels=0;
    const chartRect=document.getElementById('chart').getBoundingClientRect();
    for(const canvas of document.querySelectorAll('#chart canvas')){
     const ctx=canvas.getContext('2d');if(!ctx)continue;
     const px=ctx.getImageData(0,0,canvas.width,canvas.height).data;
     for(let i=0;i<px.length;i+=4){if(px[i+1]>80&&px[i+1]>px[i]*1.3&&px[i+2]>60)coloured++;}
     const r=canvas.getBoundingClientRect();
     if(!r.width||!r.height)continue;
     for(const bar of k.s.cs.data()){
      const x=k.s.chart.timeScale().timeToCoordinate(bar.time),y=k.s.cs.priceToCoordinate((bar.open+bar.close)/2);
      if(x===null||y===null)continue;
      const cx=Math.round((chartRect.left+x-r.left)*canvas.width/r.width),cy=Math.round((chartRect.top+y-r.top)*canvas.height/r.height);
      if(cx<1||cy<1||cx>=canvas.width-1||cy>=canvas.height-1)continue;
      const i=(cy*canvas.width+cx)*4;
      if(px[i+1]>80&&px[i+1]>px[i]*1.3&&px[i+2]>60)candlePixels++;
     }
    }
    return {prices:k.s.cs.data(),volumes:k.s.vs.data(),context:k.s.candleContext,coloured,candlePixels,trade:document.getElementById('tradeBtn').disabled,submit:document.getElementById('orderSubmit').disabled};
   });
  }
  await page.waitForFunction(()=>document.getElementById('tradeBtn').disabled&&document.getElementById('orderSubmit').disabled);
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  let actual=await verify();assert.equal(actual.prices.length,rows.length);assert.equal(actual.volumes.length,rows.length);assert.equal(actual.prices.at(-1).close,rows.at(-1).close);assert.ok(actual.coloured>100,'no genuine green candle pixels');assert.ok(actual.candlePixels>=20,'candle bodies absent at original time/price coordinates');assert.ok(actual.trade&&actual.submit);const bodyPixels=actual.candlePixels;
  // User timeframe click invokes the original loadCandles handler.
  await page.locator('.tf-btn[data-tf="5m"]').click();
  await page.waitForFunction(()=>window.KTRADE_APP.s.candleContext?.tf==='5m');
  actual=await verify();assert.equal(actual.prices[1].time-actual.prices[0].time,300);
  mode='invalid';await page.locator('.tf-btn[data-tf="15m"]').click();
  await page.waitForFunction(()=>document.getElementById('statusText').textContent==='Market data unavailable'&&window.KTRADE_APP.s.candleContext===null);
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  actual=await verify();assert.deepEqual(actual.prices,[]);assert.deepEqual(actual.volumes,[]);assert.ok(actual.coloured<10,'old candles remain painted');assert.ok(actual.trade&&actual.submit);const clearedPixels=actual.coloured;
  mode='unavailable';await page.locator('.tf-btn[data-tf="1h"]').click();
  await page.waitForFunction(()=>window.KTRADE_APP.s.tf==='1h'&&document.getElementById('loading').style.display==='none');
  actual=await verify();assert.deepEqual(actual.prices,[]);assert.deepEqual(actual.volumes,[]);
  mode='valid';await page.locator('.tf-btn[data-tf="1m"]').click();
  await page.waitForFunction(()=>window.KTRADE_APP.s.candleContext?.tf==='1m'&&window.KTRADE_APP.s.candles.length===30);
  assert.equal(hash(template),before,'installed chart template changed');assert.equal(external.length,0,'unexpected external browser request');assert.equal(requests.filter(x=>!x.startsWith('GET ')).length,0,'unexpected action request');assert.equal(rejectedFrames,0,'unexpected WebSocket application frame');
  assert.equal(failures.length,0,'uncaught chart failure: '+failures.join(';'));
  report={schema:'ktrade.w32a.renderer-witness.v1',browser:browser.version(),template_sha256:before,valid_rows:rows.length,candle_body_pixels:bodyPixels,cleared_green_pixels:clearedPixels,renderer:'Microsoft Edge loopback fixture; not installed Go feed or WebView2 candle acceptance',external_requests:external.length,action_requests:0,live_armed:false};
 }finally{closing=true;if(browser)await browser.close();for(const socket of sockets)socket.destroy();await new Promise(resolve=>server.close(resolve));}
 assert.deepEqual(socketErrors,[],'unexpected fixture socket error');
 assert.ok(report,'renderer did not complete');
 console.log('::notice::W32A_EXACT_INSTALLED_CHART_REAL_WINDOWS_EDGE_CANDLES_PIXELS_REJECTION_RECOVERY_STOPPED=PASS');
 console.log(JSON.stringify(report));
})().catch(e=>{console.error(e);process.exitCode=1;});

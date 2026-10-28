'use strict';
// Real original Go HTTP handler + original chart/Monaco/LightweightCharts.
// The Go test process owns a sealed synthetic market transport. This is an
// Edge fixture witness, separate from shipping Wails/WebView2 acceptance.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const {chromium}=require(process.env.W32_PLAYWRIGHT_MODULE);
const metadata=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const root=process.argv[3],template=path.join(root,'templates/chart.tmpl');
const hash=()=>crypto.createHash('sha256').update(fs.readFileSync(template)).digest('hex');const before=hash();
(async()=>{
 let browser,report;
 const external=[],errors=[],actions=[];
 try{
  browser=await chromium.launch({channel:'msedge',headless:false});
  const context=await browser.newContext({viewport:{width:1280,height:900}});
  await context.route('**/*',route=>{const req=route.request(),url=new URL(req.url());if(url.origin!==metadata.url){external.push(url.origin);return route.abort();}if(req.method()!=='GET')actions.push(url.pathname);return route.continue();});
  const page=await context.newPage();page.on('pageerror',error=>errors.push(error.message));
  await page.goto(metadata.url+'/chart',{waitUntil:'domcontentloaded'});
  await page.locator('#symbolBtn').click();await page.locator('.ritem[data-s="BTC-USDC"]').click();
  await page.waitForFunction(()=>window.KTRADE_APP?.s.candleContext?.product==='BTC-USDC'&&window.KTRADE_APP.s.candles.length===30);
  await page.locator('#pineBtn').click();
  const editor=page.getByRole('textbox',{name:/Pine source editor/});
  async function apply(source,secondary){
   await editor.click();await editor.press('Control+A');await page.keyboard.insertText(source);
   const responsePromise=page.waitForResponse(r=>r.url()===metadata.url+'/api/pine/overlay'&&r.request().method()==='POST');
   await page.locator('#pineAddToChart').click();
   const response=await responsePromise;assert.equal(response.status(),200);const payload=await response.json();
   assert.equal(payload.success,true);const p=payload.pane_model[0].plots[0];assert.equal(p.values.length,30);assert.deepEqual(p.values.slice(0,2),[null,null]);
   for(let i=2;i<30;i++)assert.equal(p.values[i],99+i,'independent original Go SMA value');
   await page.waitForFunction(()=>document.getElementById('pineApplyStatus').textContent==='Pine plots applied.');
   await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
   const actual=await page.evaluate(secondary=>{
    const k=window.KTRADE_APP,s=k.s._indicatorSeries[0],chart=secondary?k.s.vchart:k.s.chart;
    let hits=0;
    const container=document.getElementById(secondary?'volumeChart':'chart'),box=container.getBoundingClientRect();
    for(const canvas of container.querySelectorAll('canvas')){
     const r=canvas.getBoundingClientRect();if(!r.width||!r.height)continue;
     const ctx=canvas.getContext('2d'),px=ctx.getImageData(0,0,canvas.width,canvas.height).data;
     for(const point of s.data()){
      if(typeof point.value!=='number')continue;
      const x=chart.timeScale().timeToCoordinate(point.time),y=s.priceToCoordinate(point.value);if(x===null||y===null)continue;
      const cx=Math.round((box.left+x-r.left)*canvas.width/r.width),cy=Math.round((box.top+y-r.top)*canvas.height/r.height);
      let found=false;
      for(let dy=-3;dy<=3&&!found;dy++)for(let dx=-3;dx<=3;dx++){
       const xx=cx+dx,yy=cy+dy;if(xx<0||yy<0||xx>=canvas.width||yy>=canvas.height)continue;
       const i=(yy*canvas.width+xx)*4;if(px[i]>170&&px[i+2]>150&&px[i+1]<130){found=true;break;}
      }
      if(found)hits++;
     }
    }
    return {data:s.data(),owner:s._chart===chart,count:k.s._indicatorSeries.length,hits,trade:document.getElementById('tradeBtn').disabled,submit:document.getElementById('orderSubmit').disabled};
   },secondary);
   assert.equal(actual.count,1);assert.ok(actual.owner);assert.equal(actual.data.length,30);assert.equal('value' in actual.data[0],false);assert.equal('value' in actual.data[1],false);assert.equal(actual.data[29].value,128);assert.ok(actual.hits>=15,'original native average is absent at expected canvas coordinates');assert.ok(actual.trade&&actual.submit);
   return actual.hits;
  }
  const priceHits=await apply(metadata.v5,false),secondaryHits=await apply(metadata.v6,true);
  assert.equal(before,hash());assert.deepEqual(external,[]);assert.deepEqual(errors,[]);assert.deepEqual(actions,['/api/pine/overlay','/api/pine/overlay']);
  report={schema:'ktrade.w32c.original-go-renderer.v1',browser:browser.version(),template_sha256:before,rows:30,na_prefix:2,price_plot_pixel_hits:priceHits,secondary_plot_pixel_hits:secondaryHits,original_go_http:true,external_requests:0,financial_actions:0,live_armed:false,scope:'Windows Edge against original Go HTTP handlers with test-only synthetic transport; separate shipping WebView2 lifecycle proof'};
 }finally{if(browser)await browser.close();fs.writeFileSync(metadata.stop,'renderer finished');}
 assert.ok(report);console.log('::notice::W32C_ORIGINAL_GO_HTTP_V5_V6_PANE_ALIGNMENT_REAL_EDGE_PIXELS=PASS');console.log(JSON.stringify(report));
})().catch(e=>{console.error(e);process.exitCode=1;});

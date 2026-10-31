'use strict';
// W94A: independent presentation-boundary contract. This is deliberately NOT
// a pixel/image, retail-performance, LIVE, account, or release qualification.
const test=require('node:test');
const assert=require('node:assert/strict');
const path=require('node:path');
const {performance}=require('node:perf_hooks');
const candidate=process.env.KTRADE_CANDIDATE;
assert.ok(candidate,'W94A_EXACT_SOURCE_ROOT_REQUIRED');
const renderer=require(path.join(candidate,'static','pine_plot_renderer.js'));

const n=65;
const times=Array.from({length:n},(_,i)=>1700000000+i*60);
const values=Array.from({length:n},(_,i)=>i<9?null:110+((i*7)%13));
function payload(v=values,t=times,overlay=true){
 return {success:true,candles:t.map(time=>({time})),
  pane_model:[{id:'supertrend',overlay,plots:[{
   id:'trend',title:'Supertrend',style:'line',color:'#2962ff',
   lineWidth:2,values:v
  }]}]};
}
function chart(label){
 const record={label,created:[],removed:[]};
 const obj={
  addLineSeries(opts){
   const series={_chart:obj,options:opts,data:undefined,setData(d){this.data=d;}};
   record.created.push(series);return series;
  },
  removeSeries(s){record.removed.push(s);}
 };
 return {record,obj};
}
function app(){
 const main=chart('price'),separate=chart('pine'),captions=[],paneVisible=[];
 return {s:{chart:main.obj,pchart:separate.obj,_indicatorSeries:[]},
  main:main.record,separate:separate.record,captions,paneVisible,
  setPinePaneCaption:xs=>captions.push(xs),
  setPinePaneVisible:x=>paneVisible.push(x)};
}

test('W94A independent source-to-price-time alignment and NaN warmup gaps',()=>{
 const planned=renderer.plan(payload());
 assert.equal(planned.length,1);
 assert.equal(planned[0].overlay,true);
 assert.equal(planned[0].title,'Supertrend');
 assert.equal(planned[0].data.length,n);
 for(let i=0;i<n;i++){
  assert.deepEqual(planned[0].data[i],i<9?{time:times[i]}:{time:times[i],value:values[i]});
 }
 assert.ok(planned[0].data.slice(0,9).every(d=>!Object.hasOwn(d,'value')));
 console.log('W94A_INDEPENDENT_PRICE_TIME_GAP_ALIGNMENT=PASS bars='+n);
});

test('W94A real renderer routes overlay to original price chart and replaces stale series',()=>{
 const a=app();
 assert.equal(renderer.apply(a,payload()),1);
 assert.equal(a.main.created.length,1);
 assert.equal(a.separate.created.length,0);
 assert.deepEqual(a.main.created[0].data[11],{time:times[11],value:values[11]});
 assert.equal(a.s._indicatorSeries.length,1);
 assert.equal(a.paneVisible.length,0);
 assert.equal(a.captions.at(-1).length,0);
 const old=a.main.created[0];
 const other=payload(values,times,false);
 other.pane_model[0].plots[0].title='Williams %R';
 assert.equal(renderer.apply(a,other),1);
 assert.equal(a.separate.created.length,1);
 assert.equal(a.main.removed.length,1);
 assert.strictEqual(a.main.removed[0],old);
 assert.deepEqual(a.captions.at(-1),['Williams %R']);
 console.log('W94A_PRICE_OVERLAY_SERIES_REPLACEMENT=PASS');
});

test('W94A invalid alignment and nonfinite values fail closed before creating series',()=>{
 const a=app();
 const tests=[
  payload(values.slice(1)),
  payload(values,[...times.slice(0,12),times[11],...times.slice(13)]),
  payload(values.map((v,i)=>i===15?Number.NaN:v)),
  payload(values.map((v,i)=>i===14?Number.POSITIVE_INFINITY:v)),
  {...payload(),success:false},
 ];
 for(const bad of tests)assert.throws(()=>renderer.apply(a,bad));
 assert.equal(a.main.created.length,0);
 assert.equal(a.separate.created.length,0);
 assert.equal(a.s._indicatorSeries.length,0);
 console.log('W94A_ALIGNMENT_NONFINITE_FAILURE_CLOSED=PASS cases='+tests.length);
});

test('W94A render failure rolls back provisional series and preserves earlier applied series',()=>{
 const a=app();
 assert.equal(renderer.apply(a,payload()),1);
 const previous=a.s._indicatorSeries[0];
 a.s.chart.addLineSeries=()=>{
  const series={_chart:a.s.chart,setData(){throw Error('simulated presentation failure');}};
  a.main.created.push(series);return series;
 };
 assert.throws(()=>renderer.apply(a,payload()),/simulated presentation failure/);
 assert.equal(a.main.removed.length,1);
 assert.equal(a.main.removed[0],a.main.created[1]);
 assert.strictEqual(a.s._indicatorSeries[0],previous);
 console.log('W94A_RENDER_FAILURE_ROLLBACK=PASS');
});

test('W94A bounded presenter timing observation, not a product performance PASS',()=>{
 const bigN=300;
 const t=Array.from({length:bigN},(_,i)=>1700000000+i*60);
 const v=Array.from({length:bigN},(_,i)=>i<9?null:100+(i%7));
 const p=payload(v,t);
 const dt=[];
 for(let j=0;j<25;j++){
  const start=performance.now();
  const a=app();
  assert.equal(renderer.apply(a,p),1);
  dt.push(performance.now()-start);
 }
 dt.sort((a,b)=>a-b);
 const obs={iterations:dt.length,bars:bigN,median_ms:dt[12],max_ms:dt.at(-1),scope:'Node test doubles for chart-series input; no WebView2/rasterization/total RSS/FPS'};
 console.log('W94A_PRESENTER_TIMING_OBSERVATION='+JSON.stringify(obs));
});

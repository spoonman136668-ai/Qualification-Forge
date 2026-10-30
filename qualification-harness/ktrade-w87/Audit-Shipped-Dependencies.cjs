"use strict";
// Read-only lockfile and public-registry review. No install or lifecycle scripts.
const fs=require('node:fs'), path=require('node:path'), cp=require('node:child_process');
const crypto=require('node:crypto'), zlib=require('node:zlib');
const root=path.resolve(process.argv[2]);
const lock=JSON.parse(fs.readFileSync(path.join(root,'package-lock.json'),'utf8'));
if(lock.lockfileVersion!==3)throw Error('W87_LOCK_SCHEMA_DRIFT');
const roots={'monaco-editor':'0.45.0','lightweight-charts':'4.1.0'};
const shipping=new Set();
function resolve(from,name){
  let dir=from;
  for(;;){const key=(dir?dir+'/':'')+'node_modules/'+name;if(lock.packages[key])return key;
    if(!dir)throw Error('W87_UNRESOLVED_SHIPPING_DEPENDENCY');
    dir=path.posix.dirname(dir);if(dir==='.')dir='';
  }
}
function walk(key){if(shipping.has(key))return;shipping.add(key);
  const p=lock.packages[key];if(!p||!p.integrity||!p.resolved.startsWith('https://registry.npmjs.org/'))throw Error('W87_UNPINNED_SHIPPING_DEPENDENCY');
  for(const name of Object.keys(p.dependencies||{}))walk(resolve(key,name));
}
for(const [name,version]of Object.entries(roots)){const key='node_modules/'+name;if(lock.packages[key]?.version!==version)throw Error('W87_SHIPPING_ROOT_DRIFT');walk(key);}
if([...shipping].sort().join(',')!=='node_modules/fancy-canvas,node_modules/lightweight-charts,node_modules/monaco-editor')throw Error('W87_SHIPPING_GRAPH_DRIFT');
const audit=cp.spawnSync(process.platform==='win32'?'npm.cmd':'npm',['audit','--json','--ignore-scripts','--no-fund','--no-progress'],{cwd:root,encoding:'utf8',maxBuffer:16*1024*1024,shell:process.platform==='win32',timeout:120000});
if(audit.error||![0,1].includes(audit.status))throw Error('W87_REGISTRY_AUDIT_TRANSPORT_FAILURE');
const report=JSON.parse(audit.stdout);
if(report.error||report.auditReportVersion!==2||!report.metadata?.dependencies||!report.vulnerabilities)throw Error('W87_AUDIT_REPORT_INVALID');
const affected=[],preserved=[];
for(const [name,v]of Object.entries(report.vulnerabilities)){
  if(!Array.isArray(v.nodes)||!Array.isArray(v.via))throw Error('W87_AUDIT_NODE_SCHEMA_INVALID');
  const item={name,severity:v.severity,nodes:v.nodes,advisories:v.via.filter(x=>typeof x==='object').map(x=>({id:x.source,url:x.url,severity:x.severity,title:x.title}))};
  (v.nodes.some(n=>shipping.has(n))?affected:preserved).push(item);
}
console.log('W87_NPM_AUDIT='+JSON.stringify({shipping_nodes:[...shipping].map(key=>({key,version:lock.packages[key].version})),shipping_affected:affected,nonshipping_preserved_build_legacy:preserved,metadata:report.metadata}));
// Inspect only licensing metadata inside exact SRI-verified public tarballs.
// Never extract/execute package content or print source text.
function tarEntries(bytes){
 const out=[];let i=0;
 while(i+512<=bytes.length){const h=bytes.subarray(i,i+512);if(h.every(b=>b===0))break;
  const str=(start,end)=>h.subarray(start,end).toString('utf8').replace(/\0.*$/s,'');
  const size=parseInt(str(124,136).trim()||'0',8),prefix=str(345,500),name=(prefix?prefix+'/':'')+str(0,100);
  if(!Number.isSafeInteger(size)||size<0||i+512+size>bytes.length)throw Error('W87_TAR_INVALID');
  if((h[156]===0||h[156]===48)&&/\/(?:LICENSE[^/]*|NOTICE[^/]*|ThirdPartyNotices[^/]*|COPYING[^/]*)$/i.test(name)){
   out.push({path:name,bytes:size,sha256:crypto.createHash('sha256').update(bytes.subarray(i+512,i+512+size)).digest('hex')});
  }
  i+=512+Math.ceil(size/512)*512;
 }return out;
}
(async()=>{
 const licenses=[];
 for(const key of shipping){const p=lock.packages[key];const r=await fetch(p.resolved,{signal:AbortSignal.timeout(60000)});if(!r.ok)throw Error('W87_REGISTRY_PACKAGE_FAILED');
  const data=Buffer.from(await r.arrayBuffer());if(data.length>40*1024*1024)throw Error('W87_PACKAGE_SIZE_REFUSED');
  const [alg,sum]=p.integrity.split('-');if(!['sha512','sha256'].includes(alg)||crypto.createHash(alg).update(data).digest('base64')!==sum)throw Error('W87_PACKAGE_INTEGRITY_FAILED');
  const entries=tarEntries(zlib.gunzipSync(data,{maxOutputLength:200*1024*1024}));if(key!=='node_modules/fancy-canvas'&&!entries.some(x=>/\/LICENSE/i.test(x.path)))throw Error('W87_LICENSE_MISSING');
  const rootNotices=entries.filter(x=>/^package\/[^/]+$/.test(x.path));
  const primary=['LICENSE','LICENSE.md','LICENSE.txt','license'].find(n=>rootNotices.some(x=>x.path==='package/'+n));
  let fallback=null;
  if(!primary&&key==='node_modules/fancy-canvas'){
    const upstream='https://raw.githubusercontent.com/tradingview/fancy-canvas/7ece7601f05b624496f485cee65789ad691427df/LICENSE';
    const response=await fetch(upstream,{signal:AbortSignal.timeout(30000)});if(!response.ok)throw Error('W87_UPSTREAM_LICENSE_UNAVAILABLE');
    const expected=Buffer.from(await response.arrayBuffer()),hash='52d2ba0c8f8f4532bd524358d679693ff3dd9e40c56fe0c0c63061ed0733aa18';
    for(const b of [expected,fs.readFileSync(path.join(root,'scripts/vendor-licenses/fancy-canvas-2.1.0.LICENSE')),fs.readFileSync(path.join(root,'static/vendor/licenses/fancy-canvas.LICENSE'))])if(crypto.createHash('sha256').update(b).digest('hex')!==hash)throw Error('W87_UPSTREAM_LICENSE_BYTES_DRIFT');
    fallback={url:upstream,sha256:hash,shipped:true,reason:'published npm2.1.0 omits license'};
  }else if(!primary)throw Error('W87_PRIMARY_LICENSE_MISSING');
  const name=key.replace('node_modules/','');
  for(const entry of rootNotices){const base=entry.path.slice('package/'.length);const target=name+'.'+(base===primary?'LICENSE':base);
    const shipped=fs.readFileSync(path.join(root,'static/vendor/licenses',target));
    if(crypto.createHash('sha256').update(shipped).digest('hex')!==entry.sha256)throw Error('W87_LICENSE_OR_NOTICE_NOT_SHIPPED_EXACTLY');
  }
  licenses.push({package:key,version:p.version,licenses:entries,root_notices_shipped:rootNotices.length,upstream_fallback:fallback});
 }
 console.log('W87_EXACT_NPM_TARBALL_LICENSE_INVENTORY='+JSON.stringify(licenses));
 if(affected.length)throw Error('W87_KNOWN_SHIPPING_JAVASCRIPT_VULNERABILITY');
 console.log('W87_LOCKED_SHIPPING_JAVASCRIPT_KNOWN_ADVISORY_SCAN=PASS');
 console.log('W87_ALL_EXACT_ROOT_LICENSES_AND_NOTICES_SHIPPED=PASS');
})().catch(e=>{console.error(e.message);process.exitCode=1;});

"use strict";
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const kinds={
 go:['Full original Go engine app and Wails tests and vet','pwsh'],
 node:['All current Node cases and original two-root browser compatibility','pwsh'],
 assets:['Locked assets repeatability shipping advisories and exact notices','pwsh'],
 build:['Fresh original unsigned Windows installer and actual shipping binary scans','powershell']
};
const kind=process.argv[2],spec=kinds[kind];if(!spec)throw Error('SOURCE_CI_STEP_NOT_ALLOWLISTED');
const root=path.join(process.env.GITHUB_WORKSPACE,'product');
const lines=fs.readFileSync(path.join(root,'.github/workflows/ktrade-native-windows.yml'),'utf8').split(/\r?\n/);
const matches=lines.flatMap((line,i)=>line==='      - name: '+spec[0]?[i]:[]);
if(matches.length!==1)throw Error('SOURCE_CI_STEP_NAME_NOT_UNIQUE');
const start=matches[0];let end=start+1;
while(end<lines.length&&!/^      - /.test(lines[end]))end++;
const block=lines.slice(start,end);
if(!block.includes('        shell: '+spec[1])||!block.includes('        working-directory: product'))throw Error('SOURCE_CI_EXECUTION_SEAM_DRIFT');
const run=block.indexOf('        run: |');if(run<0)throw Error('SOURCE_CI_RUN_BLOCK_MISSING');
const body=block.slice(run+1).map(line=>{if(!line.trim())return '';if(!line.startsWith('          '))throw Error('SOURCE_CI_INDENT_DRIFT');return line.slice(10);}).join('\n').trimEnd()+'\n';
if(body.includes('${{'))throw Error('SOURCE_CI_UNRESOLVED_EXPRESSION');
const output=path.join(process.env.RUNNER_TEMP,'ktrade-source-ci-'+kind+'.ps1');
fs.writeFileSync(output,body,{encoding:'utf8',flag:'wx',mode:0o600});
console.log(JSON.stringify({kind,shell:spec[1],path:output,script_sha256:crypto.createHash('sha256').update(body).digest('hex'),lines:body.split('\n').length-1}));

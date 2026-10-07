const fs=require('node:fs'),assert=require('node:assert/strict'),path=require('node:path'),{execFileSync}=require('node:child_process'),crypto=require('node:crypto');
const html=fs.readFileSync('index.html','utf8'),sources=[...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)],results=[];
for(const [i,m] of sources.entries()){
 const src=m[1].match(/src=["']([^"']+)/)?.[1];
 if(src&&!/^https?:/.test(src)){const file=src.split('?')[0];assert(fs.existsSync(file),file);execFileSync(process.execPath,['--check',file]);results.push({file,status:'PASS'});}
 if(!src&&m[2].trim()){execFileSync(process.execPath,['--check',...(m[1].includes('module')?['--input-type=module']:[])],{input:m[2]});results.push({inline:i,status:'PASS'});}
}
assert.equal(fs.readFileSync('report-renderers.js','utf8'),fs.readFileSync('supabase/functions/_shared/report-renderers.js','utf8'));
for(const file of ['financial-commands.js','project-team.js','obligations.js'])assert(html.includes(file+'?v=20261007-operator'));
const publishable=execFileSync('git',['ls-files','--cached','--others','--exclude-standard'],{encoding:'utf8'}).trim().split('\n');const findings=[];
for(const file of publishable){if(!fs.existsSync(file)||fs.statSync(file).isDirectory())continue;const text=fs.readFileSync(file,'utf8');if(/\b(?:sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{25,}|sb_secret_[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{25,})\b|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(text))findings.push(file);}
assert.deepEqual(findings,[],'Private credential pattern in publishable files');
const evidence={status:'PASS',scripts:results,identical_report_renderer:true,renderer_sha256:crypto.createHash('sha256').update(fs.readFileSync('report-renderers.js')).digest('hex'),private_credential_pattern_findings:findings,publication:'not performed'};
fs.writeFileSync('tests/artifacts/frontend-compatibility.json',JSON.stringify(evidence,null,2));console.log('PASS: local assets and inline/module syntax, cache versions, identical UI/server report renderer, no private credential patterns in publishable files');

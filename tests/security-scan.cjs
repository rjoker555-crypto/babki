// Never prints credential values or surrounding source lines.
const fs=require('node:fs'),path=require('node:path'),{execFileSync}=require('node:child_process');
const git=args=>execFileSync('git',args,{encoding:'utf8',maxBuffer:80*1024*1024});
const findings=[],seen=new Set();let files=0,blobs=0;
function scan(text,location){
 const patterns=[['OpenAI',/\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}/g],['Supabase secret',/\bsb_secret_[A-Za-z0-9_-]{16,}/g],['GitHub token',/\b(?:gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{30,})/g],['Private key',/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/g],['Password connection URL',/\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?):\/\/[^\s:/]+:[^\s@]+@/g],['AWS access key',/\b(?:AKIA|ASIA)[A-Z0-9]{16}\b/g],['Credential assignment',/(?:password|passwd|jwt_secret|client_secret|webhook_secret|access_token|api_key|service_role_key)\s*[=:]\s*["']([^"'\r\n]{8,})["']/gi],['JWT',/\beyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g]];
 for(const [type,re] of patterns)for(const m of text.matchAll(re)){
  let kind=type,value=m[1]||m[0];
  if(type==='JWT'){try{const p=JSON.parse(Buffer.from(value.split('.')[1],'base64url'));kind=p.role==='anon'?'Supabase anon (public)':p.role==='service_role'?'Supabase service_role':'JWT credential';}catch{}}
  if(type==='Credential assignment'&&/^(?:test|mock|fake|YOUR|example|placeholder|Bearer |OpenAI|SUPABASE)/i.test(value))continue;
  const key=location+'|'+kind+'|'+value;if(seen.has(key))continue;seen.add(key);
  findings.push({location,type:kind,masked:type==='Private key'?'private-key-header':value.slice(0,Math.min(8,value.length-4))+'...'+value.slice(-4),line:text.slice(0,m.index).split('\n').length});
 }
}
function walk(dir){for(const d of fs.readdirSync(dir,{withFileTypes:true})){if(['.git','node_modules','.agents','.codex'].includes(d.name))continue;const f=path.join(dir,d.name);if(d.isDirectory())walk(f);else if(d.isFile()&&fs.statSync(f).size<20*1024*1024){files++;scan(fs.readFileSync(f,'utf8'),'worktree:'+f.replaceAll('\\','/'));}}}
walk('.');
for(const row of git(['rev-list','--objects','--all']).trim().split('\n')){const [oid,...rest]=row.split(' ');if(!oid)continue;if(git(['cat-file','-t',oid]).trim()==='blob'){blobs++;scan(git(['cat-file','blob',oid]),'git:'+oid.slice(0,12)+':'+rest.join(' '));}}
scan(git(['log','--all','--format=%B']),'git:commit-messages');scan(git(['config','--get-regexp','remote\..*\.url']),'git:remote-config');
const report={commits:Number(git(['rev-list','--all','--count']).trim()),shallow:git(['rev-parse','--is-shallow-repository']).trim(),worktree_files:files,history_blobs:blobs,findings};
fs.mkdirSync('tests/artifacts',{recursive:true});fs.writeFileSync('tests/artifacts/security-secret-scan.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));

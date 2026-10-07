// Real isolated Auth / main-agent / private Storage, direct report route makes no model call.
const fs=require('fs'),assert=require('node:assert/strict');
const f=JSON.parse(fs.readFileSync('tests/artifacts/report-fixture.json','utf8')),html=fs.readFileSync('index.html','utf8'),base=html.match(/const SUPABASE_URL='([^']+)'/)[1],key=html.match(/const SUPABASE_PUBLISHABLE_KEY='([^']+)'/)[1];
async function req(path,token,body,status=200){const r=await fetch(base+path,{method:body?'POST':'GET',headers:{apikey:key,Authorization:'Bearer '+token,...(body?{'Content-Type':'application/json'}:{})},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(30000)});const text=await r.text();let value;try{value=JSON.parse(text)}catch{value=text}assert.equal(r.status,status,JSON.stringify(value));return value;}
(async()=>{
 const auth=await req('/auth/v1/token?grant_type=password',key,{email:f.email,password:f.password});
 const files=[];
 if(process.argv.includes('--cleanup')){const result=JSON.parse(fs.readFileSync('tests/artifacts/report-live-result.json','utf8'));for(const file of result.files){const deleted=await req('/functions/v1/agent-files',auth.access_token,{operation:'delete_report',report_id:file.id});assert(deleted.removed&&deleted.verified);const response=await req('/rest/v1/agent_report_assets?id=eq.'+file.id+'&select=id',auth.access_token);assert.equal(response.length,0);}console.log('PASS: real report files physically cleaned through checked owner endpoint, metadata absent');return;}
 for(const kind of ['statement','statement_text','production','organization_month','proposals']){
  const args={kind,project_id:['statement','statement_text','production'].includes(kind)?f.project:null,month:kind==='organization_month'?'2026-10':null,company:'all',from:kind==='production'?'2026-10-01':null,to:kind==='production'?'2026-10-31':null};
  const result=await req('/functions/v1/main-agent',auth.access_token,{operation:'build_report',message_id:f.message,report_args:args});assert.equal(result.model_calls,0);assert(result.report.verified&&result.report.mime_type===(kind==='statement_text'?'text/plain':'text/html'));
  const response=await fetch(result.report.url);assert(response.ok);const bytes=Buffer.from(await response.arrayBuffer());assert.equal(await crypto.subtle.digest('SHA-256',bytes).then(x=>Buffer.from(x).toString('hex')),result.report.sha256);if(kind!=='statement_text')assert(bytes.includes(Buffer.from('Content-Security-Policy')));assert(!/<script\b/i.test(bytes.toString()));
  const [asset]=await req('/rest/v1/agent_report_assets?id=eq.'+result.report.report_id+'&select=*',auth.access_token);assert.equal(asset.owner_id,f.actor);files.push({id:asset.id,path:asset.file_path});
  const publicResponse=await fetch(base+'/storage/v1/object/public/operator-reports/'+asset.file_path);assert(!publicResponse.ok);
  if(kind==='statement'){assert(bytes.toString().includes('123'));const repeat=await req('/functions/v1/main-agent',auth.access_token,{operation:'build_report',message_id:f.message,report_args:args});assert.equal(repeat.report.report_id,asset.id);}
  console.log('PASS: deployed '+kind+', actual private file bytes/hash, no model call, anonymous public URL denied');
 }
 fs.writeFileSync('tests/artifacts/report-live-result.json',JSON.stringify({actor:f.actor,files,status:'PASS'}));
})().catch(e=>{console.error(e.message);process.exitCode=1});

// Public-key-only outsider probes. No real writes, user creation or paid calls.
const fs=require('node:fs'),assert=require('node:assert/strict');
(async()=>{
 const html=fs.readFileSync('index.html','utf8'),base=html.match(/const SUPABASE_URL='([^']+)'/)[1],key=html.match(/const SUPABASE_PUBLISHABLE_KEY='([^']+)'/)[1];const results=[];
 async function probe(name,path,options={}){const r=await fetch(base+path,{...options,headers:{apikey:key,'Content-Type':'application/json',...options.headers},signal:AbortSignal.timeout(15000)});let body;try{body=await r.json()}catch{body=null}results.push({name,status:r.status,...(Array.isArray(body)?{rows:body.length}:{})});return {r,body};}
 for(const name of ['main-agent','transcribe-voice','agent-files','agent-worker','operator-evaluation']){
  const {r}=await probe('no authorization: '+name,'/functions/v1/'+name,{method:'POST',body:'{}'});assert([401,403].includes(r.status));
  const forged=await probe('public key used as bearer: '+name,'/functions/v1/'+name,{method:'POST',headers:{Authorization:'Bearer '+key},body:'{}'});assert([401,403].includes(forged.r.status));
 }
 for(const table of ['projects','operations','profiles','agent_chat_messages','project_documents','agent_file_assets','agent_report_assets','agent_operator_plans']){const {r,body}=await probe('anonymous read: '+table,'/rest/v1/'+table+'?select=id&limit=1');assert([401,403].includes(r.status)||r.status===200&&Array.isArray(body)&&body.length===0);}
 for(const bucket of ['project-documents','agent-files','operator-reports']){const {r,body}=await probe('anonymous storage listing: '+bucket,'/storage/v1/object/list/'+bucket,{method:'POST',body:'{"limit":1,"prefix":""}'});assert(r.status>=400||Array.isArray(body)&&body.length===0);}
 const {r,body}=await probe('public Auth settings','/auth/v1/settings');results.push({auth_settings_available:r.ok,email_enabled:body?.external?.email??null,anonymous_sign_ins_enabled:body?.external?.anonymous_users??null,disable_signup:body?.disable_signup??null});
 const internal=await probe('internal net schema not exposed','/rest/v1/http_request_queue?select=id&limit=1',{headers:{'Accept-Profile':'net'}});assert([401,403,406].includes(internal.r.status));
 fs.mkdirSync('tests/artifacts',{recursive:true});fs.writeFileSync('tests/artifacts/security-http.json',JSON.stringify(results,null,2));console.log(JSON.stringify(results,null,2));
})().catch(e=>{console.error(e.name+': '+e.message);process.exit(1)});

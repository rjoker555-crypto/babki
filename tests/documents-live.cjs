// Real Auth + private Storage. Explicit synthetic actors/project; no model calls.
const fs=require('node:fs'),assert=require('node:assert/strict'),JSZip=require('jszip');
const f=JSON.parse(fs.readFileSync('tests/artifacts/document-fixture.json','utf8')),html=fs.readFileSync('index.html','utf8');
const base=html.match(/const SUPABASE_URL='([^']+)'/)[1],key=html.match(/const SUPABASE_PUBLISHABLE_KEY='([^']+)'/)[1];
async function req(path,token,opt={},expect=200){const r=await fetch(base+path,{...opt,headers:{apikey:key,Authorization:'Bearer '+token,...opt.headers},signal:AbortSignal.timeout(25000)});const t=await r.text();let b;try{b=JSON.parse(t)}catch{b=t}if(r.status!==expect)throw Error(path+' HTTP '+r.status+': '+JSON.stringify(b));return b;}
const post=(path,t,b)=>req(path,t,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)});
(async()=>{
 const a=await post('/auth/v1/token?grant_type=password',key,{email:f.email,password:f.password}),fm=await post('/auth/v1/token?grant_type=password',key,{email:f.foremanEmail,password:f.password});
 if(f.plan){const confirmed=await post('/functions/v1/main-agent',a.access_token,{message_id:f.confirmation,approval:f.plan});assert.equal(confirmed.data_changed,true);assert(confirmed.message.content.includes('Производ')||confirmed.message.content.includes('производ'));const sections=await req('/rest/v1/project_work_sections?select=id&project_id=eq.'+f.project,a.access_token);assert.equal(sections.length,1);console.log('PASS: deployed main-agent HTTP confirmation executes production plan and returns verified readable result without a model call');}
 const zip=new JSZip();zip.file('[Content_Types].xml','<Types/>');zip.file('word/document.xml','<w:document><w:p><w:r><w:t>TEST CONTRACT ONLY</w:t></w:r></w:p></w:document>');
 const content=await zip.generateAsync({type:'nodebuffer',compression:'DEFLATE'}),fileId=crypto.randomUUID(),form=new FormData();form.set('chat_id',f.chat);form.set('file_id',fileId);form.set('file',new Blob([content]),'test.docx');
 const uploaded=await req('/functions/v1/agent-files',a.access_token,{method:'POST',body:form});assert.equal(uploaded.file.id,fileId);
 const rpc=cmd=>post('/rest/v1/rpc/execute_document_command',a.access_token,{p_request:crypto.randomUUID(),p_command:cmd});
 const attach=await rpc({action:'attach',project_id:f.project,document_type:'contract',file_id:fileId,values:{title:'TEST contract'}});assert(attach.verified);let doc=attach.document;
 await req('/functions/v1/agent-files',fm.access_token,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({operation:'download',file_id:fileId})},403);
 const path=f.project+'/'+crypto.randomUUID()+'/replacement.txt',text='TEST READY REPLACEMENT';
 await req('/storage/v1/object/project-documents/'+path,a.access_token,{method:'POST',headers:{'Content-Type':'text/plain','x-upsert':'false'},body:text});
 const replace=await rpc({action:'replace',id:doc.id,expected:doc,uploaded_file:{storage_bucket:'project-documents',file_path:path,file_name:'replacement.txt',mime_type:'text/plain',file_size:Buffer.byteLength(text)},values:{title:'TEST replacement'}});assert.equal(replace.document.version_no,2);doc=replace.document;
 const versions=await req('/rest/v1/project_document_versions?select=*&document_id=eq.'+doc.id,a.access_token);assert.equal(versions.length,2);assert.equal(versions.find(x=>x.version_no===1).storage_bucket,'agent-files');
 const signed=await post('/functions/v1/agent-files',a.access_token,{operation:'download',file_id:fileId});const old=await fetch(signed.url);assert(old.ok);assert.deepEqual(Buffer.from(await old.arrayBuffer()),content);
 const request=crypto.randomUUID(),deleted=await post('/rest/v1/rpc/execute_document_command',a.access_token,{p_request:request,p_command:{action:'delete',id:doc.id,expected:doc,values:{}}});assert(deleted.verified&&deleted.file_cleanup_pending);
 const cleanup=await post('/functions/v1/agent-files',a.access_token,{operation:'cleanup_document',request_id:request});assert.equal(cleanup.cleanup.status,'completed');
 assert(cleanup.cleanup.outcomes.some(x=>x.path===path&&x.status==='removed'));assert(cleanup.cleanup.outcomes.some(x=>x.path===uploaded.file.storage_path&&x.status==='retained'));
 assert.equal((await req('/rest/v1/project_documents?select=id&id=eq.'+doc.id,a.access_token)).length,0);assert.equal((await req('/rest/v1/project_document_versions?select=id&document_id=eq.'+doc.id,a.access_token)).length,0);
 const retry=await post('/functions/v1/agent-files',a.access_token,{operation:'cleanup_document',request_id:request});assert.equal(retry.cleanup.status,'completed');
 await req('/storage/v1/object/project-documents/'+path,a.access_token,{},400);
 // Same personal draft as a real proposal letter, then a prepared replacement.
 const kpRpc=cmd=>post('/rest/v1/rpc/execute_proposal_command',a.access_token,{p_request:crypto.randomUUID(),p_command:cmd});
 let kp=(await kpRpc({action:'create',values:{name:'TEST live KP',status:'review',amount:1234.56},file_id:fileId})).proposal;assert.equal(kp.letter_storage_bucket,'agent-files');
 await req('/functions/v1/agent-files',fm.access_token,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({operation:'download',file_id:fileId})},403);
 const kpPath='kps/'+crypto.randomUUID()+'/replacement.txt';await req('/storage/v1/object/project-documents/'+kpPath,a.access_token,{method:'POST',headers:{'Content-Type':'text/plain','x-upsert':'false'},body:text});
 let kpResult=await kpRpc({action:'update',id:kp.id,expected:kp,values:{status:'won'},uploaded_file:{storage_bucket:'project-documents',file_path:kpPath,file_name:'replacement.txt',mime_type:'text/plain',file_size:Buffer.byteLength(text)}});kp=kpResult.proposal;
 let kpCleanup=await post('/functions/v1/agent-files',a.access_token,{operation:'cleanup_document',request_id:kpResult.cleanup_request_id});assert.equal(kpCleanup.cleanup.outcomes[0].status,'retained');
 kpResult=await kpRpc({action:'delete',id:kp.id,expected:kp,values:{}});kpCleanup=await post('/functions/v1/agent-files',a.access_token,{operation:'cleanup_document',request_id:kpResult.cleanup_request_id});assert.equal(kpCleanup.cleanup.outcomes[0].status,'removed');assert.equal((await req('/rest/v1/commercial_proposals?select=id&id=eq.'+kp.id,a.access_token)).length,0);await req('/storage/v1/object/project-documents/'+kpPath,a.access_token,{},400);
 console.log('PASS: real proposal draft letter, foreman refusal after document deletion, checked replacement/status/delete; personal draft retained and prepared replacement physically removed');
 // Remove own chat draft only after metadata and versions have been verified absent.
 fs.writeFileSync('tests/artifacts/document-live-result.json',JSON.stringify({actor:f.actor,asset:fileId,path:uploaded.file.storage_path,request,result:'PASS'}));
 console.log('PASS: real DOCX chat upload; foreman contract download denied; atomic replacement preserves version 1 and bytes; agreed deletion removes version 2, retains personal draft, retries safely; no paid calls');
})().catch(e=>{console.error(e.message);process.exitCode=1});

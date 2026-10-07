const vm=require('node:vm'),assert=require('node:assert/strict'),JSZip=require('jszip'),{inflateRawSync}=require('node:zlib'),{webcrypto}=require('node:crypto'),{PDFDocument}=require('pdf-lib'),{mainSource}=require('./load-edge.cjs');
const id='11111111-1111-4111-8111-111111111111';
(async()=>{
 const zip=new JSZip();zip.file('word/document.xml','<w:document><w:body><w:p><w:r><w:t>Договор 27-2. Мы подрядчики.</w:t></w:r></w:p><w:p><w:r><w:t>4.1 Заказчик оплачивает работы в течение 60 дней после подписания КС.</w:t></w:r></w:p></w:body></w:document>');const bytes=await zip.generateAsync({type:'uint8array',compression:'DEFLATE'});
 const doc={id,project_id:id,title:'Договор',document_type:'contract',file_name:'contract.docx',file_path:'project/contract.docx',storage_bucket:'project-documents',version_no:1,file_size:bytes.length,updated_at:'2026-10-05'};let calls=0,downloaded=0,providerInput;
 const context={Response,AbortSignal,TextDecoder,Uint8Array,DataView,Array,crypto:webcrypto,inflateRawSync,PDFDocument,btoa,Deno:{env:{get:name=>name==='SUPABASE_URL'?'https://test':'server-secret'}},fetch:async(url,opt={})=>{
  const json=v=>new Response(JSON.stringify(v));
  if(url.endsWith('/auth/v1/user'))return json({id});if(url.includes('/profiles?'))return json([{role:'director',is_active:true}]);if(url.includes('/agent_director_access?'))return json([{user_id:id}]);
  if(url.includes('/storage/v1/')){downloaded++;return new Response(bytes);}
  if(url.includes('/projects?'))return json([{id,name:'Гостиница кузня',responsible_user_id:id}]);if(url.includes('/project_documents?'))return json([doc]);if(url.includes('/project_work_items?'))return json([]);
  if(url.includes('/rpc/agent_reserve_request'))return json('reserved');if(url.includes('/rpc/'))return json(true);if(url.includes('/agent_request_runs?')||url.endsWith('/agent_tool_runs'))return json([]);
  if(url.endsWith('/agent_chat_messages'))return json([{id,...JSON.parse(opt.body)}]);
  if(url.includes('/agent_chat_messages?'))return json([{id,chat_id:id,owner_id:id,kind:'user',content:'Какие слабые места договора гостиницы для нас как подрядчиков?',created_at:'2026-10-06T00:00:00Z'}]);
  if(url==='https://api.openai.com/v1/responses'){
   const body=JSON.parse(opt.body);calls++;providerInput=body.input;
   const steps=[['get_project_context',{project_id:id}],['select_specialization',{module:'russian_law'}],['read_company_document',{document_id:id,offset:0}]];
   const step=steps[calls-1];if(step)return json({output:[{type:'function_call',call_id:'call-'+calls,name:step[0],arguments:JSON.stringify(step[1])}],usage:{input_tokens:10,output_tokens:5}});
   const supplied=body.input.find(x=>x.type==='function_call_output'&&JSON.parse(x.output).content_read);assert(supplied,'Document text missing from actual provider input');assert(JSON.parse(supplied.output).text.includes('60 дней'));assert(body.instructions.includes('Специализация russian_law'));assert(!JSON.stringify(body.input).includes('server-secret'));
   return json({output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({explanation:'Пункт 4.1: оплата через 60 дней после подписания КС создаёт для подрядчика кассовый разрыв.',instruction_summary:null,action:null})}]}],usage:{input_tokens:10,output_tokens:5}});
  }throw Error('Unexpected route '+url);
 }};vm.createContext(context);vm.runInContext(mainSource(),context);const r=await context.handle(new Request('https://test',{method:'POST',headers:{Authorization:'Bearer user'},body:JSON.stringify({message_id:id})}));const result=await r.json();assert.equal(r.status,200,result.error);assert.equal(downloaded,1);assert.equal(calls,4);assert(result.message.content.includes('Пункт 4.1'));assert(providerInput.some(x=>x.type==='function_call_output'&&JSON.parse(x.output).sha256));
 console.log('PASS: metadata -> legal specialization -> private DOCX text -> grounded response; actual provider payload carries clauses and excludes credentials');
})().catch(e=>{console.error(e);process.exit(1)});

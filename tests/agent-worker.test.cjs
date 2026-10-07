const vm=require('node:vm'),assert=require('node:assert/strict'),{webcrypto}=require('node:crypto'),{PDFDocument}=require('pdf-lib'),{plain}=require('./load-edge.cjs');
(async()=>{
 const pdf=await PDFDocument.create();for(let i=0;i<4;i++)pdf.addPage().drawText('Page '+(i+1));const bytes=await pdf.save();const sha=Buffer.from(await webcrypto.subtle.digest('SHA-256',bytes)).toString('hex');
 async function run({begin=true,timeout=false,hash=sha,validToken=true}={}){
  const calls=[];let chunk;const ctx={Response,AbortSignal,TextDecoder,Uint8Array,Array,crypto:webcrypto,PDFDocument,btoa,Deno:{env:{get:k=>k==='SUPABASE_URL'?'https://test':'server-key'}},fetch:async(url,opt={})=>{
   calls.push({url,opt});const json=v=>new Response(JSON.stringify(v));
   if(url.includes('rpc/agent_reserve_api_call')||url.includes('rpc/agent_record_api_usage'))return json(true);
   if(url.includes('rpc/agent_check_worker_token'))return json(validToken);
   if(url.includes('rpc/agent_claim_analysis'))return json({job:{id:'job',lease_id:'lease',step_cursor:1,instruction:'Извлечь ведомость'},file:{id:'file',storage_path:'owner/file.pdf',file_size:bytes.length,sha256:hash,mime_type:'application/pdf',page_count:4,file_name:'project.pdf'}});
   if(url.includes('/storage/v1/'))return new Response(bytes);
   if(url.includes('rpc/agent_begin_step'))return json(begin);
   if(url.includes('rpc/agent_finish_step')||url.includes('rpc/agent_fail_analysis'))return json(true);
   if(url.includes('api.openai.com')){
    if(timeout)throw Error('Synthetic network timeout');const body=JSON.parse(opt.body);chunk=body.input[0].content[0];
    return json({id:'response',usage:{input_tokens:10,output_tokens:5},output:[{type:'message',content:[{type:'output_text',text:JSON.stringify({summary:'Ведомость',pages:[{number:3,readable:true,notes:''},{number:4,readable:true,notes:''}],rows:[{name:'Кабель',unit:'м',quantity:'10.5',kind:'material',provenance:'extracted',source_page:3,source_quote:'10.5 m',formula:null,questions:[]}],risks:[]})}]}]});
   }throw Error('Unexpected route '+url);
  }};vm.createContext(ctx);vm.runInContext(plain('supabase/functions/_shared/http.ts')+plain('supabase/functions/main-agent/modules.ts')+plain('supabase/functions/agent-worker/analysis.ts')+plain('supabase/functions/agent-worker/index.ts'),ctx);
  const res=await ctx.handle(new Request('https://test/worker',{method:'POST',headers:{'x-worker-token':'a'.repeat(64)}}));return {status:res.status,body:await res.json(),calls,chunk};
 }
 const good=await run();assert.equal(good.body.status,'step_completed',good.body.error);const actual=await PDFDocument.load(Buffer.from(good.chunk.file_data.split(',')[1],'base64'));assert.equal(actual.getPageCount(),2);assert(good.chunk.filename.includes('3-4'));
 const saved=JSON.parse(good.calls.find(c=>c.url.includes('rpc/agent_finish_step')).opt.body);assert.equal(saved.p_result.rows[0].source_page,3);assert.equal(saved.p_result.rows[0].review_status,'needs_review');
 const cancelled=await run({begin:false});assert(!cancelled.calls.some(c=>c.url.includes('api.openai.com')));
 const failed=await run({timeout:true});assert.equal(JSON.parse(failed.calls.find(c=>c.url.includes('rpc/agent_fail_analysis')).opt.body).p_uncertain,true);assert.equal(failed.calls.filter(c=>c.url.includes('api.openai.com')).length,1);
 const corrupt=await run({hash:'0'.repeat(64)});assert(!corrupt.calls.some(c=>c.url.includes('api.openai.com')));
 const unauthorized=await run({validToken:false});assert.equal(unauthorized.status,401);assert(!unauthorized.calls.some(c=>c.url.includes('rpc/agent_claim_analysis')));
 console.log('PASS: authenticated worker, real PDF splitting, absolute page sources, durable checkpoint, cancellation, corrupted bytes and no automatic paid retry');
})().catch(e=>{console.error(e);process.exit(1)});

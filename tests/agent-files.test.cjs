const vm=require('node:vm'),assert=require('node:assert/strict'),{File}=require('node:buffer'),{webcrypto}=require('node:crypto'),{PDFDocument}=require('pdf-lib'),{plain}=require('./load-edge.cjs');
const actor='11111111-1111-4111-8111-111111111111',chat='22222222-2222-4222-8222-222222222222',fileId='33333333-3333-4333-8333-333333333333';
async function scenario(file,{active=true,chatOwned=true,duplicate=null}={}){
 const calls=[];let saved;const ctx={Response,Request,File,AbortSignal,TextDecoder,Uint8Array,crypto:webcrypto,PDFDocument,Deno:{env:{get:k=>k==='SUPABASE_URL'?'https://test':k==='SUPABASE_SERVICE_ROLE_KEY'?'server-key':'anon-key'}},fetch:async(url,opt={})=>{
  calls.push({url,opt});const json=(v,status=200)=>new Response(JSON.stringify(v),{status});
  if(url.endsWith('/auth/v1/user'))return json({id:actor});if(url.includes('/profiles?'))return json([{id:actor,role:'director',is_active:active}]);
  if(url.includes('/agent_conversations?'))return json(chatOwned?[{id:chat}]:[]);
  if(url.includes('/agent_file_assets?'))return json(url.includes('&id=eq.')?duplicate?[duplicate]:[]:[]);
  if(url.includes('/storage/v1/object/agent-files/'))return json({Key:'stored'});
  if(url.endsWith('/agent_file_assets')){saved=JSON.parse(opt.body);return json([saved]);}
  throw Error('Unexpected route '+url);
 }};vm.createContext(ctx);vm.runInContext(plain('supabase/functions/_shared/http.ts')+plain('supabase/functions/agent-files/index.ts'),ctx);
 const form=new FormData();form.set('file',file);form.set('chat_id',chat);form.set('file_id',fileId);
 const res=await ctx.handle(new Request('https://test/functions/v1/agent-files',{method:'POST',headers:{Authorization:'Bearer user'},body:form}));return {status:res.status,body:await res.json(),calls,saved};
}
(async()=>{
 const pdf=await PDFDocument.create();pdf.addPage().drawText('Cable specification: 10.5 m');const bytes=await pdf.save();
 const good=await scenario(new File([bytes],'project.pdf',{type:'application/pdf'}));assert.equal(good.status,200);assert.equal(good.saved.page_count,1);assert.equal(good.saved.owner_id,actor);assert.equal(good.saved.sha256.length,64);
 assert(good.calls.find(c=>c.url.includes('/storage/v1/')).opt.headers.Authorization==='Bearer server-key');
 const forged=await scenario(new File(['not a pdf'],'project.pdf',{type:'application/pdf'}));assert.equal(forged.status,415);assert(!forged.calls.some(c=>c.url.includes('/storage/v1/')));
 const foreign=await scenario(new File([bytes],'project.pdf'),{chatOwned:false});assert.equal(foreign.status,403);assert(!foreign.calls.some(c=>c.url.includes('/storage/v1/')));
 const inactive=await scenario(new File([bytes],'project.pdf'),{active:false});assert.equal(inactive.status,401);
 const bigPdf=await PDFDocument.create();for(let i=0;i<41;i++)bigPdf.addPage();const big=await scenario(new File([await bigPdf.save()],'large.pdf'));assert.equal(big.status,413);
 const text=await scenario(new File(['Кабель: 10 м'],'project.txt'));assert.equal(text.status,200);assert.equal(text.saved.mime_type,'text/plain');
 const repeat=await scenario(new File([bytes],'project.pdf'),{duplicate:good.saved});assert.equal(repeat.status,200);assert(!repeat.calls.some(c=>c.url.includes('/storage/v1/')));
 console.log('PASS: real PDF parsing/pages/hash, MIME spoofing, own chat, inactive account, page limit, UTF-8 text, safe upload retry');
})().catch(e=>{console.error(e);process.exit(1)});

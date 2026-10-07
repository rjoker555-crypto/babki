const vm=require('node:vm'),assert=require('node:assert/strict'),JSZip=require('jszip'),{inflateRawSync}=require('node:zlib'),{webcrypto}=require('node:crypto'),{PDFDocument}=require('pdf-lib'),{plain}=require('./load-edge.cjs');
const id='11111111-1111-4111-8111-111111111111',project='22222222-2222-4222-8222-222222222222';
async function docx(text){const z=new JSZip();z.file('word/document.xml','<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'+text+'</w:body></w:document>');z.file('word/footnotes.xml','<w:footnotes><w:p><w:r><w:t>Сноска: срок приёмки</w:t></w:r></w:p></w:footnotes>');return z.generateAsync({type:'uint8array',compression:'DEFLATE'});}
function context(bytes,{director=true,allowlist=true,active=true,assigned=true,role=null,type='contract',file='contract.docx',path='project/contract.docx',status=200}={}){
 const downloads=[],ctx={Response,AbortSignal,TextDecoder,Uint8Array,DataView,Array,crypto:webcrypto,btoa,inflateRawSync,PDFDocument,Deno:{env:{get:k=>k==='SUPABASE_URL'?'https://test':'server-secret'}},fetch:async(url,opt)=>{downloads.push({url,opt});return new Response(bytes,{status});}};
 vm.createContext(ctx);vm.runInContext(plain('supabase/functions/main-agent/documents.ts'),ctx);
 const actor={owner:'owner',director,documentCache:new Map(),documentAttachments:[],db:async route=>{
  if(route.startsWith('project_documents?'))return [{id,project_id:project,file_name:file,file_path:path,storage_bucket:'project-documents',document_type:type,title:'Договор',version_no:1,updated_at:'2026-10-05',file_size:bytes.length}];
  if(route.startsWith('profiles?'))return [{role:role||(director?'director':'foreman'),is_active:active}];
  if(route.startsWith('agent_director_access?'))return allowlist?[{user_id:'owner'}]:[];
  if(route==='rpc/agent_project_scope')return assigned;
  if(route.startsWith('projects?'))return [{id:project,responsible_user_id:assigned?'owner':'foreign'}];throw Error('Unexpected route');
 }};return {ctx,actor,downloads,read:offset=>ctx.readCompanyDocument({document_id:id,offset},actor)};
}
(async()=>{
 const bytes=await docx('<w:p><w:r><w:t>Договор № 27-2</w:t></w:r></w:p><w:p><w:r><w:t>Подрядчик: Вольтмастер. 4.1 Оплата через 60 дней &amp; после подписания КС.</w:t></w:r></w:p><w:p><w:del><w:r><w:delText>Удалённый срок</w:delText></w:r></w:del><w:r><w:t>Действующий срок</w:t></w:r></w:p>');
 const good=context(bytes),r=await good.read(0);assert.equal(r.status,'text_extracted');assert(r.text.includes('27-2'));assert(r.text.includes('4.1 Оплата через 60 дней & после'));assert(r.text.includes('Сноска'));assert(!r.text.includes('Удалённый срок'));assert.equal(r.complete,true);assert.equal(r.sha256.length,64);assert(r.text.includes('абзац 2'));
 assert.equal(good.downloads[0].opt.headers.Authorization,'Bearer server-secret');assert(!JSON.stringify(r).includes('server-secret'));
 for(const options of [{director:false},{allowlist:false},{active:false},{director:false,type:'project',assigned:false}]){const c=context(bytes,options);await assert.rejects(c.read(0));assert.equal(c.downloads.length,0);}
 const assigned=context(bytes,{director:false,type:'project'});assert((await assigned.read(0)).content_read);
 const manager=context(bytes,{director:false,role:'manager'});assert((await manager.read(0)).content_read);await assert.rejects(context(bytes,{director:false,role:'manager',assigned:false}).read(0));
 await assert.rejects(context(bytes,{path:'../outside.docx'}).read(0));await assert.rejects(context(bytes,{file:'old.doc'}).read(0));await assert.rejects(context(bytes,{status:404}).read(0));await assert.rejects(context(new Uint8Array([1,2,3])).read(0));
 const long=context(await docx('<w:p><w:r><w:t>'+'Условие договора. '.repeat(3000)+'</w:t></w:r></w:p>'));let offset=0,count=0,coverage=0;do{const part=await long.read(offset);assert(JSON.stringify(part).length<22000);assert.equal(part.coverage.from,coverage);coverage=part.coverage.to;offset=part.next_offset;count++;}while(offset!==null);assert(count>1);assert.equal(long.downloads.length,1);
 const pdf=await PDFDocument.create();for(let i=0;i<5;i++)pdf.addPage().drawText('Contract page '+(i+1));const p=context(await pdf.save(),{file:'contract.pdf'});const first=await p.read(0);assert.equal(first.next_offset,4);assert.equal(first.content_read,false);assert.equal((await PDFDocument.load(Buffer.from(p.actor.documentAttachments[0].file_data.split(',')[1],'base64'))).getPageCount(),4);assert.equal((await p.read(4)).pages_provided.from,5);
 console.log('PASS: real compressed DOCX clauses/footnotes/deleted edits, full text windows/cache, actual PDF pages, active/director/assigned access, path traversal and missing/corrupt/unsupported files');
})().catch(e=>{console.error(e);process.exit(1)});

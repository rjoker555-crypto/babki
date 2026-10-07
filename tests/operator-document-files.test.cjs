const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),JSZip=require('jszip'),{PDFDocument}=require('pdf-lib'),{plain,mainSource}=require('./load-edge.cjs');
const crypto=require('node:crypto').webcrypto,id='11111111-1111-4111-8111-111111111111',version='22222222-2222-4222-8222-222222222222';
async function signed({role='director',active=true,type='project',scope=true,path='owner/file.pdf',bucket='project-documents',old=false}={}){
 const calls=[],ctx={Response,Request,AbortSignal,TextEncoder,TextDecoder,Uint8Array,crypto,PDFDocument,Date,Deno:{env:{get:k=>k==='SUPABASE_URL'?'https://fixture.supabase.co':'server-key'}},fetch:async(url,opt)=>{calls.push({url,opt});return new Response(JSON.stringify({signedURL:'/object/sign/'+(old?'agent-files':bucket)+'/owner/file.pdf?token=temporary'}));},db:async(p,opt,admin)=>{
  calls.push({p,admin});if(p.startsWith('project_documents?'))return [{id,project_id:id,document_type:type,file_path:path,storage_bucket:bucket,file_name:'file.pdf',version_no:2}];if(p.startsWith('profiles?'))return [{role,is_active:active}];if(p==='rpc/agent_project_scope')return scope;if(p.startsWith('project_document_versions?'))return [{id:version,document_id:id,storage_bucket:'agent-files',file_path:path,file_name:'old.pdf',version_no:1}];throw Error(p);
 }};vm.createContext(ctx);vm.runInContext(mainSource(),ctx);let result,error;
 try{result=await ctx.getCompanyDocumentFile({document_id:id,version_id:old?version:null},{db:ctx.db,owner:id,director:role==='director'});}catch(e){error=e.message;}return {result,error,calls};
}
(async()=>{
 const current=await signed();assert(!current.error);assert(current.result.url.startsWith('https://fixture.supabase.co/storage/v1/object/sign/'));assert.equal(current.result.content_read,false);assert(current.calls.some(c=>c.p?.startsWith('project_documents')&&c.admin!==true));assert(!JSON.stringify(current.result).includes('server-key'));
 const old=await signed({old:true});assert.equal(old.result.version_no,1);assert(old.result.url.includes('/agent-files/'));
 for(const options of [{role:'foreman',type:'contract'},{role:'foreman',scope:false},{active:false},{path:'owner/../secret.pdf'},{bucket:'public'}]){const r=await signed(options);assert(r.error);assert(!r.calls.some(c=>c.url));}
 const ctx={DataView,TextDecoder};vm.createContext(ctx);vm.runInContext(plain('supabase/functions/_shared/office-file.ts'),ctx);
 const zip=new JSZip();zip.file('word/document.xml','<w:document><w:p><w:r><w:t>Original contract</w:t></w:r></w:p></w:document>');const bytes=await zip.generateAsync({type:'uint8array',compression:'DEFLATE'});ctx.validateOfficeFile(bytes,'docx');assert.throws(()=>ctx.validateOfficeFile(bytes,'xlsx'),/содержимому/);
 zip.file('word/vbaProject.bin','macro');const macro=await zip.generateAsync({type:'uint8array',compression:'DEFLATE'});assert.throws(()=>ctx.validateOfficeFile(macro,'docx'),/Макросы/);
 const huge=new JSZip();huge.file('word/document.xml','x'.repeat(9*1024*1024));const bomb=await huge.generateAsync({type:'uint8array',compression:'DEFLATE'});assert.throws(()=>ctx.validateOfficeFile(bomb,'docx'),/распаковки/);
 assert.throws(()=>ctx.validateOfficeFile(new Uint8Array([1,2,3]),'docx'),/повреждён/);
 console.log('PASS: current/old real file links via user RLS, version bucket, foreman contract/revoked/inactive/traversal denial, no secret exposure; real Office ZIP/macro/type/bomb bounds');
})().catch(e=>{console.error(e);process.exitCode=1});

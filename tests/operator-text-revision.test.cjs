const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const source=fs.readFileSync('supabase/functions/_shared/text-revision.ts','utf8').replace(/^import .*;$/gm,'').replace(/^export /gm,'');
let asset=null,uploaded=null,reads=0;const context={TextEncoder,TextDecoder,AbortSignal,Deno:{env:{get:()=> 'https://example.invalid'}},
 fetch:async()=>{reads++;return new Response('Пункт 1: оплата 50 000 рублей.\nОстальное сохраняется.');},
 boundedBytes:async r=>new Uint8Array(await r.arrayBuffer()),sha256:async b=>crypto.createHash('sha256').update(b).digest('hex'),
 rest:async(path,options={})=>{if(path.includes('&limit=101'))return [];if(options.method==='POST'){asset=JSON.parse(options.body);return [asset];}return asset?[asset]:[];},
 storage:async(path,options={})=>{if(options.method==='POST'&&!path.includes('/sign/')){uploaded=options.body;return {};}return {json:async()=>({signedURL:'/object/sign/agent-files/test?token=temporary'})};}};
vm.createContext(context);vm.runInContext(source,context);
(async()=>{
 const args={document_id:'doc',changes_json:JSON.stringify([{find:'50 000',replace:'13 000',expected_occurrences:1}])},ctx={owner:'owner',message:'message',chat:'chat'},doc={id:'doc',file_name:'contract.txt',mime_type:'text/plain'};
 const result=await context.draftTextRevision(args,ctx,{url:'https://example.invalid/private'},doc);assert(result.verified&&result.draft_only&&!result.current_document_changed);assert(new TextDecoder().decode(uploaded).includes('13 000'));assert(new TextDecoder().decode(uploaded).includes('Остальное сохраняется.'));assert(result.next_step.includes('propose_document'));assert.deepEqual(await context.draftTextRevision(args,ctx,{url:'https://example.invalid/private'},doc).then(x=>x.file_id),result.file_id);
 await assert.rejects(()=>context.draftTextRevision({...args,changes_json:JSON.stringify([{find:'Нет такого пункта',replace:'x',expected_occurrences:1}])},ctx,{url:'https://example.invalid/private'},doc),/Число вхождений/);
 const before=reads;await assert.rejects(()=>context.draftTextRevision(args,ctx,{}, {...doc,file_name:'contract.docx',mime_type:'application/docx'}),/готовую редакцию/);assert.equal(reads,before);
 console.log('PASS: actual UTF-8 TXT draft bytes/hash, exact occurrences, stable draft identity, unchanged other clauses, no document mutation, unsupported formats rejected before reading');
})().catch(e=>{console.error(e);process.exitCode=1});

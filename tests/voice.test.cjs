const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('supabase/functions/transcribe-voice/index.ts','utf8').replace('export async function handle','async function handle').replace('if(import.meta.main)Deno.serve(handle);','');
const id='11111111-1111-4111-8111-111111111111';
async function scenario({auth=true,owns=true,reserve=true,size=200,openai=200}={}){
 const calls=[];const ctx={Response,Request,File,FormData,Uint8Array,AbortSignal,Deno:{env:{get:()=> 'test'}},fetch:async(url,options={})=>{
  calls.push({url,options});const json=(x,status=200)=>new Response(JSON.stringify(x),{status});
  if(url.includes('/auth/'))return json({id:'owner'},auth?200:401);
  if(url.includes('/profiles?'))return json([{is_active:true}]);
  if(url.includes('/agent_conversations?'))return json(owns?[{id}]:[]);
  if(url.includes('/rpc/'))return json(reserve);
  if(url==='https://api.openai.com/v1/audio/transcriptions'){assert.equal(options.body.get('model'),'gpt-4o-mini-transcribe');assert.equal(options.body.get('file').size,size);return json({text:'На объект 1 поступило 10000 рублей, подрядчику оплачено полностью.'},openai);}
  throw Error('Unexpected route');
 }};vm.createContext(ctx);vm.runInContext(source,ctx);const form=new FormData();form.set('file',new File([new Uint8Array(size)],'voice.webm',{type:'audio/webm'}));form.set('chat_id',id);form.set('request_id',id);
 const encoded=new Request('https://test',{method:'POST',body:form}),bytes=await encoded.arrayBuffer();
 const r=await ctx.handle(new Request('https://test',{method:'POST',headers:{Authorization:'Bearer session','Content-Type':encoded.headers.get('Content-Type')},body:bytes}));return {status:r.status,body:await r.json(),calls};
}
(async()=>{
 for(const options of [{auth:false},{owns:false},{reserve:false},{size:3*1024*1024+20000}]){const r=await scenario(options);assert(r.body.error);assert(!r.calls.some(x=>x.url.includes('api.openai.com')));}
 const r=await scenario();assert.equal(r.status,200);assert.equal(r.body.text,'На объект 1 поступило 10000 рублей, подрядчику оплачено полностью.');assert.equal(r.calls.filter(x=>x.url.includes('api.openai.com')).length,1);
 const denied=await scenario({openai:403});assert.equal(denied.status,502);assert(denied.body.error.includes('разрешения'));
 console.log('PASS: voice auth, chat ownership, replay/quota, actual upload byte limit, full transcript, permission error and no automatic paid retry');
})().catch(e=>{console.error(e);process.exitCode=1});

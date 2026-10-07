const vm=require('node:vm'),assert=require('node:assert/strict');
const {mainSource}=require('./load-edge.cjs');

const owner='11111111-1111-4111-8111-111111111111';
const chat='22222222-2222-4222-8222-222222222222';
const message='33333333-3333-4333-8333-333333333333';
const service='service-test-key-long-enough-for-server-authentication';
const internal='telegram-internal-test-secret';
const calls=[];

function response(value,status=200){return new Response(value===null?'':JSON.stringify(value),{status,headers:{'Content-Type':'application/json'}});}
function requireServerHeaders(options,path){
 assert.equal(options.headers.apikey,service,'server key missing for '+path);
 assert.equal(options.headers.Authorization,'Bearer '+service,'server authorization missing for '+path);
}

const ctx={Response,Request,AbortSignal,TextDecoder,TextEncoder,FormData,File,Blob,crypto:require('node:crypto').webcrypto,
 Deno:{env:{get:name=>({SUPABASE_URL:'https://example.supabase.co',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:service,TELEGRAM_INTERNAL_SECRET:internal,OPENAI_API_KEY:'unused'}[name])}},
 fetch:async(url,options={})=>{
  const path=new URL(url).pathname+new URL(url).search;calls.push({path,options});
  if(path.includes('/rest/v1/'))requireServerHeaders(options,path);
  if(path.includes('/rpc/telegram_bridge'))return response({owner_id:owner,role:'director'});
  if(path.includes('/rpc/telegram_verify_update'))return response(true);
  if(path.includes('/profiles?'))return response([{is_active:true,role:'director'}]);
  if(path.includes('/agent_director_access?'))return response([{user_id:owner}]);
  if(path.includes('/agent_chat_messages?')&&path.includes('id=eq.'))return response([{id:message,chat_id:chat,kind:'user',source:'telegram',content:'покажи список объектов',created_at:'2026-10-08T00:00:00Z'}]);
  if(path.includes('/rpc/agent_reserve_request'))return response('reserved');
  if(path.includes('/projects?'))return response([{id:'44444444-4444-4444-8444-444444444444',name:'Тестовый объект',customer:'Заказчик',status:'active',contract_number:'1'}]);
  if(path.endsWith('/rest/v1/agent_chat_messages'))return response([{id:'55555555-5555-4555-8555-555555555555',chat_id:chat,kind:'assistant',source:'telegram',content:'Объекты — 1 запись:\n1. Тестовый объект'}]);
  if(path.includes('/agent_request_runs?'))return response([]);
  throw Error('Unexpected route '+path);
 }};

vm.createContext(ctx);vm.runInContext(mainSource(),ctx);
(async()=>{
 const result=await ctx.handle(new Request('https://example.supabase.co/functions/v1/main-agent',{method:'POST',headers:{Authorization:'Bearer '+service,'X-Voltmaster-Internal':internal},body:JSON.stringify({message_id:message,telegram:{owner_id:owner,telegram_user_id:123456,chat_id:chat,mode:'consultation',update_id:789}})}));
 const body=await result.json();assert.equal(result.status,200,JSON.stringify(body));assert.equal(body.message.source,'telegram');assert.match(body.message.content,/Тестовый объект/);
 assert(calls.some(x=>x.path.includes('/profiles?')));console.log('PASS: Telegram main-agent uses authenticated server database access and returns the shared-chat answer');
 const worker= require('node:fs').readFileSync('supabase/functions/telegram-worker/index.ts','utf8');
 assert(worker.includes("message_id:messageId,chat_id:link.chat_id,telegram:"));
 assert(worker.includes("if(fixed.mode==='instruction'){const keyboard=await approvals(fixed,link,msg.id);"));
 assert(worker.includes("if(!item.body||typeof item.body!=='object'||Array.isArray(item.body)"));
 console.log('PASS: consultation skips approval lookup and approval status carries the shared chat id');
})().catch(error=>{console.error(error);process.exitCode=1;});

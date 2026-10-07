import {parseTelegramUpdate} from '../_shared/telegram-core.mjs';
const answer=(status,body)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
const hex=b=>Array.from(new Uint8Array(b),x=>x.toString(16).padStart(2,'0')).join('');
async function rpc(action,payload){const base=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');const r=await fetch(base+'/rest/v1/rpc/telegram_bridge',{method:'POST',headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({p_action:action,p_payload:payload}),signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('Queue unavailable');return r.json();}
export async function handle(req){
 if(req.method!=='POST')return answer(405,{error:'POST required'});
 const secret=Deno.env.get('TELEGRAM_WEBHOOK_SECRET'),actual=req.headers.get('X-Telegram-Bot-Api-Secret-Token')||'';
 if(!secret)return answer(503,{error:'Telegram integration is not configured'});
 const x=new TextEncoder().encode(actual),y=new TextEncoder().encode(secret);let difference=x.length^y.length;for(let i=0;i<Math.max(x.length,y.length);i++)difference|=(x[i]||0)^(y[i]||0);
 if(difference)return answer(401,{error:'Unauthorized'});
 try{
  const reader=req.body?.getReader();if(!reader)return answer(400,{error:'Empty update'});let size=0;const chunks=[];
  while(true){const part=await reader.read();if(part.done)break;size+=part.value.length;if(size>65536){await reader.cancel();return answer(413,{error:'Update too large'});}chunks.push(part.value);}
  const bytes=new Uint8Array(size);let at=0;for(const chunk of chunks){bytes.set(chunk,at);at+=chunk.length;}const content=new TextDecoder().decode(bytes);
  const update=JSON.parse(content),item=parseTelegramUpdate(update);if(!item)return answer(200,{ignored:true});
  let payload=update;
  if(/^\/start\s+[A-Fa-f0-9]{48}$/.test(item.text)){
   const code=item.text.split(/\s+/)[1],digest=hex(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(code)));
   const linked=await rpc('consume',{hash:digest,telegram_user_id:item.telegram_user_id});
   // The one-use code never reaches the update queue, logs, or agent history.
   if(!linked.linked)return answer(200,{accepted:false});
   payload={update_id:item.update_id,message:{chat:{id:item.telegram_user_id,type:'private'},from:{id:item.telegram_user_id},text:'/linked'}};
  }
  const queued=await rpc('enqueue',{update_id:item.update_id,telegram_user_id:item.telegram_user_id,update:payload,event:item.event});
  if(queued.accepted&&!queued.duplicate){const key=Deno.env.get('TELEGRAM_INTERNAL_SECRET'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');if(key){const call=fetch(Deno.env.get('SUPABASE_URL')+'/functions/v1/telegram-worker',{method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'X-Voltmaster-Internal':key,'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(20000)}).catch(()=>{});globalThis.EdgeRuntime?.waitUntil?.(call);}}
  return answer(200,{accepted:Boolean(queued.accepted)});
 }catch{return answer(503,{error:'Telegram queue unavailable'});}
}
if(import.meta.main)Deno.serve(handle);

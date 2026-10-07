const respond=(status,value)=>new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'}});
export async function handle(req){
 if(req.method==='OPTIONS')return respond(200,{});
 if(req.method!=='POST')return respond(405,{error:'POST required'});
 const base=Deno.env.get('SUPABASE_URL'),publicKey=Deno.env.get('SUPABASE_ANON_KEY'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),authorization=req.headers.get('authorization')||'';
 if(!authorization.startsWith('Bearer '))return respond(401,{error:'Войдите в приложение.'});
 try{
  const auth=await fetch(base+'/auth/v1/user',{headers:{apikey:publicKey,Authorization:authorization},signal:AbortSignal.timeout(10000)});if(!auth.ok)return respond(401,{error:'Сессия истекла.'});const user=await auth.json();
  async function get(path){const r=await fetch(base+'/rest/v1/'+path,{headers:{apikey:service,Authorization:'Bearer '+service},signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('Authorization unavailable');return r.json();}
  const [profile,access]=await Promise.all([get('profiles?select=role,is_active&id=eq.'+user.id),get('agent_director_access?select=user_id&user_id=eq.'+user.id)]);
  if(profile[0]?.role!=='director'||!profile[0]?.is_active||access.length!==1)return respond(403,{error:'Доступно только директору с допуском.'});
  const raw=await req.text();if(raw.length>1000)return respond(413,{error:'Request too large'});const {operation}=JSON.parse(raw);
  if(!['register','info','disable','configure_worker'].includes(operation))return respond(400,{error:'Unknown operation'});
  if(operation==='configure_worker'){
   const internal=Deno.env.get('TELEGRAM_INTERNAL_SECRET');
   if(!service||!internal)return respond(503,{error:'Сначала задайте TELEGRAM_INTERNAL_SECRET в Edge Function Secrets.'});
   const configured=await fetch(base+'/rest/v1/rpc/configure_telegram_worker_cron',{method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify({p_service_role_key:service,p_internal_secret:internal}),signal:AbortSignal.timeout(15000)});
   if(!configured.ok)return respond(503,{error:'Не удалось настроить минутную очередь.'});
   const result=await configured.json();
   return respond(200,{ok:true,job_id:result?.job_id||null,schedule:result?.schedule||'* * * * *'});
  }
  const token=Deno.env.get('TELEGRAM_BOT_TOKEN'),secret=Deno.env.get('TELEGRAM_WEBHOOK_SECRET');if(!token||!secret)return respond(503,{error:'Сначала задайте TELEGRAM_BOT_TOKEN и TELEGRAM_WEBHOOK_SECRET в Edge Function Secrets.'});
  const method=operation==='register'?'setWebhook':operation==='disable'?'deleteWebhook':'getWebhookInfo';
  const body=operation==='register'?{url:base+'/functions/v1/telegram-webhook',secret_token:secret,allowed_updates:['message','callback_query'],max_connections:1}:operation==='disable'?{drop_pending_updates:false}:{};
  const r=await fetch('https://api.telegram.org/bot'+token+'/'+method,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(10000)});const data=await r.json();
  if(!r.ok||!data.ok)return respond(502,{error:'Telegram не принял настройку webhook. Проверьте токен и права бота в BotFather.'});
  if(operation==='info')return respond(200,{url:data.result?.url||null,pending_update_count:data.result?.pending_update_count||0,last_error_date:data.result?.last_error_date||null,allowed_updates:data.result?.allowed_updates||[]});
  return respond(200,{ok:true,webhook:operation==='register'?body.url:null});
 }catch{return respond(503,{error:'Настройка Telegram сейчас недоступна.'});}
}
if(import.meta.main)Deno.serve(handle);

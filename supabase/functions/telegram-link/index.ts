const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
const result=(status,body)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
const hex=bytes=>Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
export async function handle(req){
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return result(405,{error:'POST required'});
 const base=Deno.env.get('SUPABASE_URL'),publicKey=Deno.env.get('SUPABASE_ANON_KEY'),authorization=req.headers.get('authorization')||'';
 if(!authorization.startsWith('Bearer '))return result(401,{error:'Войдите в приложение.'});
 try{
  const who=await fetch(base+'/auth/v1/user',{headers:{apikey:publicKey,Authorization:authorization},signal:AbortSignal.timeout(10000)});
  if(!who.ok)return result(401,{error:'Сессия истекла.'});
  const user=await who.json();
  async function rpc(name,body={}){const r=await fetch(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:publicKey,Authorization:authorization,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('Telegram access denied');return r.json();}
  const raw=await req.text();if(raw.length>1000)return result(413,{error:'Request too large'});
  const body=JSON.parse(raw);if(!body||!['status','connect','disconnect'].includes(body.operation))return result(400,{error:'Unknown operation'});
  if(body.operation==='status')return result(200,{status:await rpc('telegram_link_status')});
  if(body.operation==='disconnect')return result(200,{disconnected:await rpc('telegram_disconnect')});
  const bytes=crypto.getRandomValues(new Uint8Array(24));const code=Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
  const hash=hex(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(code))));
  const status=await rpc('telegram_begin_link',{p_hash:hash});
  const username=Deno.env.get('TELEGRAM_BOT_USERNAME')||'';
  if(!/^[A-Za-z][A-Za-z0-9_]{4,31}$/.test(username))return result(503,{error:'Адрес бота ещё не настроен. Код выпущен на 10 минут, но ссылку открыть нельзя.'});
  return result(200,{url:'https://t.me/'+username+'?start='+code,expires_at:status.expires_at,linked:status.linked});
 }catch{return result(403,{error:'Telegram доступен только активному директору с допуском и активному прорабу.'});}
}
if(import.meta.main)Deno.serve(handle);

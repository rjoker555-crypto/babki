const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
function reply(status,body){return new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});}
export async function handle(req){
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return reply(405,{error:'Используйте POST.'});
 const base=Deno.env.get('SUPABASE_URL'),anon=Deno.env.get('SUPABASE_ANON_KEY'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),key=Deno.env.get('OPENAI_API_KEY');
 const authorization=req.headers.get('authorization')||'';
 if(!authorization.startsWith('Bearer '))return reply(401,{error:'Войдите в приложение.'});
 try{
  const auth=await fetch(base+'/auth/v1/user',{headers:{apikey:anon,Authorization:authorization},signal:AbortSignal.timeout(10000)});
  if(!auth.ok)return reply(401,{error:'Сессия истекла.'});const user=await auth.json();
  async function db(path,body,admin=false){const r=await fetch(base+'/rest/v1/'+path,{method:body?'POST':'GET',headers:{apikey:admin?service:anon,Authorization:admin?'Bearer '+service:authorization,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(10000)});if(!r.ok)throw new Error('database');return r.json();}
  const profiles=await db('profiles?select=is_active&id=eq.'+user.id);if(!profiles[0]?.is_active)return reply(403,{error:'Доступ отключён.'});
  // Bound actual request bytes, independent of an untrusted Content-Length header.
  const reader=req.body?.getReader();if(!reader)return reply(400,{error:'Нет записи.'});const chunks=[];let length=0;
  while(true){const part=await reader.read();if(part.done)break;length+=part.value.length;if(length>3*1024*1024+16384){await reader.cancel();return reply(413,{error:'Запись больше 3 МБ. Запишите более короткое сообщение.'});}chunks.push(part.value);}
  const bytes=new Uint8Array(length);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  const form=await new Request(req.url,{method:'POST',headers:{'Content-Type':req.headers.get('Content-Type')||''},body:bytes}).formData();
  const file=form.get('file'),chat=form.get('chat_id'),id=form.get('request_id');
  if(!(file instanceof File)||file.size<100||file.size>3*1024*1024||!/^audio\/(webm|mp4|mpeg|wav|x-wav|m4a|x-m4a)(;.*)?$/i.test(file.type))return reply(400,{error:'Нужна аудиозапись WebM, MP4, MP3 или WAV до 3 МБ.'});
  if(!/^[0-9a-f-]{36}$/i.test(String(chat))||!/^[0-9a-f-]{36}$/i.test(String(id)))return reply(400,{error:'Не указан чат.'});
  const conversations=await db('agent_conversations?select=id&id=eq.'+chat+'&owner_id=eq.'+user.id);if(!conversations[0])return reply(404,{error:'Чат недоступен или срок хранения истёк.'});
  if(!key)return reply(503,{error:'Ключ OpenAI не настроен.'});
  const reserved=await db('rpc/agent_reserve_voice',{p_id:id,p_owner:user.id},true);if(!reserved)return reply(429,{error:'Повтор записи или лимит голоса: 20 в сутки на пользователя, 300 в месяц на приложение. Между запросами нужно 10 секунд.'});
  if(await db('rpc/agent_reserve_api_call',{p_owner:user.id,p_scope:'voice',p_request:id,p_step:0},true)!==true)return reply(429,{error:'Общий лимит платных вызовов исчерпан. Запрос в OpenAI не отправлен.'});
  const upload=new FormData();upload.set('file',file,file.name);upload.set('model','gpt-4o-mini-transcribe');upload.set('language','ru');upload.set('response_format','json');upload.set('prompt','Строительная компания: объекты, ООО, ИП, субподрядчик, дебиторка, кредиторка, ПТО, КС-2, КС-3, ФЕР. Точно передавай произнесённые суммы и числа.');
  const answer=await fetch('https://api.openai.com/v1/audio/transcriptions',{method:'POST',headers:{Authorization:'Bearer '+key},body:upload,signal:AbortSignal.timeout(60000)});
  if(!answer.ok)return reply(502,{error:answer.status===403?'У ключа нет разрешения на распознавание голоса (Audio → Request).':'OpenAI не смог расшифровать запись. Проверьте баланс, ключ и разрешения; автоматический повтор отключён.'});
  const result=await answer.json();const text=result.text?.trim();if(!text)return reply(422,{error:'Речь не распознана. Попробуйте записать ещё раз.'});
  await db('rpc/agent_record_api_usage',{p_owner:user.id,p_scope:'voice',p_request:id,p_step:0,p_input:result.usage?.input_tokens??null,p_output:result.usage?.output_tokens??null},true);
  if(text.length>8000)return reply(413,{error:'Расшифровка длиннее 8000 символов. Разделите поручение на несколько записей; текст не обрезан и поручение не выполнено.'});
  return reply(200,{text});
 }catch{return reply(502,{error:'Не удалось расшифровать голосовое сообщение. Автоматический повтор отключён.'});}
}
if(import.meta.main)Deno.serve(handle);

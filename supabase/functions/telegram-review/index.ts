const reply=(status,value)=>new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'}});
const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
const hex=bytes=>Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
export async function handle(req){
 if(req.method==='OPTIONS')return reply(200,{});if(req.method!=='POST')return reply(405,{error:'POST required'});
 const base=Deno.env.get('SUPABASE_URL'),anon=Deno.env.get('SUPABASE_ANON_KEY'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),authorization=req.headers.get('authorization')||'';
 if(!authorization.startsWith('Bearer '))return reply(401,{error:'Войдите в приложение.'});
 try{
  const auth=await fetch(base+'/auth/v1/user',{headers:{apikey:anon,Authorization:authorization},signal:AbortSignal.timeout(10000)});if(!auth.ok)return reply(401,{error:'Сессия истекла.'});const actor=await auth.json();
  async function rest(path,body,asService=false){const key=asService?service:anon;const r=await fetch(base+'/rest/v1/'+path,{method:'POST',headers:{apikey:key,Authorization:asService?'Bearer '+service:authorization,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});if(!r.ok)throw Error('Документ изменился или доступ отозван.');return r.json();}
  const [profiles,access]=await Promise.all([fetch(base+'/rest/v1/profiles?select=role,is_active&id=eq.'+actor.id,{headers:{apikey:service,Authorization:'Bearer '+service}}).then(r=>r.json()),fetch(base+'/rest/v1/agent_director_access?select=user_id&user_id=eq.'+actor.id,{headers:{apikey:service,Authorization:'Bearer '+service}}).then(r=>r.json())]);
  if(profiles[0]?.role!=='director'||!profiles[0]?.is_active||access.length!==1)return reply(403,{error:'Принимает только директор с допуском.'});
  const raw=await req.text();if(raw.length>1000)return reply(413,{error:'Request too large'});const body=JSON.parse(raw);
  if(body.operation==='list')return reply(200,{submissions:await rest('rpc/telegram_review_submissions',{})});
  if(!uuid(body.file_id)||!['accept','reject'].includes(body.operation))return reply(400,{error:'Укажите точный файл и действие.'});
  const type=body.document_type;if(body.operation==='accept'&&!['contract','project','estimate','addendum','other'].includes(type))return reply(400,{error:'Выберите назначение документа.'});
  const source=await rest('rpc/telegram_review_claim',{p_director:actor.id,p_file:body.file_id},true);
  if(body.operation==='reject'){
   const result=await rest('rpc/telegram_review_finish',{p_director:actor.id,p_file:body.file_id,p_document:null,p_error:null},true);
   return reply(200,{result,file_name:source.file_name,storage_cleanup:'retained_until_scheduled_cleanup'});
  }
  const file=await fetch(base+'/storage/v1/object/telegram-inbox/'+source.storage_path,{headers:{apikey:service,Authorization:'Bearer '+service},signal:AbortSignal.timeout(20000)});if(!file.ok)return reply(409,{error:'Исходный файл подачи недоступен.'});
  const bytes=new Uint8Array(await file.arrayBuffer());if(bytes.length!==source.file_size||hex(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)))!==source.sha256)return reply(409,{error:'Файл подачи изменился; приём остановлен.'});
  const path=source.project_id+'/'+source.file_id+'/'+String(source.file_name).replace(/[\\/\x00-\x1f]/g,'_');
  const uploaded=await fetch(base+'/storage/v1/object/project-documents/'+path,{method:'POST',headers:{apikey:anon,Authorization:authorization,'Content-Type':source.mime_type,'x-upsert':'false'},body:bytes,signal:AbortSignal.timeout(20000)});
  if(!uploaded.ok&&uploaded.status!==409)return reply(409,{error:'Не удалось подготовить файл в документах объекта.'});
  if(uploaded.status===409){
   const existing=await fetch(base+'/storage/v1/object/project-documents/'+path,{headers:{apikey:service,Authorization:'Bearer '+service},signal:AbortSignal.timeout(20000)});
   if(!existing.ok)return reply(409,{error:'Повторно загруженный файл недоступен для сверки.'});
   const previous=new Uint8Array(await existing.arrayBuffer());
   if(previous.length!==bytes.length||hex(new Uint8Array(await crypto.subtle.digest('SHA-256',previous)))!==source.sha256)return reply(409,{error:'Файл по этому пути отличается; приём остановлен.'});
  }
  const prepared={storage_bucket:'project-documents',file_path:path,file_name:source.file_name,mime_type:source.mime_type,file_size:bytes.length};
  const command={action:'attach',project_id:source.project_id,document_type:type,uploaded_file:prepared,values:{title:source.file_name,comment:'Входящая подача Telegram '+source.file_id+'; пояснение: '+String(source.explanation||'').slice(0,1000)}};
  const done=await rest('rpc/execute_document_command',{p_request:body.file_id,p_command:command});
  if(!done.verified||!uuid(done.document?.id))return reply(409,{error:'Документ не подтверждён сервером.'});
  const result=await rest('rpc/telegram_review_finish',{p_director:actor.id,p_file:body.file_id,p_document:done.document.id,p_error:null},true);
  return reply(200,{result,document_id:done.document.id,file_name:source.file_name,project_name:source.project_name});
 }catch{return reply(409,{error:'Подача изменилась или сервер не подтвердил приём. Обновите список и проверьте документ.'});}
}
if(import.meta.main)Deno.serve(handle);

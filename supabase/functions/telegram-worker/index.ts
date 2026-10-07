import {parseTelegramUpdate,telegramMenu,identifyFile,voiceAllowed,safeName,safeTelegramText} from '../_shared/telegram-core.mjs';
import {validateOfficeFile} from '../_shared/office-file.ts';
const json=(status,body)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
const base=()=>Deno.env.get('SUPABASE_URL'),service=()=>Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
async function request(path,options={}){const key=service(),r=await fetch(base()+'/rest/v1/'+path,{...options,headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json',Prefer:'return=representation',...options.headers},signal:AbortSignal.timeout(15000)});if(!r.ok)throw Error('Database request failed');return r.status===204?null:r.json();}
const bridge=(action,payload={})=>request('rpc/telegram_bridge',{method:'POST',body:JSON.stringify({p_action:action,p_payload:payload})});
async function createCallback(link,action,{plan_id=null,version=null,project_id=null}={}){return request('rpc/telegram_create_callback',{method:'POST',body:JSON.stringify({p_owner:link.owner_id,p_telegram:link.telegram_user_id,p_generation:link.generation,p_action:action,p_plan:plan_id,p_revision:version,p_project:project_id})});}
async function saveChat(update,link,content,kind='text'){
 return request('rpc/telegram_save_incoming',{method:'POST',body:JSON.stringify({p_update:update.update_id,p_owner:link.owner_id,p_chat:update.chat_id,p_mode:update.mode,p_kind:kind,p_content:content.slice(0,8000)})});
}
const plain=(link,text,extra={})=>({method:'sendMessage',chat_id:link.telegram_user_id,text:safeTelegramText(text),reply_markup:extra.inline_keyboard?extra:telegramMenu(link.role)});
async function projectsKeyboard(update,link){
 const rows=await bridge('projects',{owner_id:link.owner_id});if(!rows.length)return plain(link,'Доступных объектов нет. Проверьте назначение в приложении.');
 const keyboard=[];for(const project of rows){const id=await createCallback(link,'project',{project_id:project.id});keyboard.push([{text:project.name.slice(0,45),callback_data:'c:'+id}]);}
 return plain(link,'Выберите объект для подачи. Доступные объекты: '+rows.length+'.',{inline_keyboard:keyboard});
}
async function documentTypeKeyboard(link){
 const types=[['project','Проект'],['contract','Договор'],['estimate','Смета'],['addendum','Доп. соглашение'],['other','Другое']],keyboard=[];
 for(const [type,title] of types){const id=await createCallback(link,'doc_type',{version:type});keyboard.push([{text:title,callback_data:'c:'+id}]);}
 return plain(link,'Выберите назначение документа. Затем отправьте до пяти файлов и общее пояснение.',{inline_keyboard:keyboard});
}
async function telegramApi(method,payload){const token=Deno.env.get('TELEGRAM_BOT_TOKEN');if(!token)throw Error('Telegram token unavailable');const {method:ignored,...parameters}=payload;const r=await fetch('https://api.telegram.org/bot'+token+'/'+method,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(parameters),signal:AbortSignal.timeout(15000)});let data;try{data=await r.json();}catch{}return {status:r.status,data};}
async function telegramFile(fileId,max){
 const answer=await telegramApi('getFile',{file_id:fileId});if(!answer.data?.ok||!answer.data.result?.file_path||answer.data.result.file_size>max)throw Error('Файл слишком большой или недоступен через Telegram. Загрузите его через приложение.');
 const path=answer.data.result.file_path;if(!/^[A-Za-z0-9_./-]+$/.test(path)||path.split('/').includes('..'))throw Error('Недопустимый путь файла Telegram.');
 const response=await fetch('https://api.telegram.org/file/bot'+Deno.env.get('TELEGRAM_BOT_TOKEN')+'/'+path,{signal:AbortSignal.timeout(20000)});if(!response.ok)throw Error('Не удалось получить файл Telegram.');
 const reader=response.body?.getReader();if(!reader)throw Error('Пустой файл Telegram.');let length=0;const parts=[];while(true){const p=await reader.read();if(p.done)break;length+=p.value.length;if(length>max){await reader.cancel();throw Error('Файл превышает лимит приложения.');}parts.push(p.value);}
 const bytes=new Uint8Array(length);let at=0;for(const part of parts){bytes.set(part,at);at+=part.length;}return bytes;
}
async function transcribe(update,link,item){
 if(update.transcript)return update.transcript;
 const voice=item.message.voice;if(!voiceAllowed(voice))throw Error('Голосовое сообщение: не более 3 минут и 3 МБ.');
 const bytes=await telegramFile(voice.file_id,3*1024*1024);
 if(String.fromCharCode(...bytes.slice(0,4))!=='OggS')throw Error('Telegram Voice должен быть OGG/Opus; фактический формат другой.');
 const identity=new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(link.owner_id+':voice:'+update.update_id)));
 const raw=Array.from(identity.slice(0,16),b=>b.toString(16).padStart(2,'0')).join('');const requestId=raw.slice(0,8)+'-'+raw.slice(8,12)+'-4'+raw.slice(13,16)+'-8'+raw.slice(17,20)+'-'+raw.slice(20,32);
 const reserved=await request('rpc/agent_reserve_voice',{method:'POST',body:JSON.stringify({p_id:requestId,p_owner:link.owner_id})});
 if(reserved!==true){const previous=await request('agent_voice_runs?select=id,owner_id&id=eq.'+requestId);throw Error(previous.length?'Предыдущая обработка голоса прервалась; повторный платный вызов не выполнен. Отправьте запись заново.':'Лимит голоса исчерпан.');}
 const budget=await request('rpc/agent_reserve_api_call',{method:'POST',body:JSON.stringify({p_owner:link.owner_id,p_scope:'voice',p_request:requestId,p_step:0})});if(budget!==true)throw Error('Общий лимит платных вызовов исчерпан.');
 const form=new FormData();form.set('file',new File([bytes],'telegram-voice.ogg',{type:'audio/ogg'}));form.set('model','gpt-4o-mini-transcribe');form.set('language','ru');form.set('response_format','json');
 const response=await fetch('https://api.openai.com/v1/audio/transcriptions',{method:'POST',headers:{Authorization:'Bearer '+Deno.env.get('OPENAI_API_KEY')},body:form,signal:AbortSignal.timeout(60000)});
 if(!response.ok)throw Error('Речь не распознана. Попробуйте текст или запись в приложении.');
 const result=await response.json(),text=String(result.text||'').trim();if(!text||text.length>7800)throw Error('Расшифровка пуста или слишком длинна.');
 await request('rpc/agent_record_api_usage',{method:'POST',body:JSON.stringify({p_owner:link.owner_id,p_scope:'voice',p_request:requestId,p_step:0,p_input:result.usage?.input_tokens??null,p_output:result.usage?.output_tokens??null})});
 await request('rpc/telegram_store_transcript',{method:'POST',body:JSON.stringify({p_update:update.update_id,p_owner:link.owner_id,p_text:text})});
 return text;
}
async function stageFile(update,link,item){
 if(update.mode!=='document')return plain(link,'Файл не прикреплён. Откройте «📎 Подать документ», выберите объект и отправьте файл.');
 if(!link.project_id)return projectsKeyboard(update,link);
 const documentType=await request('rpc/telegram_link_document_type',{method:'POST',body:JSON.stringify({p_owner:link.owner_id,p_telegram:link.telegram_user_id})});
 if(!documentType)return documentTypeKeyboard(link);
 const msg=item.message,photo=Boolean(msg.photo),file=photo?msg.photo.at(-1):msg.document;
 if(!file?.file_id||file.file_size>8*1024*1024)return plain(link,'Файл больше 8 МБ. Загрузите его через приложение.');
 const name=safeName(photo?'telegram-photo-'+update.update_id+'.jpg':file.file_name);
 const ext=name.toLowerCase().split('.').pop();const bytes=await telegramFile(file.file_id,8*1024*1024);
 const mime=identifyFile(bytes,name,photo);
 if(['docx','xlsx'].includes(ext))validateOfficeFile(bytes,ext);
 if(mime==='application/pdf'&&bytes.length>8*1024*1024)throw Error('PDF слишком большой.');
 const draft=await bridge('draft',{owner_id:link.owner_id,chat_id:update.chat_id,project_id:link.project_id});
 await request('rpc/telegram_select_document_type',{method:'POST',body:JSON.stringify({p_owner:link.owner_id,p_telegram:link.telegram_user_id,p_chat:update.chat_id,p_generation:link.generation,p_type:documentType})});
 const digest=new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),hash=Array.from(digest,b=>b.toString(16).padStart(2,'0')).join('');
 const stable=new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(link.owner_id+':'+update.update_id)));const id=Array.from(stable.slice(0,16),b=>b.toString(16).padStart(2,'0')).join('');
 const path=link.owner_id+'/'+id+'.'+ext,upload=await fetch(base()+'/storage/v1/object/telegram-inbox/'+path,{method:'POST',headers:{apikey:service(),Authorization:'Bearer '+service(),'Content-Type':mime,'x-upsert':'false'},body:bytes,signal:AbortSignal.timeout(20000)});
 if(!upload.ok&&upload.status!==409)throw Error('Закрытое хранилище не приняло файл.');
 if(upload.status===409){const old=await fetch(base()+'/storage/v1/object/telegram-inbox/'+path,{headers:{apikey:service(),Authorization:'Bearer '+service()},signal:AbortSignal.timeout(20000)});if(!old.ok||Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await old.arrayBuffer())),b=>b.toString(16).padStart(2,'0')).join('')!==hash)throw Error('Файл этого сообщения уже существует с другим содержимым.');}
 const saved=await bridge('append_file',{submission_id:draft.id,owner_id:link.owner_id,telegram_file_id:file.file_id,file_name:name,mime_type:mime,file_size:bytes.length,storage_path:path,sha256:hash});
 let personalId=null;
 if(link.role==='director'){
  const raw=id,assetId=raw.slice(0,8)+'-'+raw.slice(8,12)+'-4'+raw.slice(13,16)+'-8'+raw.slice(17,20)+'-'+raw.slice(20,32),personalPath=link.owner_id+'/'+assetId+'.'+ext;
  const rows=await request('agent_file_assets?select=id,sha256,chat_id,file_size&owner_id=eq.'+link.owner_id+'&id=eq.'+assetId);
  if(rows.length){if(rows[0].sha256!==hash||rows[0].chat_id!==update.chat_id||Number(rows[0].file_size)!==bytes.length)throw Error('Личный файл с таким ID изменился.');}
  else{
   const existing=await request('agent_file_assets?select=file_size&owner_id=eq.'+link.owner_id+'&order=created_at.desc&limit=101');
   if(existing.length>=100||existing.reduce((sum,x)=>sum+Number(x.file_size),0)+bytes.length>100*1024*1024)throw Error('Лимит личных файлов: 100 штук или 100 МБ.');
   const up=await fetch(base()+'/storage/v1/object/agent-files/'+personalPath,{method:'POST',headers:{apikey:service(),Authorization:'Bearer '+service(),'Content-Type':mime,'x-upsert':'false'},body:bytes,signal:AbortSignal.timeout(20000)});
   if(!up.ok&&up.status!==409)throw Error('Не удалось подготовить личный файл директора.');
   if(up.status===409){const old=await fetch(base()+'/storage/v1/object/agent-files/'+personalPath,{headers:{apikey:service(),Authorization:'Bearer '+service()},signal:AbortSignal.timeout(20000)});if(!old.ok||Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await old.arrayBuffer())),b=>b.toString(16).padStart(2,'0')).join('')!==hash)throw Error('Личный файл с таким ID отличается от загрузки.');}
   await request('agent_file_assets',{method:'POST',body:JSON.stringify({id:assetId,owner_id:link.owner_id,chat_id:update.chat_id,file_name:name,storage_path:personalPath,mime_type:mime,file_size:bytes.length,sha256:hash})});
  }
  personalId=assetId;await request('rpc/telegram_set_asset',{method:'POST',body:JSON.stringify({p_submission:draft.id,p_telegram_file:file.file_id,p_asset:assetId})});
 }
 await saveChat(update,link,'[Telegram: файл] '+name+' · размер '+bytes.length+' байт · объект '+draft.project_name+(personalId?' · file_id: '+personalId:''),'document');
 return plain(link,'Принят в закрытый черновик: '+name+' ('+bytes.length+' байт). Файлов в подборе: '+saved.files+'. Добавьте пояснение или нажмите «Завершить подбор».',{inline_keyboard:[[{text:'Завершить подбор',callback_data:'c:'+await createCallback(link,'finish')}]]});
}
async function callAgent(update,link,messageId,operation=null,approval=null){
 const key=Deno.env.get('TELEGRAM_INTERNAL_SECRET'),s=service();if(!key)throw Error('Внутренний канал агента не настроен.');
 const payload={message_id:messageId,chat_id:link.chat_id,telegram:{owner_id:link.owner_id,telegram_user_id:link.telegram_user_id,chat_id:update.chat_id,mode:update.mode,update_id:update.update_id},...(operation?{operation}:{}),...(approval?{approval}:{})};
 const r=await fetch(base()+'/functions/v1/main-agent',{method:'POST',headers:{apikey:s,Authorization:'Bearer '+s,'X-Voltmaster-Internal':key,'Content-Type':'application/json'},body:JSON.stringify(payload),signal:AbortSignal.timeout(125000)});
 const data=await r.json();if(!r.ok)throw Error(data.error||'Агент не ответил. Сообщение сохранено в приложении.');return data;
}
async function approvalPlans(update,link,messageId){
 if(link.chat_id!==update.chat_id||link.generation!==update.generation)return null;
 const response=await callAgent(update,link,messageId,'list_approvals');const plans=response.approvals||[];if(!plans.length)return null;
 return plans;
}
async function approvalKeyboard(link,plans){
 const keyboard=[];for(const plan of plans.slice(0,8)){
  const yes=await createCallback(link,'confirm',{plan_id:plan.id,version:plan.version}),no=await createCallback(link,'cancel',{plan_id:plan.id,version:plan.version});
  keyboard.push([{text:'✅ Подтвердить',callback_data:'c:'+yes},{text:'✏️ Уточнить',callback_data:'mode:instruction'},{text:'❌ Отменить',callback_data:'c:'+no}]);
 }
 return {inline_keyboard:keyboard};
}
async function approvals(update,link,messageId){const plans=await approvalPlans(update,link,messageId);return plans?approvalKeyboard(link,plans):null;}
async function executionStatus(update,link,messageId){
 const pending=await approvalPlans(update,link,messageId);
 if(pending?.length){
  const text='Ожидают подтверждения:\n\n'+pending.slice(0,8).map((plan,index)=>(index+1)+'. '+plan.description+'\nДействует до '+new Date(plan.expires_at).toLocaleString('ru-RU',{timeZone:'Asia/Krasnoyarsk'})).join('\n\n');
  return plain(link,text,await approvalKeyboard(link,pending));
 }
 const tables=['agent_operator_plans','agent_action_plans','agent_file_action_plans'];
 const rows=[];
 for(const table of tables){
  const found=await request(table+'?select=id,status,created_at&owner_id=eq.'+link.owner_id+'&chat_id=eq.'+link.chat_id+'&order=created_at.desc&limit=5');
  for(const row of found)rows.push(row);
 }
 rows.sort((a,b)=>String(b.created_at).localeCompare(String(a.created_at)));
 return plain(link,rows.length?'Последние планы текущего чата:\n'+rows.slice(0,8).map(x=>x.id+' · '+x.status).join('\n'):'В текущем чате планов нет. Документы и фоновые задания проверьте в приложении.');
}
async function processCallback(update,link,item){
 const data=item.callback_data;if(data==='mode:instruction'&&link.role==='director')return plain(link,'Напишите уточнение в режиме «📝 Подать указание».');
 if(!/^c:[0-9a-f-]{36}$/.test(data||''))return plain(link,'Кнопка устарела. Откройте актуальный статус.');
 const cb=await bridge('callback_consume',{id:data.slice(2),telegram_user_id:link.telegram_user_id});if(!cb||cb.owner_id!==link.owner_id||cb.chat_id!==update.chat_id)return plain(link,'Кнопка устарела или принадлежит другому чату.');
 if(cb.action==='project'){
  const chosen=await bridge('choose_project',{owner_id:link.owner_id,telegram_user_id:link.telegram_user_id,project_id:cb.project_id,generation:link.generation});
  return chosen?documentTypeKeyboard(link):plain(link,'Назначение объекта изменилось. Выберите объект заново.');
 }
 if(cb.action==='doc_type'){
  const chosen=await request('rpc/telegram_select_document_type',{method:'POST',body:JSON.stringify({p_owner:link.owner_id,p_telegram:link.telegram_user_id,p_chat:update.chat_id,p_generation:link.generation,p_type:cb.plan_revision})});
  return plain(link,chosen?'Назначение выбрано: '+cb.plan_revision+'. Отправьте файлы и пояснение.':'Режим подачи изменился. Выберите объект заново.');
 }
 if(cb.action==='finish'){
  const preview=await request('rpc/telegram_submission_preview',{method:'POST',body:JSON.stringify({p_owner:link.owner_id,p_chat:update.chat_id})});if(!preview||!preview.files?.length)return plain(link,'Нет файлов для подачи.');
  const review=await createCallback(link,'review',{plan_id:preview.id,version:preview.digest});
  return plain(link,'Проверьте подачу: '+preview.project_name+'\nНазначение: '+preview.document_type+'\nФайлы: '+preview.files.map(f=>f.file_name).join(', ')+'\nПояснение: '+(preview.explanation||'нет')+'\n'+(link.role==='director'?'После подтверждения файлы будут прикреплены к объекту.':'После подтверждения статус будет «принято на рассмотрение».'),{inline_keyboard:[[{text:'✅ Подтвердить подачу',callback_data:'c:'+review},{text:'✏️ Уточнить',callback_data:'mode:document'}]]});
 }
 if(cb.action==='review'){
  const preview=await request('rpc/telegram_submission_preview',{method:'POST',body:JSON.stringify({p_owner:link.owner_id,p_chat:update.chat_id})});if(!preview||!preview.files?.length||preview.id!==cb.plan_id||preview.digest!==cb.plan_revision)return plain(link,'Черновик изменился. Проверьте и подтвердите подачу заново.');
  if(link.role==='director'){
   const msg=await saveChat(update,link,'ПОДТВЕРЖДАЮ ПОДАЧУ '+preview.id,'callback');
   const done=await request('rpc/telegram_attach_batch',{method:'POST',body:JSON.stringify({p_owner:link.owner_id,p_chat:update.chat_id,p_submission:preview.id,p_confirm:msg.id,p_expected:preview.digest})});
   return plain(link,'Квитанция '+done.submission_id+'\nОбъект: '+done.project_name+'\nНастоящие документы прикреплены: '+done.documents.map(d=>d.file_name+' ('+d.document_id+')').join(', ')+'.');
  }
  const done=await bridge('submit',{owner_id:link.owner_id,chat_id:update.chat_id,project_id:preview.project_id,explanation:preview.explanation});
  await saveChat(update,link,'[Telegram: подтверждена подача документов] '+done.project_name+' · файлов '+done.files,'callback');
  return plain(link,'Квитанция '+done.submission_id+'\nОбъект: '+done.project_name+'\nФайлов: '+done.files+'\nСтатус: принято на рассмотрение. Это ещё не утверждение.');
 }
 if(link.role!=='director'||update.mode!=='instruction'||!['confirm','cancel'].includes(cb.action))return plain(link,'Подтверждение недоступно в этом режиме.');
 const content=(cb.action==='confirm'?'ПОДТВЕРЖДАЮ ':'ОТМЕНЯЮ ')+cb.plan_id;
 const msg=await saveChat(update,link,content,'callback');
 const response=await callAgent(update,link,msg.id,null,{id:cb.plan_id,version:cb.plan_revision});
 return {...plain(link,response.message?.content||'Результат сохранён в приложении.'),_agent_saved:true};
}
export async function processUpdate(update){
 const item=parseTelegramUpdate(update.payload);if(!item)return {result:{ignored:true},answer:null};
 if(item.kind==='callback'&&update.payload.callback_query?.id){try{await telegramApi('answerCallbackQuery',{callback_query_id:update.payload.callback_query.id,text:'Проверяем…'});}catch{}}
 const link=await bridge('get_link',{telegram_user_id:item.telegram_user_id});if(!link||link.owner_id!==update.owner_id)return {result:{access_revoked:true},answer:null};
 link.telegram_user_id=item.telegram_user_id;
 // Fixed at enqueue time even if a subsequent update already changed mode/chat.
 const fixed={...update,chat_id:update.chat_id,mode:update.mode};
 if((item.kind==='document'||item.kind==='photo'||item.kind==='callback')&&(link.chat_id!==fixed.chat_id||link.generation!==fixed.generation)){
  const answer=plain(link,'Чат или права изменились после отправки. Повторите действие в текущем чате.');
  return {result:{stale_chat:true},answer};
 }
 let answer;
 if(item.kind==='callback')answer=await processCallback(fixed,link,item);
 else if(item.text==='/linked')answer=plain(link,'Telegram подключён к VoltMaster. Сообщения сохраняются в приложении.');
 else if(item.event==='new_chat'||item.event==='new_submission')answer=plain(link,'Новый личный '+(link.role==='foreman'?'разговор подачи':'чат')+' создан. Прежняя история доступна в приложении.');
 else if(item.event==='consultation'||item.event==='instruction'||item.event==='document')answer=item.event==='document'&&!link.project_id?await projectsKeyboard(fixed,link):plain(link,item.event==='document'?'Режим подачи документа. Объект уже выбран; можно отправлять файлы.':item.event==='consultation'?'Режим консультации: чтение и анализ.':'Режим указаний: поручения выполняются только после подтверждения.');
 else if(item.text==='❓ Помощь'||item.text==='/start')answer=plain(link,link.role==='foreman'?'Выберите объект и отправьте документы, затем пояснение и подтвердите подачу.':'Выберите консультацию, подачу документа или указание. Подтверждение записи происходит отдельной кнопкой.');
 else if(item.text==='🌐 Открыть приложение')answer=plain(link,'Откройте приложение: '+(Deno.env.get('VOLTMASTER_APP_URL')||'https://rjoker555-crypto.github.io/babki/'));
 else if(item.event==='cancel')answer=plain(link,'Текущий ввод отменён. Уже выполненные действия не изменились.');
 else if(item.text==='📬 Статус подачи'){
  const rows=await bridge('status',{owner_id:link.owner_id,telegram_user_id:link.telegram_user_id});answer=plain(link,rows.length?rows.map(x=>x.project_name+' · '+x.status+' · '+x.id).join('\n'):'Сохранённых подач пока нет.');
 }
 else if(item.text==='📊 Статус выполнения'&&link.role==='director'){
  const msg=await saveChat(fixed,link,item.text,'text');answer=await executionStatus(fixed,link,msg.id);answer._incoming_saved=true;
 }
 else if(item.text==='Выбрать объект'||item.text==='📎 Подать документ'&&!link.project_id)answer=await projectsKeyboard(fixed,link);
 else if(item.kind==='document'||item.kind==='photo')answer=await stageFile(fixed,link,item);
 else if(item.kind==='voice'){
  const transcript=await transcribe(fixed,link,item);
  if(link.role==='foreman'||fixed.mode==='document'){
   await saveChat(fixed,link,'[голос, Telegram] '+transcript,'voice');await bridge('explain',{owner_id:link.owner_id,chat_id:fixed.chat_id,text:transcript});
   answer=plain(link,'Распознано: '+transcript+'\nДобавлено как пояснение. Для отправки документов нажмите «Завершить подбор».');
  }else{
   const msg=await saveChat(fixed,link,'[голос, Telegram] '+transcript,'voice');const r=await callAgent(fixed,link,msg.id);answer=plain(link,'Распознано: '+transcript+'\n\n'+(r.message?.content||'Ответ сохранён.'));
   if(fixed.mode==='instruction'){const keyboard=await approvals(fixed,link,msg.id);if(keyboard)answer.reply_markup=keyboard;}answer._agent_saved=true;
  }
 }
 else if(item.kind==='text'){
  const content=item.text.slice(0,7900);
  if(link.role==='foreman'||fixed.mode==='document'){
   await saveChat(fixed,link,content,'text');const changed=await bridge('explain',{owner_id:link.owner_id,chat_id:fixed.chat_id,text:content});answer=plain(link,changed?'Пояснение добавлено к черновику подачи.':'Сначала выберите объект и отправьте документ. Текст не выполняется как команда.');
  }else{
   const msg=await saveChat(fixed,link,content);const r=await callAgent(fixed,link,msg.id);answer=plain(link,r.message?.content||'Ответ сохранён в приложении.');
   if(fixed.mode==='instruction'){const keyboard=await approvals(fixed,link,msg.id);if(keyboard)answer.reply_markup=keyboard;}answer._agent_saved=true;
  }
 }
 else answer=plain(link,'Поддерживаются сообщения, голос и документы.');
 if(!answer._agent_saved){if(!answer._incoming_saved)await saveChat(fixed,link,item.text||'[Telegram: '+item.kind+']',item.kind==='callback'?'callback':item.kind==='voice'?'voice':item.kind==='document'||item.kind==='photo'?'document':'system');await request('rpc/telegram_save_transport_answer',{method:'POST',body:JSON.stringify({p_update:fixed.update_id,p_owner:link.owner_id,p_chat:fixed.chat_id,p_content:answer.text})});}
 delete answer._agent_saved;delete answer._incoming_saved;
 return {result:{processed:true,mode:fixed.mode,owner_id:link.owner_id},answer};
}
export async function drain(limit=3){
 let processed=0;for(let i=0;i<limit;i++){
  const update=await bridge('claim');if(!update)break;
  try{const done=await processUpdate(update);await bridge('finish',{update_id:update.update_id,result:done.result,answer:done.answer});}
  catch(error){const errorText=safeTelegramText(error.message),permanent=/лимит|недоступ|слишком|формат|объект|проект|измен|отключ|расшифр|повторн|прервал/i.test(error.message||'');if(permanent&&update.owner_id&&update.chat_id)try{await request('rpc/telegram_save_transport_answer',{method:'POST',body:JSON.stringify({p_update:update.update_id,p_owner:update.owner_id,p_chat:update.chat_id,p_content:errorText})});}catch{/* The incoming message may not have reached shared chat yet. */}await bridge('finish',{update_id:update.update_id,result:{error:errorText},answer:permanent?{method:'sendMessage',chat_id:update.telegram_user_id,text:errorText}:null,retry_seconds:permanent?null:Math.min(3600,30*(update.attempts+1))});}
  processed++;
 }
 return processed;
}
export async function sendOutbox(limit=5){
 let count=0;for(let i=0;i<limit;i++){
  const item=await bridge('claim_outbox');if(!item)break;
  if(!item.body||typeof item.body!=='object'||Array.isArray(item.body)||typeof item.body.method!=='string'||!Number.isSafeInteger(item.body.chat_id)){await bridge('finish_outbox',{id:item.id,state:'blocked'});count++;continue;}
  const link=await bridge('get_link',{telegram_user_id:item.telegram_user_id});if(!link){await bridge('finish_outbox',{id:item.id,state:'blocked'});continue;}
  const response=await telegramApi(item.body.method||'sendMessage',item.body);
  if(response.data?.ok)await bridge('finish_outbox',{id:item.id,state:'sent',telegram_message_id:response.data.result?.message_id});
  else if(response.status===403||response.status===400)await bridge('finish_outbox',{id:item.id,state:'blocked'});
  else await bridge('finish_outbox',{id:item.id,state:'retry',retry_seconds:response.data?.parameters?.retry_after||Math.min(3600,2**item.attempts)});
  count++;
 }
 return count;
}
export async function cleanupInbox(limit=2){
 const files=await request('rpc/telegram_cleanup_candidates',{method:'POST',body:JSON.stringify({p_limit:limit})});
 for(const file of files||[]){
  const response=await fetch(base()+'/storage/v1/object/telegram-inbox/'+file.storage_path,{method:'DELETE',headers:{apikey:service(),Authorization:'Bearer '+service()},signal:AbortSignal.timeout(15000)});
  if(response.ok||response.status===404)await request('rpc/telegram_mark_cleaned',{method:'POST',body:JSON.stringify({p_file:file.id})});
 }
}
export async function handle(req){
 if(req.method!=='POST')return json(405,{error:'POST required'});
 const secret=Deno.env.get('TELEGRAM_INTERNAL_SECRET');if(!secret||req.headers.get('X-Voltmaster-Internal')!==secret||req.headers.get('authorization')!=='Bearer '+service())return json(401,{error:'Unauthorized'});
 const work=(async()=>{try{await drain(1);await sendOutbox(5);await cleanupInbox(2);}catch{/* Durable queue leases allow retry by the scheduled invocation. */}})();
 if(globalThis.EdgeRuntime?.waitUntil){globalThis.EdgeRuntime.waitUntil(work);return json(202,{accepted:true});}
 await work;return json(200,{accepted:true});
}
if(import.meta.main)Deno.serve(handle);

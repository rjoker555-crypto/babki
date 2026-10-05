/* Private threads, separate protocol and microphone transcription. */
window.financeChat=(()=>{
 let owner=null,chatId=null,generation=0,timer=null,loading=false,sending=false,mode='chat',page=0,bound=false;
 let messages=[],conversations=[],events=[],protocol=[];
 let recorder=null,stream=null,recordTimeout=null,recordCancelled=false,recordingBusy=false;
 const el=id=>document.getElementById(id),time=v=>new Date(v).toLocaleString('ru-RU');
 function status(text){el('agentChatStatus').textContent=text;}
 function controls(){el('agentChatSend').disabled=!owner||sending||recordingBusy;el('agentChatInput').disabled=!owner||sending||recordingBusy;el('agentChatVoice').disabled=!owner||sending||(recordingBusy&&!recorder);el('agentChatNew').disabled=!owner||sending||recordingBusy;}
 function releaseMic(){clearTimeout(recordTimeout);recordTimeout=null;stream?.getTracks().forEach(t=>t.stop());stream=null;}
 function cancelVoice(){recordCancelled=true;if(recorder?.state==='recording')recorder.stop();releaseMic();recorder=null;recordingBusy=false;el('agentChatVoice').textContent='🎙 Голос';el('agentChatVoiceCancel').hidden=true;controls();}
 function reset(){generation++;owner=null;chatId=null;clearInterval(timer);timer=null;loading=false;sending=false;cancelVoice();messages=[];conversations=[];events=[];protocol=[];page=0;mode='chat';el('agentChatInput').value='';for(const id of ['agentChatMessages','agentChatHistoryList','agentChatProtocolList'])el(id).replaceChildren();el('agentChatBadge').textContent='';el('agentChatMore').hidden=true;controls();status('Войдите в систему, чтобы открыть свой чат.');}
 function bubble(item){const box=document.createElement('article');box.className='chat-message chat-'+item.kind;const header=document.createElement('div');header.className='chat-message-meta';header.textContent=item.kind==='user'?(item.source==='voice'?'Вы · голос, расшифровка':'Вы'):item.kind==='assistant'?'Главный агент':item.actor_name||'Системный процесс';const body=document.createElement('div');body.className='chat-message-body';body.textContent=item.content;const stamp=document.createElement('time');stamp.textContent=time(item.created_at);header.append(' · ',stamp);box.append(header,body);return box;}
 function empty(list,text){if(!list.children.length){const p=document.createElement('p');p.className='empty';p.textContent=text;list.append(p);}}
 function render(){
  const list=el('agentChatMessages'),nearEnd=list.scrollHeight-list.scrollTop-list.clientHeight<80;
  list.replaceChildren(...[...messages].sort((a,b)=>a.created_at.localeCompare(b.created_at)||a.id.localeCompare(b.id)).map(bubble));empty(list,'Начните новый разговор с главным агентом.');if(nearEnd)list.scrollTop=list.scrollHeight;
  const history=el('agentChatHistoryList');history.replaceChildren(...conversations.map(c=>{const b=document.createElement('button');b.type='button';b.className='chat-history-item';b.textContent=c.title+' · '+time(c.last_message_at);b.onclick=()=>selectChat(c.id);return b;}));empty(history,'Сохранённых чатов пока нет.');
  const combined=[...protocol.map(p=>({...p,kind:'activity',content:p.summary})),...events.map(e=>({...e,kind:'activity',content:e.summary+(e.project_name?' · Объект «'+e.project_name+'»':'')}))].sort((a,b)=>b.created_at.localeCompare(a.created_at)||b.id.localeCompare(a.id));
  el('agentChatProtocolList').replaceChildren(...combined.map(bubble));empty(el('agentChatProtocolList'),'Поручений и изменений пока нет.');
  let last='';try{last=localStorage.getItem('agentProtocolSeen:'+owner)||'';}catch{}
  const unread=combined.filter(p=>p.actor_id!==owner&&p.created_at>last).length;el('agentChatBadge').textContent=unread?' ('+unread+')':'';
 }
 function setMode(next){mode=next;for(const name of ['chat','history','protocol']){el('agentChat'+({chat:'Pane',history:'HistoryPane',protocol:'ProtocolPane'}[name])).hidden=name!==mode;el('agentChatTab'+name).setAttribute('aria-pressed',String(name===mode));}render();if(mode==='protocol'){try{localStorage.setItem('agentProtocolSeen:'+owner,new Date().toISOString());}catch{}el('agentChatBadge').textContent='';}}
 async function selectChat(id){if(sending||recordingBusy){status('Дождитесь окончания ответа или отмените запись.');return;}generation++;loading=false;chatId=id;messages=[];page=0;el('agentChatInput').value='';setMode('chat');await refresh();}
 async function newChat(){if(!owner||sending||recordingBusy)return;const token=generation;try{const r=await sbClient.from('agent_conversations').insert({id:crypto.randomUUID(),owner_id:owner,title:'Новый чат'}).select('id,title,last_message_at').single();if(token!==generation)return;if(r.error)throw r.error;conversations.unshift(r.data);await selectChat(r.data.id);}catch(e){if(token===generation)status('Не удалось создать чат: '+e.message);}}
 async function refresh(older=false){
  if(!owner||loading)return;loading=true;const token=generation,userId=owner,id=chatId,nextPage=older?page+1:0;
  try{
   const [cr,mr,er,pr]=await Promise.all([
    sbClient.from('agent_conversations').select('id,title,last_message_at').eq('owner_id',userId).order('last_message_at',{ascending:false}).limit(200),
    id?sbClient.from('agent_chat_messages').select('id,kind,source,content,created_at').eq('owner_id',userId).eq('chat_id',id).order('created_at',{ascending:false}).order('id',{ascending:false}).range(nextPage*50,nextPage*50+49):Promise.resolve({data:[]}),
    sbClient.from('agent_activity_events').select('id,actor_id,actor_name,summary,project_name,created_at').order('created_at',{ascending:false}).order('id',{ascending:false}).limit(100),
    sbClient.from('agent_protocol_entries').select('id,actor_id,actor_name,summary,entry_type,created_at').order('created_at',{ascending:false}).order('id',{ascending:false}).limit(100)
   ]);
   if(token!==generation)return;for(const r of [cr,mr,er,pr])if(r.error)throw r.error;
   conversations=cr.data;events=er.data;protocol=pr.data;
   if(chatId&&!conversations.some(c=>c.id===chatId)){chatId=null;messages=[];page=0;}
   if(older){messages=[...new Map([...messages,...mr.data].map(m=>[m.id,m])).values()];page=nextPage;}else if(page>0)messages=[...new Map([...messages,...mr.data].map(m=>[m.id,m])).values()];else messages=mr.data;
   el('agentChatMore').hidden=mr.data.length<50;render();if(!sending&&!recordingBusy)status('Личный чат · '+(conversations.find(c=>c.id===chatId)?.title||'Главный агент'));
   if(!chatId&&conversations.length){loading=false;await selectChat(conversations[0].id);}
  }catch(e){if(token===generation)status('Не удалось обновить чат: '+e.message);}finally{if(token===generation)loading=false;}
 }
 function bind(){if(bound)return;bound=true;const input=el('agentChatInput');let newline=false;input.addEventListener('keydown',e=>{if(e.key==='Enter')newline=Boolean(e.shiftKey);if(e.key==='Enter'&&!e.shiftKey&&!e.isComposing&&e.keyCode!==229){e.preventDefault();send();}});input.addEventListener('keyup',e=>{if(e.key==='Enter')newline=false;});input.addEventListener('beforeinput',e=>{if(e.inputType==='insertParagraph'||e.inputType==='insertLineBreak'){const allowNewline=newline||e.shiftKey;newline=false;if(!e.isComposing&&!allowNewline){e.preventDefault();send();}}});}
 async function init(session){bind();const next=session?.user?.id||null;if(next===owner)return;reset();if(!next)return;owner=next;controls();setMode('chat');await refresh();if(owner===next)timer=setInterval(()=>{if(document.visibilityState==='visible'&&el('agentchat').classList.contains('active'))refresh();},30000);}
 async function invoke(name,body){const r=await sbClient.functions.invoke(name,{body});if(r.error){let detail=r.error.message;try{detail=(await r.error.context.json()).error||detail;}catch{}throw new Error(detail);}if(r.data?.error)throw new Error(r.data.error);return r.data;}
 async function send(source='text',spoken=null){
  if(!owner||sending||recordingBusy)return;const input=el('agentChatInput'),content=(spoken??input.value).trim();if(!content)return;if(content.length>8000){status('Сообщение должно быть не длиннее 8000 символов.');return;}if(source==='voice'&&spoken!==null)input.value=content;
  if(!chatId){await newChat();if(!chatId)return;}
  const token=generation,userId=owner,idChat=chatId;sending=true;controls();setMode('chat');
  try{
   const id=crypto.randomUUID(),r=await sbClient.from('agent_chat_messages').insert({id,owner_id:userId,chat_id:idChat,kind:'user',source,content}).select('id,kind,source,content,created_at').single();if(token!==generation)return;if(r.error)throw r.error;messages.push(r.data);if(spoken===null||input.value===content)input.value='';render();el('agentChatMessages').scrollTop=el('agentChatMessages').scrollHeight;status('Главный агент готовит ответ…');
   const answer=await invoke('main-agent',{message_id:id});if(token!==generation)return;if(!answer.message)throw new Error('Сервер не вернул ответ.');messages=[...new Map([...messages,answer.message].map(m=>[m.id,m])).values()];render();el('agentChatMessages').scrollTop=el('agentChatMessages').scrollHeight;status('Личный чат · Главный агент');
  }catch(e){if(token===generation)status('Ошибка: '+e.message+' Сохранённое сообщение остаётся в истории.');}finally{if(token===generation){sending=false;controls();await refresh();}}
 }
 async function voice(){
  if(recorder?.state==='recording'){recorder.stop();return;}if(!owner||sending||recordingBusy)return;
  if(!navigator.mediaDevices?.getUserMedia||typeof MediaRecorder==='undefined'){status('Микрофон недоступен. Откройте приложение по HTTPS или на localhost в браузере с записью звука.');return;}
  if(!chatId){await newChat();if(!chatId)return;}const token=generation,idChat=chatId;recordingBusy=true;recordCancelled=false;controls();
  try{
   stream=await navigator.mediaDevices.getUserMedia({audio:true});if(token!==generation||recordCancelled){releaseMic();return;}
   const mime=['audio/webm;codecs=opus','audio/mp4','audio/webm'].find(v=>MediaRecorder.isTypeSupported(v));if(!mime){releaseMic();throw new Error('Браузер не поддерживает WebM/MP4 для записи.');}
   recorder=new MediaRecorder(stream,{mimeType:mime,audioBitsPerSecond:64000});const chunks=[];let size=0;
   recorder.ondataavailable=e=>{if(e.data.size){chunks.push(e.data);size+=e.data.size;if(size>3*1024*1024&&recorder?.state==='recording')recorder.stop();}};
   recorder.onerror=()=>{cancelVoice();status('Не удалось записать звук.');};
   recorder.onstop=async()=>{
    const cancelled=recordCancelled||token!==generation;releaseMic();recorder=null;el('agentChatVoice').textContent='🎙 Голос';el('agentChatVoiceCancel').hidden=true;if(cancelled){recordingBusy=false;controls();return;}
    try{status('Расшифровываю голосовое сообщение…');const form=new FormData(),type=mime.split(';')[0];form.set('file',new Blob(chunks,{type}),type==='audio/mp4'?'voice.mp4':'voice.webm');form.set('chat_id',idChat);form.set('request_id',crypto.randomUUID());const decoded=await invoke('transcribe-voice',form);if(token!==generation)return;recordingBusy=false;controls();await send('voice',decoded.text);}
    catch(e){if(token===generation)status('Голос не отправлен: '+e.message);}finally{if(token===generation){recordingBusy=false;controls();}}
   };
   recorder.start(1000);el('agentChatVoice').textContent='⏹ Отправить голос';el('agentChatVoiceCancel').hidden=false;controls();status('Запись идёт. Нажмите «Отправить голос», когда закончите. Максимум 3 минуты.');recordTimeout=setTimeout(()=>{if(recorder?.state==='recording')recorder.stop();},180000);
  }catch(e){releaseMic();if(token===generation){recordingBusy=false;controls();status('Микрофон не включён: '+e.message);}}
 }
 return {init,reset,refresh,send,newChat,setMode,voice,cancelVoice};
})();

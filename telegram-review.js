(function(){
 const $=id=>document.getElementById(id),types=[['other','Другое'],['project','Проект'],['contract','Договор'],['estimate','Смета'],['addendum','Дополнительное соглашение']];
 const invoke=async body=>{const r=await sbClient.functions.invoke('telegram-review',{body});if(r.error)throw Error(r.data?.error||r.error.message);return r.data;};
 async function open(){if(profile?.role!=='director'||!profile?.is_active)return;$('telegramReviewModal').hidden=false;$('telegramReviewModal').classList.add('open');await refresh();}
 async function refresh(){const list=$('telegramReviewList');list.replaceChildren();try{const data=await invoke({operation:'list'});if(!data.submissions.length){list.textContent='Новых подач нет.';return;}
  for(const submission of data.submissions){const card=document.createElement('div');card.className='card';const head=document.createElement('h3');head.textContent=submission.project_name+' · '+submission.status;card.append(head);const explanation=document.createElement('p');explanation.textContent='Пояснение: '+(submission.explanation||'нет');card.append(explanation);
   for(const file of submission.files){const line=document.createElement('div');line.style.cssText='display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin:8px 0';const label=document.createElement('span');label.textContent=file.file_name+' · '+file.file_size+' байт · '+file.status;line.append(label);if(file.status==='received'){
    const select=document.createElement('select');for(const [value,title] of types){const option=document.createElement('option');option.value=value;option.textContent=title;select.append(option);}line.append(select);
    for(const [action,title] of [['accept','Принять в документы'],['reject','Отклонить']]){const button=document.createElement('button');button.className='smallbtn';button.type='button';button.textContent=title;button.onclick=async()=>{if(!confirm((action==='accept'?'Принять «':'Отклонить «')+file.file_name+'» для объекта «'+submission.project_name+'»?'))return;button.disabled=true;try{const result=await invoke({operation:action,file_id:file.id,document_type:select.value});$('telegramReviewStatus').textContent=result.result?.status==='approved'?'Документ принят и сохранён: '+result.file_name:'Подача обновлена.';await refresh();if(result.result?.status==='approved'&&typeof window.scheduleRealtimeReload==='function')window.scheduleRealtimeReload();}catch(e){$('telegramReviewStatus').textContent=e.message;button.disabled=false;}};line.append(button);}
   }card.append(line);}list.append(card);}
 }catch(e){list.textContent=e.message;}}
 function close(){$('telegramReviewModal').classList.remove('open');$('telegramReviewModal').hidden=true;}
 window.telegramReview={open,refresh,close,reset:close};
})();

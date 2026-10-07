(function(root){
 'use strict';
 const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const statuses={open:'Ожидает подачи',overdue:'Просрочено',completed:'Подача подтверждена',cancelled:'Отменено изменением регламента'};
 let client,projects=[],state={},notifications=[],offset=0,hasMore=false,epoch=0,loading=false;
 function el(id){return document.getElementById(id);}
 function renderTasks(){
  el('obligationTasks').innerHTML=(state.tasks||[]).length?(state.tasks||[]).map(t=>`<div class="work-item"><b>${esc(t.project_name)}</b>
   <div>Подача за ${esc(t.period_from)} — ${esc(t.period_to)}</div><div>Срок: ${esc(t.due_date)} · ${esc(statuses[t.status]||t.status)}</div>
   <div class="muted">Основание: ${esc(t.authority_basis)}</div>
   ${t.evidence_submission_id?'<div class="muted">Связана с подтверждающей подачей.</div>':''}
   <button class="smallbtn" data-project="${esc(t.project_id)}">Открыть «Ход работ»</button></div>`).join(''):'<div class="muted">Назначенных вам задач по регламенту пока нет. Общие задачи объекта остаются в «Ходе работ».</div>';
 }
 function renderNotifications(){
  el('obligationNotifications').innerHTML=notifications.length?notifications.map(n=>`<div class="work-item"><b>${esc(n.title)}</b><div class="muted">${esc(n.local_date)} · ${n.read_at?'Прочитано':'Не прочитано'}</div>
   ${n.read_at?'':`<button class="smallbtn" data-read="${esc(n.id)}">Отметить прочитанным</button>`}</div>`).join(''):'<div class="muted">Внутренних уведомлений пока нет.</div>';
  el('obligationMore').hidden=!hasMore;
 }
 async function loadNotifications(token,append){
  const start=append?offset:0;
  const {data,error}=await client.from('in_app_notifications').select('id,title,local_date,read_at').order('created_at',{ascending:false}).order('id',{ascending:false}).range(start,start+49);
  if(token!==epoch)return;
  if(error)throw new Error(error.message);
  notifications=append?notifications.concat(data||[]):data||[];offset=start+(data||[]).length;hasMore=(data||[]).length===50;renderNotifications();
 }
 function fillRule(){
  const project=el('obligationProject').value,rule=(state.rules||[]).find(r=>r.project_id===project);
  el('obligationDay').value=rule?.due_day||'';el('obligationTime').value=rule?.reminder_time?.slice(0,5)||'';
  el('obligationShortMonth').value=rule?.short_month_policy||'';el('obligationPeriod').value=rule?String(rule.period_offset):'';
  el('obligationBasis').value=rule?.authority_basis||'';el('obligationEnabled').checked=rule?.enabled===true;
  const assigned=projects.find(p=>p.id===project)?.responsible_user_id;
  el('obligationRecipient').textContent=assigned?'Получатель — назначенный в карточке ответственный аккаунт. Сервер проверит его активность.':'В карточке объекта не назначен ответственный аккаунт. Доставка недоступна.';
 }
 async function refresh(token){
  const {data,error}=await client.rpc('get_my_volume_obligations');if(token!==epoch)return;
  if(error)throw new Error(error.message);state=data||{};renderTasks();
  el('obligationSettings').hidden=!state.can_configure;
  if(state.can_configure){
   const current=el('obligationProject').value;
   el('obligationProject').innerHTML='<option value="">Выберите объект</option>'+projects.map(p=>`<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('');
   el('obligationProject').value=current;fillRule();
  }
  await loadNotifications(token,false);
 }
 async function save(event){
  event.preventDefault();if(loading)return;loading=true;const token=epoch;el('obligationSave').disabled=true;
  try{
   const project=projects.find(p=>p.id===el('obligationProject').value);if(!project?.responsible_user_id)throw new Error('Сначала назначьте ответственного в карточке объекта.');
   const rule=(state.rules||[]).find(r=>r.project_id===project.id);
   const settings=await client.rpc('get_project_settings',{p_project:project.id});if(settings.error)throw settings.error;
   const {error}=await client.rpc('execute_project_settings',{p_request:crypto.randomUUID(),p_command:{kind:'volume_rule',project_id:project.id,expected:settings.data,config:{project_id:project.id,assignee_id:project.responsible_user_id,
    expected_version:rule?.version||null,due_day:Number(el('obligationDay').value),reminder_time:el('obligationTime').value,
    short_month_policy:el('obligationShortMonth').value,period_offset:Number(el('obligationPeriod').value),
    authority_basis:el('obligationBasis').value.trim(),enabled:el('obligationEnabled').checked}}});
   if(token!==epoch)return;if(error)throw new Error(error.message);
   await refresh(token);el('obligationStatus').textContent='Регламент сохранён. Активный регламент обработает серверный планировщик в течение минуты.';
  }catch(error){if(token===epoch)el('obligationStatus').textContent='Настройка не подтверждена: '+error.message+' При сетевой ошибке обновите список перед повтором.';}
  finally{loading=false;if(token===epoch)el('obligationSave').disabled=false;}
 }
 function mount(){
  if(el('obligationModal'))return;
  const modal=document.createElement('div');modal.id='obligationModal';modal.className='modal';
  modal.innerHTML=`<div class="sheet"><h2>Мои задачи и уведомления</h2><div class="muted">Уведомления хранятся внутри приложения. Прочтение не подтверждает выполнение.</div>
   <p id="obligationStatus" role="status"></p><button class="smallbtn" id="obligationRefresh">Обновить</button>
   <h3>Мои задачи</h3><div id="obligationTasks"></div><h3>Уведомления</h3><div id="obligationNotifications"></div><button class="smallbtn" id="obligationMore" hidden>Загрузить ещё</button>
   <details id="obligationSettings" hidden><summary>Настроить регламент подачи объёмов</summary>
   <p class="muted">Это явное поручение: задача за семь дней до срока, ежедневное уведомление в указанное время до срока включительно. После срока сохраняется просрочка. Смена настроек отменяет незавершённые задачи прежней версии.</p>
   <form id="obligationForm"><label>Объект<select id="obligationProject" required></select></label><div id="obligationRecipient" class="muted"></div>
   <label>День подачи каждый месяц<input id="obligationDay" type="number" min="1" max="31" step="1" required></label>
   <label>Время уведомлений · Asia/Krasnoyarsk<input id="obligationTime" type="time" required></label>
   <label>Если дня нет в месяце<select id="obligationShortMonth" required><option value="">Выберите правило</option><option value="last_day">Последний день месяца</option><option value="skip">Пропустить месяц</option></select></label>
   <label>Период подачи<select id="obligationPeriod" required><option value="">Выберите период</option><option value="-1">Предыдущий календарный месяц</option><option value="0">Текущий календарный месяц целиком</option></select></label>
   <div class="muted">Завершение требует подачи с точно совпадающими датами периода. Для иных периодов регламент пока не реализован.</div>
   <label>Основание / поручение<textarea id="obligationBasis" maxlength="2000" required></textarea></label>
   <label><input id="obligationEnabled" type="checkbox"> Включить регламент</label><button class="primary" id="obligationSave" type="submit">Сохранить регламент</button></form></details>
   <button class="smallbtn" id="obligationClose" style="margin-top:16px">Закрыть</button></div>`;
  document.body.appendChild(modal);el('obligationForm').addEventListener('submit',save);el('obligationProject').addEventListener('change',fillRule);
  el('obligationClose').onclick=()=>{epoch++;modal.classList.remove('open');};modal.onclick=e=>{if(e.target===modal)el('obligationClose').click();};
  el('obligationRefresh').onclick=()=>refresh(epoch).catch(e=>el('obligationStatus').textContent=e.message);
  el('obligationMore').onclick=()=>loadNotifications(epoch,true).catch(e=>el('obligationStatus').textContent=e.message);
  el('obligationNotifications').onclick=async e=>{const id=e.target.dataset.read;if(!id)return;const token=epoch;
   const {error}=await client.rpc('read_in_app_notification',{p_id:id});if(token!==epoch)return;
   if(error)el('obligationStatus').textContent=error.message;else await loadNotifications(token,false);
  };
  el('obligationTasks').onclick=e=>{const id=e.target.dataset.project;if(id){el('obligationClose').click();root.openWorkPanel(id);}};
 }
 root.volumeObligations={async open(sb,rows){client=sb;projects=rows;state={};notifications=[];mount();el('obligationModal').classList.add('open');
  el('obligationTasks').textContent='Загрузка…';el('obligationNotifications').textContent='Загрузка…';el('obligationSettings').hidden=true;el('obligationMore').hidden=true;el('obligationStatus').textContent='';
  const token=++epoch;try{await refresh(token);}catch(error){if(token===epoch)el('obligationStatus').textContent='Не удалось загрузить: '+error.message;}
 },reset(){epoch++;state={};notifications=[];client=null;projects=[];if(el('obligationModal'))el('obligationModal').classList.remove('open');}};
})(window);

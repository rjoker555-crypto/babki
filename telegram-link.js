(function(){
 let open=false;
 const $=id=>document.getElementById(id);
 const status=text=>{if($('telegramLinkStatus'))$('telegramLinkStatus').textContent=text;};
 async function invoke(operation){const session=(await sbClient.auth.getSession()).data.session;if(!session)throw Error('Войдите в приложение.');const result=await sbClient.functions.invoke('telegram-link',{body:{operation}});if(result.error)throw Error(result.data?.error||result.error.message);return result.data;}
 async function show(){
  if(!profile?.is_active||!['director','foreman'].includes(profile.role)){status('Telegram доступен только активному директору и прорабу.');return;}
  $('telegramLinkModal').hidden=false;$('telegramLinkModal').classList.add('open');open=true;status('Проверка привязки…');
  try{const r=await invoke('status');status(r.status?.linked?'Telegram подключён. Вы можете отключить его здесь.':'Telegram пока не подключён. Ссылка для подключения действует 10 минут.');}catch(e){status(e.message);}
 }
 async function connect(){status('Создаём одноразовую ссылку…');try{const r=await invoke('connect');$('telegramLinkUrl').href=r.url;$('telegramLinkUrl').textContent='Открыть бота для привязки';$('telegramLinkUrl').hidden=false;status('Откройте ссылку в личном чате Telegram до '+new Date(r.expires_at).toLocaleTimeString('ru-RU')+'. Код нельзя пересылать другим.');}catch(e){status(e.message);}}
 async function disconnect(){status('Отключаем…');try{await invoke('disconnect');$('telegramLinkUrl').hidden=true;status('Telegram отключён. Для перепривязки создайте новую ссылку.');}catch(e){status(e.message);}}
 async function admin(operation){status(operation==='configure_worker'?'Настраиваем минутную очередь…':'Проверка Telegram…');try{const r=await sbClient.functions.invoke('telegram-admin',{body:{operation}});if(r.error)throw Error(r.data?.error||r.error.message);status(operation==='info'?'Webhook: '+(r.data.url||'не зарегистрирован')+'; ожидает '+r.data.pending_update_count:operation==='register'?'Webhook зарегистрирован: '+r.data.webhook:operation==='configure_worker'?'Минутная очередь Telegram настроена и включена.':'Webhook отключён.');}catch(e){status(e.message);}}
 function close(){open=false;$('telegramLinkModal').classList.remove('open');$('telegramLinkModal').hidden=true;$('telegramLinkUrl').hidden=true;$('telegramLinkUrl').removeAttribute('href');}
 window.telegramLink={show,connect,disconnect,admin,close,reset:close};
})();

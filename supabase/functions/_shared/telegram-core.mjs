export const telegramMenu=role=>({keyboard:role==='foreman'?
 [['📎 Подать документ','🆕 Новая подача'],['📬 Статус подачи','🌐 Открыть приложение'],['❓ Помощь','↩️ Отмена']]:
 [['🆕 Новый чат','💬 Консультация'],['📎 Подать документ','📝 Подать указание'],['📊 Статус выполнения','🌐 Открыть приложение'],['❓ Помощь','↩️ Отмена']],resize_keyboard:true,is_persistent:true});
export function parseTelegramUpdate(update){
 if(!Number.isSafeInteger(update?.update_id)||update.update_id<0)return null;
 const q=update.callback_query,m=q?.message||update.message;
 if(!m||m.chat?.type!=='private'||!Number.isSafeInteger(m.chat.id)||!Number.isSafeInteger(q?.from?.id??m.from?.id))return null;
 const sender=q?.from?.id??m.from?.id;
 if(sender!==m.chat.id)return null;
 const text=typeof m.text==='string'?m.text.trim():'';
 const event=({ '🆕 Новый чат':'new_chat','🆕 Новая подача':'new_submission','💬 Консультация':'consultation','📝 Подать указание':'instruction','📎 Подать документ':'document','↩️ Отмена':'cancel'}[text])||null;
 return {update_id:update.update_id,telegram_user_id:sender,kind:q?'callback':m.voice?'voice':m.document?'document':m.photo?'photo':'text',event,text,callback_data:q?.data||null,message:m};
}
export const safeName=name=>String(name||'file').normalize('NFC').replace(/[\\/\x00-\x1f]/g,'_').slice(0,160);
export function identifyFile(bytes,name,isPhoto=false){
 const ext=safeName(name).toLowerCase().split('.').pop(),a=bytes;
 if(a.length<4||a.length>8*1024*1024)throw Error('Размер файла превышает 8 МБ или файл пустой. Загрузите его через приложение.');
 if(ext==='pdf'&&String.fromCharCode(...a.slice(0,5))==='%PDF-')return 'application/pdf';
 if(ext==='txt'){new TextDecoder('utf-8',{fatal:true}).decode(a);if(a.includes(0))throw Error('TXT содержит двоичные данные.');return 'text/plain';}
 if((ext==='docx'||ext==='xlsx')&&a[0]===80&&a[1]===75&&a[2]===3&&a[3]===4)return ext==='docx'?'application/vnd.openxmlformats-officedocument.wordprocessingml.document':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
 if((ext==='jpg'||ext==='jpeg'||isPhoto)&&a[0]===255&&a[1]===216&&a[2]===255)return 'image/jpeg';
 if(ext==='png'&&a[0]===137&&a[1]===80&&a[2]===78&&a[3]===71)return 'image/png';
 throw Error('Формат или содержимое файла не поддерживается: PDF, DOCX, XLSX, TXT, JPEG, PNG.');
}
export function voiceAllowed(voice){return Boolean(voice&&typeof voice.file_id==='string'&&voice.file_id.length<512&&Number.isFinite(voice.duration)&&voice.duration>0&&voice.duration<=180&&(voice.file_size===undefined||Number.isFinite(voice.file_size)&&voice.file_size>100&&voice.file_size<=3*1024*1024));}
export function safeTelegramText(value){return String(value||'').replace(/https?:\/\/api\.telegram\.org\/file\/bot[^\s]+/gi,'[скрытая ссылка Telegram]').slice(0,3800);}

const assert=require('node:assert/strict');
(async()=>{const {parseTelegramUpdate,identifyFile,voiceAllowed,safeTelegramText,telegramMenu}=await import('../supabase/functions/_shared/telegram-core.mjs');
 const update={update_id:123,message:{chat:{id:456,type:'private'},from:{id:456},voice:{file_id:'voice',duration:13,file_size:1234}}};
 assert.equal(parseTelegramUpdate(update).kind,'voice');assert.equal(parseTelegramUpdate({...update,message:{...update.message,chat:{id:-99,type:'supergroup'}}}),null);assert.equal(parseTelegramUpdate({...update,message:{...update.message,from:{id:789}}}),null);
 assert(voiceAllowed(update.message.voice));assert(voiceAllowed({file_id:'voice',duration:13}));assert(!voiceAllowed({file_id:'voice',duration:181}));assert(!voiceAllowed({file_id:'voice',duration:12,file_size:4*1024*1024}));
 assert.equal(identifyFile(new Uint8Array(Buffer.from('%PDF-1.4')), 'plan.pdf'),'application/pdf');assert.equal(identifyFile(new Uint8Array(Buffer.from('Привет')),'doc.txt'),'text/plain');assert.throws(()=>identifyFile(new Uint8Array([1,2,3,4]),'x.docx'));
 assert(!safeTelegramText('https://api.telegram.org/file/botSECRET/path').includes('SECRET'));assert(telegramMenu('foreman').keyboard.flat().every(x=>!x.includes('Консультация')&&!x.includes('указание')));
 console.log('PASS: private chat identity, group/forged sender denied, Telegram voice bounds, actual file magic, no token-bearing URL in response, foreman menu excludes agent');
})().catch(e=>{console.error(e);process.exit(1)});

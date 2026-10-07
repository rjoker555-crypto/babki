const fs=require('node:fs'),assert=require('node:assert/strict'),{chromium}=require('playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,channel:'msedge'});const page=await browser.newPage({viewport:{width:390,height:844}});const html=fs.readFileSync('index.html','utf8');
 const style=html.match(/<style[^>]*>([\s\S]*?)<\/style>/)[1];const section=html.match(/<section id="agentchat"[\s\S]*?<\/section>/)[0].replace('class="page"','class="page active"');
 await page.route('https://voltmaster-test.invalid/**',route=>route.fulfill({contentType:'text/html; charset=utf-8',body:'<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>'+style+'</style></head><body><div class="app">'+section+'</div></body></html>'}));
 await page.route('**/*',route=>route.request().url().startsWith('https://voltmaster-test.invalid/')?route.fallback():route.abort());
 await page.goto('https://voltmaster-test.invalid/',{waitUntil:'domcontentloaded'});
 await page.evaluate(()=>{
  window.tables={agent_conversations:[{id:'chat',owner_id:'user',title:'Проект',last_message_at:new Date().toISOString()}],agent_chat_messages:[],agent_activity_events:[],agent_protocol_entries:[]};window.assets=[];window.requests=[];
  window.sbClient={from(table){return {select(){const filters=[];const q={eq(k,v){filters.push([k,v]);return q},order(){return q},limit(){return get()},range(){return get()}};function get(){return Promise.resolve({data:tables[table].filter(r=>filters.every(([k,v])=>r[k]===v))})}return q},insert(payload){const row={...payload,created_at:new Date().toISOString(),last_message_at:new Date().toISOString()};tables[table].push(row);return {select(){return {single:async()=>({data:row})}}}}}},functions:{invoke:async(name,{body})=>{
   requests.push({name,form:body instanceof FormData});
   if(name==='agent-files'&&body instanceof FormData){const file={id:body.get('file_id'),file_name:body.get('file').name,mime_type:'text/plain',file_size:body.get('file').size};assets.push(file);return {data:{file}};}
   if(name==='agent-files')return {data:{files:assets}};
   const row={id:crypto.randomUUID(),kind:'assistant',chat_id:'chat',owner_id:'user',content:'Разбор запущен. Это ещё не готовый расчёт.',created_at:new Date().toISOString()};tables.agent_chat_messages.push(row);return {data:{message:row}};
  }}};
 });
 await page.addScriptTag({path:'chat.js'});await page.evaluate(()=>financeChat.init({user:{id:'user'}}));
 await page.setInputFiles('#agentChatFileInput',{name:'проект.txt',mimeType:'text/plain',buffer:Buffer.from('Кабель — 10,5 м','utf8')});
 await page.waitForFunction(()=>document.querySelector('#agentChatStatus').textContent.includes('личный черновик'));
 assert((await page.locator('#agentChatFiles').innerText()).includes('выбран для следующего сообщения'));
 await page.click('#agentChatSend');await page.waitForFunction(()=>document.querySelector('#agentChatMessages').textContent.includes('Разбор запущен'));
 const message=await page.evaluate(()=>tables.agent_chat_messages.find(m=>m.kind==='user'));assert(message.content.includes('Разбери приложенный проект'));assert(message.content.includes('file_id: '));assert.equal(message.chat_id,'chat');
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth));
 fs.mkdirSync('tests/artifacts',{recursive:true});await page.screenshot({path:'tests/artifacts/chat-files-mobile.png',fullPage:true});
 await page.evaluate(()=>financeChat.reset());assert.equal(await page.locator('#agentChatFiles').innerText(),'');assert.equal(await page.locator('#agentChatAttach').isDisabled(),true);
 await browser.close();console.log('PASS: actual mobile file picker, private draft upload, attachment-only message, saved file ID, chat scoping and logout');
})().catch(e=>{console.error(e);process.exit(1)});

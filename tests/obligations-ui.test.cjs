const assert=require('node:assert/strict'),fs=require('node:fs'),{chromium}=require('playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,channel:'msedge'});const page=await browser.newPage({viewport:{width:390,height:844}});
 const style=fs.readFileSync('index.html','utf8').match(/<style[^>]*>([\s\S]*?)<\/style>/)[1];
 await page.setContent(`<html lang="ru"><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>${style}</style></head><body></body></html>`);
 await page.evaluate(()=>{
  Object.defineProperty(crypto,'randomUUID',{value:()=> '11111111-1111-4111-8111-111111111111'});window.calls=[];window.openedProject=null;window.openWorkPanel=id=>window.openedProject=id;
  window.fixture={can_configure:true,rules:[],tasks:[{id:'task',project_id:'p',project_name:'Тест <img src=x onerror="window.injected=1">',period_from:'2026-09-01',period_to:'2026-09-30',due_date:'2026-10-15',status:'open',authority_basis:'Поручение владельца'}]};
  window.notes=[{id:'n',title:'Подайте объёмы',local_date:'2026-10-08',read_at:null}];
  window.client={rpc:async(name,args)=>{calls.push({name,args});if(name==='get_my_volume_obligations')return {data:fixture};
   if(name==='read_in_app_notification'){notes[0].read_at='2026-10-08';return {data:true};}
   if(name==='get_project_settings')return {data:{project_id:'p',responsible_user_id:'foreman',members:[],rule:null}};
   if(name==='execute_project_settings'){fixture.rules=[{...args.p_command.config,version:1}];return {data:fixture.rules[0]};}return {error:{message:'Unknown RPC'}};},
   from:()=>({select(){return this},order(){return this},range:async()=>({data:notes})})};
 });
 await page.addScriptTag({path:'obligations.js'});
 await page.evaluate(()=>volumeObligations.open(client,[{id:'p',name:'Объект 1',responsible_user_id:'foreman'}]));
 assert.equal(await page.locator('#obligationTasks img').count(),0);assert.equal(await page.evaluate(()=>window.injected),undefined);
 await page.getByText('Отметить прочитанным',{exact:true}).click();await page.waitForFunction(()=>document.querySelector('#obligationNotifications').textContent.includes('Прочитано'));
 assert((await page.locator('#obligationTasks').innerText()).includes('Ожидает подачи'));
 await page.locator('#obligationSettings summary').click();await page.selectOption('#obligationProject','p');
 assert.equal(await page.inputValue('#obligationTime'),'');assert.equal(await page.inputValue('#obligationDay'),'');
 await page.fill('#obligationDay','15');await page.fill('#obligationTime','09:30');await page.selectOption('#obligationShortMonth','last_day');await page.selectOption('#obligationPeriod','-1');await page.fill('#obligationBasis','Поручение владельца');await page.check('#obligationEnabled');await page.click('#obligationSave');
 await page.waitForFunction(()=>document.querySelector('#obligationStatus').textContent.includes('Регламент сохранён'));
 const call=await page.evaluate(()=>calls.find(c=>c.name==='execute_project_settings'));assert.equal(call.args.p_command.config.period_offset,-1);assert.equal(call.args.p_command.config.reminder_time,'09:30');assert.equal(call.args.p_command.config.assignee_id,'foreman');
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth));
 fs.mkdirSync('tests/artifacts',{recursive:true});await page.locator('#obligationModal .sheet').evaluate(e=>e.scrollTop=0);await page.screenshot({path:'tests/artifacts/obligations-mobile.png',fullPage:true});
 await page.locator('[data-project]').click();assert.equal(await page.evaluate(()=>openedProject),'p');
 await page.evaluate(()=>{fixture.can_configure=false;return volumeObligations.open(client,[{id:'p',name:'Объект 1'}]);});
 assert.equal(await page.locator('#obligationSettings').isVisible(),false);
 await page.evaluate(()=>volumeObligations.reset());assert.equal(await page.locator('#obligationModal').isVisible(),false);
 await browser.close();console.log('PASS: mobile UI, escaped data, read without completion, explicit settings, exact RPC payload, foreman settings hidden, task link, logout');
})().catch(e=>{console.error(e);process.exit(1)});

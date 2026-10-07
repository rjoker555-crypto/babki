const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=require('./load-edge.cjs').mainSource();
const id='11111111-1111-4111-8111-111111111111';
async function scenario({auth=true,active=true,owns=true,reserve='reserved',openai=200,key=true,director=false,action=null,content='Оплатили 10000',explanation='Уточните объект.',projectRows=[{id,name:'Объект 1'}],eventRows=[],toolSteps=[],following=[],documentRows=[]}={}) {
 const calls=[];let payload,modelCalls=0;
 const ctx={Response,AbortSignal,TextDecoder,Deno:{env:{get:name=>name==='OPENAI_API_KEY'?(key?'secret':null):name==='AGENT_CHAT_MODEL'?null:'test'}},fetch:async(url,options={})=>{
  calls.push({url,options});
  const json=(value,status=200)=>new Response(JSON.stringify(value),{status});
  if(url.includes('/auth/v1/user'))return json({id:'owner'},auth?200:401);
  if(url.includes('/profiles?'))return json([{is_active:active,role:director?'director':'foreman'}]);
  if(url.includes('/agent_director_access?'))return json(director?[{user_id:'owner'}]:[]);
  if(url.includes('rpc/agent_execute_plan'))return json({status:'completed',result:[{name:'Объект 1'}]});
  if(url.includes('/agent_action_plans?'))return json([{id,action:'read',table_name:'projects'}]);
  if(url.includes('/agent_file_action_plans?')||url.includes('/agent_operator_plans?'))return json([]);
  if(url.endsWith('/agent_action_plans'))return json([{id}]);
  if(url.includes('rpc/agent_prepare_operator_plan')){const b=JSON.parse(options.body);return json({id,revision:id,kind:b.p_kind,command_json:b.p_command,preview_json:b.p_kind==='project_create'?{values:b.p_command}:{before:null,operation:{...b.p_command.values,operation_date:'2026-10-06',payer_company:'ИП'},related:[]}});}
  if(url.includes('rpc/agent_reserve_api_call')||url.includes('rpc/agent_record_api_usage')||url.includes('rpc/agent_project_scope'))return json(true);
  if(url.includes('rpc/'))return json(reserve);
  if(url.includes('/agent_request_runs?'))return json([]);
  if(url==='https://api.openai.com/v1/responses') {payload=JSON.parse(options.body);modelCalls++;const next=toolSteps[modelCalls-1];return json({output:next?[{type:'function_call',call_id:'call-'+modelCalls,name:next.name,arguments:JSON.stringify(next.args)}]:[{type:'message',content:[{type:'output_text',text:JSON.stringify({explanation,instruction_summary:null,action:action?.type==='read'&&modelCalls>1?null:action})}]}],usage:{input_tokens:10,output_tokens:5}},openai);}
  if(url.includes('/project_documents?'))return json(url.includes('&title=ilike.')?[]:documentRows);
  if(url.includes('/project_work_items?'))return json([]);
  if(url.includes('/projects?'))return json(projectRows);
  if(url.includes('/agent_activity_events?'))return json(eventRows);
  if(url.endsWith('/agent_chat_messages'))return json([{id:'answer',...JSON.parse(options.body)}]);
  if(url.includes('/agent_chat_messages?')&&url.includes('created_at=gt.'))return json(following);
  if(url.includes('created_at=lte'))return json([{id,kind:'user',content:'Оплатили 10000',created_at:'2026-10-05T00:00:00Z'}]);
  if(url.includes('/agent_chat_messages?'))return json(owns?[{id,chat_id:id,kind:'user',content,created_at:'2026-10-05T00:00:00Z'}]:[]);
  throw new Error('Unexpected route '+url);
 }};
 vm.createContext(ctx);vm.runInContext(source,ctx);
 const response=await ctx.handle(new Request('https://test',{method:'POST',headers:{Authorization:'Bearer user'},body:JSON.stringify({message_id:id})}));
 return {status:response.status,body:await response.json(),calls,payload};
}
(async()=>{
 for(const options of [{auth:false},{active:false},{owns:false},{reserve:'monthly_limit'},{reserve:'pending'},{reserve:'completed'},{key:false}]) {
  const r=await scenario(options);assert(!r.calls.some(x=>x.url.includes('api.openai.com')));assert(r.body.error);
 }
 const success=await scenario();assert.equal(success.status,200);assert.equal(success.body.message.kind,'assistant');assert.equal(success.payload.store,false);assert.equal(success.payload.max_output_tokens,2000);assert.equal(success.payload.model,'gpt-6-luna');assert(success.payload.tools.some(t=>t.name==='analyze_project'));assert.equal(success.payload.text.format.strict,true);
 const denied=await scenario({openai:403});assert.equal(denied.status,502);assert(denied.body.error.includes('разрешений'));assert(!denied.calls.some(x=>x.url.endsWith('/agent_chat_messages')));
 assert.equal(success.calls.filter(x=>x.url.includes('api.openai.com')).length,1);
 const action={type:'insert',table:'projects',row_id:null,values_json:'{"name":"Новый объект"}',filters_json:'{}'};
 const proposal=await scenario({director:true,action});assert.equal(proposal.status,502);assert(!proposal.calls.some(x=>x.url.endsWith('/agent_action_plans')));assert(!proposal.calls.some(x=>x.url.includes('rpc/agent_execute_plan')));assert(!proposal.calls.some(x=>x.url.includes('/projects?')));
 const unauthorized=await scenario({action});assert.equal(unauthorized.status,502);assert(!unauthorized.calls.some(x=>x.url.endsWith('/agent_action_plans')));
 const reading=await scenario({director:true,action:{...action,type:'read',values_json:'{}'}});assert.equal(reading.status,200);assert(reading.calls.some(x=>x.url.includes('/projects?')));assert(!reading.calls.some(x=>x.url.endsWith('/agent_action_plans')));assert(!reading.calls.some(x=>x.url.includes('rpc/agent_execute_plan')));assert.equal(reading.calls.filter(x=>x.url.includes('api.openai.com')).length,2);
 assert(reading.calls.some(x=>x.url.includes('/agent_chat_messages?')&&x.url.includes('chat_id=eq.'+id)));
 const emptyClaim=await scenario({director:true,action:{...action,type:'read',values_json:'{}'},explanation:'Показываю список объектов из результата чтения приложения.'});assert.equal(emptyClaim.status,200);assert(emptyClaim.body.message.content.includes('Объект 1'));
 const pretending=await scenario({director:true,explanation:'Показываю список объектов из результата чтения приложения.'});assert(pretending.body.message.content.includes('Чтение данных для этого ответа не выполнено'));
 const eight=Array.from({length:8},(_,i)=>({id:String(i),name:'Объект '+(i+1),status:'В работе'}));
 const direct=await scenario({director:true,content:'Покажи мне список объектов.',projectRows:eight,key:false});assert.equal(direct.status,200);for(const row of eight)assert(direct.body.message.content.includes(row.name));assert(!direct.calls.some(x=>x.url.includes('api.openai.com')));assert(!direct.calls.some(x=>x.url.includes('agent_action_plans')));
 const empty=await scenario({director:true,content:'Покажи список объектов',projectRows:[]});assert(empty.body.message.content.includes('не найдено'));
 const partial=await scenario({director:true,content:'Покажи список объектов',projectRows:Array.from({length:31},(_,i)=>({id:String(i),name:'Объект '+i}))});assert(partial.body.message.content.includes('В базе есть ещё записи'));assert(!partial.body.message.content.includes('31 записей'));
 const restricted=await scenario({director:false,content:'Покажи список объектов'});assert(!restricted.calls.some(x=>x.url.includes('/projects?')));
 const confirmed=await scenario({director:true,content:'ПОДТВЕРЖДАЮ '+id});assert.equal(confirmed.status,200);assert(confirmed.calls.some(x=>x.url.includes('rpc/agent_execute_plan')));assert(!confirmed.calls.some(x=>x.url.includes('api.openai.com')));
 const recent=await scenario({director:true,key:false,content:'Так, назови мне два самых последних изменения в объектах.',eventRows:[{project_id:id,project_name:'Объект 2',summary:'Добавлен субподрядчик',actor_name:'Антон',created_at:'2026-10-05T18:00:00Z'}]});
 assert.equal(recent.status,200);assert(recent.body.message.content.includes('Добавлен субподрядчик'));assert(recent.body.message.content.includes('Антон'));assert(recent.body.message.content.includes('Объект 2'));assert(recent.body.message.content.includes('найдено 1 из запрошенных 2'));assert(!recent.calls.some(x=>x.url.includes('api.openai.com')));
 const eventCall=recent.calls.find(x=>x.url.includes('/agent_activity_events?'));assert(eventCall.url.includes('order=created_at.desc,id.desc&limit=2'));assert.equal(eventCall.options.headers.Authorization,'Bearer user');
 const noEvents=await scenario({director:true,content:'Покажи 2 последних изменения в объектах'});assert(noEvents.body.message.content.includes('нет доступных изменений'));
 const compound=await scenario({director:true,content:'Покажи два последних изменения в объектах и добавь объект'});assert(compound.calls.some(x=>x.url.includes('api.openai.com')));
 const notDirector=await scenario({content:'ПОДТВЕРЖДАЮ '+id});assert.equal(notDirector.status,403);assert(!notDirector.calls.some(x=>x.url.includes('rpc/agent_execute_plan')));
 const specialized=await scenario({director:true,toolSteps:[{name:'select_specialization',args:{module:'economics'}},{name:'get_project_context',args:{project_id:id}}]});
 const recovered=await scenario({reserve:'completed',following:[{id:'saved',kind:'assistant',content:'Сохранённый ответ'}]});assert.equal(recovered.status,200);assert.equal(recovered.body.message.id,'saved');assert(!recovered.calls.some(x=>x.url.includes('api.openai.com')));
 const ambiguous=await scenario({reserve:'completed',following:[{id:'next',kind:'user'}]});assert.equal(ambiguous.status,409);assert(!ambiguous.body.message);
 const fallback=await scenario({director:true,documentRows:[{id,title:'Договор',document_type:'contract'}],toolSteps:[{name:'search_company_documents',args:{project_id:id,query:'договор гостиница Новокузнецк 27-2'}}]});const found=JSON.parse(fallback.payload.input.find(x=>x.type==='function_call_output').output);assert.equal(found.documents[0].id,id);assert.equal(found.query_matched,false);assert.equal(found.content_read,false);
 const restrictedFallback=await scenario({documentRows:[{id,title:'Проект',document_type:'project'}],projectRows:[{id,responsible_user_id:'owner'}],toolSteps:[{name:'search_company_documents',args:{project_id:id,query:'проект гостиницы'}}]});assert(restrictedFallback.calls.filter(x=>x.url.includes('/project_documents?')).every(x=>x.url.includes('document_type=eq.project')));
 assert.equal(specialized.status,200);assert(specialized.payload.instructions.includes('Специализация economics'));assert(!specialized.payload.instructions.includes('Специализация pto:'));
 assert(specialized.payload.input.some(i=>i.type==='function_call_output'&&JSON.parse(i.output).project?.id===id));
 const forbiddenTool=await scenario({toolSteps:[{name:'get_financial_metrics',args:{project_id:id}}]});assert.equal(forbiddenTool.status,200);assert(forbiddenTool.payload.input.some(i=>i.type==='function_call_output'&&JSON.parse(i.output).status==='error'));assert(!forbiddenTool.calls.some(x=>x.url.includes('rpc/agent_cash_summary')));
 const maliciousTool=await scenario({director:true,toolSteps:[{name:'get_project_context',args:{project_id:id,owner_id:'other'}}]});assert.equal(maliciousTool.status,200);assert(maliciousTool.payload.input.some(i=>i.type==='function_call_output'&&JSON.parse(i.output).status==='error'));
 const sparsePlan=await scenario({director:true,content:'Мы взяли ЖК Ёлки на три миллиона на ИП, создай карточку',explanation:'Подготовлена карточка.',toolSteps:[{name:'propose_project',args:{values_json:'{"name":"ЖК Ёлки","contractor_company":"ИП","planned_revenue":3000000}'}}]});assert.equal(sparsePlan.status,200);assert(sparsePlan.body.message.content.includes('ЖК Ёлки'));assert(sparsePlan.body.message.content.includes('Договорная сумма'));assert(!sparsePlan.calls.some(x=>x.url.includes('rpc/agent_execute_operator_plan')));
 const incomePlan=await scenario({director:true,content:'Пришло полтинника по ёлкам',explanation:'Подготовлен приход.',toolSteps:[{name:'propose_operation',args:{action:'create',operation_id:null,values_json:'{"operation_type":"income","article":"Аванс заказчика","amount":50000,"project_id":"11111111-1111-4111-8111-111111111111"}',expected_json:'null'}}]});assert.equal(incomePlan.status,200);assert(incomePlan.body.message.content.includes('Добавить операцию'));assert(incomePlan.body.message.content.includes('2026-10-06'));assert(!incomePlan.calls.some(x=>x.url.includes('rpc/agent_execute_operator_plan')));
 console.log('PASS: auth, active profile, message ownership, quotas, duplicate prevention, missing key, server answer, bounded API request, permission failure, no automatic retry');
})().catch(e=>{console.error(e);process.exitCode=1});

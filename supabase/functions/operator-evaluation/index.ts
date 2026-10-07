import { response,rest } from '../_shared/http.ts';
import { coreInstructions } from '../main-agent/modules.ts';
import { schema } from '../main-agent/schema.ts';
import { subjectTools,executeSubjectTool } from '../main-agent/tools.ts';
const id='11111111-1111-4111-8111-111111111111',id2='22222222-2222-4222-8222-222222222222';
const project={id,name:'ЖК Ёлки',contractor_company:'ИП',customer:null,status:'active'};
const old={id:id2,project_id:id,amount:50000,operation_date:'2026-10-05',created_at:'2026-10-06T01:00:00Z',operation_type:'income',article:'Аванс заказчика',payer_company:'ИП',comment:'Не менять',receivable_id:null};
const tests=[
 {name:'create_project',request:'Создай ЖК Сосны на три миллиона на ИП. Реквизиты заполню позже.',amount:3000000,tool:'propose_project'},
 {name:'income_no_date',request:'Пришло пятьдесят тысяч по ЖК Ёлки, это аванс заказчика.',amount:50000,tool:'propose_operation'},
 {name:'amount_decimal',request:'Добавь приход по ЖК Ёлки 13 500,50 рублей как аванс заказчика.',amount:13500.5,tool:'propose_operation'},
 {name:'amount_short',request:'По ЖК Ёлки поступил аванс 1,2 млн руб.',amount:1200000,tool:'propose_operation'},
 {name:'ambiguous_project',request:'Добавь 50 тысяч аванса по объекту Ёлки.',ambiguous:true,tool:null},
 {name:'amount_only',request:'В приходе по ЖК Ёлки от 5 октября на 50 тысяч поставь тринадцать тысяч, остальное оставь.',amount:13000,tool:'propose_operation',action:'update'},
 {name:'delete',request:'Удали приход по ЖК Ёлки от 5 октября на 50 тысяч.',tool:'propose_operation',action:'delete'},
 {name:'last_ambiguous',request:'Измени последнюю приходную операцию по ЖК Ёлки на 13 тысяч.',last:true,tool:null},
 {name:'last_by_date',request:'По ЖК Ёлки в последнем приходе именно по дате операции поставь 13 тысяч, остальное оставь.',last:true,sort:'operation_date',amount:13000,tool:'propose_operation',action:'update'},
 {name:'last_entered',request:'По ЖК Ёлки в последнем внесённом приходе поставь 13 тысяч, остальное оставь.',last:true,sort:'created_at',amount:13000,tool:'propose_operation',action:'update'}
];
const newestDate={...old,id:'33333333-3333-4333-8333-333333333333',operation_date:'2026-10-06',created_at:'2026-10-05T00:00:00Z'};
const allowed=['list_projects','list_operations','get_operation_options','propose_project','propose_operation'];
async function evaluate(run){
 const key=Deno.env.get('OPENAI_API_KEY');if(!key)throw Error('OpenAI key unavailable');
 for(const test of tests.filter(t=>['income_no_date','last_entered'].includes(t.name))){
  let input=[{role:'user',content:test.request}],trace=[],plans=[],usage={input_tokens:0,output_tokens:0},answer='',failure=null;
  const db=async(path,options={},admin=false)=>{
   if(path.startsWith('profiles?'))return [{role:'director',is_active:true}];
   if(path.startsWith('agent_director_access?'))return [{user_id:id}];
   if(path.startsWith('projects?')){const rows=test.ambiguous?[{...project,name:'Ёлки Север'},{...project,id:id2,name:'Ёлки Юг'}]:[project];return path.includes('&id=eq.')?rows.filter(r=>path.includes('&id=eq.'+r.id)):rows;}
   if(path.startsWith('operations?'))return test.last?(path.includes('order=created_at')?[old,newestDate]:[newestDate,old]):[old];
   if(path.startsWith('rpc/agent_prepare_operator_plan')){
    const args=JSON.parse(options.body),command=args.p_command;plans.push(command);
    return {id,revision:id2,kind:args.p_kind,command_json:command,preview_json:args.p_kind==='project_create'?command:{operation:{...command.values,operation_date:command.values.operation_date||'2026-10-06'}},status:'pending'};
   }
   if(/^(receivables|payables|subcontractors|project_materials|project_other_expenses)\?/.test(path))return [];
   throw Error('Fixture rejects non-subject path: '+path);
  };
  try{
   for(let step=0;step<4;step++){
    const outputSchema={type:'object',properties:{explanation:{type:'string'},instruction_summary:{type:['string','null']},action:{anyOf:[{type:'null'},{type:'object',properties:{type:{type:'string',enum:['read','insert','update','delete']},table:{type:'string',enum:Object.keys(schema)},row_id:{type:['string','null']},values_json:{type:'string'},filters_json:{type:'string'}},required:['type','table','row_id','values_json','filters_json'],additionalProperties:false}]}},required:['explanation','instruction_summary','action'],additionalProperties:false};
    const body={model:'gpt-6-luna',service_tier:'default',store:false,reasoning:{effort:'none'},max_output_tokens:2000,instructions:coreInstructions+'\nМестная дата: 2026-10-06 (Asia/Krasnoyarsk). Директорский доступ: true. instruction_summary — краткое описание нового поручения до 300 символов; для вопроса или чтения null.',tools:subjectTools,parallel_tool_calls:false,text:{format:{type:'json_schema',name:'director_plan',strict:true,schema:outputSchema}},input};
    // Input tokens cannot exceed UTF-8 byte count + ample framing allowance.
    // Standard price: $0.10/M input, $0.50/M output; upper bound <= $0.0075.
    const bytes=new TextEncoder().encode(JSON.stringify(body)).length;
    if(bytes>64000)throw Error('Input cap: no paid call');
    if(await rest('rpc/operator_eval_reserve',{method:'POST',body:JSON.stringify({p_run:run})})!==true)throw Error('Hard $0.48 reserve exhausted: no paid call');
    const r=await fetch('https://api.openai.com/v1/responses',{method:'POST',headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});
    if(!r.ok)throw Error('Provider '+r.status+'; no paid retry');const result=await r.json();
    usage.input_tokens+=result.usage?.input_tokens||0;usage.output_tokens+=result.usage?.output_tokens||0;
    input.push(...result.output);const calls=result.output.filter(x=>x.type==='function_call');
    answer=result.output.filter(x=>x.type==='message').flatMap(x=>x.content||[]).filter(x=>x.type==='output_text').map(x=>x.text).join('\n');
    if(!calls.length){try{const structured=JSON.parse(answer);answer=structured.explanation;if(structured.action!==null)failure='Unexpected legacy action instead of subject plan';}catch(e){failure=e.message;}break;}
    for(const call of calls){const args=JSON.parse(call.arguments);trace.push({tool:call.name,args});const value=await executeSubjectTool(call.name,args,{db,owner:id,chat:id,message:id,director:true,modules:new Set()});input.push({type:'function_call_output',call_id:call.call_id,output:JSON.stringify(value)});}
    if(plans.length)break;
   }
  }catch(e){failure=e.message;}
  let passed=!failure;
  const proposal=trace.find(x=>x.tool===test.tool),command=plans[0];
  if(test.tool){passed=passed&&plans.length===1&&!!proposal;
   if(command){const values=test.tool==='propose_project'?command:command.values;
    if(test.amount!==undefined)passed=passed&&(test.tool==='propose_project'?values.planned_revenue===test.amount:values.amount===test.amount);
    if(test.action){passed=passed&&command.action===test.action;if(test.action==='update')passed=passed&&Object.keys(values).length===1&&Object.hasOwn(values,'amount');}
    else if(test.tool==='propose_operation')passed=passed&&command.action==='create'&&values.project_id===id&&!values.receivable_id;
    if(test.sort)passed=passed&&command.id===(test.sort==='created_at'?old.id:newestDate.id);
   }
  }else passed=passed&&plans.length===0&&answer.length>0;
  await rest('rpc/operator_eval_result',{method:'POST',body:JSON.stringify({p_run:run,p_result:{name:test.name,request:test.request,passed,failure,trace,plans,answer,usage,cost_usd:(usage.input_tokens*0.1+usage.output_tokens*0.5)/1000000}})});
 }
 await rest('rpc/operator_eval_result',{method:'POST',body:JSON.stringify({p_run:run,p_finish:true,p_result:{finished:true,financial_writes:0,model:'gpt-6-luna',price_source:'https://developers.openai.com/api/docs/models/gpt-6-luna',reserved_limit_usd:0.48}})});
}
export async function handle(req){
 try{
 if(req.method!=='POST')return response(405,{error:'POST required'});
 const token=req.headers.get('x-worker-token')||'';
 if(!/^[0-9a-f]{64}$/.test(token)||await rest('rpc/agent_check_worker_token',{method:'POST',body:JSON.stringify({p_token:token})})!==true)return response(401,{error:'Worker authentication required'});
 const run=await rest('rpc/operator_eval_claim',{method:'POST',body:'{}'});if(!run)return response(200,{status:'idle'});
 const task=evaluate(run).catch(async e=>{await rest('rpc/operator_eval_result',{method:'POST',body:JSON.stringify({p_run:run,p_finish:true,p_result:{fatal:e.message}})});});
 EdgeRuntime.waitUntil(task);return response(202,{status:'accepted'});
 }catch(e){return response(503,{error:String(e.message).slice(0,300)});}
}
if(import.meta.main)Deno.serve(handle);

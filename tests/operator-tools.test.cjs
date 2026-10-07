const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=require('./load-edge.cjs').mainSource();
const id='11111111-1111-4111-8111-111111111111';
async function scenario(role,name,args){
 const calls=[],ctx={Response,AbortSignal,TextDecoder,TextEncoder,crypto:require('node:crypto').webcrypto,Deno:{env:{get:()=>null}}};
 ctx.db=async(path,options={},admin=false)=>{calls.push({path,options,admin});if(path.startsWith('profiles?'))return [{role,is_active:true}];if(path.startsWith('agent_director_access?'))return role==='director'?[{user_id:id}]:[];if(path==='rpc/agent_prepare_operator_plan')return {id,revision:id,preview_json:{operation:{amount:13000}},status:'pending'};if(path.startsWith('operations?'))return [{id,amount:13000}];throw Error('Unexpected '+path);};
 vm.createContext(ctx);vm.runInContext(source,ctx);ctx.args=args;ctx.tool=name;ctx.owner=id;ctx.director=role==='director';
 let result,error;try{result=await vm.runInContext('executeSubjectTool(tool,args,{db,owner,chat:owner,message:owner,director,modules:new Set()})',ctx);}catch(e){error=e.message;}
 return {result,error,calls};
}
(async()=>{
 const create={action:'create',operation_id:null,values_json:JSON.stringify({operation_type:'income',amount:50000,project_id:id,article:'Аванс заказчика'}),expected_json:'null'};
 for(const role of ['director','finance','accountant']){const r=await scenario(role,'propose_operation',create);assert(!r.error);assert.equal(r.result.execution_confirmed,false);assert.equal(r.result.status,'awaiting_confirmation');const command=JSON.parse(r.calls.at(-1).options.body).p_command;assert.equal(command.values.operation_date,undefined);assert.equal(command.values.receivable_id,undefined);assert(!r.calls.some(x=>/execute/.test(x.path)));}
 for(const role of ['manager','foreman']){const r=await scenario(role,'propose_operation',create);assert.match(r.error,/Financial access denied/);assert(!r.calls.some(x=>x.path.startsWith('rpc/')));}
 const old={id,amount:50000,operation_date:'2026-10-06',counterparty:'Заказчик'};
 const edit=await scenario('director','propose_operation',{action:'update',operation_id:id,values_json:'{"amount":13000}',expected_json:JSON.stringify(old)});const cmd=JSON.parse(edit.calls.at(-1).options.body).p_command;assert.deepEqual(cmd.values,{amount:13000});assert.deepEqual(cmd.expected,old);
 const missing=await scenario('director','propose_operation',{action:'delete',operation_id:id,values_json:'{}',expected_json:'null'});assert.match(missing.error,/Read original/);
 const project=await scenario('director','propose_project',{values_json:'{"name":"ЖК Ёлки","contractor_company":"ИП","planned_revenue":3000000}'});assert(!project.error);assert.deepEqual(Object.keys(JSON.parse(project.calls.at(-1).options.body).p_command).sort(),['contractor_company','name','planned_revenue']);
 assert(!(await scenario('finance','propose_project',{values_json:'{"name":"Ёлки"}'})).error);assert.match((await scenario('foreman','propose_project',{values_json:'{"name":"Ёлки"}'})).error,/Financial access denied/);
 for(const sort of ['created_at','operation_date']){const r=await scenario('finance','list_operations',{project_id:id,operation_type:'income',sort,offset:0});assert(r.calls.at(-1).path.includes('order='+sort+'.desc'));assert.equal(r.calls.at(-1).admin,false);}
 const ctx={Intl,Date,crypto:require('node:crypto').webcrypto,window:{},sbClient:{rpc:async()=>({data:{status:'completed',verified:true}})}};vm.createContext(ctx);vm.runInContext(fs.readFileSync('financial-commands.js','utf8'),ctx);assert.match(ctx.window.financialCommands.today(),/^\d{4}-\d{2}-\d{2}$/);
 let attempts=[],reject=true;ctx.sbClient.rpc=async(_,payload)=>{attempts.push(payload);return reject?{error:{message:'transport failure'}}:{data:{status:'completed',verified:true}};};const change={action:'create',values:{amount:100}};await assert.rejects(ctx.window.financialCommands.execute(change));reject=false;await ctx.window.financialCommands.execute(change);assert.equal(attempts[0].p_request,attempts[1].p_request);await ctx.window.financialCommands.execute(change);assert.notEqual(attempts[1].p_request,attempts[2].p_request);
 console.log('PASS: subject financial role guard, create plans without writes, no invented date/debt, amount-only edit, fresh expected row, sparse project, explicit operation ordering, stable retry receipt');
})().catch(e=>{console.error(e);process.exitCode=1});

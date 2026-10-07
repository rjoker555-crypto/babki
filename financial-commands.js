/* Same atomic financial command for the manual form and agent confirmations. */
window.financialCommands=(()=>{
 let pending=null,busy=false;
 const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Krasnoyarsk',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 async function execute(command){
  if(busy)throw new Error('Эта операция уже сохраняется.');
  const signature=JSON.stringify(command);
  if(!pending||pending.signature!==signature)pending={signature,id:crypto.randomUUID()};
  busy=true;
  try{
   const payload={...command};if(['proposal','project_delete'].includes(command.kind))delete payload.kind;
   const r=await sbClient.rpc(command.kind==='project_delete'?'execute_project_delete':['assignment','responsible','volume_rule'].includes(command.kind)?'execute_project_settings':command.kind==='proposal'?'execute_proposal_command':Object.hasOwn(command,'cost_changes')?'execute_project_card':['work','section','manual_fact','save_template','apply_template','foreman_subcontractor'].includes(command.kind)?'execute_production_command':command.kind?'execute_obligation_command':Object.hasOwn(command,'credit')?'execute_credit_operation':'execute_financial_operation',{p_request:pending.id,p_command:payload});
   if(r.error)throw new Error(r.error.message==='Record changed; create a new approval'?'Операция изменилась в другой сессии. Обновите данные перед сохранением.':r.error.message);
   if(r.data?.status!=='completed'||r.data.verified!==true)throw new Error('Сервер не подтвердил изменение операции.');
   pending=null;return r.data;
  }finally{busy=false;}
 }
 function reset(){pending=null;}
 async function register(kind,action,id,expected,values){
  try{const result=await execute({kind,action,...(action==='create'?{}:{id,expected}),values});return {data:result.record,error:null};}
  catch(e){return {data:null,error:{message:e.message}};}
 }
 async function document(command){
  if(busy)throw new Error('Документ уже сохраняется.');
  const signature=JSON.stringify(command);
  if(!pending||pending.signature!==signature)pending={signature,id:crypto.randomUUID()};
  busy=true;
  try{const r=await sbClient.rpc('execute_document_command',{p_request:pending.id,p_command:command});
   if(r.error)throw new Error(r.error.message);
   if(r.data?.status!=='completed'||!r.data.verified)throw new Error('Сервер не подтвердил документ.');
   pending=null;return r.data;
  }finally{busy=false;}
 }
 return {execute,today,reset,register,document};
})();

/* Atomic volume commands. Keep the request ID after transport errors so retries cannot duplicate facts. */
(function(root){
 'use strict';
 function create(client,randomUUID){
  let pending=null,busy=false;
  return {async execute(payload){
   if(busy)throw new Error('Подача уже сохраняется. Дождитесь результата.');
   const signature=JSON.stringify(payload);
   if(!pending||pending.signature!==signature)pending={signature,id:randomUUID()};
   busy=true;
   try{
    const {data,error}=await client.rpc('submit_work_volumes',{p_request:pending.id,p_payload:payload});
    if(error)throw new Error(error.message);
    if(!data||data.operation!==payload.operation||!data.submission_id||!Array.isArray(data.affected_work_ids)||!Array.isArray(data.items)||!Array.isArray(data.works)||!Array.isArray(data.progress))throw new Error('Сервер вернул неполный результат. Повторите запрос с теми же данными.');
    pending=null;return data;
   }finally{busy=false;}
  }};
 }
 const api={create};if(typeof module==='object'&&module.exports)module.exports=api;else root.workVolumeCommands=api;
})(typeof window==='object'?window:globalThis);

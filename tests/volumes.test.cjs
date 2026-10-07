const assert=require('node:assert/strict'),{create}=require('../volumes.js');
(async()=>{
 const calls=[];let failures=1,next=0;
 const client={rpc:async(name,args)=>{calls.push({name,args});if(failures-->0)return {error:{message:'network timeout'}};return {data:{operation:args.p_payload.operation,submission_id:'sub',affected_work_ids:[],items:[],works:[],progress:[]}};}};
 const api=create(client,()=>`request-${++next}`),payload={operation:'save',items:[{unit_count:2,completed_volume:20}]};
 await assert.rejects(api.execute(payload),/network timeout/);await api.execute(payload);
 assert.equal(calls[0].args.p_request,calls[1].args.p_request);assert.equal(calls[0].name,'submit_work_volumes');
 await api.execute(payload);assert.notEqual(calls[2].args.p_request,calls[1].args.p_request);
 failures=1;await assert.rejects(api.execute(payload));await api.execute({...payload,comment:'changed'});assert.notEqual(calls[3].args.p_request,calls[4].args.p_request);
 let release;const blocked=create({rpc:()=>new Promise(resolve=>release=resolve)},()=> 'busy');const first=blocked.execute(payload);
 await assert.rejects(blocked.execute(payload),/уже сохраняется/);release({data:{operation:'save',submission_id:'sub',affected_work_ids:[],items:[],works:[],progress:[]}});await first;
 const invalid=create({rpc:async()=>({data:{}})},()=> 'invalid');await assert.rejects(invalid.execute(payload),/неполный/);
 console.log('PASS: atomic RPC, stable retry ID, changed payload, double-click protection, incomplete result');
})();

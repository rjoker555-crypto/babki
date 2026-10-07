// Two independent real Auth sessions. Explicit synthetic IDs only. No OpenAI calls.
const fs=require('node:fs'),assert=require('node:assert/strict');
const fixture=JSON.parse(fs.readFileSync('tests/artifacts/realtime-fixture.json','utf8'));
const html=fs.readFileSync('index.html','utf8'),base=html.match(/const SUPABASE_URL='([^']+)'/)[1],key=html.match(/const SUPABASE_PUBLISHABLE_KEY='([^']+)'/)[1];
const wait=ms=>new Promise(r=>setTimeout(r,ms));
async function request(path,token,options={}){const r=await fetch(base+path,{...options,headers:{apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json',...options.headers},signal:AbortSignal.timeout(12000)});const body=await r.json();if(!r.ok)throw Error('HTTP '+r.status+': '+(body.message||body.msg||body.error_description||body.error));return body;}
async function session(name){
 const auth=await request('/auth/v1/token?grant_type=password',key,{method:'POST',body:JSON.stringify({email:fixture.email,password:fixture.password})});assert.equal(auth.user.id,fixture.actor);
 const events=[];const socket=new WebSocket(base.replace('https:','wss:')+'/realtime/v1/websocket?apikey='+encodeURIComponent(key)+'&vsn=1.0.0');
 await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('Socket open timeout')),15000);socket.onopen=()=>{clearTimeout(timer);resolve();};socket.onerror=()=>reject(Error('Socket error'));});
 const topic='realtime:operator-live-'+name;let ref=0;
 await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('Join timeout')),15000);socket.onmessage=e=>{const msg=JSON.parse(e.data);if(msg.event==='phx_reply'&&msg.ref==='1'){clearTimeout(timer);if(msg.payload.status!=='ok')reject(Error('Join failed'));else resolve();}if(msg.event==='postgres_changes')events.push(msg.payload.data);};socket.send(JSON.stringify({topic,event:'phx_join',ref:String(++ref),payload:{config:{broadcast:{self:false},presence:{key:''},postgres_changes:[{event:'*',schema:'public',table:'operations',filter:'created_by=eq.'+fixture.actor}]},access_token:auth.access_token}}));});
 return {token:auth.access_token,events,socket};
}
(async()=>{
 const sessions=[];let operation=null;
 try{
  sessions.push(await session('a'),await session('b'));assert.notEqual(sessions[0].token,sessions[1].token);
  await wait(1000);
  const command={action:'create',values:{operation_type:'income',article:'Аванс заказчика',amount:123.45,project_id:fixture.project}};
  const created=await request('/rest/v1/rpc/execute_financial_operation',sessions[0].token,{method:'POST',body:JSON.stringify({p_request:crypto.randomUUID(),p_command:command})});assert.equal(created.verified,true);operation=created.operation;
  for(let tries=0;tries<20&&!sessions.every(s=>s.events.some(e=>e.type==='INSERT'&&e.record.id===operation.id));tries++)await wait(500);
  assert(sessions.every(s=>s.events.some(e=>e.type==='INSERT'&&e.record.id===operation.id)),'both sessions receive committed INSERT');
  for(const s of sessions){const rows=await request('/rest/v1/operations?select=id,amount&project_id=eq.'+fixture.project,s.token);assert.equal(rows.length,1);assert.equal(rows[0].amount,123.45);}
  const changed=await request('/rest/v1/rpc/execute_financial_operation',sessions[1].token,{method:'POST',body:JSON.stringify({p_request:crypto.randomUUID(),p_command:{action:'update',id:operation.id,expected:operation,values:{amount:67.89}}})});operation=changed.operation;
  for(let tries=0;tries<20&&!sessions.every(s=>s.events.some(e=>e.type==='UPDATE'&&e.record.id===operation.id&&Number(e.record.amount)===67.89));tries++)await wait(500);
  assert(sessions.every(s=>s.events.some(e=>e.type==='UPDATE'&&e.record.id===operation.id&&Number(e.record.amount)===67.89)),'both sessions receive UPDATE');
  for(const s of sessions){const rows=await request('/rest/v1/operations?select=id,amount&project_id=eq.'+fixture.project,s.token);assert.equal(rows[0].amount,67.89);}
  console.log('PASS: two simultaneously open real Auth/WebSocket sessions receive INSERT/UPDATE and reread 123.45 → 67.89; isolated RPC only, no paid calls');
 }finally{
  if(operation&&sessions[0])await request('/rest/v1/rpc/execute_financial_operation',sessions[0].token,{method:'POST',body:JSON.stringify({p_request:crypto.randomUUID(),p_command:{action:'delete',id:operation.id,expected:operation,values:{}}})});
  for(const s of sessions)s.socket.close();
 }
})().catch(e=>{console.error(e.name+': '+e.message);process.exitCode=1});

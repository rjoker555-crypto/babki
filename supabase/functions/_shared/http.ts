export const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
export function response(status,body){return new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});}
export async function rest(path,options={}){
 const url=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 const r=await fetch(url+'/rest/v1/'+path,{...options,headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json',Prefer:'return=representation',...options.headers},signal:AbortSignal.timeout(15000)});
 if(!r.ok){let e;try{e=await r.json();}catch{}throw new Error(e?.message||'Database operation failed');}return r.status===204?null:r.json();
}
export async function authenticated(req){
 const authorization=req.headers.get('authorization')||'';if(!authorization.startsWith('Bearer '))throw new Error('Войдите в приложение.');
 const r=await fetch(Deno.env.get('SUPABASE_URL')+'/auth/v1/user',{headers:{apikey:Deno.env.get('SUPABASE_ANON_KEY'),Authorization:authorization},signal:AbortSignal.timeout(10000)});
 if(!r.ok)throw new Error('Сессия истекла.');const user=await r.json();
 const rows=await rest('profiles?select=id,role,is_active&id=eq.'+user.id);if(!rows[0]?.is_active)throw new Error('Доступ отключён.');return rows[0];
}
export async function storage(path,options={}){
 const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');const r=await fetch(Deno.env.get('SUPABASE_URL')+'/storage/v1/'+path,{...options,headers:{apikey:key,Authorization:'Bearer '+key,...options.headers},signal:AbortSignal.timeout(20000)});
 if(!r.ok)throw new Error('Не удалось обработать файл в закрытом хранилище.');return r;
}
export const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
export async function cleanupDocumentFiles(owner,request){
 const job=await rest('rpc/agent_document_cleanup',{method:'POST',body:JSON.stringify({p_owner:owner,p_request:request})});
 if(job.status==='completed')return job;
 const outcomes=[];
 for(const item of job.items){
  if(!['project-documents','agent-files'].includes(item.bucket)||typeof item.path!=='string'||item.path.split('/').some(p=>!p||p==='.'||p==='..')||/[\\\x00-\x1f]/.test(item.path))throw Error('Некорректный согласованный путь удаления.');
  if(item.remove_allowed)await storage('object/'+item.bucket,{method:'DELETE',headers:{'Content-Type':'application/json'},body:JSON.stringify({prefixes:[item.path]})});
  outcomes.push({...item,status:item.remove_allowed?'removed':'retained'});
 }
 return rest('rpc/agent_document_cleanup',{method:'POST',body:JSON.stringify({p_owner:owner,p_request:request,p_outcomes:outcomes})});
}
export async function sha256(bytes){const digest=await crypto.subtle.digest('SHA-256',bytes);return Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,'0')).join('');}
export async function boundedBytes(req,max){
 const reader=req.body?.getReader();if(!reader)throw new Error('Пустой запрос.');const chunks=[];let size=0;
 try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>max)throw new Error('Размер файла превышает лимит 8 МБ.');chunks.push(value);}}
 finally{await reader.cancel();}
 const all=new Uint8Array(size);let at=0;for(const c of chunks){all.set(c,at);at+=c.length;}return all;
}

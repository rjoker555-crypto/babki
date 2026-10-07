import { PDFDocument } from 'npm:pdf-lib@1.17.1';
import { cors,response,authenticated,rest,storage,uuid,sha256,boundedBytes,cleanupDocumentFiles } from '../_shared/http.ts';
import { validateOfficeFile } from '../_shared/office-file.ts';
export async function handle(req){
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});if(req.method!=='POST')return response(405,{error:'POST required'});
 let actor;try{actor=await authenticated(req);}catch(e){return response(401,{error:e.message});}
 try{
  if((req.headers.get('content-type')||'').startsWith('application/json')){
   const body=JSON.parse(new TextDecoder().decode(await boundedBytes(req,4096)));
   if(body.operation==='list'&&uuid(body.chat_id)){return response(200,{files:await rest('rpc/agent_list_chat_files',{method:'POST',body:JSON.stringify({p_owner:actor.id,p_chat:body.chat_id})})});}
   if(body.operation==='cleanup_document'&&uuid(body.request_id))return response(200,{cleanup:await cleanupDocumentFiles(actor.id,body.request_id)});
   if(body.operation==='delete_report'&&uuid(body.report_id)){
    const rows=await rest('agent_report_assets?select=*&id=eq.'+body.report_id+'&owner_id=eq.'+actor.id);if(rows.length!==1)return response(404,{error:'Own report not found'});
    const asset=rows[0];if(asset.file_path){if(asset.file_path!==actor.id+'/'+asset.id+(asset.kind==='statement_text'?'.txt':'.html'))throw new Error('Invalid report path');await storage('object/operator-reports',{method:'DELETE',headers:{'Content-Type':'application/json'},body:JSON.stringify({prefixes:[asset.file_path]})});}
    await rest('agent_report_assets?id=eq.'+asset.id+'&owner_id=eq.'+actor.id,{method:'DELETE'});return response(200,{report_id:asset.id,removed:true,verified:true});
   }
   if(body.operation!=='download'||!uuid(body.file_id))return response(400,{error:'Invalid download request'});
   const assets=await rest('agent_file_assets?select=*&id=eq.'+body.file_id);const asset=assets[0];if(!asset)return response(404,{error:'File not found'});
   if(asset.owner_id!==actor.id){
    const versions=await rest('project_document_versions?select=document_id&storage_bucket=eq.agent-files&file_path=eq.'+encodeURIComponent(asset.storage_path));
    const direct=await rest('project_documents?select=id,project_id,document_type&storage_bucket=eq.agent-files&file_path=eq.'+encodeURIComponent(asset.storage_path));
    const docs=[...direct];for(const v of versions)if(!docs.some(d=>d.id===v.document_id))docs.push(...await rest('project_documents?select=id,project_id,document_type&id=eq.'+v.document_id));
    const access=actor.role==='director'?await rest('agent_director_access?select=user_id&user_id=eq.'+actor.id):[];
    const proposals=await rest('commercial_proposals?select=id&letter_storage_bucket=eq.agent-files&letter_file_path=eq.'+encodeURIComponent(asset.storage_path));
    let allowed=access.length===1&&(docs.length>0||proposals.length>0)||proposals.length>0&&['finance','accountant','manager'].includes(actor.role);
    if(!allowed){for(const doc of docs){if((actor.role==='manager'||actor.role==='foreman'&&doc.document_type==='project')&&await rest('rpc/agent_project_scope',{method:'POST',body:JSON.stringify({p_owner:actor.id,p_project:doc.project_id})})===true)allowed=true;}}
    if(!allowed)return response(403,{error:'File access denied'});
   }
   const signed=await (await storage('object/sign/agent-files/'+asset.storage_path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({expiresIn:60})})).json();
   return response(200,{url:Deno.env.get('SUPABASE_URL')+'/storage/v1'+signed.signedURL,file_name:asset.file_name,mime_type:asset.mime_type});
  }
  const bytes=await boundedBytes(req,8*1024*1024+65536);
  const form=await new Request(req.url,{method:'POST',headers:req.headers,body:bytes}).formData();
  const file=form.get('file'),chat=form.get('chat_id'),id=form.get('file_id');if(!(file instanceof File)||!uuid(chat)||!uuid(id))return response(400,{error:'File, own chat and file ID required'});
  if(file.size<1||file.size>8388608||file.name.length>200)return response(413,{error:'Файл должен быть от 1 байта до 8 МБ, имя до 200 символов.'});
  const chats=await rest('agent_conversations?select=id&id=eq.'+chat+'&owner_id=eq.'+actor.id);if(chats.length!==1)return response(403,{error:'Own live chat required'});
  const content=new Uint8Array(await file.arrayBuffer());let mime,pages=null;
  if(file.name.toLowerCase().endsWith('.pdf')&&new TextDecoder().decode(content.slice(0,5))==='%PDF-'){
   mime='application/pdf';let pdf;try{pdf=await PDFDocument.load(content,{updateMetadata:false});}catch{throw new Error('PDF повреждён или защищён. Пришлите незашифрованный экспорт.');}
   pages=pdf.getPageCount();if(pages<1||pages>40)return response(413,{error:'Для проверяемого разбора разделите проект на PDF до 40 страниц каждый.'});
  }else if(file.name.toLowerCase().endsWith('.txt')){
   const text=new TextDecoder('utf-8',{fatal:true}).decode(content);if(text.includes('\0')||text.length>120000)throw new Error('TXT должен быть UTF-8 без двоичных данных, до 120000 символов.');mime='text/plain';
  }else if(/\.(docx|xlsx)$/i.test(file.name)){
   const ext=file.name.toLowerCase().split('.').pop();validateOfficeFile(content,ext);
   mime=ext==='docx'?'application/vnd.openxmlformats-officedocument.wordprocessingml.document':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }else return response(415,{error:'Для чата доступны PDF, UTF-8 TXT, DOCX и XLSX до 8 МБ. DOC/CAD/XLS экспортируйте в один из этих форматов либо загрузите готовый файл через карточку документа. Редактирование исходного формата не выполняется.'});
  const hash=await sha256(content);const old=await rest('agent_file_assets?select=*&id=eq.'+id+'&owner_id=eq.'+actor.id);
  if(old.length){if(old[0].sha256!==hash||old[0].chat_id!==chat)throw new Error('ID файла уже использован для других данных.');return response(200,{file:old[0]});}
  const count=await rest('agent_file_assets?select=file_size&owner_id=eq.'+actor.id+'&order=created_at.desc&limit=101');
  if(count.length>=100||count.reduce((sum,x)=>sum+Number(x.file_size),0)+file.size>100*1024*1024)return response(429,{error:'Лимит черновых файлов: 100 файлов / 100 МБ на аккаунт. Автоматического удаления нет.'});
  const path=actor.id+'/'+id+'.'+file.name.toLowerCase().split('.').pop();
  try{await storage('object/agent-files/'+path,{method:'POST',headers:{'Content-Type':mime,'x-upsert':'false'},body:content});}
  catch(error){const existing=new Uint8Array(await (await storage('object/agent-files/'+path)).arrayBuffer());if(await sha256(existing)!==hash)throw error;}
  try{
   const rows=await rest('agent_file_assets',{method:'POST',body:JSON.stringify({id,owner_id:actor.id,chat_id:chat,file_name:file.name,storage_path:path,mime_type:mime,file_size:file.size,sha256:hash,page_count:pages})});
   return response(200,{file:rows[0]});
  }catch(error){try{await storage('object/agent-files',{method:'DELETE',headers:{'Content-Type':'application/json'},body:JSON.stringify({prefixes:[path]})});}catch{}throw error;}
 }catch(e){return response(400,{error:e.message||'File processing failed'});}
}
if(import.meta.main)Deno.serve(handle);

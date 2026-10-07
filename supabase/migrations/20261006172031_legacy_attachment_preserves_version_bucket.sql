CREATE OR REPLACE FUNCTION public.agent_execute_file_action(p_owner uuid, p_plan uuid, p_message uuid, p_cancel boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare plan public.agent_file_action_plans; asset public.agent_file_assets; project uuid; doc uuid;
begin
 if not exists(select 1 from public.agent_director_access a join public.profiles p on p.id=a.user_id where a.user_id=p_owner and p.role='director' and p.is_active) then raise exception 'Trusted director required'; end if;
 select * into plan from public.agent_file_action_plans where id=p_plan and owner_id=p_owner for update;
 if not found then raise exception 'Plan not found'; end if;
 if not exists(select 1 from public.agent_chat_messages where id=p_message and owner_id=p_owner and chat_id=plan.chat_id and kind='user'
  and content=(case when p_cancel then 'ОТМЕНЯЮ ' else 'ПОДТВЕРЖДАЮ ' end)||p_plan::text) then raise exception 'Exact confirmation in own thread required'; end if;
 if plan.status<>'pending' then return jsonb_build_object('status',plan.status,'result',plan.result_json); end if;
 if p_cancel then update public.agent_file_action_plans set status='cancelled' where id=p_plan;return '{"status":"cancelled"}'::jsonb;end if;
 if plan.expires_at<now() then raise exception 'Plan expired'; end if;
 select * into asset from public.agent_file_assets where id=plan.file_id and owner_id=p_owner;
 if not found or asset.sha256<>plan.file_sha256 then raise exception 'Source file changed'; end if;
 if plan.kind='create_project' then
  insert into public.projects(name,customer,status) values(plan.values_json->>'name',plan.values_json->>'customer','planned') returning id into project;
 else project:=(plan.values_json->>'project_id')::uuid;
 end if;
 select document_id into doc from public.agent_file_project_links where file_id=asset.id and project_id=project;
 if doc is null then
  insert into public.project_documents(project_id,document_type,title,file_name,file_path,mime_type,file_size,version_no,is_current,uploaded_by,storage_bucket)
   values(project,'project',asset.file_name,asset.file_name,asset.storage_path,asset.mime_type,asset.file_size,1,true,p_owner,'agent-files') returning id into doc;
  insert into public.project_document_versions(document_id,version_no,file_name,file_path,mime_type,file_size,uploaded_by,storage_bucket)
   values(doc,1,asset.file_name,asset.storage_path,asset.mime_type,asset.file_size,p_owner,'agent-files');
  insert into public.agent_file_project_links(file_id,project_id,document_id) values(asset.id,project,doc);
 end if;
 update public.agent_file_action_plans set status='completed',result_json=jsonb_build_object('project_id',project,'document_id',doc,'file_id',asset.id) where id=p_plan returning * into plan;
 return jsonb_build_object('status','completed','result',plan.result_json);
end $function$


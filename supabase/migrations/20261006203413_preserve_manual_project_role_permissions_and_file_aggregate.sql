-- Atomic, explicitly approved aggregate deletion. Global counterparties and personal files survive.
create or replace function voltmaster_private.project_delete_snapshot(p_project uuid) returns jsonb language plpgsql set search_path='' as $$
declare result jsonb; rows jsonb;t text;files jsonb;
begin
 select jsonb_build_object('project',to_jsonb(p)) into result from public.projects p where id=p_project;if result is null then raise exception 'Project not found';end if;
 foreach t in array array['operations','receivables','payables','subcontractors','project_materials','project_other_expenses','pto_documents','project_customer_contacts','project_work_tasks','project_documents','project_price_history','project_work_items','project_work_sections','project_work_section_templates','work_volume_submissions','project_team_members','project_subcontractors','agent_file_project_links'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),''[]'') from public.%I x where project_id=$1',t) into rows using p_project;
  if jsonb_array_length(rows)>20000 then raise exception 'Project deletion too large: %',t;end if;result:=result||jsonb_build_object(t,rows);
 end loop;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into rows from public.project_document_versions x join public.project_documents d on d.id=x.document_id where d.project_id=p_project;result:=result||jsonb_build_object('project_document_versions',rows);
 foreach t in array array['project_work_materials','project_work_progress'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(x) order by x.id),''[]'') from public.%I x join public.project_work_items w on w.id=x.work_item_id where w.project_id=$1',t) into rows using p_project;result:=result||jsonb_build_object(t,rows);
 end loop;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into rows from public.work_volume_submission_items x join public.work_volume_submissions s on s.id=x.submission_id where s.project_id=p_project;result:=result||jsonb_build_object('work_volume_submission_items',rows);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into rows from public.project_work_section_template_items x join public.project_work_section_templates s on s.id=x.template_id where s.project_id=p_project;result:=result||jsonb_build_object('template_items',rows);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into rows from public.project_work_section_template_materials x join public.project_work_section_template_items i on i.id=x.template_item_id join public.project_work_section_templates s on s.id=i.template_id where s.project_id=p_project;result:=result||jsonb_build_object('template_materials',rows);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into rows from voltmaster_private.volume_rules x where project_id=p_project;result:=result||jsonb_build_object('rules',rows);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into rows from voltmaster_private.volume_obligations x where project_id=p_project;result:=result||jsonb_build_object('obligations',rows);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into rows from public.in_app_notifications x join voltmaster_private.volume_obligations o on o.id=x.obligation_id where o.project_id=p_project;result:=result||jsonb_build_object('notifications',rows);
 select coalesce(jsonb_agg(jsonb_build_object('bucket',f.b,'path',f.p,'remove_allowed',not(exists(select 1 from public.project_documents d where d.project_id<>p_project and d.storage_bucket=f.b and d.file_path=f.p) or exists(select 1 from public.project_document_versions v join public.project_documents d on d.id=v.document_id where d.project_id<>p_project and v.storage_bucket=f.b and v.file_path=f.p) or exists(select 1 from public.commercial_proposals k where k.letter_storage_bucket=f.b and k.letter_file_path=f.p) or f.b='agent-files' and exists(select 1 from public.agent_file_assets a where a.storage_path=f.p))) order by f.b,f.p),'[]') into files from (select d.storage_bucket b,d.file_path p from public.project_documents d where d.project_id=p_project and d.file_path is not null union select v.storage_bucket,v.file_path from public.project_document_versions v join public.project_documents d on d.id=v.document_id where d.project_id=p_project and v.file_path is not null) f;
 return result||jsonb_build_object('files',files);
end $$;
revoke all on function voltmaster_private.project_delete_snapshot(uuid) from public,anon,authenticated;
create or replace function voltmaster_private.project_delete_command(p_owner uuid,p_request uuid,p_command jsonb,p_preview boolean default false) returns jsonb language plpgsql set search_path='' as $$
declare pid uuid:=(p_command->>'project_id')::uuid;snapshot jsonb;result jsonb;stored jsonb;r jsonb;o jsonb;credit jsonb;doc jsonb;jobs jsonb:='[]';counts jsonb;request uuid;t text;
begin
 if not exists(select 1 from public.profiles where id=p_owner and role in ('director','finance','accountant') and is_active) then raise exception 'Financial access denied';end if;perform voltmaster_private.assert_operator_actor(p_owner);
 if p_request is null or pid is null or p_command->>'action' is distinct from 'delete' or exists(select 1 from jsonb_object_keys(p_command) k where k not in ('action','project_id','expected','expected_snapshot')) then raise exception 'Invalid aggregate deletion command';end if;
 perform pg_advisory_xact_lock(hashtextextended('voltmaster.financial.commands',0));
 if not p_preview then
  select result_json,command_json into result,stored from voltmaster_private.financial_command_receipts where owner_id=p_owner and request_id=p_request;
  if found then if stored is distinct from p_command then raise exception 'Request reused with different command';end if;return result;end if;
  -- Older published forms can still write directly. Hold all affected source tables through commit.
  lock table public.projects,public.operations,public.receivables,public.payables,public.subcontractors,public.project_materials,public.project_other_expenses,public.pto_documents,public.project_customer_contacts,public.project_work_tasks,public.project_documents,public.project_document_versions,public.project_price_history,public.project_work_items,public.project_work_sections,public.project_work_materials,public.project_work_progress,public.project_work_section_templates,public.project_work_section_template_items,public.project_work_section_template_materials,public.work_volume_submissions,public.work_volume_submission_items,public.project_team_members,public.project_subcontractors,public.agent_file_project_links,public.commercial_proposals,public.agent_file_assets,public.in_app_notifications,voltmaster_private.volume_rules,voltmaster_private.volume_obligations in share row exclusive mode;
 end if;
 snapshot:=voltmaster_private.project_delete_snapshot(pid);
 if snapshot->'project' is distinct from p_command->'expected' then raise exception 'Project changed; reload';end if;
 if exists(select 1 from public.operations o where o.project_id is distinct from pid and (o.receivable_id in(select id from public.receivables where project_id=pid) or o.payable_id in(select id from public.payables where project_id=pid) or o.subcontractor_id in(select id from public.subcontractors where project_id=pid) or o.cost_item_id in(select id from public.project_materials where project_id=pid union all select id from public.project_other_expenses where project_id=pid))) then raise exception 'Other project operations reference this project; unlink explicitly first';end if;
 select jsonb_object_agg(key,jsonb_array_length(value)) into counts from jsonb_each(snapshot) where jsonb_typeof(value)='array';
 snapshot:=snapshot||jsonb_build_object('counts',counts,'personal_files_preserved',true);
 if p_preview then return snapshot;end if;
 if snapshot is distinct from p_command->'expected_snapshot' then raise exception 'Project contents changed; create a new approval';end if;
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 -- Delete payments first, with the same recalculation used by individual manual operations.
 for o in select to_jsonb(x) from public.operations x where project_id=pid and not(operation_type='credit' or article='ТМЦ' and credit_kind='material') order by id loop
  perform voltmaster_private.financial_command(p_owner,gen_random_uuid(),jsonb_build_object('action','delete','id',o->>'id','expected',o,'values','{}'::jsonb),false);
 end loop;
 for o in select to_jsonb(x) from public.operations x where project_id=pid and (operation_type='credit' or article='ТМЦ' and credit_kind='material') order by id loop
  select to_jsonb(p) into credit from public.payables p where id=(o->>'payable_id')::uuid;
  perform voltmaster_private.credit_command(p_owner,gen_random_uuid(),jsonb_build_object('action','delete','id',o->>'id','expected',o,'expected_credit',credit,'values','{}'::jsonb,'credit','null'::jsonb),false);
 end loop;
 if jsonb_array_length(snapshot->'files')>0 then insert into voltmaster_private.document_cleanup_jobs(owner_id,request_id,document_id,items,domain) values(p_owner,p_request,pid,snapshot->'files','project');jobs:=jsonb_build_array(p_request);end if;
 delete from public.in_app_notifications where obligation_id in(select id from voltmaster_private.volume_obligations where project_id=pid);
 delete from voltmaster_private.volume_obligations where project_id=pid;delete from voltmaster_private.volume_rules where project_id=pid;
 delete from public.project_team_members where project_id=pid;delete from public.receivables where project_id=pid;delete from public.payables where project_id=pid;
 delete from public.projects where id=pid;
 if exists(select 1 from public.projects where id=pid) then raise exception 'Aggregate deletion verification failed';end if;
 result:=jsonb_build_object('status','completed','kind','project_delete','action','delete','project_id',pid,'project_name',snapshot->'project'->>'name','deleted_counts',counts,'cleanup_requests',jobs,'file_cleanup_pending',jsonb_array_length(jobs)>0,'verified',true);
 insert into voltmaster_private.financial_command_receipts values(p_owner,p_request,p_command,result,now());return result;
end $$;
revoke all on function voltmaster_private.project_delete_command(uuid,uuid,jsonb,boolean) from public,anon,authenticated;grant execute on function voltmaster_private.project_delete_command(uuid,uuid,jsonb,boolean) to service_role;
create or replace function public.execute_project_delete(p_request uuid,p_command jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.project_delete_command(auth.uid(),p_request,p_command,false);end $$;
revoke all on function public.execute_project_delete(uuid,jsonb) from public,anon;grant execute on function public.execute_project_delete(uuid,jsonb) to authenticated;
create or replace function public.preview_project_delete(p_command jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.project_delete_command(auth.uid(),gen_random_uuid(),p_command,true);end $$;
revoke all on function public.preview_project_delete(jsonb) from public,anon;grant execute on function public.preview_project_delete(jsonb) to authenticated;



-- Agent adapter reuses the existing manual atomic volume command verbatim.
create or replace function voltmaster_private.volume_plan_preview(p_owner uuid,p_payload jsonb)
returns jsonb language plpgsql set search_path='' as $$
declare project uuid:=(p_payload->>'project_id')::uuid; sid uuid:=(p_payload->>'submission_id')::uuid; workids uuid[]; snapshot jsonb;
begin
 if not exists(select 1 from public.profiles where id=p_owner and is_active) then raise exception 'Active account required';end if;
 if not exists(select 1 from public.projects p where p.id=project and (p.responsible_user_id=p_owner or exists(select 1 from public.project_team_members m where m.project_id=p.id and m.user_id=p_owner and m.is_active) or exists(select 1 from public.agent_director_access a join public.profiles u on u.id=a.user_id where a.user_id=p_owner and u.role='director' and u.is_active))) then raise exception 'Project access denied';end if;
 perform 1 from public.projects where id=project for update;
 select array_agg(distinct id order by id) into workids from (
  select work_item_id as id from public.work_volume_submission_items where submission_id=sid
  union select (e->>'work_item_id')::uuid from jsonb_array_elements(case when p_payload->>'operation'='save' then p_payload->'items' else '[]'::jsonb end) e
 ) x;
 perform 1 from public.project_work_items where id=any(workids) order by id for update;
 snapshot:=jsonb_build_object('payload',p_payload,'submission',(select to_jsonb(x) from public.work_volume_submissions x where id=sid),'items',coalesce((select jsonb_agg(to_jsonb(x) order by id) from public.work_volume_submission_items x where submission_id=sid),'[]'::jsonb),'works',coalesce((select jsonb_agg(to_jsonb(x) order by id) from public.project_work_items x where id=any(workids)),'[]'::jsonb),'progress',coalesce((select jsonb_agg(to_jsonb(x) order by id) from public.project_work_progress x where work_item_id=any(workids)),'[]'::jsonb));
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 -- Validate using the exact atomic command in a rollback-only savepoint. Its tables,
 -- receipts, audit records and notifications all roll back; no network/model call.
 begin
  perform voltmaster_private.volume_command(gen_random_uuid(),p_payload);
  raise exception using errcode='P0993',message='ROLLBACK_VOLUME_PREVIEW';
 exception when sqlstate 'P0993' then null;end;
 return snapshot;
end $$;
revoke all on function voltmaster_private.volume_plan_preview(uuid,jsonb) from public,anon,authenticated;
grant execute on function voltmaster_private.volume_plan_preview(uuid,jsonb) to service_role;
alter table public.agent_operator_plans drop constraint if exists agent_operator_plans_kind_check;
alter table public.agent_operator_plans add constraint agent_operator_plans_kind_check check(kind in ('operation_write','project_create','credit_write','obligation_write','project_card_write','volume_write'));

create or replace function public.agent_prepare_operator_plan(p_owner uuid,p_chat uuid,p_request uuid,p_kind text,p_command jsonb)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare preview jsonb; p public.agent_operator_plans; k text; v jsonb;
begin
 if not exists(select 1 from public.agent_chat_messages where id=p_request and chat_id=p_chat and owner_id=p_owner and kind='user') then raise exception 'Own user request required';end if;
 select * into p from public.agent_operator_plans where owner_id=p_owner and request_id=p_request and kind=p_kind;
 if found then
  if p_kind in ('operation_write','credit_write') and p_command->>'action'='create' then p_command:=jsonb_set(p_command,'{values}',p_command->'values'||jsonb_build_object('operation_date',coalesce(p_command->'values'->'operation_date',p.command_json->'values'->'operation_date'),'payer_company',coalesce(p_command->'values'->'payer_company',p.command_json->'values'->'payer_company')));end if;
  if p.command_json is distinct from p_command then raise exception 'Existing proposal differs; send a new request';end if;return to_jsonb(p);
 end if;
 if p_kind='volume_write' then
  preview:=voltmaster_private.volume_plan_preview(p_owner,p_command);
 elsif p_kind='project_card_write' then
  if not exists(select 1 from public.agent_director_access a join public.profiles u on u.id=a.user_id where u.id=p_owner and u.role='director' and u.is_active) then raise exception 'Trusted director required';end if;
  preview:=voltmaster_private.project_card_command(p_owner,p_request,p_command,true);
 elsif p_kind='obligation_write' then
  preview:=voltmaster_private.obligation_command(p_owner,p_request,p_command,true);
 elsif p_kind='credit_write' then
  preview:=voltmaster_private.credit_command(p_owner,p_request,p_command,true);
  if p_command->>'action'='create' then p_command:=jsonb_set(p_command,'{values}',p_command->'values'||jsonb_build_object('operation_date',preview->'operation'->'operation_date','payer_company',preview->'operation'->'payer_company'));end if;
 elsif p_kind='operation_write' then
  preview:=voltmaster_private.financial_command(p_owner,p_request,p_command,true);
  -- Freeze the local date and derived organization at preparation, never at confirmation.
  if p_command->>'action'='create' then p_command:=jsonb_set(p_command,'{values}',p_command->'values'||jsonb_build_object('operation_date',preview->'operation'->'operation_date','payer_company',preview->'operation'->'payer_company'));end if;
 elsif p_kind='project_create' then
  if not exists(select 1 from public.agent_director_access a join public.profiles u on u.id=a.user_id where u.id=p_owner and u.is_active and u.role='director') then raise exception 'Trusted director required';end if;
  v:=p_command;
  if jsonb_typeof(v)<>'object' or nullif(btrim(v->>'name'),'') is null or length(v->>'name')>500 then raise exception 'Project name required';end if;
  for k in select jsonb_object_keys(v) loop if k not in ('name','contractor_company','planned_revenue','customer','contract_number','contract_date','start_date','end_date','comment','status') then raise exception 'Unsupported project field';end if;end loop;
  if v ? 'contractor_company' and v->>'contractor_company' not in ('ООО','ИП') then raise exception 'Invalid company';end if;
  if v ? 'planned_revenue' and ((v->>'planned_revenue')::numeric<0 or (v->>'planned_revenue')::numeric::text in ('NaN','Infinity','-Infinity')) then raise exception 'Invalid contract amount';end if;
  if exists(select 1 from public.projects where lower(replace(btrim(name),'ё','е'))=lower(replace(btrim(v->>'name'),'ё','е'))) then raise exception 'Possible duplicate project; inspect existing card';end if;
  preview:=jsonb_build_object('values',v,'meaning','planned_revenue is the contract amount used by the existing project card; no income operation is created');
 else raise exception 'Unsupported operator command';end if;
 insert into public.agent_operator_plans(owner_id,chat_id,request_id,kind,command_json,preview_json) values(p_owner,p_chat,p_request,p_kind,p_command,preview) returning * into p;
 return to_jsonb(p);
end $fn$;
revoke all on function public.agent_prepare_operator_plan(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.agent_prepare_operator_plan(uuid,uuid,uuid,text,jsonb) to service_role;

create or replace function public.agent_execute_operator_plan(p_owner uuid,p_plan uuid,p_revision uuid,p_message uuid,p_cancel boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare p public.agent_operator_plans; check_preview jsonb; result jsonb; pr public.projects; k text; cols text; vals text;
begin
 select * into p from public.agent_operator_plans where id=p_plan and owner_id=p_owner for update;
 if not found or p.revision is distinct from p_revision then raise exception 'Plan version mismatch';end if;
 if not exists(select 1 from public.profiles where id=p_owner and is_active and (p.kind='volume_write' or role in ('director','finance','accountant'))) then raise exception 'Operator access denied';end if;
 if p.kind in ('project_create','project_card_write') and not exists(select 1 from public.agent_director_access a join public.profiles u on u.id=a.user_id where u.id=p_owner and u.role='director' and u.is_active) then raise exception 'Trusted director required';end if;
 if not exists(select 1 from public.agent_chat_messages where id=p_message and owner_id=p_owner and chat_id=p.chat_id and kind='user' and content=(case when p_cancel then 'ОТМЕНЯЮ ' else 'ПОДТВЕРЖДАЮ ' end)||p.id::text) then raise exception 'Exact chat confirmation required';end if;
 if p.status<>'pending' then return jsonb_build_object('status',p.status,'result',p.result_json);end if;
 if p.expires_at<now() then raise exception 'Plan expired';end if;
 if p_cancel then update public.agent_operator_plans set status='cancelled' where id=p.id;return jsonb_build_object('status','cancelled');end if;
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 if p.kind='volume_write' then
  check_preview:=voltmaster_private.volume_plan_preview(p_owner,p.command_json);
  if check_preview is distinct from p.preview_json then raise exception 'Record changed; create a new approval';end if;
  result:=voltmaster_private.volume_command(p.id,p.command_json);
  result:=result||jsonb_build_object('verified',true);
 elsif p.kind='project_card_write' then
  check_preview:=voltmaster_private.project_card_command(p_owner,p.id,p.command_json,true);
  if check_preview is distinct from p.preview_json then raise exception 'Record changed; create a new approval';end if;
  result:=voltmaster_private.project_card_command(p_owner,p.id,p.command_json,false);
 elsif p.kind='obligation_write' then
  check_preview:=voltmaster_private.obligation_command(p_owner,p.id,p.command_json,true);
  if check_preview is distinct from p.preview_json then raise exception 'Record changed; create a new approval';end if;
  result:=voltmaster_private.obligation_command(p_owner,p.id,p.command_json,false);
 elsif p.kind='credit_write' then
  check_preview:=voltmaster_private.credit_command(p_owner,p.id,p.command_json,true);
  if check_preview is distinct from p.preview_json then raise exception 'Record changed; create a new approval';end if;
  result:=voltmaster_private.credit_command(p_owner,p.id,p.command_json,false);
 elsif p.kind='operation_write' then
  check_preview:=voltmaster_private.financial_command(p_owner,p.id,p.command_json,true);
  if check_preview is distinct from p.preview_json then raise exception 'Record changed; create a new approval';end if;
  result:=voltmaster_private.financial_command(p_owner,p.id,p.command_json,false);
 else
  perform pg_advisory_xact_lock(hashtextextended('voltmaster.project.create',0));
  if exists(select 1 from public.projects where lower(replace(btrim(name),'ё','е'))=lower(replace(btrim(p.command_json->>'name'),'ё','е'))) then raise exception 'Possible duplicate project; inspect existing card';end if;
  select string_agg(format('%I',key),','),string_agg(format('r.%I',key),',') into cols,vals from jsonb_object_keys(p.command_json) key;
  execute format('insert into public.projects (%s) select %s from jsonb_populate_record(null::public.projects,$1) r returning *',cols,vals) into pr using p.command_json;
  result:=jsonb_build_object('status','completed','project',to_jsonb(pr),'verified',exists(select 1 from public.projects where id=pr.id));
 end if;
 update public.agent_operator_plans set status='completed',result_json=result where id=p.id;
 return jsonb_build_object('status','completed','result',result);
end $fn$;
revoke all on function public.agent_execute_operator_plan(uuid,uuid,uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.agent_execute_operator_plan(uuid,uuid,uuid,uuid,boolean) to service_role;


-- Project card and its three cost lists commit together.
create or replace function voltmaster_private.project_card_command(p_owner uuid,p_request uuid,p_command jsonb,p_preview boolean default false)
returns jsonb language plpgsql set search_path='' as $fn$
declare act text:=p_command->>'action'; v jsonb:=p_command->'values'; old public.projects; pr public.projects; pid uuid; result jsonb; stored jsonb; child jsonb; proposal jsonb; child_result jsonb; previews jsonb:='[]'; linked jsonb; cols text; vals text; k text; idx integer:=0; cid uuid; typ text; fields text[];
begin
 if not exists(select 1 from public.profiles where id=p_owner and is_active and role in ('director','finance','accountant')) then raise exception 'Project card access denied';end if;
 if p_request is null or act is null or act not in ('create','update') or jsonb_typeof(p_command)<>'object' or exists(select 1 from jsonb_object_keys(p_command) x where x not in ('action','id','expected','values','cost_changes')) then raise exception 'Invalid project card command';end if;
 if jsonb_typeof(v) is distinct from 'object' or exists(select 1 from jsonb_object_keys(v) x where x not in ('name','contractor_company','customer','contract_number','contract_date','start_date','end_date','planned_revenue','status','comment')) then raise exception 'Unsupported project fields';end if;
 perform pg_advisory_xact_lock(hashtextextended('voltmaster.financial.commands',0));
 if not p_preview then
  select result_json,command_json into result,stored from voltmaster_private.financial_command_receipts where owner_id=p_owner and request_id=p_request;
  if found then if stored is distinct from p_command then raise exception 'Request reused with different command';end if;return result;end if;
 end if;
 if act='update' then
  select * into old from public.projects where id=(p_command->>'id')::uuid for update;
  if not found or to_jsonb(old) is distinct from p_command->'expected' then raise exception 'Record changed; create a new approval';end if;pr:=old;pid:=old.id;
 else
  if p_command ? 'id' or p_command ? 'expected' then raise exception 'Create cannot set identity';end if;
  pr.planned_revenue:=0;pr.status:='active';
 end if;
 pr:=jsonb_populate_record(pr,v);
 if nullif(btrim(pr.name),'') is null or length(pr.name)>500 or pr.contractor_company not in ('ООО','ИП') or pr.contractor_company is null or pr.planned_revenue is null or pr.planned_revenue<0 or pr.planned_revenue::text in ('NaN','Infinity','-Infinity') or pr.planned_revenue<>round(pr.planned_revenue,2) or pr.status not in ('planned','active','completed','paused') or pr.status is null or pr.end_date<pr.start_date then raise exception 'Invalid project card values';end if;
 if exists(select 1 from public.projects where lower(replace(btrim(name),'ё','е'))=lower(replace(btrim(pr.name),'ё','е')) and id is distinct from pid) then raise exception 'Possible duplicate project; inspect existing card';end if;
 if jsonb_typeof(coalesce(p_command->'cost_changes','[]')) is distinct from 'array' or jsonb_array_length(coalesce(p_command->'cost_changes','[]'))>200 then raise exception 'Invalid cost change list';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') into linked from public.operations x where project_id=pid;
 if not p_preview then
  perform set_config('request.jwt.claim.sub',p_owner::text,true);
  select string_agg(format('%I',key),','),string_agg(format('r.%I',key),','),string_agg(format('%I=r.%I',key,key),',') into cols,vals,k from jsonb_object_keys(v) key;
  if act='create' then execute format('insert into public.projects (%s) select %s from jsonb_populate_record(null::public.projects,$1) r returning *',cols,vals) into pr using v;pid:=pr.id;
  elsif v<>'{}' then execute format('update public.projects x set %s from jsonb_populate_record(null::public.projects,$1) r where x.id=$2 returning x.*',k) into pr using v,pid;end if;
 end if;
 for child in select value from jsonb_array_elements(coalesce(p_command->'cost_changes','[]')) loop
  idx:=idx+1;typ:=child->>'kind';
  if typ is null or typ not in ('subcontractor','material','other_expense') or jsonb_typeof(child)<>'object' or child->>'action' is null then raise exception 'Invalid card cost command';end if;
  proposal:=child;
  if child->>'action'<>'delete' then proposal:=jsonb_set(proposal,'{values}',child->'values'||jsonb_build_object('project_id',pid));end if;
  if child->>'action'<>'create' and (child->'expected'->>'project_id')::uuid is distinct from pid then raise exception 'Cost belongs to another project';end if;
  if p_preview and act='create' then
   if child->>'action'<>'create' or child ? 'id' or child ? 'expected' then raise exception 'New card costs must be new';end if;
   fields:=case when typ='subcontractor' then array['name','planned_amount','has_vat','comment'] else array['name','planned_amount','actual_amount','expense_date','comment'] end;
   if jsonb_typeof(child->'values') is distinct from 'object' or nullif(btrim(child->'values'->>'name'),'') is null or exists(select 1 from jsonb_object_keys(child->'values') x where not(x=any(fields))) then raise exception 'Invalid new card cost fields';end if;
   for k in select unnest(array['planned_amount','actual_amount']) loop if child->'values' ? k and ((child->'values'->>k)::numeric is null or (child->'values'->>k)::numeric<0 or (child->'values'->>k)::numeric::text in ('NaN','Infinity','-Infinity')) then raise exception 'Invalid new card cost amount';end if;end loop;
   previews:=previews||jsonb_build_array(child);
  else
   cid:=md5(p_owner::text||p_request::text||'cardcost'||idx)::uuid;
   child_result:=voltmaster_private.obligation_command(p_owner,cid,proposal,p_preview);
   previews:=previews||jsonb_build_array(child_result);
  end if;
 end loop;
 if p_preview then return jsonb_build_object('before',case when old.id is null then null else to_jsonb(old) end,'values',v,'cost_changes',previews,'linked_operations',linked);end if;
 result:=jsonb_build_object('status','completed','action',act,'project',to_jsonb(pr),'cost_changes',previews,'verified',exists(select 1 from public.projects where id=pid));
 insert into voltmaster_private.financial_command_receipts values(p_owner,p_request,p_command,result,now());return result;
end $fn$;
revoke all on function voltmaster_private.project_card_command(uuid,uuid,jsonb,boolean) from public,anon,authenticated;
grant execute on function voltmaster_private.project_card_command(uuid,uuid,jsonb,boolean) to service_role;
create or replace function public.execute_project_card(p_request uuid,p_command jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.project_card_command(auth.uid(),p_request,p_command,false);end $$;
revoke all on function public.execute_project_card(uuid,jsonb) from public,anon;
grant execute on function public.execute_project_card(uuid,jsonb) to authenticated;
alter table public.agent_operator_plans drop constraint if exists agent_operator_plans_kind_check;
alter table public.agent_operator_plans add constraint agent_operator_plans_kind_check check(kind in ('operation_write','project_create','credit_write','obligation_write','project_card_write'));

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
 if p_kind='project_card_write' then
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
 if not exists(select 1 from public.profiles where id=p_owner and is_active and role in ('director','finance','accountant')) then raise exception 'Operator access denied';end if;
 if p.kind in ('project_create','project_card_write') and not exists(select 1 from public.agent_director_access a join public.profiles u on u.id=a.user_id where u.id=p_owner and u.role='director' and u.is_active) then raise exception 'Trusted director required';end if;
 if not exists(select 1 from public.agent_chat_messages where id=p_message and owner_id=p_owner and chat_id=p.chat_id and kind='user' and content=(case when p_cancel then 'ОТМЕНЯЮ ' else 'ПОДТВЕРЖДАЮ ' end)||p.id::text) then raise exception 'Exact chat confirmation required';end if;
 if p.status<>'pending' then return jsonb_build_object('status',p.status,'result',p.result_json);end if;
 if p.expires_at<now() then raise exception 'Plan expired';end if;
 if p_cancel then update public.agent_operator_plans set status='cancelled' where id=p.id;return jsonb_build_object('status','cancelled');end if;
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 if p.kind='project_card_write' then
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


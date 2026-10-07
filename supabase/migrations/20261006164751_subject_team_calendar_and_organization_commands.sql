-- Financial registers have explicit semantics, not unrestricted table CRUD.
create or replace function voltmaster_private.obligation_command(p_owner uuid,p_request uuid,p_command jsonb,p_preview boolean default false)
returns jsonb language plpgsql set search_path='' as $fn$
declare kind text:=p_command->>'kind'; act text:=p_command->>'action'; tab text; allowed text[]; label text; required_name text;
 old jsonb; candidate jsonb; v jsonb:=p_command->'values'; linked jsonb; result jsonb; stored jsonb; pid uuid; rid uuid; cols text; vals text; k text; sources numeric; paid numeric; actor_role text;
begin
 select role into actor_role from public.profiles where id=p_owner and is_active;
 if actor_role is null or not(actor_role in ('director','finance','accountant') or kind='task' and actor_role in ('foreman','manager') or kind='contact' and actor_role='manager' or kind in ('event','org_expense') and actor_role='manager' and act='create') then raise exception 'Financial access denied';end if;
 if p_request is null or act is null or act not in ('create','update','delete','archive') or act='archive' and kind not in ('employee','org_expense') or act='delete' and kind in ('employee','org_expense') or jsonb_typeof(p_command)<>'object' or exists(select 1 from jsonb_object_keys(p_command) x where x not in ('kind','action','id','expected','values')) then raise exception 'Invalid obligation command';end if;
 case kind
 when 'receivable' then tab:='receivables';required_name:='customer';allowed:=array['project_id','customer','amount','document_type','document_number','document_date','document_status','due_date','comment'];
 when 'payable' then tab:='payables';required_name:='counterparty';allowed:=array['project_id','counterparty','amount','document_type','document_number','document_date','due_date','comment','is_credit','owner_company','credit_kind','credit_start_date','full_repayment_date'];
 when 'material' then tab:='project_materials';required_name:='name';allowed:=array['project_id','name','planned_amount','actual_amount','expense_date','comment'];
 when 'other_expense' then tab:='project_other_expenses';required_name:='name';allowed:=array['project_id','name','planned_amount','actual_amount','expense_date','comment'];
 when 'subcontractor' then tab:='subcontractors';required_name:='name';allowed:=array['project_id','name','planned_amount','has_vat','comment'];
 when 'creditor' then tab:='creditors';required_name:='name';allowed:=array['name'];
 when 'employee' then tab:='org_employees';required_name:='name';allowed:=array['name','position','monthly_salary','pay_day','payment_date','company','active','comment'];
 when 'org_expense' then tab:='org_expenses';required_name:='name';allowed:=array['name','category','monthly_amount','pay_day','payment_date','company','active','comment'];
 when 'event' then tab:='events';required_name:='title';allowed:=array['title','name','event_type','event_date','company','planned_amount','comment'];
 when 'contact' then tab:='project_customer_contacts';required_name:='full_name';allowed:=array['project_id','full_name','phone','position'];
 when 'task' then tab:='project_work_tasks';required_name:='title';allowed:=array['project_id','title','due_date','priority','status','comment'];
 else raise exception 'Unsupported financial register';end case;
 perform pg_advisory_xact_lock(hashtextextended('voltmaster.financial.commands',0));
 if not p_preview then
  select result_json,command_json into result,stored from voltmaster_private.financial_command_receipts where owner_id=p_owner and request_id=p_request;
  if found then if stored is distinct from p_command then raise exception 'Request reused with different command';end if;return result;end if;
 end if;
 if act<>'create' then
  rid:=(p_command->>'id')::uuid;execute format('select to_jsonb(x) from public.%I x where id=$1 for update',tab) into old using rid;
  if old is null or old is distinct from p_command->'expected' then raise exception 'Record changed; create a new approval';end if;
 else if p_command ? 'id' or p_command ? 'expected' then raise exception 'Create cannot set identity';end if;end if;
 execute format('select coalesce(jsonb_agg(to_jsonb(x) order by id),''[]''::jsonb) from public.operations x where %s',case kind when 'receivable' then 'receivable_id=$1' when 'payable' then 'payable_id=$1' when 'subcontractor' then 'subcontractor_id=$1' when 'material' then 'cost_item_id=$1 and cost_item_type=''material''' when 'other_expense' then 'cost_item_id=$1 and cost_item_type=''other''' when 'employee' then 'org_employee_id=$1' when 'org_expense' then 'org_expense_id=$1' when 'event' then 'org_event_id=$1' else 'false and id=$1' end) into linked using rid;
 if act='delete' and linked<>'[]' then raise exception 'Unlink financial operations before deleting register';end if;
 if act='archive' then
  if coalesce(v,'{}')<>'{}' then raise exception 'Archive cannot change values';end if;v:='{"active":false}';candidate:=old||v;
 elsif act<>'delete' then
  if jsonb_typeof(v) is distinct from 'object' or v='{}' or exists(select 1 from jsonb_object_keys(v) x where not(x=any(allowed))) then raise exception 'Unsupported register fields';end if;
  candidate:=coalesce(old,jsonb_build_object('amount',0,'paid_amount',0,'planned_amount',0,'actual_amount',0,'is_credit',false,'document_status','not_signed'))||v;
  if nullif(btrim(candidate->>required_name),'') is null or length(candidate->>required_name)>500 then raise exception 'Register name required';end if;
  for k in select unnest(array['amount','planned_amount','actual_amount','monthly_salary','monthly_amount']) loop
   if candidate ? k and ((candidate->>k)::numeric is null or (candidate->>k)::numeric<0 or (candidate->>k)::numeric::text in ('NaN','Infinity','-Infinity') or (candidate->>k)::numeric<>round((candidate->>k)::numeric,2)) then raise exception 'Invalid register amount';end if;
  end loop;
  pid:=(candidate->>'project_id')::uuid;
  if kind in ('receivable','material','other_expense','subcontractor','contact','task') and pid is null then raise exception 'Register project required';end if;
  if pid is not null then perform 1 from public.projects where id=pid for update;if not found then raise exception 'Project not found';end if;end if;
  if linked<>'[]' and candidate->'project_id' is distinct from old->'project_id' then raise exception 'Unlink operations before moving register';end if;
  if kind in ('receivable','payable') then
   paid:=coalesce((old->>'paid_amount')::numeric,0);
   if (candidate->>'amount')::numeric<=0 or (candidate->>'amount')::numeric<paid then raise exception 'Register amount below paid';end if;
  end if;
  if kind='payable' then
   if exists(select 1 from jsonb_array_elements(linked) x where x->>'operation_type'='credit' or x->>'credit_kind'='material') then raise exception 'Edit loan source with credit command';end if;
   if coalesce((candidate->>'is_credit')::boolean,false) then
    if candidate->>'owner_company' not in ('ООО','ИП') or candidate->>'owner_company' is null or candidate->>'credit_kind' not in ('money','material') or candidate->>'credit_kind' is null or nullif(candidate->>'credit_start_date','') is null or nullif(candidate->>'due_date','') is null or nullif(candidate->>'full_repayment_date','') is null or (candidate->>'due_date')::date<(candidate->>'credit_start_date')::date or (candidate->>'full_repayment_date')::date<(candidate->>'due_date')::date then raise exception 'Credit register dates/company required';end if;
   end if;
  end if;
  if kind='creditor' and exists(select 1 from public.creditors where lower(btrim(name))=lower(btrim(candidate->>'name')) and id is distinct from rid) then raise exception 'Duplicate creditor';end if;
  if kind in ('employee','org_expense','event') then
   if act='create' then candidate:=jsonb_build_object('company','ООО')||candidate;end if;
   if candidate->>'company' not in ('ООО','ИП') or candidate->>'company' is null then raise exception 'Invalid organization company';end if;
   if candidate ? 'pay_day' and candidate->>'pay_day' is not null and (candidate->>'pay_day')::integer not between 1 and 31 then raise exception 'Invalid pay day';end if;
   if candidate ? 'payment_date' then perform (candidate->>'payment_date')::date;end if;
  end if;
  if kind='event' and nullif(candidate->>'event_date','') is null then raise exception 'Event date required';end if;
  if kind='task' and (coalesce(candidate->>'status','open') not in ('open','done') or coalesce(candidate->>'priority','normal') not in ('low','normal','high')) then raise exception 'Invalid task state';end if;
 else if coalesce(v,'{}')<>'{}' then raise exception 'Delete cannot change values';end if;candidate:=old;end if;
 if kind in ('contact','task') then
  pid:=(candidate->>'project_id')::uuid;
  if pid is null or not exists(select 1 from public.projects where id=pid) or actor_role='foreman' and not exists(select 1 from public.projects p where p.id=pid and (p.responsible_user_id=p_owner or exists(select 1 from public.project_team_members m where m.project_id=p.id and m.user_id=p_owner and m.is_active))) then raise exception 'Project access denied';end if;
  if old is not null and old->'project_id' is distinct from candidate->'project_id' then raise exception 'Project task/contact cannot move';end if;
 end if;
 if p_preview then return jsonb_build_object('kind',kind,'before',old,'values',case when act='delete' then null else v end,'linked_operations',linked);end if;
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 if act='create' then
  if kind in ('event','task','contact') then v:=v||jsonb_build_object('created_by',p_owner);end if;
  select string_agg(format('%I',key),','),string_agg(format('r.%I',key),',') into cols,vals from jsonb_object_keys(v) key;
  execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I,$1) r returning to_jsonb(%I.*)',tab,cols,vals,tab,tab) into result using v;
 elsif act in ('update','archive') then
  select string_agg(format('%I=r.%I',key,key),',') into cols from jsonb_object_keys(v) key;
  execute format('update public.%I x set %s from jsonb_populate_record(null::public.%I,$1) r where x.id=$2 returning to_jsonb(x)',tab,cols,tab) into result using v,rid;
 else execute format('delete from public.%I where id=$1 returning to_jsonb(%I.*)',tab,tab) into result using rid;end if;
 if result is null then raise exception 'Register verification failed';end if;
 result:=jsonb_build_object('status','completed','kind',kind,'action',act,'record',result,'verified',true);
 insert into voltmaster_private.financial_command_receipts values(p_owner,p_request,p_command,result,now());return result;
end $fn$;
revoke all on function voltmaster_private.obligation_command(uuid,uuid,jsonb,boolean) from public,anon,authenticated;
grant execute on function voltmaster_private.obligation_command(uuid,uuid,jsonb,boolean) to service_role;
create or replace function public.execute_obligation_command(p_request uuid,p_command jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.obligation_command(auth.uid(),p_request,p_command,false);end $$;
revoke all on function public.execute_obligation_command(uuid,jsonb) from public,anon;
grant execute on function public.execute_obligation_command(uuid,jsonb) to authenticated;
alter table public.agent_operator_plans drop constraint if exists agent_operator_plans_kind_check;
alter table public.agent_operator_plans add constraint agent_operator_plans_kind_check check(kind in ('operation_write','project_create','credit_write','obligation_write','project_card_write','volume_write','team_record_write'));

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
 elsif p_kind in ('obligation_write','team_record_write') then
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
 if not exists(select 1 from public.profiles where id=p_owner and is_active and (p.kind in ('volume_write','team_record_write') or role in ('director','finance','accountant'))) then raise exception 'Operator access denied';end if;
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
 elsif p.kind in ('obligation_write','team_record_write') then
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


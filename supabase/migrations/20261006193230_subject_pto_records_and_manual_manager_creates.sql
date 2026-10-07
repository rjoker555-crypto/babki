-- Financial registers have explicit semantics, not unrestricted table CRUD.
create or replace function voltmaster_private.obligation_command(p_owner uuid,p_request uuid,p_command jsonb,p_preview boolean default false)
returns jsonb language plpgsql set search_path='' as $fn$
declare kind text:=p_command->>'kind'; act text:=p_command->>'action'; tab text; allowed text[]; label text; required_name text;
 old jsonb; candidate jsonb; v jsonb:=p_command->'values'; linked jsonb; result jsonb; stored jsonb; pid uuid; rid uuid; cols text; vals text; k text; sources numeric; paid numeric; actor_role text;
begin
 select role into actor_role from public.profiles where id=p_owner and is_active;
 if actor_role is null or not(actor_role in ('director','finance','accountant') or kind='task' and actor_role in ('foreman','manager') or kind in ('contact','pto_record') and actor_role='manager' or kind in ('event','org_expense','material','other_expense','subcontractor') and actor_role='manager' and act='create') then raise exception 'Financial access denied';end if;
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
 when 'pto_record' then tab:='pto_documents';required_name:='document_type';allowed:=array['project_id','document_type','final_date','status','comment'];
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
  if kind in ('receivable','material','other_expense','subcontractor','contact','task','pto_record') and pid is null then raise exception 'Register project required';end if;
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
  if kind='pto_record' and (candidate->>'document_type' is null or candidate->>'document_type' not in ('executive_schemes','aosr','work_log','cable_log','other') or coalesce(candidate->>'status','requested') not in ('requested','in_progress','signing','signed') or nullif(candidate->>'final_date','') is null) then raise exception 'Explicit PTO type, date and status required';end if;
  if kind='task' and (coalesce(candidate->>'status','open') not in ('open','done') or coalesce(candidate->>'priority','normal') not in ('low','normal','high')) then raise exception 'Invalid task state';end if;
 else if coalesce(v,'{}')<>'{}' then raise exception 'Delete cannot change values';end if;candidate:=old;end if;
 if kind in ('contact','task','pto_record') then
  pid:=(candidate->>'project_id')::uuid;
  if pid is null or not exists(select 1 from public.projects where id=pid) or actor_role='foreman' and not exists(select 1 from public.projects p where p.id=pid and (p.responsible_user_id=p_owner or exists(select 1 from public.project_team_members m where m.project_id=p.id and m.user_id=p_owner and m.is_active))) then raise exception 'Project access denied';end if;
  if old is not null and old->'project_id' is distinct from candidate->'project_id' then raise exception 'Project task/contact cannot move';end if;
 end if;
 if p_preview then return jsonb_build_object('kind',kind,'before',old,'values',case when act='delete' then null else v end,'linked_operations',linked);end if;
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 if act='create' then
  if kind in ('event','task','contact','pto_record') then v:=v||jsonb_build_object('created_by',p_owner);end if;
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



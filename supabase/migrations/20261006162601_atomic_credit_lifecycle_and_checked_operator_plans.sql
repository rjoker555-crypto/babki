-- Dedicated atomic lifecycle for money loans and deferred project materials.
create or replace function voltmaster_private.credit_command(p_owner uuid,p_request uuid,p_command jsonb,p_preview boolean default false)
returns jsonb language plpgsql set search_path='' as $fn$
declare old public.operations; op public.operations; debt public.payables; pr public.projects; item record;
 act text:=p_command->>'action'; v jsonb:=p_command->'values'; credit jsonb:=p_command->'credit';
 result jsonb; stored jsonb; snapshot jsonb:='[]'; is_deferred boolean; due date; finish date; k text; debt_id uuid;
begin
 if not exists(select 1 from public.profiles where id=p_owner and is_active and role in ('director','finance','accountant')) then raise exception 'Financial access denied';end if;
 if p_request is null or act is null or act not in ('create','update','delete') or jsonb_typeof(p_command)<>'object' then raise exception 'Invalid credit command';end if;
 if exists(select 1 from jsonb_object_keys(p_command) x where x not in ('action','id','values','credit','expected','expected_credit')) then raise exception 'Unknown credit field';end if;
 perform pg_advisory_xact_lock(hashtextextended('voltmaster.financial.commands',0));
 if not p_preview then
  select result_json,command_json into result,stored from voltmaster_private.financial_command_receipts where owner_id=p_owner and request_id=p_request;
  if found then if stored is distinct from p_command then raise exception 'Request reused with different command';end if;return result;end if;
 end if;
 if act<>'create' then
  select * into old from public.operations where id=(p_command->>'id')::uuid for update;
  if not found or to_jsonb(old) is distinct from p_command->'expected' then raise exception 'Record changed; create a new approval';end if;
  if old.operation_type<>'credit' and not(old.article='ТМЦ' and old.operation_type='expense') then raise exception 'Not a loan/material receipt';end if;
  if old.payable_id is not null then
   select * into debt from public.payables where id=old.payable_id for update;
   if not found or not debt.is_credit or to_jsonb(debt) is distinct from p_command->'expected_credit' then raise exception 'Credit changed; create a new approval';end if;
   if exists(select 1 from public.operations where payable_id=debt.id and id<>old.id and article<>'Погашение кредиторки') then raise exception 'Credit has another source';end if;
   snapshot:=snapshot||jsonb_build_array(jsonb_build_object('payable',to_jsonb(debt)));
  elsif coalesce(p_command->'expected_credit','null')<>'null' then raise exception 'Unexpected credit original';end if;
  op:=old;
 else
  if p_command ? 'id' or p_command ? 'expected' or p_command ? 'expected_credit' then raise exception 'Create cannot set identity';end if;
  op.operation_date:=(now() at time zone 'Asia/Krasnoyarsk')::date;op.vat_included:=false;
 end if;
 if act<>'delete' then
  if jsonb_typeof(v) is distinct from 'object' or v='{}' then raise exception 'Empty credit values';end if;
  for k in select jsonb_object_keys(v) loop if k not in ('operation_date','operation_type','article','amount','project_id','payer_company','vat_included','cost_item_id','cost_item_type','credit_kind','credit_recipient_company','counterparty','document_number','comment') then raise exception 'Unsupported credit operation field %',k;end if;end loop;
  op:=jsonb_populate_record(op,v);
  if op.amount is null or op.amount<=0 or op.amount::text in ('NaN','Infinity','-Infinity') or op.amount<>round(op.amount,2) or op.operation_date is null then raise exception 'Invalid credit amount/date';end if;
  if old.operation_type='credit' and op.operation_type<>'credit' then raise exception 'Loan type cannot change';end if;
  if op.operation_type='credit' then
   if op.project_id is not null or op.cost_item_id is not null or op.credit_kind not in ('money','material') or op.credit_kind is null or op.credit_recipient_company not in ('ООО','ИП') or op.credit_recipient_company is null then raise exception 'Invalid loan parameters';end if;
   op.article:='Получение кредита';op.payer_company:=op.credit_recipient_company;op.vat_included:=false;
  elsif op.operation_type='expense' and op.article='ТМЦ' and op.project_id is not null and op.cost_item_id is not null and op.cost_item_type='material' and (op.credit_kind is null or op.credit_kind='material') then
   select * into pr from public.projects where id=op.project_id for update;if not found then raise exception 'Project not found';end if;
   snapshot:=snapshot||jsonb_build_array(jsonb_build_object('project',to_jsonb(pr)));op.payer_company:=pr.contractor_company;
   if op.payer_company not in ('ООО','ИП') or op.payer_company is null then raise exception 'Company required';end if;
   if op.payer_company='ИП' then op.vat_included:=false;end if;op.credit_recipient_company:=null;
  else raise exception 'Invalid deferred material operation';end if;
  if num_nonnulls(op.receivable_id,op.subcontractor_id,op.org_employee_id,op.org_event_id,op.org_expense_id)>0 then raise exception 'Invalid credit links';end if;
  is_deferred:=op.operation_type='credit' or op.credit_kind='material';
  if is_deferred then
   if jsonb_typeof(credit) is distinct from 'object' or exists(select 1 from jsonb_object_keys(credit) x where x not in ('due_date','full_repayment_date')) then raise exception 'Credit dates required';end if;
   due:=coalesce((credit->>'due_date')::date,debt.due_date);finish:=coalesce((credit->>'full_repayment_date')::date,debt.full_repayment_date);
   if due is null or finish is null or due<op.operation_date or finish<due or nullif(btrim(op.counterparty),'') is null then raise exception 'Creditor and valid repayment dates required';end if;
   if op.amount<coalesce(debt.paid_amount,0) then raise exception 'Credit less than repayments';end if;
   if debt.id is not null and exists(select 1 from public.operations where payable_id=debt.id and article='Погашение кредиторки') and (op.project_id is distinct from debt.project_id or op.payer_company is distinct from debt.owner_company or op.credit_kind is distinct from debt.credit_kind) then raise exception 'Cannot move a repaid credit';end if;
  elsif credit is not null and credit<>'null'::jsonb and credit<>'{}'::jsonb then raise exception 'Cash material has no credit dates';end if;
 else
  if coalesce(v,'{}')<>'{}' or coalesce(credit,'null')<>'null' then raise exception 'Delete cannot change values';end if;is_deferred:=false;
 end if;
 if not coalesce(is_deferred,false) and debt.id is not null and (debt.paid_amount<>0 or exists(select 1 from public.operations where payable_id=debt.id and article='Погашение кредиторки')) then raise exception 'Remove repayments before deleting/converting credit';end if;
 for item in select * from public.project_materials where id=old.cost_item_id or (act<>'delete' and id=op.cost_item_id) order by id for update loop
  if act<>'delete' and item.id=op.cost_item_id and item.project_id is distinct from op.project_id then raise exception 'Material project mismatch';end if;
  snapshot:=snapshot||jsonb_build_array(jsonb_build_object('material',to_jsonb(item)));
  if not p_preview then update public.project_materials set actual_amount=greatest(0,actual_amount-case when old.cost_item_id=item.id then old.amount else 0 end)+case when act<>'delete' and op.cost_item_id=item.id then op.amount else 0 end where id=item.id;end if;
 end loop;
 if act<>'delete' and op.cost_item_id is not null and not exists(select 1 from public.project_materials where id=op.cost_item_id) then raise exception 'Material not found';end if;
 if p_preview then return jsonb_build_object('operation',to_jsonb(op),'before',case when old.id is not null then to_jsonb(old) else null end,'credit',case when is_deferred then jsonb_build_object('due_date',due,'full_repayment_date',finish,'amount',op.amount,'counterparty',op.counterparty,'owner_company',op.payer_company,'credit_kind',op.credit_kind,'project_id',op.project_id) else null end,'related',snapshot);end if;
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 if is_deferred then
  debt_id:=coalesce(debt.id,gen_random_uuid());
  if debt.id is null then
   insert into public.payables(id,project_id,counterparty,document_type,document_number,document_date,amount,paid_amount,due_date,is_credit,credit_start_date,full_repayment_date,owner_company,credit_kind,comment) values(debt_id,op.project_id,op.counterparty,case when op.operation_type='credit' then 'Кредит' else 'ТМЦ / отсрочка' end,op.document_number,op.operation_date,op.amount,0,due,true,op.operation_date,finish,op.payer_company,op.credit_kind,op.comment);
  else
   update public.payables set project_id=op.project_id,counterparty=op.counterparty,document_number=op.document_number,document_date=op.operation_date,amount=op.amount,due_date=due,credit_start_date=op.operation_date,full_repayment_date=finish,owner_company=op.payer_company,credit_kind=op.credit_kind,comment=op.comment,updated_at=now() where id=debt_id;
  end if;op.payable_id:=debt_id;
 else op.payable_id:=null;end if;
 if act='create' then
  insert into public.operations(operation_date,operation_type,article,amount,project_id,payer_company,vat_included,cost_item_id,cost_item_type,credit_kind,credit_recipient_company,counterparty,document_number,comment,payable_id,created_by) values(op.operation_date,op.operation_type,op.article,op.amount,op.project_id,op.payer_company,op.vat_included,op.cost_item_id,op.cost_item_type,op.credit_kind,op.credit_recipient_company,op.counterparty,op.document_number,op.comment,op.payable_id,p_owner) returning * into op;
 elsif act='update' then
  update public.operations set operation_date=op.operation_date,operation_type=op.operation_type,article=op.article,amount=op.amount,project_id=op.project_id,payer_company=op.payer_company,vat_included=op.vat_included,cost_item_id=op.cost_item_id,cost_item_type=op.cost_item_type,credit_kind=op.credit_kind,credit_recipient_company=op.credit_recipient_company,counterparty=op.counterparty,document_number=op.document_number,comment=op.comment,payable_id=op.payable_id,updated_at=now() where id=old.id returning * into op;
 else delete from public.operations where id=old.id;op:=old;end if;
 if not is_deferred and debt.id is not null then delete from public.payables where id=debt.id;end if;
 result:=jsonb_build_object('status','completed','action',act,'operation',to_jsonb(op),'credit',case when is_deferred then (select to_jsonb(x) from public.payables x where id=debt_id) else null end,'verified',case when act='delete' then not exists(select 1 from public.operations where id=old.id) else exists(select 1 from public.operations where id=op.id and amount=op.amount) end);
 if result->>'verified'<>'true' then raise exception 'Credit result verification failed';end if;
 insert into voltmaster_private.financial_command_receipts values(p_owner,p_request,p_command,result,now());return result;
end $fn$;
revoke all on function voltmaster_private.credit_command(uuid,uuid,jsonb,boolean) from public,anon,authenticated;
grant execute on function voltmaster_private.credit_command(uuid,uuid,jsonb,boolean) to service_role;
create or replace function public.execute_credit_operation(p_request uuid,p_command jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.credit_command(auth.uid(),p_request,p_command,false);end $$;
revoke all on function public.execute_credit_operation(uuid,jsonb) from public,anon;
grant execute on function public.execute_credit_operation(uuid,jsonb) to authenticated;
alter table public.agent_operator_plans drop constraint if exists agent_operator_plans_kind_check;
alter table public.agent_operator_plans add constraint agent_operator_plans_kind_check check(kind in ('operation_write','project_create','credit_write'));

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
 if p_kind='credit_write' then
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
 if p.kind='project_create' and not exists(select 1 from public.agent_director_access a join public.profiles u on u.id=a.user_id where u.id=p_owner and u.role='director' and u.is_active) then raise exception 'Trusted director required';end if;
 if not exists(select 1 from public.agent_chat_messages where id=p_message and owner_id=p_owner and chat_id=p.chat_id and kind='user' and content=(case when p_cancel then 'ОТМЕНЯЮ ' else 'ПОДТВЕРЖДАЮ ' end)||p.id::text) then raise exception 'Exact chat confirmation required';end if;
 if p.status<>'pending' then return jsonb_build_object('status',p.status,'result',p.result_json);end if;
 if p.expires_at<now() then raise exception 'Plan expired';end if;
 if p_cancel then update public.agent_operator_plans set status='cancelled' where id=p.id;return jsonb_build_object('status','cancelled');end if;
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 if p.kind='credit_write' then
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


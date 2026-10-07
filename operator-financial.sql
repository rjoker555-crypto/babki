-- Additive commands: existing triggers and financial formulas remain unchanged.
create table if not exists voltmaster_private.financial_command_receipts (
 owner_id uuid not null, request_id uuid not null, command_json jsonb not null,
 result_json jsonb not null, created_at timestamptz not null default now(), primary key(owner_id,request_id)
);
revoke all on voltmaster_private.financial_command_receipts from public,anon,authenticated;
grant all on voltmaster_private.financial_command_receipts to service_role;
alter table voltmaster_private.financial_command_receipts enable row level security;

create or replace function voltmaster_private.financial_command(p_owner uuid,p_request uuid,p_command jsonb,p_preview boolean default false)
returns jsonb language plpgsql set search_path='' as $fn$
declare old public.operations; op public.operations; pr public.projects; debt record; k text; v jsonb;
 act text:=p_command->>'action'; amount_delta numeric; result jsonb; snapshot jsonb:='[]'; linked jsonb;
begin
 if not exists(select 1 from public.profiles where id=p_owner and is_active and role in ('director','finance','accountant')) then raise exception 'Financial access denied';end if;
 if p_request is null or act not in ('create','update','delete') or act is null or jsonb_typeof(p_command)<>'object' then raise exception 'Invalid command';end if;
 if exists(select 1 from jsonb_object_keys(p_command) x where x not in ('action','id','values','expected')) then raise exception 'Unknown command field';end if;
 perform pg_advisory_xact_lock(hashtextextended('voltmaster.financial.commands',0));
 if not p_preview then perform set_config('request.jwt.claim.sub',p_owner::text,true);end if;
 if not p_preview then
  select result_json,command_json into result,linked from voltmaster_private.financial_command_receipts where owner_id=p_owner and request_id=p_request;
  if found then if linked is distinct from p_command then raise exception 'Request reused with different command';end if;return result;end if;
 end if;
 if act in ('update','delete') then
  select * into old from public.operations where id=(p_command->>'id')::uuid for update;
  if not found then raise exception 'Operation not found';end if;
  if to_jsonb(old) is distinct from p_command->'expected' then raise exception 'Record changed; create a new approval';end if;
  op:=old;
 else
  if p_command ? 'id' or p_command ? 'expected' then raise exception 'Create cannot set identity';end if;
  op.operation_date:=(now() at time zone 'Asia/Krasnoyarsk')::date;op.vat_included:=false;
 end if;
 if act<>'delete' then
  v:=p_command->'values';if jsonb_typeof(v) is distinct from 'object' or v='{}' then raise exception 'Empty values';end if;
  for k in select jsonb_object_keys(v) loop
   if k not in ('operation_date','operation_type','article','amount','project_id','payer_company','vat_included','receivable_id','payable_id','subcontractor_id','cost_item_id','cost_item_type','org_employee_id','org_event_id','org_expense_id','counterparty','document_number','comment') then raise exception 'Unsupported operation field %',k;end if;
  end loop;
  op:=jsonb_populate_record(op,v);
  if op.operation_type not in ('income','expense') or op.operation_type is null or old.operation_type='credit' or old.credit_kind='material' then raise exception 'Credit lifecycle requires dedicated command';end if;
  if op.operation_date is null or op.amount is null or op.amount<=0 or op.amount::text in ('NaN','Infinity','-Infinity') or op.amount<>round(op.amount,2) then raise exception 'Invalid date or amount';end if;
  if op.article is null or btrim(op.article)='' then raise exception 'Article required';end if;
  if op.project_id is not null then
   select * into pr from public.projects where id=op.project_id for update;if not found then raise exception 'Project not found';end if;
   snapshot:=snapshot||jsonb_build_array(jsonb_build_object('project',to_jsonb(pr)));
   if pr.contractor_company in ('ООО','ИП') then op.payer_company:=pr.contractor_company;end if;
  end if;
  if op.payer_company not in ('ООО','ИП') or op.payer_company is null then raise exception 'Company required';end if;
  if op.payer_company='ИП' or op.operation_type='income' then op.vat_included:=false;end if;
  if op.cost_item_id is null and op.cost_item_type is not null then raise exception 'Cost type without item';end if;
  if op.operation_type='income' and (op.payable_id is not null or op.cost_item_id is not null or op.subcontractor_id is not null or op.org_employee_id is not null or op.org_event_id is not null or op.org_expense_id is not null) then raise exception 'Invalid income links';end if;
  if op.operation_type='expense' and op.receivable_id is not null then raise exception 'Invalid expense receivable';end if;
  if op.article='Налог ИП' and op.payer_company<>'ИП' or op.article='НДС' and op.payer_company<>'ООО' then raise exception 'Tax company mismatch';end if;
  if op.operation_type='expense' and op.project_id is not null and op.article not in ('Погашение кредиторки','Субподрядчики','ТМЦ','Прочие расходы','Налог ИП','НДС') then raise exception 'Invalid project expense article';end if;
  if op.article='Субподрядчики' and op.operation_type='expense' and op.project_id is not null and op.subcontractor_id is null then raise exception 'Subcontractor required';end if;
  if op.article in ('ТМЦ','Прочие расходы') and op.operation_type='expense' and op.project_id is not null and op.cost_item_id is null then raise exception 'Cost item required';end if;
  if op.subcontractor_id is not null then
   select to_jsonb(s) into linked from public.subcontractors s where id=op.subcontractor_id and project_id=op.project_id for update;
   if linked is null or op.article<>'Субподрядчики' or op.operation_type<>'expense' then raise exception 'Invalid subcontractor link';end if;snapshot:=snapshot||jsonb_build_array(jsonb_build_object('subcontractor',linked));
  end if;
  if op.cost_item_id is not null and (op.operation_type<>'expense' or op.project_id is null or op.cost_item_type is null or op.cost_item_type='material' and op.article<>'ТМЦ' or op.cost_item_type='other' and op.article<>'Прочие расходы') then raise exception 'Invalid cost link';end if;
  if op.payable_id is not null and (op.article<>'Погашение кредиторки' or op.operation_type<>'expense') then raise exception 'Invalid payable link';end if;
  if op.article='Погашение кредиторки' and op.operation_type='expense' and op.payable_id is null then raise exception 'Payable required';end if;
  if op.article='Орг. расходы' and op.operation_type='expense' then
   if op.project_id is not null or num_nonnulls(op.org_employee_id,op.org_event_id,op.org_expense_id)<>1 then raise exception 'Organizational consumer required';end if;
  elsif num_nonnulls(op.org_employee_id,op.org_event_id,op.org_expense_id)>0 then raise exception 'Invalid organizational links';end if;
  if op.org_employee_id is not null then select to_jsonb(x) into linked from public.org_employees x where id=op.org_employee_id for update;if linked is null then raise exception 'Employee not found';end if;snapshot:=snapshot||jsonb_build_array(jsonb_build_object('employee',linked));end if;
  if op.org_event_id is not null then select to_jsonb(x) into linked from public.events x where id=op.org_event_id for update;if linked is null then raise exception 'Event not found';end if;snapshot:=snapshot||jsonb_build_array(jsonb_build_object('event',linked));end if;
  if op.org_expense_id is not null then select to_jsonb(x) into linked from public.org_expenses x where id=op.org_expense_id for update;if linked is null then raise exception 'Expense not found';end if;snapshot:=snapshot||jsonb_build_array(jsonb_build_object('expense',linked));end if;
 elsif old.operation_type='credit' or old.credit_kind='material' then raise exception 'Credit lifecycle requires dedicated command';
 elsif coalesce(p_command->'values','{}')<>'{}' then raise exception 'Delete cannot change values';end if;
 -- Debt and cost rows are locked in identity order, including the previous link.
 for debt in select * from public.receivables where id=old.receivable_id or (act<>'delete' and id=op.receivable_id) order by id for update loop
  snapshot:=snapshot||jsonb_build_array(jsonb_build_object('receivable',to_jsonb(debt)));
  amount_delta:=(case when act<>'delete' and op.receivable_id=debt.id then op.amount else 0 end)-(case when old.receivable_id=debt.id then old.amount else 0 end);
  if act<>'delete' and op.receivable_id=debt.id and op.project_id is distinct from debt.project_id then raise exception 'Receivable project mismatch';end if;
  if debt.paid_amount+amount_delta>debt.amount or debt.paid_amount+amount_delta<0 then raise exception 'Receivable balance exceeded';end if;
  if not p_preview then update public.receivables set paid_amount=paid_amount+amount_delta,updated_at=now() where id=debt.id;end if;
 end loop;
 if act<>'delete' and op.receivable_id is not null and not exists(select 1 from public.receivables where id=op.receivable_id) then raise exception 'Receivable not found';end if;
 for debt in select * from public.payables where id=old.payable_id or (act<>'delete' and id=op.payable_id) order by id for update loop
  snapshot:=snapshot||jsonb_build_array(jsonb_build_object('payable',to_jsonb(debt)));
  if act<>'delete' and op.payable_id=debt.id then
   if op.project_id is distinct from debt.project_id then raise exception 'Payable project mismatch';end if;
   if op.amount>greatest(0,debt.amount-debt.paid_amount)+(case when old.payable_id=debt.id and old.article='Погашение кредиторки' then old.amount else 0 end) then raise exception 'Payable balance exceeded';end if;
  end if;
 end loop;
 if act<>'delete' and op.payable_id is not null and not exists(select 1 from public.payables where id=op.payable_id) then raise exception 'Payable not found';end if;
 for debt in select * from public.project_materials where id=old.cost_item_id and old.cost_item_type='material' or act<>'delete' and id=op.cost_item_id and op.cost_item_type='material' order by id for update loop
  snapshot:=snapshot||jsonb_build_array(jsonb_build_object('material',to_jsonb(debt)));
  if act<>'delete' and op.cost_item_id=debt.id and op.project_id is distinct from debt.project_id then raise exception 'Material project mismatch';end if;
  amount_delta:=(case when act<>'delete' and op.cost_item_id=debt.id and op.cost_item_type='material' then op.amount else 0 end)-(case when old.cost_item_id=debt.id and old.cost_item_type='material' then old.amount else 0 end);
  if not p_preview then update public.project_materials set actual_amount=greatest(0,actual_amount-(case when old.cost_item_id=debt.id and old.cost_item_type='material' then old.amount else 0 end))+(case when act<>'delete' and op.cost_item_id=debt.id and op.cost_item_type='material' then op.amount else 0 end) where id=debt.id;end if;
 end loop;
 for debt in select * from public.project_other_expenses where id=old.cost_item_id and old.cost_item_type='other' or act<>'delete' and id=op.cost_item_id and op.cost_item_type='other' order by id for update loop
  snapshot:=snapshot||jsonb_build_array(jsonb_build_object('cost',to_jsonb(debt)));
  if act<>'delete' and op.cost_item_id=debt.id and op.project_id is distinct from debt.project_id then raise exception 'Cost project mismatch';end if;
  amount_delta:=(case when act<>'delete' and op.cost_item_id=debt.id and op.cost_item_type='other' then op.amount else 0 end)-(case when old.cost_item_id=debt.id and old.cost_item_type='other' then old.amount else 0 end);
  if not p_preview then update public.project_other_expenses set actual_amount=greatest(0,actual_amount-(case when old.cost_item_id=debt.id and old.cost_item_type='other' then old.amount else 0 end))+(case when act<>'delete' and op.cost_item_id=debt.id and op.cost_item_type='other' then op.amount else 0 end) where id=debt.id;end if;
 end loop;
 if act<>'delete' and op.cost_item_id is not null and not (op.cost_item_type='material' and exists(select 1 from public.project_materials where id=op.cost_item_id) or op.cost_item_type='other' and exists(select 1 from public.project_other_expenses where id=op.cost_item_id)) then raise exception 'Cost item not found';end if;
 if p_preview then return jsonb_build_object('operation',to_jsonb(op),'before',case when act='create' then null else to_jsonb(old) end,'related',snapshot);end if;
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 if act='create' then
  op.id:=gen_random_uuid();op.created_by:=p_owner;op.created_at:=now();op.updated_at:=now();insert into public.operations select (op).*;
 elsif act='update' then
  op.updated_at:=now();update public.operations set operation_date=op.operation_date,operation_type=op.operation_type,article=op.article,amount=op.amount,project_id=op.project_id,payer_company=op.payer_company,vat_included=op.vat_included,receivable_id=op.receivable_id,payable_id=op.payable_id,subcontractor_id=op.subcontractor_id,cost_item_id=op.cost_item_id,cost_item_type=op.cost_item_type,org_employee_id=op.org_employee_id,org_event_id=op.org_event_id,org_expense_id=op.org_expense_id,counterparty=op.counterparty,document_number=op.document_number,comment=op.comment,updated_at=op.updated_at where id=op.id;
 else delete from public.operations where id=old.id;end if;
 -- Existing payable trigger alone recalculates repayments; no second increment.
 result:=jsonb_build_object('status','completed','action',act,'operation',to_jsonb(op),'verified',case when act='delete' then not exists(select 1 from public.operations where id=old.id) else exists(select 1 from public.operations where id=op.id and amount=op.amount) end);
 insert into voltmaster_private.financial_command_receipts values(p_owner,p_request,p_command,result,now());return result;
end $fn$;
revoke all on function voltmaster_private.financial_command(uuid,uuid,jsonb,boolean) from public,anon,authenticated;
grant execute on function voltmaster_private.financial_command(uuid,uuid,jsonb,boolean) to service_role;
create or replace function public.execute_financial_operation(p_request uuid,p_command jsonb)
returns jsonb language plpgsql security definer set search_path='' as $fn$
begin
 if auth.uid() is null then raise exception 'Authentication required';end if;
 return voltmaster_private.financial_command(auth.uid(),p_request,p_command,false);
end $fn$;
revoke all on function public.execute_financial_operation(uuid,jsonb) from public,anon;
grant execute on function public.execute_financial_operation(uuid,jsonb) to authenticated;

create table if not exists public.agent_operator_plans (
 id uuid primary key default gen_random_uuid(), revision uuid not null default gen_random_uuid(),
 owner_id uuid not null references public.profiles(id), chat_id uuid not null references public.agent_conversations(id),
 request_id uuid not null, kind text not null check(kind in ('operation_write','project_create')),
 command_json jsonb not null, preview_json jsonb not null,
 status text not null default 'pending' check(status in ('pending','completed','cancelled')),
 result_json jsonb, created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '30 minutes',
 unique(owner_id,request_id,kind)
);
alter table public.agent_operator_plans enable row level security;
revoke all on public.agent_operator_plans from public,anon,authenticated;
grant all on public.agent_operator_plans to service_role;

create or replace function public.agent_prepare_operator_plan(p_owner uuid,p_chat uuid,p_request uuid,p_kind text,p_command jsonb)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare preview jsonb; p public.agent_operator_plans; k text; v jsonb;
begin
 if not exists(select 1 from public.profiles where id=p_owner and is_active) then raise exception 'Active account required';end if;
 if exists(select 1 from public.profiles where id=p_owner and role='director') and not exists(select 1 from public.agent_director_access where user_id=p_owner) then raise exception 'Trusted director required';end if;
 if not exists(select 1 from public.agent_chat_messages where id=p_request and chat_id=p_chat and owner_id=p_owner and kind='user') then raise exception 'Own user request required';end if;
 select * into p from public.agent_operator_plans where owner_id=p_owner and request_id=p_request and kind=p_kind;
 if found then
  if p_kind in ('operation_write','credit_write') and p_command->>'action'='create' then p_command:=jsonb_set(p_command,'{values}',p_command->'values'||jsonb_build_object('operation_date',coalesce(p_command->'values'->'operation_date',p.command_json->'values'->'operation_date'),'payer_company',coalesce(p_command->'values'->'payer_company',p.command_json->'values'->'payer_company')));end if;
  if p_kind='project_delete' then p_command:=p_command||jsonb_build_object('expected_snapshot',p.command_json->'expected_snapshot');end if;
  if p.command_json is distinct from p_command then raise exception 'Existing proposal differs; send a new request';end if;return to_jsonb(p);
 end if;
 if p_kind='project_delete' then
  preview:=voltmaster_private.project_delete_command(p_owner,p_request,p_command,true);
  p_command:=p_command||jsonb_build_object('expected_snapshot',preview);
 elsif p_kind='project_settings_write' then
  preview:=voltmaster_private.project_settings_command(p_owner,p_request,p_command,true);
 elsif p_kind='proposal_write' then
  preview:=voltmaster_private.proposal_command(p_owner,p_request,p_command,true);
 elsif p_kind='production_write' then
  preview:=voltmaster_private.production_command(p_owner,p_request,p_command,true);
 elsif p_kind='document_write' then
  preview:=voltmaster_private.document_command(p_owner,p_request,p_command,true);
 elsif p_kind='volume_write' then
  preview:=voltmaster_private.volume_plan_preview(p_owner,p_command);
 elsif p_kind='project_card_write' then
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
  if not exists(select 1 from public.profiles where id=p_owner and is_active and role in ('director','finance','accountant')) then raise exception 'Financial access denied';end if;
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
 if not exists(select 1 from public.profiles where id=p_owner and is_active and (p.kind in ('obligation_write','volume_write','team_record_write','document_write','production_write','proposal_write') or role in ('director','finance','accountant'))) then raise exception 'Operator access denied';end if;
 if exists(select 1 from public.profiles where id=p_owner and role='director') and not exists(select 1 from public.agent_director_access where user_id=p_owner) then raise exception 'Trusted director required';end if;

 if not exists(select 1 from public.agent_chat_messages where id=p_message and owner_id=p_owner and chat_id=p.chat_id and kind='user' and content=(case when p_cancel then 'ОТМЕНЯЮ ' else 'ПОДТВЕРЖДАЮ ' end)||p.id::text) then raise exception 'Exact chat confirmation required';end if;
 if p.status<>'pending' then return jsonb_build_object('status',p.status,'result',p.result_json);end if;
 if p.expires_at<now() then raise exception 'Plan expired';end if;
 if p_cancel then update public.agent_operator_plans set status='cancelled' where id=p.id;return jsonb_build_object('status','cancelled');end if;
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 if p.kind='project_delete' then
  check_preview:=voltmaster_private.project_delete_command(p_owner,p.id,p.command_json,true);
  if check_preview is distinct from p.preview_json then raise exception 'Record changed; create a new approval';end if;
  result:=voltmaster_private.project_delete_command(p_owner,p.id,p.command_json,false);
 elsif p.kind='project_settings_write' then
  check_preview:=voltmaster_private.project_settings_command(p_owner,p.id,p.command_json,true);
  if check_preview is distinct from p.preview_json then raise exception 'Record changed; create a new approval';end if;
  result:=voltmaster_private.project_settings_command(p_owner,p.id,p.command_json,false);
 elsif p.kind='proposal_write' then
  check_preview:=voltmaster_private.proposal_command(p_owner,p.id,p.command_json,true);
  if check_preview is distinct from p.preview_json then raise exception 'Record changed; create a new approval';end if;
  result:=voltmaster_private.proposal_command(p_owner,p.id,p.command_json,false);
 elsif p.kind='production_write' then
  check_preview:=voltmaster_private.production_command(p_owner,p.id,p.command_json,true);
  if check_preview is distinct from p.preview_json then raise exception 'Record changed; create a new approval';end if;
  result:=voltmaster_private.production_command(p_owner,p.id,p.command_json,false);
 elsif p.kind='document_write' then
  check_preview:=voltmaster_private.document_command(p_owner,p.id,p.command_json,true);
  if check_preview is distinct from p.preview_json then raise exception 'Record changed; create a new approval';end if;
  result:=voltmaster_private.document_command(p_owner,p.id,p.command_json,false);
 elsif p.kind='volume_write' then
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

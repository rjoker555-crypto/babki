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

-- Entire fixture, including receipts and audit events, is rolled back.
do $test$
declare actor uuid:=gen_random_uuid(); project uuid:=gen_random_uuid(); rec uuid:=gen_random_uuid(); pay uuid:=gen_random_uuid(); mat uuid:=gen_random_uuid(); req uuid:=gen_random_uuid(); chat uuid:=gen_random_uuid(); msg uuid:=gen_random_uuid(); confirm_id uuid:=gen_random_uuid(); plan jsonb; cmd jsonb; r jsonb; original jsonb; edited jsonb; opid uuid; caught boolean; role_name text;
begin
 begin
 insert into auth.users(id) values(actor);insert into public.profiles(id,role,is_active) values(actor,'director',true);insert into public.agent_director_access values(actor);
 insert into public.projects(id,name,contractor_company) values(project,'TEST operator fixture','ИП');
 insert into public.receivables(id,project_id,customer,amount,paid_amount) values(rec,project,'TEST customer',1000,100);
 insert into public.payables(id,project_id,counterparty,amount,paid_amount) values(pay,project,'TEST supplier',1000,0);
 insert into public.project_materials(id,project_id,name,actual_amount) values(mat,project,'TEST material',75);
 perform set_config('request.jwt.claim.sub',actor::text,true);
 cmd:=jsonb_build_object('action','create','values',jsonb_build_object('operation_type','income','article','Аванс заказчика','amount',200,'project_id',project,'receivable_id',rec));
 execute 'set local role authenticated';r:=public.execute_financial_operation(req,cmd);execute 'reset role';
 opid:=(r->'operation'->>'id')::uuid;
 if r->>'verified'<>'true' or (r->'operation'->>'operation_date')::date<>(now() at time zone 'Asia/Krasnoyarsk')::date or r->'operation'->>'payer_company'<>'ИП' then raise exception 'Default local date/company/verification failed';end if;
 if (select paid_amount from public.receivables where id=rec)<>300 then raise exception 'Income did not update receivable';end if;
 execute 'set local role authenticated';if public.execute_financial_operation(req,cmd) is distinct from r then raise exception 'Replay differs';end if;execute 'reset role';
 if (select count(*) from public.operations where id=opid)<>1 or (select paid_amount from public.receivables where id=rec)<>300 then raise exception 'Replay duplicated effect';end if;
 select to_jsonb(o) into original from public.operations o where id=opid;
 cmd:=jsonb_build_object('action','update','id',opid,'expected',original,'values',jsonb_build_object('amount',130));
 execute 'set local role authenticated';r:=public.execute_financial_operation(gen_random_uuid(),cmd);execute 'reset role';
 select to_jsonb(o) into edited from public.operations o where id=opid;
 if (edited-'amount'-'updated_at') is distinct from (original-'amount'-'updated_at') or (select paid_amount from public.receivables where id=rec)<>230 then raise exception 'Amount-only edit lost fields/balance';end if;
 caught:=false;begin perform public.execute_financial_operation(gen_random_uuid(),cmd);exception when others then caught:=sqlerrm='Record changed; create a new approval';end;if not caught then raise exception 'Stale edit accepted';end if;
 execute 'set local role authenticated';perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','delete','id',opid,'expected',edited,'values','{}'::jsonb));execute 'reset role';
 if exists(select 1 from public.operations where id=opid) or (select paid_amount from public.receivables where id=rec)<>100 then raise exception 'Delete lost manual receivable baseline';end if;
 cmd:=jsonb_build_object('action','create','values',jsonb_build_object('operation_type','expense','article','ТМЦ','amount',250,'project_id',project,'cost_item_id',mat,'cost_item_type','material'));
 r:=public.execute_financial_operation(gen_random_uuid(),cmd);opid:=(r->'operation'->>'id')::uuid;
 if (select actual_amount from public.project_materials where id=mat)<>325 then raise exception 'Material fact not incremented';end if;
 select to_jsonb(o) into original from public.operations o where id=opid;
 perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','delete','id',opid,'expected',original,'values','{}'::jsonb));
 if (select actual_amount from public.project_materials where id=mat)<>75 then raise exception 'Material baseline lost';end if;
 cmd:=jsonb_build_object('action','create','values',jsonb_build_object('operation_type','expense','article','Погашение кредиторки','amount',250,'project_id',project,'payable_id',pay));
 r:=public.execute_financial_operation(gen_random_uuid(),cmd);opid:=(r->'operation'->>'id')::uuid;
 if (select paid_amount from public.payables where id=pay)<>250 then raise exception 'Payable double increment or missing trigger';end if;
 select to_jsonb(o) into original from public.operations o where id=opid;
 perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','update','id',opid,'expected',original,'values',jsonb_build_object('amount',130)));
 if (select paid_amount from public.payables where id=pay)<>130 then raise exception 'Payable edit recalculation';end if;
 select to_jsonb(o) into original from public.operations o where id=opid;
 perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','delete','id',opid,'expected',original,'values','{}'::jsonb));
 if (select paid_amount from public.payables where id=pay)<>0 then raise exception 'Payable delete recalculation';end if;
 -- Failure after the receivable delta must roll back that delta and the receipt.
 execute $ddl$create function pg_temp.reject_operator_fixture() returns trigger language plpgsql as $body$ begin if current_setting('voltmaster.test_fail_operation',true)='true' then raise exception using errcode='P0993',message='TEST synthetic mid-write failure';end if;return new;end $body$ $ddl$;
execute 'create trigger operator_test_mid_write before insert on public.operations for each row execute function pg_temp.reject_operator_fixture()';
perform set_config('voltmaster.test_fail_operation','true',true);
cmd:=jsonb_build_object('action','create','values',jsonb_build_object('operation_type','income','article','Аванс заказчика','amount',200,'project_id',project,'receivable_id',rec));
 caught:=false;begin perform public.execute_financial_operation(gen_random_uuid(),cmd);exception when sqlstate 'P0993' then caught:=true;end;
 if not caught or (select paid_amount from public.receivables where id=rec)<>100 then raise exception 'Partial failure did not roll back';end if;
 perform set_config('voltmaster.test_fail_operation','false',true);
 foreach role_name in array array['foreman','manager'] loop
 update public.profiles set role=role_name where id=actor;caught:=false;
 execute 'set local role authenticated';begin perform public.execute_financial_operation(gen_random_uuid(),cmd);exception when others then caught:=sqlerrm='Financial access denied';end;execute 'reset role';
 if not caught then raise exception 'Unauthorized finance role %',role_name;end if;end loop;
 update public.profiles set role='director' where id=actor;
 insert into public.agent_conversations(id,owner_id,title) values(chat,actor,'TEST operator');
 insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(msg,actor,chat,'user','Создай объект TEST оператор ёлки на три миллиона на ИП');
 plan:=public.agent_prepare_operator_plan(actor,chat,msg,'project_create',jsonb_build_object('name','TEST оператор ёлки','planned_revenue',3000000,'contractor_company','ИП'));
 insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(confirm_id,actor,chat,'user','ПОДТВЕРЖДАЮ '||(plan->>'id'));
 r:=public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,(plan->>'revision')::uuid,confirm_id);
 if r->'result'->'project'->>'contract_date' is not null or r->'result'->'project'->>'customer' is not null or (r->'result'->'project'->>'planned_revenue')::numeric<>3000000 then raise exception 'Sparse project fabricated fields';end if;
 if public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,(plan->>'revision')::uuid,confirm_id) is distinct from r then raise exception 'Plan replay differs';end if;
 caught:=false;begin perform public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,gen_random_uuid(),confirm_id);exception when others then caught:=sqlerrm='Plan version mismatch';end;if not caught then raise exception 'Wrong revision accepted';end if;
 -- A financial plan freezes both the operation and linked debt, even if the operation itself is unchanged.
msg:=gen_random_uuid();insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(msg,actor,chat,'user','Поступило 50 рублей по долгу TEST');
cmd:=jsonb_build_object('action','create','values',jsonb_build_object('operation_type','income','article','Аванс заказчика','amount',50,'project_id',project,'receivable_id',rec));
plan:=public.agent_prepare_operator_plan(actor,chat,msg,'operation_write',cmd);confirm_id:=gen_random_uuid();
insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(confirm_id,actor,chat,'user','ПОДТВЕРЖДАЮ '||(plan->>'id'));
update public.receivables set paid_amount=110 where id=rec;caught:=false;
begin perform public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,(plan->>'revision')::uuid,confirm_id);exception when others then caught:=sqlerrm='Record changed; create a new approval';end;
if not caught or (select paid_amount from public.receivables where id=rec)<>110 then raise exception 'Stale related debt executed';end if;
update public.receivables set paid_amount=100 where id=rec;
r:=public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,(plan->>'revision')::uuid,confirm_id);
if r->>'status'<>'completed' or (select paid_amount from public.receivables where id=rec)<>150 then raise exception 'Financial plan confirmation failed';end if;
if public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,(plan->>'revision')::uuid,confirm_id) is distinct from r or (select paid_amount from public.receivables where id=rec)<>150 then raise exception 'Financial plan replay changed debt';end if;
if has_function_privilege('anon','public.execute_financial_operation(uuid,jsonb)','execute') or has_function_privilege('authenticated','public.agent_execute_operator_plan(uuid,uuid,uuid,uuid,boolean)','execute') then raise exception 'RPC grants leaked';end if;
 raise exception using errcode='P0992',message='ROLLBACK_OPERATOR_TEST';
 exception when sqlstate 'P0992' then null;end;
end $test$;
select 'PASS: atomic income/expenses, local date, debt/cost recalculation, manual baselines, edit/delete, rollback, replay, role denial, sparse project and revision binding; all fixtures rolled back' as result;

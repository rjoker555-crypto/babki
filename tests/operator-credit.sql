do $test$
declare actor uuid:=gen_random_uuid(); project uuid:=gen_random_uuid(); mat uuid:=gen_random_uuid(); req uuid:=gen_random_uuid(); r jsonb; cmd jsonb; old jsonb; debt jsonb; oid uuid; did uuid; paid jsonb; denied boolean; chat uuid:=gen_random_uuid(); msg uuid:=gen_random_uuid(); confirm_id uuid:=gen_random_uuid(); plan jsonb;
begin
 begin
 insert into auth.users(id) values(actor);insert into public.profiles(id,role,is_active) values(actor,'director',true);insert into public.agent_director_access values(actor);
 perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into public.projects(id,name,contractor_company) values(project,'TEST credit fixture','ООО');insert into public.project_materials(id,project_id,name,actual_amount) values(mat,project,'TEST credit material',75);
 cmd:=jsonb_build_object('action','create','values',jsonb_build_object('operation_type','credit','amount',1000,'credit_kind','money','credit_recipient_company','ООО','counterparty','TEST creditor'),'credit',jsonb_build_object('due_date','2026-11-01','full_repayment_date','2026-12-01'));
 execute 'set local role authenticated';r:=public.execute_credit_operation(req,cmd);execute 'reset role';oid:=(r->'operation'->>'id')::uuid;did:=(r->'credit'->>'id')::uuid;
 if r->>'verified'<>'true' or (r->'credit'->>'amount')::numeric<>1000 then raise exception 'Create credit';end if;
 if public.execute_credit_operation(req,cmd) is distinct from r then raise exception 'Replay credit';end if;
 r:=public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','create','values',jsonb_build_object('operation_type','expense','article','Погашение кредиторки','payer_company','ООО','payable_id',did,'amount',250)));paid:=r->'operation';
 select to_jsonb(o) into old from public.operations o where id=oid;select to_jsonb(p) into debt from public.payables p where id=did;
 denied:=false;begin perform public.execute_credit_operation(gen_random_uuid(),jsonb_build_object('action','delete','id',oid,'expected',old,'expected_credit',debt,'values','{}'::jsonb,'credit','null'::jsonb));exception when others then denied:=sqlerrm='Remove repayments before deleting/converting credit';end;if not denied then raise exception 'Repaid credit deleted';end if;
 denied:=false;begin perform public.execute_credit_operation(gen_random_uuid(),jsonb_build_object('action','update','id',oid,'expected',old,'expected_credit',debt,'values',jsonb_build_object('amount',200),'credit','{}'::jsonb));exception when others then denied:=sqlerrm='Credit less than repayments';end;if not denied then raise exception 'Loan below paid accepted';end if;
 r:=public.execute_credit_operation(gen_random_uuid(),jsonb_build_object('action','update','id',oid,'expected',old,'expected_credit',debt,'values',jsonb_build_object('amount',800),'credit','{}'::jsonb));
 if (r->'credit'->>'paid_amount')::numeric<>250 or (r->'credit'->>'amount')::numeric<>800 then raise exception 'Credit edit lost repayments';end if;
 perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','delete','id',paid->>'id','expected',paid,'values','{}'::jsonb));
 select to_jsonb(o) into old from public.operations o where id=oid;select to_jsonb(p) into debt from public.payables p where id=did;
 perform public.execute_credit_operation(gen_random_uuid(),jsonb_build_object('action','delete','id',oid,'expected',old,'expected_credit',debt,'values','{}'::jsonb,'credit','null'::jsonb));
 if exists(select 1 from public.payables where id=did) or exists(select 1 from public.operations where id=oid) then raise exception 'Credit delete incomplete';end if;
 cmd:=jsonb_build_object('action','create','values',jsonb_build_object('operation_type','expense','article','ТМЦ','amount',250,'project_id',project,'cost_item_id',mat,'cost_item_type','material','credit_kind','material','counterparty','TEST supplier','vat_included',true),'credit',jsonb_build_object('due_date','2026-11-01','full_repayment_date','2026-11-01'));
 insert into public.agent_conversations(id,owner_id,title) values(chat,actor,'TEST credit');insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(msg,actor,chat,'user','TEST ТМЦ с отсрочкой');
 execute 'set local role service_role';plan:=public.agent_prepare_operator_plan(actor,chat,msg,'credit_write',cmd);execute 'reset role';
 if exists(select 1 from public.operations where created_by=actor) or (select actual_amount from public.project_materials where id=mat)<>75 then raise exception 'Plan mutated data';end if;
 insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(confirm_id,actor,chat,'user','ПОДТВЕРЖДАЮ '||(plan->>'id'));
 execute 'set local role service_role';r:=public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,(plan->>'revision')::uuid,confirm_id);execute 'reset role';
 oid:=(r->'result'->'operation'->>'id')::uuid;did:=(r->'result'->'credit'->>'id')::uuid;
 if (select actual_amount from public.project_materials where id=mat)<>325 then raise exception 'Deferred fact';end if;
 select to_jsonb(o) into old from public.operations o where id=oid;select to_jsonb(p) into debt from public.payables p where id=did;
 r:=public.execute_credit_operation(gen_random_uuid(),jsonb_build_object('action','update','id',oid,'expected',old,'expected_credit',debt,'values',jsonb_build_object('credit_kind',null),'credit','null'::jsonb));
 if exists(select 1 from public.payables where id=did) or r->'operation'->>'payable_id' is not null or (select actual_amount from public.project_materials where id=mat)<>325 then raise exception 'Deferred to cash conversion';end if;
 select to_jsonb(o) into old from public.operations o where id=oid;
 perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','delete','id',oid,'expected',old,'values','{}'::jsonb));
 if (select actual_amount from public.project_materials where id=mat)<>75 then raise exception 'Material delete baseline';end if;
 if has_function_privilege('anon','public.execute_credit_operation(uuid,jsonb)','execute') or has_function_privilege('authenticated','public.agent_execute_operator_plan(uuid,uuid,uuid,uuid,boolean)','execute') then raise exception 'Credit grants';end if;
 raise exception using errcode='P0992',message='ROLLBACK_CREDIT_TEST';exception when sqlstate 'P0992' then null;end;
end $test$;
select 'PASS: credit create/edit/repay/delete, deferred material/fact/cash conversion, replay, confirmation and actual service_role RPC; all fixtures rolled back' as result;

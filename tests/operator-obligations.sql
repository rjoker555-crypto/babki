do $test$
declare actor uuid:=gen_random_uuid(); project uuid:=gen_random_uuid(); rid uuid; r jsonb; old jsonb; cmd jsonb; k text; namefield text; denied boolean; operation jsonb; chat uuid:=gen_random_uuid(); msg uuid:=gen_random_uuid(); confirm_id uuid:=gen_random_uuid(); plan jsonb;
begin
 begin
 insert into auth.users(id) values(actor);insert into public.profiles(id,role,is_active) values(actor,'director',true);insert into public.agent_director_access values(actor);perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into public.projects(id,name,contractor_company) values(project,'TEST obligation fixture','ИП');
 for k in select unnest(array['receivable','payable','material','other_expense','subcontractor','creditor']) loop
  namefield:=case k when 'receivable' then 'customer' when 'payable' then 'counterparty' else 'name' end;
  cmd:=jsonb_build_object('kind',k,'action','create','values',jsonb_build_object(namefield,'TEST register '||k)||case when k='creditor' then '{}'::jsonb when k in ('receivable','payable') then jsonb_build_object('project_id',project,'amount',1000,'due_date','2026-11-01') else jsonb_build_object('project_id',project,'planned_amount',500) end);
  execute 'set local role authenticated';r:=public.execute_obligation_command(gen_random_uuid(),cmd);execute 'reset role';rid:=(r->'record'->>'id')::uuid;old:=r->'record';
  if r->>'verified'<>'true' then raise exception 'Register create %',k;end if;
  r:=public.execute_obligation_command(gen_random_uuid(),jsonb_build_object('kind',k,'action','update','id',rid,'expected',old,'values',jsonb_build_object(namefield,'TEST updated '||k)));old:=r->'record';
  if old->>namefield<>'TEST updated '||k then raise exception 'Register update %',k;end if;
  if k='receivable' then
   r:=public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','create','values',jsonb_build_object('operation_type','income','article','Аванс заказчика','amount',200,'project_id',project,'receivable_id',rid)));operation:=r->'operation';
   old:=jsonb_set(old,'{paid_amount}','200');
   denied:=false;begin perform public.execute_obligation_command(gen_random_uuid(),jsonb_build_object('kind',k,'action','update','id',rid,'expected',old,'values',jsonb_build_object('amount',150)));exception when others then denied:=sqlerrm='Register amount below paid';end;if not denied then raise exception 'Below paid register edit';end if;
   denied:=false;begin perform public.execute_obligation_command(gen_random_uuid(),jsonb_build_object('kind',k,'action','delete','id',rid,'expected',old,'values','{}'::jsonb));exception when others then denied:=sqlerrm='Unlink financial operations before deleting register';end;if not denied then raise exception 'Linked register deleted';end if;
   perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','delete','id',operation->>'id','expected',operation,'values','{}'::jsonb));old:=jsonb_set(old,'{paid_amount}','0');
  end if;
  if k='material' then
   denied:=false;begin perform public.execute_obligation_command(gen_random_uuid(),jsonb_build_object('kind',k,'action','update','id',rid,'expected',old,'values',jsonb_build_object('paid_amount',500)));exception when others then denied:=sqlerrm='Unsupported register fields';end;if not denied then raise exception 'Forbidden paid field';end if;
  end if;
  perform public.execute_obligation_command(gen_random_uuid(),jsonb_build_object('kind',k,'action','delete','id',rid,'expected',old,'values','{}'::jsonb));
 end loop;
 insert into public.agent_conversations(id,owner_id,title) values(chat,actor,'TEST register');insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(msg,actor,chat,'user','TEST debit register');
 cmd:=jsonb_build_object('kind','receivable','action','create','values',jsonb_build_object('project_id',project,'customer','TEST confirmed customer','amount',700));
 execute 'set local role service_role';plan:=public.agent_prepare_operator_plan(actor,chat,msg,'obligation_write',cmd);execute 'reset role';
 if exists(select 1 from public.receivables where project_id=project) then raise exception 'Register plan wrote data';end if;
 insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(confirm_id,actor,chat,'user','ПОДТВЕРЖДАЮ '||(plan->>'id'));
 execute 'set local role service_role';r:=public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,(plan->>'revision')::uuid,confirm_id);execute 'reset role';
 if (r->'result'->'record'->>'amount')::numeric<>700 then raise exception 'Register confirmation';end if;
 update public.profiles set role='foreman' where id=actor;
 denied:=false;begin perform public.execute_obligation_command(gen_random_uuid(),cmd);exception when others then denied:=sqlerrm='Financial access denied';end;if not denied then raise exception 'Foreman wrote financial register';end if;
 raise exception using errcode='P0992',message='ROLLBACK_OBLIGATION_TEST';exception when sqlstate 'P0992' then null;end;
end $test$;
select 'PASS: six subject financial registers create/edit/delete, linked deletion and paid-field denial, exact service_role confirmation, foreman denial; fixtures rolled back' as result;

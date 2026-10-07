do $test$
declare actor uuid:=gen_random_uuid(); project uuid:=gen_random_uuid(); foreign_project uuid:=gen_random_uuid(); r jsonb; old jsonb; cmd jsonb; k text; field text; rid uuid; denied boolean; chat uuid:=gen_random_uuid(); msg uuid:=gen_random_uuid(); confirm_id uuid:=gen_random_uuid(); plan jsonb;
begin
 begin
 insert into auth.users(id) values(actor);insert into public.profiles(id,role,is_active) values(actor,'director',true);insert into public.agent_director_access values(actor);perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into public.projects(id,name,responsible_user_id) values(project,'TEST team records',actor),(foreign_project,'TEST foreign team',null);
 for k in select unnest(array['employee','org_expense','event','contact','task']) loop
  field:=case k when 'event' then 'title' when 'task' then 'title' when 'contact' then 'full_name' else 'name' end;
  cmd:=jsonb_build_object('kind',k,'action','create','values',jsonb_build_object(field,'TEST '||k)||case when k in ('task','contact') then jsonb_build_object('project_id',project) when k='event' then jsonb_build_object('event_date','2026-10-06','planned_amount',100) else jsonb_build_object('company','ООО') end);
  execute 'set local role authenticated';r:=public.execute_obligation_command(gen_random_uuid(),cmd);execute 'reset role';rid:=(r->'record'->>'id')::uuid;old:=r->'record';
  r:=public.execute_obligation_command(gen_random_uuid(),jsonb_build_object('kind',k,'action','update','id',rid,'expected',old,'values',jsonb_build_object(field,'TEST updated '||k)));old:=r->'record';
  if k in ('employee','org_expense') then
   perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','create','values',jsonb_build_object('operation_type','expense','article','Орг. расходы','amount',50,'payer_company','ООО',case when k='employee' then 'org_employee_id' else 'org_expense_id' end,rid)));
   r:=public.execute_obligation_command(gen_random_uuid(),jsonb_build_object('kind',k,'action','archive','id',rid,'expected',old,'values','{}'::jsonb));
   if r->'record'->>'active'<>'false' or (select count(*) from public.operations where org_employee_id=rid or org_expense_id=rid)<>1 then raise exception 'Archive destroyed payment history';end if;
  else perform public.execute_obligation_command(gen_random_uuid(),jsonb_build_object('kind',k,'action','delete','id',rid,'expected',old,'values','{}'::jsonb));end if;
 end loop;
 update public.profiles set role='foreman' where id=actor;
 cmd:=jsonb_build_object('kind','task','action','create','values',jsonb_build_object('project_id',foreign_project,'title','TEST denied task'));
 denied:=false;begin perform public.execute_obligation_command(gen_random_uuid(),cmd);exception when others then denied:=sqlerrm='Project access denied';end;if not denied then raise exception 'Foreign task write';end if;
 cmd:=jsonb_set(cmd,'{values,project_id}',to_jsonb(project));
 insert into public.agent_conversations(id,owner_id,title) values(chat,actor,'TEST team task');insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(msg,actor,chat,'user','TEST create task');
 execute 'set local role service_role';plan:=public.agent_prepare_operator_plan(actor,chat,msg,'team_record_write',cmd);execute 'reset role';
 insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(confirm_id,actor,chat,'user','ПОДТВЕРЖДАЮ '||(plan->>'id'));
 execute 'set local role service_role';r:=public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,(plan->>'revision')::uuid,confirm_id);execute 'reset role';
 if r->'result'->>'verified'<>'true' then raise exception 'Foreman task confirmation';end if;
 cmd:=jsonb_build_object('kind','contact','action','create','values',jsonb_build_object('project_id',project,'full_name','TEST contact forbidden'));
 denied:=false;begin perform public.execute_obligation_command(gen_random_uuid(),cmd);exception when others then denied:=sqlerrm='Financial access denied';end;if not denied then raise exception 'Foreman edited contact';end if;
 raise exception using errcode='P0992',message='ROLLBACK_TEAM_RECORDS';exception when sqlstate 'P0992' then null;end;
end $test$;
select 'PASS: five subject team records, archive keeps real fixture payments, foreman assigned task confirmation, foreign project/contact denial; fixtures rolled back' as result;

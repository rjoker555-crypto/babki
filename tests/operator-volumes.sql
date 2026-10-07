do $test$
declare actor uuid:=gen_random_uuid(); project uuid:=gen_random_uuid(); work uuid:=gen_random_uuid(); chat uuid:=gen_random_uuid(); msg uuid:=gen_random_uuid(); confirm_id uuid:=gen_random_uuid(); payload jsonb; plan jsonb; r jsonb; sid uuid; denied boolean;
begin
 begin
 insert into auth.users(id) values(actor);insert into public.profiles(id,role,is_active) values(actor,'foreman',true);
 insert into public.projects(id,name,responsible_user_id) values(project,'TEST agent volumes',actor);
 insert into public.project_work_items(id,project_id,work_name,unit,planned_volume) values(work,project,'TEST cable','м',10);
 insert into public.project_work_progress(work_item_id,completed_volume,progress_date,created_by) values(work,3,'2026-10-01',actor);
 insert into public.agent_conversations(id,owner_id,title) values(chat,actor,'TEST volumes');insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(msg,actor,chat,'user','TEST submit 20m');
 payload:=jsonb_build_object('operation','save','project_id',project,'period_from','2026-10-01','period_to','2026-10-15','items',jsonb_build_array(jsonb_build_object('work_item_id',work,'completed_volume',20,'unit_count',2,'section_label','402–421','progress_date','2026-10-15')));
 execute 'set local role service_role';plan:=public.agent_prepare_operator_plan(actor,chat,msg,'volume_write',payload);execute 'reset role';
 if exists(select 1 from public.work_volume_submissions where project_id=project) or (select count(*) from public.project_work_progress where work_item_id=work)<>1 or exists(select 1 from voltmaster_private.volume_requests where actor_id=actor) then raise exception 'Volume preview left data/receipt';end if;
 insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(confirm_id,actor,chat,'user','ПОДТВЕРЖДАЮ '||(plan->>'id'));
 execute 'set local role service_role';r:=public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,(plan->>'revision')::uuid,confirm_id);execute 'reset role';sid:=(r->'result'->>'submission_id')::uuid;
 if (select completed_volume from public.project_work_items where id=work)<>23 then raise exception 'Volume doubled or manual fact lost';end if;
 execute 'set local role service_role';if public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,(plan->>'revision')::uuid,confirm_id) is distinct from r then raise exception 'Volume plan replay';end if;execute 'reset role';
 msg:=gen_random_uuid();confirm_id:=gen_random_uuid();insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(msg,actor,chat,'user','TEST delete submission');
 payload:=jsonb_build_object('operation','delete','project_id',project,'submission_id',sid,'expected_updated_at',r->'result'->'submission'->>'updated_at');
 execute 'set local role service_role';plan:=public.agent_prepare_operator_plan(actor,chat,msg,'volume_write',payload);execute 'reset role';
 insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(confirm_id,actor,chat,'user','ПОДТВЕРЖДАЮ '||(plan->>'id'));
 update public.projects set responsible_user_id=null where id=project;
 denied:=false;begin perform public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,(plan->>'revision')::uuid,confirm_id);exception when others then denied:=sqlerrm='Project access denied';end;if not denied then raise exception 'Revoked access executed';end if;
 update public.projects set responsible_user_id=actor where id=project;
 execute 'set local role service_role';r:=public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,(plan->>'revision')::uuid,confirm_id);execute 'reset role';
 if exists(select 1 from public.work_volume_submissions where id=sid) or (select completed_volume from public.project_work_items where id=work)<>3 then raise exception 'Volume delete lost manual fact';end if;
 raise exception using errcode='P0992',message='ROLLBACK_VOLUME_AGENT_TEST';exception when sqlstate 'P0992' then null;end;
end $test$;
select 'PASS: actual service_role agent volume preparation without persisted effects, confirmation, manual facts, × count exactly once, replay, revoked assignment and deletion; fixtures rolled back' as result;

do $test$
declare actor uuid:=gen_random_uuid(); req uuid:=gen_random_uuid(); r jsonb; cmd jsonb; old jsonb; project uuid; material jsonb; denied boolean; chat uuid:=gen_random_uuid(); msg uuid:=gen_random_uuid(); confirm_id uuid:=gen_random_uuid(); plan jsonb;
begin
 begin
 insert into auth.users(id) values(actor);insert into public.profiles(id,role,is_active) values(actor,'director',true);insert into public.agent_director_access values(actor);perform set_config('request.jwt.claim.sub',actor::text,true);
 cmd:=jsonb_build_object('action','create','values',jsonb_build_object('name','TEST aggregate card','contractor_company','ИП','planned_revenue',3000000,'status','closed'),'cost_changes',jsonb_build_array(jsonb_build_object('kind','material','action','create','values',jsonb_build_object('name','TEST material','planned_amount',500,'actual_amount',75)),jsonb_build_object('kind','other_expense','action','create','values',jsonb_build_object('name','TEST other','planned_amount',100)),jsonb_build_object('kind','subcontractor','action','create','values',jsonb_build_object('name','TEST sub','planned_amount',300,'has_vat',true))));
 execute 'set local role authenticated';r:=public.execute_project_card(req,cmd);execute 'reset role';old:=r->'project';project:=(old->>'id')::uuid;
 if (select count(*) from public.project_materials where project_id=project)<>1 or (select count(*) from public.subcontractors where project_id=project)<>1 or (select count(*) from public.project_other_expenses where project_id=project)<>1 or old->>'status'<>'closed' then raise exception 'Aggregate creation';end if;
 if public.execute_project_card(req,cmd) is distinct from r then raise exception 'Aggregate replay';end if;
 select to_jsonb(x) into material from public.project_materials x where project_id=project;
 cmd:=jsonb_build_object('action','update','id',project,'expected',old,'values',jsonb_build_object('name','TEST should rollback'),'cost_changes',jsonb_build_array(jsonb_build_object('kind','material','action','update','id',material->>'id','expected',material,'values',jsonb_build_object('actual_amount',90)),jsonb_build_object('kind','other_expense','action','create','values',jsonb_build_object('name','TEST invalid','planned_amount',-1))));
 denied:=false;begin perform public.execute_project_card(gen_random_uuid(),cmd);exception when others then denied:=sqlerrm='Invalid register amount';end;
 if not denied or (select name from public.projects where id=project)<>'TEST aggregate card' or (select actual_amount from public.project_materials where project_id=project)<>75 then raise exception 'Aggregate failure partially committed';end if;
 insert into public.agent_conversations(id,owner_id,title) values(chat,actor,'TEST card');insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(msg,actor,chat,'user','TEST aggregate edit');
 cmd:=jsonb_set(cmd,'{cost_changes}',jsonb_build_array(cmd->'cost_changes'->0));
 execute 'set local role service_role';plan:=public.agent_prepare_operator_plan(actor,chat,msg,'project_card_write',cmd);execute 'reset role';
 if (select actual_amount from public.project_materials where project_id=project)<>75 then raise exception 'Aggregate preview wrote';end if;
 insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(confirm_id,actor,chat,'user','ПОДТВЕРЖДАЮ '||(plan->>'id'));
 execute 'set local role service_role';r:=public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,(plan->>'revision')::uuid,confirm_id);execute 'reset role';
 if r->'result'->>'verified'<>'true' or (select actual_amount from public.project_materials where project_id=project)<>90 then raise exception 'Aggregate confirmed edit';end if;
 raise exception using errcode='P0992',message='ROLLBACK_CARD_TEST';exception when sqlstate 'P0992' then null;end;
end $test$;
select 'PASS: atomic project + three cost lists, closed status, replay, mid-list failure rollback and service_role confirmation; fixtures rolled back' as result;

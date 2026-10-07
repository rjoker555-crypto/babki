do $test$
declare actor uuid:=gen_random_uuid();r jsonb;old jsonb;cmd jsonb;denied boolean;rid uuid;request uuid:=gen_random_uuid();chat uuid:=gen_random_uuid();msg uuid:=gen_random_uuid();confirm_id uuid:=gen_random_uuid();plan jsonb;
begin begin
 insert into auth.users(id) values(actor);insert into public.profiles(id,role,is_active) values(actor,'manager',true);perform set_config('request.jwt.claim.sub',actor::text,true);
 cmd:=jsonb_build_object('action','create','values',jsonb_build_object('name','TEST existing KP','amount',1000,'status','review','segment','government'));
 if voltmaster_private.proposal_command(actor,request,cmd,true)->'proposal'->>'name'<>'TEST existing KP' or exists(select 1 from public.commercial_proposals where created_by=actor) then raise exception 'KP preview';end if;
 execute 'set local role authenticated';r:=public.execute_proposal_command(request,cmd);execute 'reset role';old:=r->'proposal';rid:=(old->>'id')::uuid;
 if public.execute_proposal_command(request,cmd) is distinct from r then raise exception 'KP replay';end if;
 denied:=false;begin perform public.execute_proposal_command(gen_random_uuid(),jsonb_build_object('action','update','id',rid,'expected',old,'values',jsonb_build_object('status','lost')));exception when others then denied:=sqlerrm='Invalid proposal values';end;if not denied then raise exception 'Lost without reason accepted';end if;
 insert into public.agent_conversations(id,owner_id,title) values(chat,actor,'TEST KP');insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(msg,actor,chat,'user','TEST KP lost');
 cmd:=jsonb_build_object('action','update','id',rid,'expected',old,'values',jsonb_build_object('status','lost','lost_reason','TEST explicit refusal'));
 execute 'set local role service_role';plan:=public.agent_prepare_operator_plan(actor,chat,msg,'proposal_write',cmd);execute 'reset role';
 insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(confirm_id,actor,chat,'user','ПОДТВЕРЖДАЮ '||(plan->>'id'));
 execute 'set local role service_role';r:=public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,(plan->>'revision')::uuid,confirm_id);execute 'reset role';old:=r->'result'->'proposal';
 if old->>'status'<>'lost' or old->>'lost_reason'<>'TEST explicit refusal' or exists(select 1 from public.operations where created_by=actor) then raise exception 'KP changed finances or status wrong';end if;
 denied:=false;begin perform public.execute_proposal_command(gen_random_uuid(),jsonb_build_object('action','delete','id',rid,'expected',old,'values','{}'::jsonb));exception when others then denied:=sqlerrm='Proposal write access denied';end;if not denied then raise exception 'Manager deleted KP';end if;
 update public.profiles set role='finance' where id=actor;perform public.execute_proposal_command(gen_random_uuid(),jsonb_build_object('action','delete','id',rid,'expected',old,'values','{}'::jsonb));if exists(select 1 from public.commercial_proposals where id=rid) then raise exception 'KP not deleted';end if;
 raise exception using errcode='P0992',message='ROLLBACK_KP_TEST';exception when sqlstate 'P0992' then null;end;end $test$;
select 'PASS: checked KP create/confirmed status update/delete, exact expected, replay, explicit loss reason, manager delete denial, no financial operation; fixtures rolled back' as result;

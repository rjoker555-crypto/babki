begin;
do $$ declare u uuid; a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); p uuid; m uuid:=gen_random_uuid(); caught boolean:=false; r jsonb; begin
 select a.user_id into u from public.agent_director_access a join public.profiles f on f.id=a.user_id where f.role='director' and f.is_active limit 1;
 insert into public.agent_conversations(id,owner_id) values(a,u),(b,u);
 insert into public.agent_action_plans(owner_id,chat_id,action,table_name,values_json) values(u,a,'insert','projects','{"name":"TEST approved in original thread"}') returning id into p;
 insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(m,u,b,'user','ПОДТВЕРЖДАЮ '||p);
 begin perform public.agent_execute_plan(p,u,m,false); exception when others then caught:=true; end;
 if not caught then raise exception 'Another thread authorized the plan'; end if;
 m:=gen_random_uuid();
 insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(m,u,a,'user','ПОДТВЕРЖДАЮ '||p);
 r:=public.agent_execute_plan(p,u,m,false);
 if r->>'status'<>'completed' then raise exception 'Original thread approval failed'; end if;
 if not exists(select 1 from public.agent_protocol_entries where plan_id=p and actor_id=u and entry_type='instruction') then raise exception 'Instruction initiator missing'; end if;
 if not exists(select 1 from public.agent_protocol_entries where plan_id=p and actor_id=u and entry_type='action') then raise exception 'Execution initiator missing'; end if;
 if not exists(select 1 from public.agent_activity_events where entity_id=(r->'result'->>'id')::uuid and actor_id=u) then raise exception 'Application event actor missing'; end if;
end $$;
rollback;
select 'PASS: cross-thread approval blocked; original approval, instruction and execution attribution verified; rolled back' as verification;

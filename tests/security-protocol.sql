do $test$
declare actor uuid:=gen_random_uuid();foreman uuid:=gen_random_uuid();plan uuid:=gen_random_uuid();leaked boolean;hardened boolean;
begin
 hardened:=exists(select 1 from pg_policies where policyname='security_raw_plan_scope');
 begin
 insert into auth.users(id) values(actor),(foreman);insert into public.profiles(id,role,is_active) values(actor,'director',true),(foreman,'foreman',true);
 insert into public.agent_action_plans(id,owner_id,action,table_name,values_json) values(plan,actor,'insert','projects','{"name":"TEST protocol","planned_revenue":123456}');
 perform set_config('request.jwt.claim.sub',foreman::text,true);execute 'set local role authenticated';
 select exists(select 1 from public.agent_protocol_entries where plan_id=plan and summary like '%123456%') into leaked;
 if hardened=leaked then raise exception 'Protocol permission assessment mismatch';end if;
 execute 'reset role';raise exception using errcode='P0996',message='ROLLBACK_PROTOCOL_TEST';
 exception when sqlstate 'P0996' then null;end;
end $test$;

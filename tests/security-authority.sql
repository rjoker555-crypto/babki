do $test$
declare director uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid(); target uuid:=gen_random_uuid(); r text; denied boolean;
begin
 begin
 insert into auth.users(id) values(director),(actor),(target);
 insert into public.profiles(id,role,is_active) values(director,'director',true),(actor,'finance',true),(target,'foreman',false);
 insert into public.agent_director_access(user_id) values(director);
 foreach r in array array['finance','accountant','manager','foreman'] loop
  update public.profiles set role=r where id=actor;
  perform set_config('request.jwt.claim.sub',actor::text,true); execute 'set local role authenticated';
  denied:=false;begin update public.profiles set role='director' where id=actor;exception when insufficient_privilege then denied:=true;end;
  execute 'reset role';if (select role from public.profiles where id=actor)<>r then raise exception 'Self escalation %',r;end if;
  execute 'set local role authenticated';
  begin update public.profiles set is_active=true where id=target;exception when insufficient_privilege then null;end;
  begin insert into public.profiles(id,role,is_active) values(gen_random_uuid(),'director',true);raise exception 'Unauthorized profile insert';exception when insufficient_privilege then null;end;
  begin delete from public.profiles where id=target;exception when insufficient_privilege then null;end;
  execute 'reset role';if not exists(select 1 from public.profiles where id=target and not is_active) then raise exception 'Unauthorized target authority changed';end if;
 end loop;
 perform set_config('request.jwt.claim.sub',director::text,true); execute 'set local role authenticated';
 update public.profiles set role='accountant',is_active=true where id=target;if not found then raise exception 'Director authority broken';end if;
 execute 'reset role';update public.profiles set is_active=false where id=director;
 execute 'set local role authenticated';begin update public.profiles set role='director' where id=actor;exception when insufficient_privilege then null;end;
 execute 'reset role';if (select role from public.profiles where id=actor)='director' then raise exception 'Inactive director bypass';end if;
 raise exception using errcode='P0996',message='ROLLBACK_AUTHORITY';
 exception when sqlstate 'P0996' then null;end;
end $test$;
select 'authority tests passed; synthetic rows rolled back' as result;

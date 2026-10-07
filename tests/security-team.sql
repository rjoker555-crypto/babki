do $test$
declare director uuid:=gen_random_uuid();foreman uuid:=gen_random_uuid();finance uuid:=gen_random_uuid();proj uuid:=gen_random_uuid();denied boolean;
begin
 begin
 insert into auth.users(id) values(director),(foreman),(finance);
 insert into public.profiles(id,role,is_active) values(director,'director',true),(foreman,'foreman',true),(finance,'finance',true);
 insert into public.agent_director_access(user_id) values(director);
 insert into public.projects(id,name) values(proj,'TEST security team');
 perform set_config('request.jwt.claim.sub',finance::text,true);execute 'set local role authenticated';
 denied:=false;begin insert into public.project_team_members(project_id,user_id,assigned_by) values(proj,finance,finance);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Finance self assignment bypass';end if;
 execute 'reset role';perform set_config('request.jwt.claim.sub',director::text,true);execute 'set local role authenticated';
 insert into public.project_team_members(project_id,user_id,assigned_by) values(proj,foreman,director);
 execute 'reset role';perform set_config('request.jwt.claim.sub',foreman::text,true);execute 'set local role authenticated';
 if not exists(select 1 from public.project_team_members where user_id=foreman and project_id=proj) then raise exception 'Own assignment invisible';end if;
 update public.project_team_members set is_active=false where user_id=foreman;if found then raise exception 'Foreman assignment mutation';end if;
 execute 'reset role';raise exception using errcode='P0995',message='ROLLBACK_TEAM';
 exception when sqlstate 'P0995' then null;end;
end $test$;
select 'team administrator and self-assignment restrictions passed; synthetic rows rolled back' as result;

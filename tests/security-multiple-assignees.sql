do $test$
declare director uuid:=gen_random_uuid();f1 uuid:=gen_random_uuid();f2 uuid:=gen_random_uuid();finance uuid:=gen_random_uuid();p1 uuid:=gen_random_uuid();p2 uuid:=gen_random_uuid();foreign_p uuid:=gen_random_uuid();w uuid:=gen_random_uuid();denied boolean;
begin
 begin
 insert into auth.users(id) values(director),(f1),(f2),(finance);
 insert into public.profiles(id,role,is_active) values(director,'director',true),(f1,'foreman',true),(f2,'foreman',true),(finance,'finance',true);
 insert into public.agent_director_access(user_id) values(director);
 insert into public.projects(id,name,responsible_user_id) values(p1,'TEST team own',f1),(p2,'TEST team shared',finance),(foreign_p,'TEST team foreign',finance);
 insert into public.project_team_members(project_id,user_id,assigned_by) values(p2,f1,director),(p2,f2,director);
 insert into public.project_work_items(id,project_id,work_name,unit,planned_volume) values(w,p2,'TEST team work','м',10);
 perform set_config('request.jwt.claim.sub',f1::text,true);execute 'set local role authenticated';
 if not exists(select 1 from public.project_work_items where id=w) or (select count(*) from public.foreman_projects() where id in(p1,p2))<>2 or exists(select 1 from public.foreman_projects() where id=foreign_p) then raise exception 'Responsible/team/foreign scope incorrect';end if;
 update public.project_work_items set comment='TEST team authorized update' where id=w;if not found then raise exception 'Team update denied';end if;
 perform public.submit_work_volumes(gen_random_uuid(),jsonb_build_object('operation','save','project_id',p2,'period_from','2026-10-01','period_to','2026-10-06','items',jsonb_build_array(jsonb_build_object('work_item_id',w,'completed_volume',2,'unit_count',1,'progress_date','2026-10-06'))));
 execute 'reset role';perform set_config('request.jwt.claim.sub',f2::text,true);execute 'set local role authenticated';
 if not exists(select 1 from public.project_work_items where id=w) then raise exception 'Second team member denied';end if;
 execute 'reset role';update public.project_team_members set is_active=false where project_id=p2 and user_id=f2;
 execute 'set local role authenticated';if exists(select 1 from public.project_work_items where id=w) then raise exception 'Revoked assignment still allowed';end if;
 denied:=false;begin perform public.submit_work_volumes(gen_random_uuid(),jsonb_build_object('operation','save','project_id',p2));exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'RPC revoked assignment allowed';end if;
 execute 'reset role';raise exception using errcode='P0994',message='ROLLBACK_MULTI_TEAM';
 exception when sqlstate 'P0994' then null;end;
end $test$;
select 'multiple team members, responsible account, foreign object, atomic volume RPC and revoked assignment checks passed' as result;

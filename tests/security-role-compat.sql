do $test$
declare director uuid:=gen_random_uuid();finance uuid:=gen_random_uuid();foreman uuid:=gen_random_uuid();inactive uuid:=gen_random_uuid();own_project uuid:=gen_random_uuid();foreign_project uuid:=gen_random_uuid();own_work uuid:=gen_random_uuid();foreign_work uuid:=gen_random_uuid();denied boolean;
begin
 begin
 insert into auth.users(id) values(director),(finance),(foreman),(inactive);
 insert into public.profiles(id,role,is_active) values(director,'director',true),(finance,'finance',true),(foreman,'foreman',true),(inactive,'foreman',false);
 insert into public.agent_director_access(user_id) values(director);
 insert into public.projects(id,name,responsible_user_id) values(own_project,'TEST security own',foreman),(foreign_project,'TEST security foreign',finance);
 insert into public.project_work_items(id,project_id,work_name) values(own_work,own_project,'TEST security own work'),(foreign_work,foreign_project,'TEST security foreign work');
 perform set_config('request.jwt.claim.sub',director::text,true);execute 'set local role authenticated';
 update public.profiles set role='accountant' where id=finance;if not found then raise exception 'Trusted account administration broken';end if;
 execute 'reset role';perform set_config('request.jwt.claim.sub',foreman::text,true);execute 'set local role authenticated';
 if not exists(select 1 from public.project_work_items where id=own_work) or exists(select 1 from public.project_work_items where id=foreign_work) then raise exception 'Own/foreign work scope broken';end if;
 update public.project_work_items set comment='TEST legitimate own change' where id=own_work;if not found then raise exception 'Own update broken';end if;
 if not exists(select 1 from public.foreman_projects() where id=own_project) or exists(select 1 from public.foreman_projects() where id=foreign_project) then raise exception 'Project RPC scope broken';end if;
 perform public.foreman_add_subcontractor(own_project,'TEST own subcontractor',null);
 denied:=false;begin perform public.foreman_add_subcontractor(foreign_project,'TEST foreign subcontractor',null);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Foreign RPC write allowed';end if;
 denied:=false;begin update public.profiles set is_active=true where id=inactive;exception when insufficient_privilege then denied:=true;end;
 -- Foreman existing RLS can return 0 rows; both 0 rows and permission error deny activation.
 if exists(select 1 from public.foreman_subcontractors() where project_id=foreign_project) then raise exception 'Foreign subcontractor read allowed';end if;
 execute 'reset role';perform set_config('request.jwt.claim.sub',inactive::text,true);execute 'set local role authenticated';
 if exists(select 1 from public.foreman_projects() where id=own_project) or exists(select 1 from public.project_work_items where id=own_work) then raise exception 'Inactive access allowed';end if;
 execute 'reset role';raise exception using errcode='P0997',message='ROLLBACK_ROLE_COMPAT';
 exception when sqlstate 'P0997' then null;end;
end $test$;

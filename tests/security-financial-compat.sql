do $test$
declare actor uuid:=gen_random_uuid();project uuid:=gen_random_uuid();op uuid:=gen_random_uuid();work uuid:=gen_random_uuid();r text;changed bigint;
begin
 begin
 insert into auth.users(id) values(actor);insert into public.profiles(id,role,is_active) values(actor,'director',true);insert into public.agent_director_access(user_id) values(actor);
 insert into public.projects(id,name) values(project,'TEST finance compatibility');insert into public.project_work_items(id,project_id,work_name) values(work,project,'TEST manager work');
 foreach r in array array['director','finance','accountant'] loop
  update public.profiles set role=r where id=actor;perform set_config('request.jwt.claim.sub',actor::text,true);execute 'set local role authenticated';
  insert into public.operations(id,project_id,operation_date,operation_type,article,amount) values(op,project,'2026-10-06','income','TEST finance compatibility',100);
  update public.operations set amount=125 where id=op;get diagnostics changed=row_count;if changed<>1 then raise exception 'Financial edit broken %',r;end if;
  if not exists(select 1 from public.operations where id=op and amount=125) then raise exception 'Financial read broken %',r;end if;
  delete from public.operations where id=op;get diagnostics changed=row_count;if changed<>1 then raise exception 'Financial deletion permission broken %',r;end if;
  execute 'reset role';
 end loop;
 update public.profiles set role='manager' where id=actor;execute 'set local role authenticated';
 if not exists(select 1 from public.foreman_projects() where id=project) then raise exception 'Manager project visibility broken';end if;
 update public.project_work_items set comment='TEST permitted manager edit' where id=work;if not found then raise exception 'Manager production edit broken';end if;
 execute 'reset role';raise exception using errcode='P0992',message='ROLLBACK_FINANCIAL_COMPAT';
 exception when sqlstate 'P0992' then null;end;
end $test$;
select 'director/finance/accountant synthetic financial CRUD and manager production compatibility passed; all rows rolled back' as result;

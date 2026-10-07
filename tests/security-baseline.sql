-- Read-only assessment plus synthetic probes that roll back all company/auth rows.
create temporary table security_audit_result(value jsonb);
do $audit$
declare t record;n bigint;anon_reads integer:=0;actor uuid:=gen_random_uuid();foreman uuid:=gen_random_uuid();foreign_project uuid:=gen_random_uuid();work uuid:=gen_random_uuid();
 escalation boolean:=false;foreign_read boolean:=false;foreign_write boolean:=false;denied boolean;changed bigint;
begin
 perform set_config('request.jwt.claim.sub','',true);
 for t in select c.relname from pg_class c join pg_namespace s on s.oid=c.relnamespace where s.nspname='public' and c.relkind='r' and has_table_privilege('anon',c.oid,'SELECT') loop
  execute 'set local role anon';execute format('select count(*) from public.%I',t.relname) into n;execute 'reset role';
  if n<>0 then raise exception 'Anonymous rows exposed: %',t.relname;end if;anon_reads:=anon_reads+1;
 end loop;
 execute 'set local role anon';select count(*) into n from storage.objects;execute 'reset role';if n<>0 then raise exception 'Anonymous storage exposed';end if;
 begin
  insert into auth.users(id) values(actor),(foreman);
  insert into public.profiles(id,role,is_active) values(actor,'finance',true),(foreman,'foreman',true);
  insert into public.projects(id,name,responsible_user_id) values(foreign_project,'TEST security foreign object',actor);
  insert into public.project_work_items(id,project_id,work_name,unit,planned_volume) values(work,foreign_project,'TEST security work','м',10);
  perform set_config('request.jwt.claim.sub','',true);execute 'set local role anon';
  denied:=false;begin insert into public.projects(name) values('TEST anon insert');exception when insufficient_privilege then denied:=true;end;
  if not denied then raise exception 'Anonymous insert allowed';end if;
  update public.projects set name='TEST anon update' where id=foreign_project;get diagnostics changed=row_count;if changed<>0 then raise exception 'Anonymous update allowed';end if;
  delete from public.projects where id=foreign_project;get diagnostics changed=row_count;if changed<>0 then raise exception 'Anonymous delete allowed';end if;
  denied:=false;begin insert into storage.objects(bucket_id,name) values('project-documents','TEST security anon');exception when insufficient_privilege then denied:=true;end;
  if not denied then raise exception 'Anonymous storage insert allowed';end if;execute 'reset role';
  perform set_config('request.jwt.claim.sub',actor::text,true);execute 'set local role authenticated';
  update public.profiles set role='director' where id=actor;get diagnostics changed=row_count;escalation:=changed=1;execute 'reset role';
  perform set_config('request.jwt.claim.sub',foreman::text,true);execute 'set local role authenticated';
  select exists(select 1 from public.project_work_items where id=work) into foreign_read;
  update public.project_work_items set comment='TEST unauthorized modification' where id=work;get diagnostics changed=row_count;foreign_write:=changed=1;
  execute 'reset role';raise exception using errcode='P0998',message='ROLLBACK_SECURITY_SYNTHETIC';
 exception when sqlstate 'P0998' then null;
 end;
 insert into security_audit_result values(jsonb_build_object('anonymous_tables_tested',anon_reads,'anonymous_read_denied',true,'anonymous_project_crud_denied',true,'anonymous_storage_denied',true,'finance_self_escalation_possible',escalation,'foreman_foreign_work_read_possible',foreign_read,'foreman_foreign_work_write_possible',foreign_write,'synthetic_rows_rolled_back',true));
end $audit$;
select value from security_audit_result;

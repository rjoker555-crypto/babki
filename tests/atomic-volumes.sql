-- This block can run before a migration commits. All synthetic records are rolled back by the sentinel.
do $test$
declare actor uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); inactive uuid:=gen_random_uuid();
 project uuid:=gen_random_uuid(); other_project uuid:=gen_random_uuid(); work uuid:=gen_random_uuid(); other_work uuid:=gen_random_uuid();
 request uuid:=gen_random_uuid(); payload jsonb; result jsonb; repeated jsonb; sid uuid; stamp text; rejected boolean;
begin
 begin
  insert into auth.users(id) values(actor),(outsider),(inactive);
  insert into public.profiles(id,role,is_active) values(actor,'foreman',true),(outsider,'finance',true),(inactive,'foreman',false);
  insert into public.projects(id,name,responsible_user_id) values(project,'TEST atomic volumes',actor),(other_project,'TEST other project',outsider);
  insert into public.project_work_items(id,project_id,work_name,unit,planned_volume) values(work,project,'TEST cable','м',10),(other_work,other_project,'TEST other cable','м',10);
  insert into public.project_work_progress(work_item_id,completed_volume,progress_date,created_by) values(work,3,'2026-10-01',actor);
  perform set_config('request.jwt.claim.sub',actor::text,true);
  payload:=jsonb_build_object('operation','save','project_id',project,'period_from','2026-10-01','period_to','2026-10-15','items',jsonb_build_array(
   jsonb_build_object('work_item_id',work,'completed_volume',20,'unit_count',2,'section_label','402–421','progress_date','2026-10-15')));
  result:=public.submit_work_volumes(request,payload); sid:=(result->>'submission_id')::uuid; stamp:=result->'submission'->>'updated_at';
  if (select completed_volume from public.project_work_items where id=work)<>23 then raise exception 'Fact total incorrect/double unit multiplication'; end if;
  if not exists(select 1 from public.work_volume_submission_items i join public.project_work_progress p on p.id=i.progress_id
   where i.submission_id=sid and p.submission_item_id=i.id and i.unit_count=2 and i.section_label='402–421' and p.created_by=actor) then raise exception 'Bidirectional link/metadata failed'; end if;
  repeated:=public.submit_work_volumes(request,payload);
  if repeated<>result or (select count(*) from public.project_work_progress where work_item_id=work)<>2 then raise exception 'Duplicate retry'; end if;
  rejected:=false;
  begin perform public.submit_work_volumes(request,payload||'{"comment":"changed"}'); exception when others then rejected:=true; end;
  if not rejected then raise exception 'Request payload replacement allowed'; end if;
  -- Changing the payload to include a foreign work cannot partially replace the original submission.
  rejected:=false;
  begin perform public.submit_work_volumes(gen_random_uuid(),payload||jsonb_build_object('submission_id',sid,'expected_updated_at',stamp,'items',jsonb_build_array(
   jsonb_build_object('work_item_id',work,'completed_volume',5,'unit_count',1,'progress_date','2026-10-15'),
   jsonb_build_object('work_item_id',other_work,'completed_volume',7,'unit_count',1,'progress_date','2026-10-15')))); exception when insufficient_privilege then rejected:=true; end;
  if not rejected or (select completed_volume from public.project_work_items where id=work)<>23 then raise exception 'Failed replacement changed facts'; end if;
  -- Force a failure after the old facts were removed, proving rollback of the entire command.
  perform set_config('voltmaster.test_work',work::text,true);
  execute $ddl$create function pg_temp.fail_test_progress() returns trigger language plpgsql as $f$
   begin if new.work_item_id=current_setting('voltmaster.test_work',true)::uuid and new.completed_volume=777 then
    raise exception using errcode='ZX002',message='Synthetic mid-command failure'; end if; return new; end $f$$ddl$;
  execute 'create trigger test_atomic_failure before insert on public.project_work_progress for each row execute function pg_temp.fail_test_progress()';
  rejected:=false;
  begin perform public.submit_work_volumes(gen_random_uuid(),payload||jsonb_build_object('submission_id',sid,'expected_updated_at',stamp,'items',jsonb_build_array(
   jsonb_build_object('work_item_id',work,'completed_volume',777,'unit_count',1,'progress_date','2026-10-15')))); exception when sqlstate 'ZX002' then rejected:=true; end;
  if not rejected or (select completed_volume from public.project_work_items where id=work)<>23 or
   (select count(*) from public.work_volume_submission_items where submission_id=sid)<>1 then raise exception 'Mid-command failure left partial state'; end if;
  execute 'drop trigger test_atomic_failure on public.project_work_progress';
  rejected:=false;
  begin perform public.submit_work_volumes(gen_random_uuid(),payload||jsonb_build_object('submission_id',sid,'expected_updated_at','2000-01-01T00:00:00Z')); exception when serialization_failure then rejected:=true; end;
  if not rejected then raise exception 'Stale edit allowed'; end if;
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  rejected:=false;
  begin perform public.submit_work_volumes(gen_random_uuid(),payload); exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'Unassigned financial role bypassed project boundary'; end if;
  -- Even a profile promotion does not grant the trusted director capability.
  update public.profiles set role='director' where id=outsider;
  rejected:=false;
  begin perform public.submit_work_volumes(gen_random_uuid(),payload); exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'Profile promotion bypassed allowlist'; end if;
  perform set_config('request.jwt.claim.sub',inactive::text,true);
  rejected:=false;
  begin perform public.submit_work_volumes(gen_random_uuid(),payload); exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'Inactive account allowed'; end if;
  perform set_config('request.jwt.claim.sub','',true);
  rejected:=false;
  begin perform public.submit_work_volumes(gen_random_uuid(),payload); exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'Anonymous actor allowed'; end if;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  execute 'set local role authenticated';
  repeated:=public.submit_work_volumes(request,payload);
  if repeated<>result then raise exception 'Authenticated RPC failed'; end if;
  execute 'reset role';
  result:=public.submit_work_volumes(gen_random_uuid(),payload||jsonb_build_object('submission_id',sid,'expected_updated_at',stamp,'items',jsonb_build_array(
   jsonb_build_object('work_item_id',work,'completed_volume',5,'unit_count',1,'section_label','new','progress_date','2026-10-15'))));
  if (select completed_volume from public.project_work_items where id=work)<>8 then raise exception 'Replacement lost manual facts'; end if;
  stamp:=result->'submission'->>'updated_at';
  result:=public.submit_work_volumes(gen_random_uuid(),jsonb_build_object('operation','delete','project_id',project,'submission_id',sid,'expected_updated_at',stamp));
  if (select completed_volume from public.project_work_items where id=work)<>3 or (select count(*) from public.project_work_progress where work_item_id=work)<>1 then raise exception 'Deletion lost manual facts'; end if;
  if exists(select 1 from public.work_volume_submissions where id=sid) then raise exception 'Delete did not complete'; end if;
  if has_function_privilege('anon','public.submit_work_volumes(uuid,jsonb)','EXECUTE') or
     has_table_privilege('authenticated','voltmaster_private.volume_requests','SELECT') then raise exception 'Unexpected client grant'; end if;
  raise exception using errcode='ZX001',message='All checks passed: rollback synthetic data';
 exception when sqlstate 'ZX001' then null;
 end;
 if exists(select 1 from auth.users where id in(actor,outsider,inactive)) or exists(select 1 from public.projects where id in(project,other_project)) then raise exception 'Test records leaked'; end if;
end $test$;

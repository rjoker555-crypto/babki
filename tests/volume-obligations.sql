do $test$
declare director uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
 project uuid:=gen_random_uuid(); work uuid:=gen_random_uuid(); rule uuid; obligation uuid; notification uuid;
 config jsonb; result jsonb; rejected boolean; sid uuid; forged uuid:=gen_random_uuid(); forged_item uuid:=gen_random_uuid(); forged_progress uuid:=gen_random_uuid();
begin
 begin
  insert into auth.users(id) values(director),(actor),(outsider);
  insert into public.profiles(id,role,is_active) values(director,'director',true),(actor,'foreman',true),(outsider,'director',true);
  insert into public.agent_director_access(user_id) values(director);
  insert into public.projects(id,name,responsible_user_id) values(project,'TEST reminders',actor);
  insert into public.project_work_items(id,project_id,work_name,unit,planned_volume) values(work,project,'TEST cable','м',10);
  config:=jsonb_build_object('project_id',project,'assignee_id',actor,'authority_basis','Явно установленный тестовый регламент','due_day',15,
   'reminder_time','09:30','short_month_policy','last_day','period_offset',-1,'enabled',true);
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  rejected:=false;
  begin perform public.configure_volume_obligation(config); exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'Untrusted director can configure'; end if;
  perform set_config('request.jwt.claim.sub',director::text,true);
  rejected:=false;
  begin perform public.configure_volume_obligation(config-'reminder_time'); exception when others then rejected:=true; end;
  if not rejected then raise exception 'Unknown notification time invented'; end if;
  result:=public.configure_volume_obligation(config);rule:=(result->>'id')::uuid;
  update voltmaster_private.volume_rules set updated_at='2026-10-01 00:00+07' where id=rule;
  perform voltmaster_private.run_volume_obligations('2026-10-07 12:00+07',rule);
  if exists(select 1 from voltmaster_private.volume_obligations where rule_id=rule) then raise exception 'Task created before 8th'; end if;
  perform voltmaster_private.run_volume_obligations('2026-10-08 09:29+07',rule);
  select id into obligation from voltmaster_private.volume_obligations where rule_id=rule;
  if obligation is null or exists(select 1 from public.in_app_notifications where obligation_id=obligation) then raise exception 'Task/time boundary failed'; end if;
  perform voltmaster_private.run_volume_obligations('2026-10-08 09:30+07',rule);
  perform voltmaster_private.run_volume_obligations('2026-10-08 23:59+07',rule);
  if (select count(*) from public.in_app_notifications where obligation_id=obligation)<>1 then raise exception 'Daily dedupe failed'; end if;
  select id into notification from public.in_app_notifications where obligation_id=obligation;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  execute 'set local role authenticated';
  if not public.read_in_app_notification(notification) then raise exception 'Own read failed'; end if;
  result:=public.get_my_volume_obligations();
  if result->>'can_configure'<>'false' or jsonb_array_length(result->'tasks')<>1 then raise exception 'Personal tasks failed'; end if;
  execute 'reset role';
  if (select status from voltmaster_private.volume_obligations where id=obligation)<>'open' then raise exception 'Read completed task'; end if;
  update public.project_work_tasks set status='done' where id=(select task_id from voltmaster_private.volume_obligations where id=obligation);
  perform voltmaster_private.run_volume_obligations('2026-10-08 12:00+07',rule);
  if (select status from voltmaster_private.volume_obligations where id=obligation)<>'open' then raise exception 'Generic task status completed obligation'; end if;
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  execute 'set local role authenticated';
  if public.read_in_app_notification(notification) or exists(select 1 from public.in_app_notifications where id=notification) then raise exception 'Other user notification leaked'; end if;
  result:=public.get_my_volume_obligations();if jsonb_array_length(result->'tasks')<>0 then raise exception 'Other user task leaked'; end if;
  execute 'reset role';
  perform voltmaster_private.run_volume_obligations('2026-10-12 10:00+07',rule);
  if (select count(*) from public.in_app_notifications where obligation_id=obligation)<>2 then raise exception 'Downtime sent a backlog'; end if;
  update public.projects set responsible_user_id=outsider where id=project;
  perform voltmaster_private.run_volume_obligations('2026-10-13 10:00+07',rule);
  if (select count(*) from public.in_app_notifications where obligation_id=obligation)<>2 then raise exception 'Old assignee still notified'; end if;
  update public.projects set responsible_user_id=actor where id=project;
  -- Fabricating author fields in the legacy tables cannot manufacture an authenticated receipt.
  insert into public.work_volume_submissions(id,project_id,period_from,period_to,created_by) values(forged,project,'2026-09-01','2026-09-30',actor);
  insert into public.work_volume_submission_items(id,submission_id,work_item_id,completed_volume,progress_date,unit_count) values(forged_item,forged,work,1,'2026-09-30',1);
  insert into public.project_work_progress(id,work_item_id,completed_volume,progress_date,created_by,submission_item_id) values(forged_progress,work,1,'2026-09-30',actor,forged_item);
  update public.work_volume_submission_items set progress_id=forged_progress where id=forged_item;
  perform voltmaster_private.run_volume_obligations('2026-10-12 11:00+07',rule);
  if (select status from voltmaster_private.volume_obligations where id=obligation)<>'open' then raise exception 'Forged author completed obligation'; end if;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  -- Wrong period must not complete this obligation.
  result:=public.submit_work_volumes(gen_random_uuid(),jsonb_build_object('operation','save','project_id',project,'period_from','2026-10-01','period_to','2026-10-15','items',jsonb_build_array(
   jsonb_build_object('work_item_id',work,'completed_volume',1,'unit_count',1,'progress_date','2026-10-15'))));
  perform voltmaster_private.run_volume_obligations('2026-10-15 10:00+07',rule);
  if (select status from voltmaster_private.volume_obligations where id=obligation)<>'open' then raise exception 'Wrong period completed obligation'; end if;
  if (select count(*) from public.in_app_notifications where obligation_id=obligation)<>3 then raise exception 'Deadline day excluded'; end if;
  perform voltmaster_private.run_volume_obligations('2026-10-16 10:00+07',rule);
  if (select status from voltmaster_private.volume_obligations where id=obligation)<>'overdue' or
   (select count(*) from public.in_app_notifications where obligation_id=obligation)<>3 then raise exception 'Post-deadline reminders continue'; end if;
  result:=public.submit_work_volumes(gen_random_uuid(),jsonb_build_object('operation','save','project_id',project,'period_from','2026-09-01','period_to','2026-09-30','items',jsonb_build_array(
   jsonb_build_object('work_item_id',work,'completed_volume',2,'unit_count',1,'progress_date','2026-09-30'))));sid:=(result->>'submission_id')::uuid;
  perform voltmaster_private.run_volume_obligations('2026-10-16 11:00+07',rule);
  if not exists(select 1 from voltmaster_private.volume_obligations where id=obligation and status='completed' and evidence_submission_id=sid) then raise exception 'Correct submission did not complete'; end if;
  result:=voltmaster_private.run_volume_obligations('2026-10-16 11:30+07',rule);
  if (result->>'obligations_completed')::integer<>0 then raise exception 'Completion repeats on every tick'; end if;
  -- Deletion/editing of evidence must invalidate completion, and forged legacy author fields are not evidence.
  delete from public.project_work_progress where submission_item_id in(select id from public.work_volume_submission_items where submission_id=sid);
  perform voltmaster_private.run_volume_obligations('2026-10-16 12:00+07',rule);
  if (select status from voltmaster_private.volume_obligations where id=obligation)<>'overdue' then raise exception 'Broken evidence remained completed'; end if;
  -- Reconfiguration cancels old outstanding instances, validates versions and short months.
  perform set_config('request.jwt.claim.sub',director::text,true);
  result:=public.configure_volume_obligation(config||jsonb_build_object('expected_version',1,'due_day',31));
  update voltmaster_private.volume_rules set updated_at='2026-02-01 00:00+07' where id=rule;
  perform voltmaster_private.run_volume_obligations('2026-02-21 10:00+07',rule);
  if not exists(select 1 from voltmaster_private.volume_obligations where rule_id=rule and rule_version=2 and due_date='2026-02-28') then raise exception 'Short month last day failed'; end if;
  result:=public.configure_volume_obligation(config||jsonb_build_object('expected_version',2,'due_day',31,'short_month_policy','skip'));
  update voltmaster_private.volume_rules set updated_at='2026-02-01 00:00+07' where id=rule;
  perform voltmaster_private.run_volume_obligations('2026-02-28 10:00+07',rule);
  if exists(select 1 from voltmaster_private.volume_obligations where rule_id=rule and rule_version=3 and due_date between '2026-02-01' and '2026-02-28') then raise exception 'Short month skip failed'; end if;
  if exists(select 1 from voltmaster_private.volume_obligations where rule_id=rule and rule_version=2 and status in ('open','overdue')) then raise exception 'Reconfigured rule did not cancel old tasks'; end if;
  if has_function_privilege('authenticated','voltmaster_private.run_volume_obligations(timestamptz,uuid)','EXECUTE') or
   has_table_privilege('authenticated','public.in_app_notifications','INSERT') then raise exception 'Scheduler/notification forging allowed'; end if;
  raise exception using errcode='ZX001',message='All checks passed: rollback synthetic data';
 exception when sqlstate 'ZX001' then null;
 end;
 if exists(select 1 from auth.users where id in(director,actor,outsider)) or exists(select 1 from public.projects where id=project) then raise exception 'Test data leaked'; end if;
end $test$;

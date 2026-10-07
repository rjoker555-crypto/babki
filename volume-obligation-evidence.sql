-- Verify completion using immutable authenticated receipts and invalidate changed evidence.
create or replace function voltmaster_private.run_volume_obligations(p_now timestamptz default now(),p_rule uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare rule voltmaster_private.volume_rules; instance voltmaster_private.volume_obligations;
 local_now timestamp:=p_now at time zone 'Asia/Krasnoyarsk'; today date:=local_now::date;
 month_start date; month_end date; due date; period_start date; period_end date; instance_id uuid;
 task uuid; evidence public.work_volume_submissions; generated integer:=0; notified integer:=0; completed integer:=0;
begin
 -- Single-flight scheduler; advisory lock is automatically released on crash/transaction end.
 if not pg_try_advisory_xact_lock(627190052) then return '{"status":"busy"}'::jsonb; end if;
 for rule in select r.* from voltmaster_private.volume_rules r
  join public.profiles p on p.id=r.assignee_id and p.is_active
  join public.projects pr on pr.id=r.project_id and pr.responsible_user_id=r.assignee_id
  where r.enabled and (p_rule is null or r.id=p_rule) order by r.id loop
  -- A disabled/reconfigured rule starts from its new version, rather than fabricating older obligations.
  for month_start in select m::date from generate_series(date_trunc('month',rule.updated_at at time zone 'Asia/Krasnoyarsk'),
   date_trunc('month',local_now)+interval '1 month',interval '1 month') m loop
   month_end:=(month_start+interval '1 month - 1 day')::date;
   if rule.due_day>extract(day from month_end) and rule.short_month_policy='skip' then continue; end if;
   due:=month_start+(least(rule.due_day,extract(day from month_end)::integer)-1);
   if today<due-7 or due<(rule.updated_at at time zone 'Asia/Krasnoyarsk')::date then continue; end if;
   period_start:=(month_start+make_interval(months=>rule.period_offset))::date;
   period_end:=(period_start+interval '1 month - 1 day')::date;
   insert into voltmaster_private.volume_obligations(rule_id,rule_version,project_id,assignee_id,initiator_id,authority_basis,
    period_from,period_to,due_date,starts_on,reminder_time)
    values(rule.id,rule.version,rule.project_id,rule.assignee_id,rule.initiator_id,rule.authority_basis,period_start,period_end,due,due-7,rule.reminder_time)
    on conflict(rule_id,rule_version,due_date) do nothing returning id into instance_id;
   if instance_id is not null then
    insert into public.project_work_tasks(project_id,title,due_date,comment,created_by)
     values(rule.project_id,'Подать объёмы за '||to_char(period_start,'DD.MM.YYYY')||' — '||to_char(period_end,'DD.MM.YYYY'),due,
      'Задача по установленному регламенту. Выполнение подтверждается подачей за указанный период.',rule.initiator_id) returning id into task;
    update voltmaster_private.volume_obligations set task_id=task where id=instance_id; generated:=generated+1;
   end if;
  end loop;
 end loop;
 for instance in select o.* from voltmaster_private.volume_obligations o
  join voltmaster_private.volume_rules r on r.id=o.rule_id and r.enabled and r.version=o.rule_version
  join public.profiles p on p.id=o.assignee_id and p.is_active
  join public.projects pr on pr.id=o.project_id and pr.responsible_user_id=o.assignee_id
  where o.status in ('open','overdue','completed') and (p_rule is null or o.rule_id=p_rule) order by o.id for update of o loop
  select s.* into evidence from public.work_volume_submissions s where s.project_id=instance.project_id
   and s.created_by=instance.assignee_id and s.status='submitted' and s.period_from=instance.period_from and s.period_to=instance.period_to
   -- Legacy table policies allow caller-supplied created_by. Only a server-authenticated receipt proves the submitter.
   and exists(select 1 from voltmaster_private.volume_requests receipt where receipt.actor_id=instance.assignee_id
    and receipt.result->'submission'=to_jsonb(s)
    and jsonb_array_length(receipt.result->'items')=(select count(*) from public.work_volume_submission_items where submission_id=s.id)
    and not exists(select 1 from public.work_volume_submission_items actual where actual.submission_id=s.id
     and not (receipt.result->'items' @> jsonb_build_array(to_jsonb(actual)))))
   and exists(select 1 from public.work_volume_submission_items where submission_id=s.id)
   and not exists(select 1 from public.work_volume_submission_items i left join public.project_work_progress p on p.id=i.progress_id
    left join public.project_work_items w on w.id=i.work_item_id where i.submission_id=s.id and
    (p.id is null or w.project_id is distinct from s.project_id or p.work_item_id is distinct from i.work_item_id or
     p.completed_volume is distinct from i.completed_volume or p.progress_date is distinct from i.progress_date or
     p.created_by is distinct from s.created_by or p.submission_item_id is distinct from i.id))
   order by s.created_at desc limit 1;
  if found then
   if instance.status='completed' and instance.evidence_submission_id=evidence.id and (instance.evidence_snapshot->>'updated_at')::timestamptz=evidence.updated_at then continue; end if;
   update voltmaster_private.volume_obligations set status='completed',evidence_submission_id=evidence.id,
    evidence_snapshot=jsonb_build_object('submission_id',evidence.id,'updated_at',evidence.updated_at,'period_from',evidence.period_from,'period_to',evidence.period_to),completed_at=p_now where id=instance.id;
   update public.project_work_tasks set status='done',updated_at=p_now where id=instance.task_id;
   completed:=completed+1;continue;
  end if;
  if instance.status='completed' then
   update voltmaster_private.volume_obligations set status=case when today>due_date then 'overdue' else 'open' end,
    evidence_submission_id=null,completed_at=null,evidence_snapshot=evidence_snapshot||jsonb_build_object('invalidated_at',p_now)
    where id=instance.id;
   update public.project_work_tasks set status='open',updated_at=p_now where id=instance.task_id;
  end if;
  if today>instance.due_date then update voltmaster_private.volume_obligations set status='overdue' where id=instance.id;continue; end if;
  if today>=instance.starts_on and local_now::time>=instance.reminder_time then
   insert into public.in_app_notifications(recipient_id,obligation_id,local_date,title,created_at)
    values(instance.assignee_id,instance.id,today,'Подайте объёмы за '||to_char(instance.period_from,'DD.MM.YYYY')||' — '||to_char(instance.period_to,'DD.MM.YYYY')||'. Срок: '||to_char(instance.due_date,'DD.MM.YYYY'),p_now)
    on conflict(recipient_id,obligation_id,local_date) do nothing;
   if found then notified:=notified+1; end if;
  end if;
 end loop;
 return jsonb_build_object('status','completed','tasks_created',generated,'notifications_saved',notified,'obligations_completed',completed);
end $$;
revoke all on function voltmaster_private.run_volume_obligations(timestamptz,uuid) from public,anon,authenticated,service_role;

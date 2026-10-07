-- First obligation category: production volumes only. No invented KS, tax or credit deadlines.
create table voltmaster_private.volume_rules (
 id uuid primary key default gen_random_uuid(), project_id uuid not null unique references public.projects(id),
 assignee_id uuid not null references public.profiles(id), initiator_id uuid not null references public.profiles(id),
 authority_basis text not null check(length(btrim(authority_basis)) between 1 and 2000),
 due_day integer not null check(due_day between 1 and 31), reminder_time time not null,
 timezone text not null default 'Asia/Krasnoyarsk' check(timezone='Asia/Krasnoyarsk'),
 short_month_policy text not null check(short_month_policy in ('skip','last_day')),
 period_offset integer not null check(period_offset in (-1,0)),
 enabled boolean not null default false, version integer not null default 1,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table voltmaster_private.volume_obligations (
 id uuid primary key default gen_random_uuid(), rule_id uuid not null references voltmaster_private.volume_rules(id),
 rule_version integer not null, project_id uuid not null references public.projects(id),
 assignee_id uuid not null references public.profiles(id), initiator_id uuid not null references public.profiles(id),
 authority_basis text not null, period_from date not null, period_to date not null,
 due_date date not null, starts_on date not null, reminder_time time not null,
 task_id uuid references public.project_work_tasks(id) on delete set null,
 status text not null default 'open' check(status in ('open','overdue','completed','cancelled')),
 evidence_submission_id uuid references public.work_volume_submissions(id) on delete set null,
 evidence_snapshot jsonb, completed_at timestamptz, created_at timestamptz not null default now(),
 unique(rule_id,rule_version,due_date), check(period_to>=period_from)
);
create table public.in_app_notifications (
 id uuid primary key default gen_random_uuid(), recipient_id uuid not null references public.profiles(id),
 obligation_id uuid not null references voltmaster_private.volume_obligations(id),
 local_date date not null, title text not null, created_at timestamptz not null default now(), read_at timestamptz,
 unique(recipient_id,obligation_id,local_date)
);
create index volume_obligations_assignee on voltmaster_private.volume_obligations(assignee_id,status,due_date);
create index in_app_notifications_recipient on public.in_app_notifications(recipient_id,created_at desc,id);
alter table voltmaster_private.volume_rules enable row level security;
alter table voltmaster_private.volume_obligations enable row level security;
alter table public.in_app_notifications enable row level security;
revoke all on voltmaster_private.volume_rules,voltmaster_private.volume_obligations,public.in_app_notifications from public,anon,authenticated;
grant select on public.in_app_notifications to authenticated;
create policy notifications_read_own on public.in_app_notifications for select to authenticated
 using(recipient_id=(select auth.uid()) and exists(select 1 from public.profiles where id=(select auth.uid()) and is_active));

create function voltmaster_private.configure_volume_rule(p_config jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); project uuid; assignee uuid; row voltmaster_private.volume_rules;
begin
 if actor is null or not exists(select 1 from public.agent_director_access a join public.profiles p on p.id=a.user_id
  where a.user_id=actor and p.role='director' and p.is_active) then raise exception 'Trusted director required' using errcode='42501'; end if;
 if jsonb_typeof(p_config) is distinct from 'object' or p_config - array['project_id','assignee_id','authority_basis','due_day','reminder_time','short_month_policy','period_offset','enabled','expected_version'] <> '{}'::jsonb then raise exception 'Invalid configuration'; end if;
 project:=(p_config->>'project_id')::uuid; assignee:=(p_config->>'assignee_id')::uuid;
 if project is null or assignee is null or not exists(select 1 from public.projects where id=project and responsible_user_id=assignee) then raise exception 'Select the assigned project account; team delegation is not configured'; end if;
 if not exists(select 1 from public.profiles where id=assignee and is_active) then raise exception 'Active recipient account required; no in-app delivery to an employee without account'; end if;
 if p_config->>'reminder_time' is null or p_config->>'due_day' is null or p_config->>'short_month_policy' is null or p_config->>'period_offset' is null or p_config->>'enabled' is null then raise exception 'Explicit schedule settings required'; end if;
 perform 1 from public.projects where id=project for update;
 select * into row from voltmaster_private.volume_rules where project_id=project for update;
 if found then
  if (p_config->>'expected_version')::integer is distinct from row.version then raise exception 'Rule changed; reload' using errcode='40001'; end if;
  update voltmaster_private.volume_obligations set status='cancelled' where rule_id=row.id and status in ('open','overdue');
  -- Old tasks are retained for history. Their status does not control obligation completion.
  update voltmaster_private.volume_rules set assignee_id=assignee,initiator_id=actor,authority_basis=p_config->>'authority_basis',
   due_day=(p_config->>'due_day')::integer,reminder_time=(p_config->>'reminder_time')::time,
   short_month_policy=p_config->>'short_month_policy',period_offset=(p_config->>'period_offset')::integer,
   enabled=(p_config->>'enabled')::boolean,version=version+1,updated_at=clock_timestamp() where id=row.id returning * into row;
 else
  if p_config->>'expected_version' is not null then raise exception 'Rule does not exist'; end if;
  insert into voltmaster_private.volume_rules(project_id,assignee_id,initiator_id,authority_basis,due_day,reminder_time,short_month_policy,period_offset,enabled)
   values(project,assignee,actor,p_config->>'authority_basis',(p_config->>'due_day')::integer,(p_config->>'reminder_time')::time,
    p_config->>'short_month_policy',(p_config->>'period_offset')::integer,(p_config->>'enabled')::boolean) returning * into row;
 end if;
 return to_jsonb(row);
end $$;
revoke all on function voltmaster_private.configure_volume_rule(jsonb) from public,anon,authenticated;
grant execute on function voltmaster_private.configure_volume_rule(jsonb) to authenticated;
create function public.configure_volume_obligation(p_config jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select voltmaster_private.configure_volume_rule(p_config); $$;
revoke all on function public.configure_volume_obligation(jsonb) from public,anon,authenticated;
grant execute on function public.configure_volume_obligation(jsonb) to authenticated;

create function voltmaster_private.run_volume_obligations(p_now timestamptz default now(),p_rule uuid default null) returns jsonb
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

create function voltmaster_private.my_volume_obligations() returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); trusted boolean;
begin
 if actor is null or not exists(select 1 from public.profiles where id=actor and is_active) then raise exception 'Active account required' using errcode='42501'; end if;
 trusted:=exists(select 1 from public.agent_director_access a join public.profiles p on p.id=a.user_id where a.user_id=actor and p.role='director' and p.is_active);
 return jsonb_build_object('can_configure',trusted,'rules',case when trusted then coalesce((select jsonb_agg(to_jsonb(r)) from voltmaster_private.volume_rules r),'[]'::jsonb) else '[]'::jsonb end,
  'tasks',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'project_id',o.project_id,'project_name',p.name,'period_from',o.period_from,'period_to',o.period_to,
   'due_date',o.due_date,'status',o.status,'authority_basis',o.authority_basis,'initiator_id',o.initiator_id,'assignee_id',o.assignee_id,'task_id',o.task_id,'evidence_submission_id',o.evidence_submission_id)
   order by o.due_date desc) from voltmaster_private.volume_obligations o join public.projects p on p.id=o.project_id where o.assignee_id=actor),'[]'::jsonb));
end $$;
revoke all on function voltmaster_private.my_volume_obligations() from public,anon,authenticated;
grant execute on function voltmaster_private.my_volume_obligations() to authenticated;
create function public.get_my_volume_obligations() returns jsonb language sql security invoker set search_path='' as $$ select voltmaster_private.my_volume_obligations(); $$;
revoke all on function public.get_my_volume_obligations() from public,anon,authenticated;
grant execute on function public.get_my_volume_obligations() to authenticated;

create function voltmaster_private.read_notification(p_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and is_active) then raise exception 'Active account required' using errcode='42501'; end if;
 update public.in_app_notifications set read_at=coalesce(read_at,now()) where id=p_id and recipient_id=auth.uid();
 return found;
end $$;
revoke all on function voltmaster_private.read_notification(uuid) from public,anon,authenticated;
grant execute on function voltmaster_private.read_notification(uuid) to authenticated;
create function public.read_in_app_notification(p_id uuid) returns boolean language sql security invoker set search_path='' as $$ select voltmaster_private.read_notification(p_id); $$;
revoke all on function public.read_in_app_notification(uuid) from public,anon,authenticated;
grant execute on function public.read_in_app_notification(uuid) to authenticated;
-- No rules are seeded. Missing user settings therefore create no tasks or deliveries.
select cron.schedule('voltmaster-volume-obligations','* * * * *','select voltmaster_private.run_volume_obligations();');

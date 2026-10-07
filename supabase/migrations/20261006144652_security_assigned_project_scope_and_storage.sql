-- Apply after owner confirms assignments. Existing permissive policies cannot bypass these restrictions.
create function voltmaster_private.security_project_scope(p_project uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_active and
 (p.role in ('director','finance','accountant','manager') or (p.role='foreman' and
 (exists(select 1 from public.projects j where j.id=p_project and j.responsible_user_id=p.id)
 or exists(select 1 from public.project_team_members m where m.project_id=p_project and m.user_id=p.id and m.is_active)))));
$$;
revoke all on function voltmaster_private.security_project_scope(uuid) from public,anon;
grant execute on function voltmaster_private.security_project_scope(uuid) to authenticated;
do $$declare t text;begin
 foreach t in array array['project_work_items','project_work_sections','project_work_tasks','work_volume_submissions','project_customer_contacts','pto_documents','project_work_section_templates','project_documents','project_price_history'] loop
 execute format('create policy security_object_scope on public.%I as restrictive for all to authenticated using(voltmaster_private.security_project_scope(project_id)) with check(voltmaster_private.security_project_scope(project_id))',t);
 end loop;
end $$;
create policy security_object_scope on public.project_work_progress as restrictive for all to authenticated
using(exists(select 1 from public.project_work_items w where w.id=work_item_id and voltmaster_private.security_project_scope(w.project_id)))
with check(exists(select 1 from public.project_work_items w where w.id=work_item_id and voltmaster_private.security_project_scope(w.project_id)));
create policy security_object_scope on public.project_work_materials as restrictive for all to authenticated
using(exists(select 1 from public.project_work_items w where w.id=work_item_id and voltmaster_private.security_project_scope(w.project_id)))
with check(exists(select 1 from public.project_work_items w where w.id=work_item_id and voltmaster_private.security_project_scope(w.project_id)));
create policy security_object_scope on public.work_volume_submission_items as restrictive for all to authenticated
using(exists(select 1 from public.work_volume_submissions s join public.project_work_items w on w.id=work_item_id and w.project_id=s.project_id where s.id=submission_id and voltmaster_private.security_project_scope(s.project_id)))
with check(exists(select 1 from public.work_volume_submissions s join public.project_work_items w on w.id=work_item_id and w.project_id=s.project_id where s.id=submission_id and voltmaster_private.security_project_scope(s.project_id)));
create policy security_object_scope on public.project_work_section_template_items as restrictive for all to authenticated
using(exists(select 1 from public.project_work_section_templates t where t.id=template_id and voltmaster_private.security_project_scope(t.project_id)))
with check(exists(select 1 from public.project_work_section_templates t where t.id=template_id and voltmaster_private.security_project_scope(t.project_id)));
create policy security_object_scope on public.project_work_section_template_materials as restrictive for all to authenticated
using(exists(select 1 from public.project_work_section_template_items i join public.project_work_section_templates t on t.id=i.template_id where i.id=template_item_id and voltmaster_private.security_project_scope(t.project_id)))
with check(exists(select 1 from public.project_work_section_template_items i join public.project_work_section_templates t on t.id=i.template_id where i.id=template_item_id and voltmaster_private.security_project_scope(t.project_id)));
create policy security_activity_scope on public.agent_activity_events as restrictive for select to authenticated
using(actor_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_active and
(p.role in ('director','finance','accountant','manager') or (p.role='foreman' and project_id is not null and voltmaster_private.security_project_scope(project_id)))));
create or replace function public.foreman_projects()
returns table(id uuid,name text,customer text,contract_number text,contract_date date,start_date date,end_date date,status text,responsible_user_id uuid,comment text,contractor_company text)
language sql stable security definer set search_path='' as $$
 select j.id,j.name,j.customer,j.contract_number,j.contract_date,j.start_date,j.end_date,j.status,j.responsible_user_id,j.comment,j.contractor_company
 from public.projects j where exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_active and p.role in ('manager','foreman'))
 and voltmaster_private.security_project_scope(j.id);
$$;
create or replace function public.foreman_subcontractors()
returns table(id uuid,project_id uuid,name text,comment text,created_at timestamptz)
language sql stable security definer set search_path='' as $$
 select s.id,s.project_id,s.name,s.comment,s.created_at from public.subcontractors s
 where public.is_foreman() and voltmaster_private.security_project_scope(s.project_id);
$$;
create or replace function public.foreman_add_subcontractor(p_project_id uuid,p_name text,p_comment text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;begin
 if not public.is_foreman() or not voltmaster_private.security_project_scope(p_project_id) then raise exception 'Access denied' using errcode='42501';end if;
 if p_project_id is null or nullif(trim(p_name),'') is null or length(p_name)>300 or length(p_comment)>4000 then raise exception 'Invalid subcontractor';end if;
 insert into public.subcontractors(project_id,name,comment,planned_amount,has_vat) values(p_project_id,trim(p_name),p_comment,0,false) returning id into result;
 return result;end $$;
revoke all on function public.foreman_projects(),public.foreman_subcontractors(),public.foreman_add_subcontractor(uuid,text,text) from public,anon;
grant execute on function public.foreman_projects(),public.foreman_subcontractors(),public.foreman_add_subcontractor(uuid,text,text) to authenticated;

-- Prepared compatibility updates: team assignments supplement, never replace, responsible_user_id.
CREATE OR REPLACE FUNCTION voltmaster_private.volume_command(p_request uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 actor uuid:=auth.uid(); project uuid; sid uuid; operation text; expected timestamptz;
 previous voltmaster_private.volume_requests; submission public.work_volume_submissions;
 entry jsonb; item_id uuid; new_progress_id uuid; wid uuid; affected uuid[]; result jsonb;
 period_start date; period_end date; qty numeric; count_units integer; progress_day date;
begin
 if actor is null or not exists(select 1 from public.profiles where id=actor and is_active) then
  raise exception 'Active account required' using errcode='42501';
 end if;
 if p_request is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Invalid request'; end if;
 if p_payload - array['operation','project_id','submission_id','expected_updated_at','period_from','period_to','comment','items'] <> '{}'::jsonb then raise exception 'Unknown request fields'; end if;
 project:=(p_payload->>'project_id')::uuid; sid:=(p_payload->>'submission_id')::uuid;
 operation:=p_payload->>'operation'; expected:=(p_payload->>'expected_updated_at')::timestamptz;
 if operation is null or operation not in ('save','delete') or project is null then raise exception 'Invalid operation/project'; end if;
 -- A profile promotion cannot grant global access: that requires the existing server-only director allowlist.
 if not exists(select 1 from public.projects p where p.id=project and (
  p.responsible_user_id=actor or exists(select 1 from public.project_team_members m where m.project_id=p.id and m.user_id=actor and m.is_active) or exists(select 1 from public.agent_director_access a
   join public.profiles u on u.id=a.user_id where a.user_id=actor and u.role='director' and u.is_active))) then
  raise exception 'Project access denied' using errcode='42501';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||p_request::text,0));
 select * into previous from voltmaster_private.volume_requests where actor_id=actor and request_id=p_request;
 if found then
  if previous.payload<>p_payload then raise exception 'Idempotency key payload mismatch'; end if;
  return previous.result;
 end if;
 -- Serializes commands for the project and locks work rows before facts are changed.
 perform 1 from public.projects where id=project for update;
 if sid is not null then
  select * into submission from public.work_volume_submissions where id=sid and project_id=project for update;
  if not found then raise exception 'Submission not found'; end if;
  if expected is null or submission.updated_at<>expected then raise exception 'Submission changed; reload before retrying' using errcode='40001'; end if;
 end if;
 if operation='delete' and sid is null then raise exception 'Submission required'; end if;
 if operation='save' then
  period_start:=(p_payload->>'period_from')::date; period_end:=(p_payload->>'period_to')::date;
  if period_start is null or period_end is null or period_end<period_start then raise exception 'Invalid period'; end if;
  if jsonb_typeof(p_payload->'items') is distinct from 'array' then raise exception 'Items array required'; end if;
  if jsonb_array_length(p_payload->'items') not between 1 and 500 then raise exception 'Expected 1..500 items'; end if;
  if length(coalesce(p_payload->>'comment',''))>4000 then raise exception 'Comment too long'; end if;
  for entry in select value from jsonb_array_elements(p_payload->'items') loop
   if jsonb_typeof(entry)<>'object' or entry - array['work_item_id','completed_volume','progress_date','unit_count','section_label'] <> '{}'::jsonb then raise exception 'Invalid item fields'; end if;
   wid:=(entry->>'work_item_id')::uuid; qty:=(entry->>'completed_volume')::numeric;
   count_units:=(entry->>'unit_count')::integer; progress_day:=(entry->>'progress_date')::date;
   if wid is null or qty is null or qty<=0 or qty::text in ('NaN','Infinity','-Infinity') or
      count_units is null or count_units<=0 or progress_day is null or progress_day<period_start or progress_day>period_end or
      length(coalesce(entry->>'section_label',''))>1000 then raise exception 'Invalid item values'; end if;
   if not exists(select 1 from public.project_work_items where id=wid and project_id=project) then raise exception 'Work belongs to another project' using errcode='42501'; end if;
  end loop;
  if exists(select 1 from jsonb_array_elements(p_payload->'items') e group by e->>'work_item_id' having count(*)>1) then raise exception 'Duplicate work item'; end if;
 end if;
 select array_agg(distinct id order by id) into affected from (
  select work_item_id as id from public.work_volume_submission_items where submission_id=sid
  union select (e->>'work_item_id')::uuid from jsonb_array_elements(case when operation='save' then p_payload->'items' else '[]'::jsonb end) e
 ) x;
 if exists(select 1 from public.project_work_items where id=any(affected) and project_id<>project) then raise exception 'Corrupt submission project'; end if;
 perform 1 from public.project_work_items where id=any(affected) order by id for update;
 -- Legacy submissions lack the reverse link; accept only the exact forward link and same work.
 if exists(select 1 from public.work_volume_submission_items i join public.project_work_progress p on p.id=i.progress_id
  where i.submission_id=sid and (p.work_item_id<>i.work_item_id or (p.submission_item_id is not null and p.submission_item_id<>i.id))) then raise exception 'Corrupt progress link'; end if;
 if exists(select 1 from public.work_volume_submission_items other_i where other_i.submission_id<>sid and other_i.progress_id in
  (select progress_id from public.work_volume_submission_items where submission_id=sid)) then raise exception 'Shared progress link'; end if;
 delete from public.project_work_progress where id in (select progress_id from public.work_volume_submission_items where submission_id=sid);
 delete from public.work_volume_submission_items where submission_id=sid;
 if operation='delete' then
  delete from public.work_volume_submissions where id=sid;
 else
  if sid is null then
   insert into public.work_volume_submissions(project_id,period_from,period_to,comment,created_by)
    values(project,period_start,period_end,nullif(p_payload->>'comment',''),actor) returning * into submission;
   sid:=submission.id;
  else
   update public.work_volume_submissions set period_from=period_start,period_to=period_end,
    comment=nullif(p_payload->>'comment',''),updated_at=clock_timestamp() where id=sid returning * into submission;
  end if;
  for entry in select value from jsonb_array_elements(p_payload->'items') loop
   insert into public.work_volume_submission_items(submission_id,work_item_id,completed_volume,progress_date,unit_count,section_label)
    values(sid,(entry->>'work_item_id')::uuid,(entry->>'completed_volume')::numeric,(entry->>'progress_date')::date,
     (entry->>'unit_count')::integer,entry->>'section_label') returning id into item_id;
   insert into public.project_work_progress(work_item_id,progress_date,completed_volume,comment,created_by,submission_item_id)
    values((entry->>'work_item_id')::uuid,(entry->>'progress_date')::date,(entry->>'completed_volume')::numeric,
     'Подача объёмов: '||coalesce(entry->>'section_label','')||' × '||(entry->>'unit_count'),actor,item_id) returning id into new_progress_id;
   update public.work_volume_submission_items set progress_id=new_progress_id where id=item_id;
  end loop;
 end if;
 -- Include manual facts. Quantity already contains planned_volume × unit_count; do not multiply twice.
 update public.project_work_items w set completed_volume=t.total,
  status=case when w.planned_volume>0 and t.total>=w.planned_volume then 'completed' when t.total>0 then 'in_progress' else 'planned' end,
  updated_at=clock_timestamp()
 from (select w2.id,coalesce(sum(p.completed_volume),0) as total from public.project_work_items w2
  left join public.project_work_progress p on p.work_item_id=w2.id where w2.id=any(affected) group by w2.id) t where w.id=t.id;
 result:=jsonb_build_object('operation',operation,'submission_id',sid,'submission',case when operation='save' then to_jsonb(submission) else null end,
  'items',coalesce((select jsonb_agg(to_jsonb(i)) from public.work_volume_submission_items i where submission_id=sid),'[]'::jsonb),
  'affected_work_ids',coalesce(to_jsonb(affected),'[]'::jsonb),
  'works',coalesce((select jsonb_agg(jsonb_build_object('id',w.id,'completed_volume',w.completed_volume,'status',w.status,'updated_at',w.updated_at)) from public.project_work_items w where w.id=any(affected)),'[]'::jsonb),
  'progress',coalesce((select jsonb_agg(to_jsonb(p)) from public.project_work_progress p where work_item_id=any(affected)),'[]'::jsonb));
 insert into voltmaster_private.volume_requests(actor_id,request_id,payload,result) values(actor,p_request,p_payload,result);
 return result;
end $function$;

CREATE OR REPLACE FUNCTION voltmaster_private.configure_volume_rule(p_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid(); project uuid; assignee uuid; row voltmaster_private.volume_rules;
begin
 if actor is null or not exists(select 1 from public.agent_director_access a join public.profiles p on p.id=a.user_id
  where a.user_id=actor and p.role='director' and p.is_active) then raise exception 'Trusted director required' using errcode='42501'; end if;
 if jsonb_typeof(p_config) is distinct from 'object' or p_config - array['project_id','assignee_id','authority_basis','due_day','reminder_time','short_month_policy','period_offset','enabled','expected_version'] <> '{}'::jsonb then raise exception 'Invalid configuration'; end if;
 project:=(p_config->>'project_id')::uuid; assignee:=(p_config->>'assignee_id')::uuid;
 if project is null or assignee is null or not exists(select 1 from public.projects where id=project and (responsible_user_id=assignee or exists(select 1 from public.project_team_members m where m.project_id=project and m.user_id=assignee and m.is_active))) then raise exception 'Select an assigned project account'; end if;
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
end $function$;

CREATE OR REPLACE FUNCTION voltmaster_private.run_volume_obligations(p_now timestamp with time zone DEFAULT now(), p_rule uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare rule voltmaster_private.volume_rules; instance voltmaster_private.volume_obligations;
 local_now timestamp:=p_now at time zone 'Asia/Krasnoyarsk'; today date:=local_now::date;
 month_start date; month_end date; due date; period_start date; period_end date; instance_id uuid;
 task uuid; evidence public.work_volume_submissions; generated integer:=0; notified integer:=0; completed integer:=0;
begin
 -- Single-flight scheduler; advisory lock is automatically released on crash/transaction end.
 if not pg_try_advisory_xact_lock(627190052) then return '{"status":"busy"}'::jsonb; end if;
 for rule in select r.* from voltmaster_private.volume_rules r
  join public.profiles p on p.id=r.assignee_id and p.is_active
  join public.projects pr on pr.id=r.project_id and (pr.responsible_user_id=r.assignee_id or exists(select 1 from public.project_team_members m where m.project_id=pr.id and m.user_id=r.assignee_id and m.is_active))
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
  join public.projects pr on pr.id=o.project_id and (pr.responsible_user_id=o.assignee_id or exists(select 1 from public.project_team_members m where m.project_id=pr.id and m.user_id=o.assignee_id and m.is_active))
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
end $function$;



-- Called only by authenticated server functions with the verified Auth user id.
create function public.agent_project_scope(p_owner uuid,p_project uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=p_owner and p.is_active and
 (p.role in ('director','finance','accountant','manager') or (p.role='foreman' and
 (exists(select 1 from public.projects j where j.id=p_project and j.responsible_user_id=p.id)
 or exists(select 1 from public.project_team_members m where m.project_id=p_project and m.user_id=p.id and m.is_active)))))
 and exists(select 1 from public.projects where id=p_project);
$$;
revoke all on function public.agent_project_scope(uuid,uuid) from public,anon,authenticated;
grant execute on function public.agent_project_scope(uuid,uuid) to service_role;
create function public.agent_allowed_projects(p_owner uuid,p_query text,p_offset integer)
returns table(id uuid,name text,customer text,status text)
language plpgsql stable security definer set search_path='' as $$
begin
 if p_offset<0 or p_offset>30000 or p_query is null or length(p_query)>2000 then raise exception 'Invalid pagination';end if;
 return query select j.id,j.name,j.customer,j.status from public.projects j
 where public.agent_project_scope(p_owner,j.id) and (p_query='' or j.name ilike '%'||replace(replace(p_query,'%',''),'*','')||'%')
 order by j.name,j.id offset p_offset limit 31;
end $$;
revoke all on function public.agent_allowed_projects(uuid,text,integer) from public,anon,authenticated;
grant execute on function public.agent_allowed_projects(uuid,text,integer) to service_role;
create policy security_document_version_scope on public.project_document_versions as restrictive for all to authenticated
using(exists(select 1 from public.project_documents d where d.id=document_id and voltmaster_private.security_project_scope(d.project_id)))
with check(exists(select 1 from public.project_documents d where d.id=document_id and voltmaster_private.security_project_scope(d.project_id)));
create policy foreman_project_document_read on public.project_documents for select to authenticated
using(public.is_foreman() and document_type='project' and voltmaster_private.security_project_scope(project_id));
create policy foreman_project_version_read on public.project_document_versions for select to authenticated
using(public.is_foreman() and exists(select 1 from public.project_documents d where d.id=document_id and d.document_type='project' and voltmaster_private.security_project_scope(d.project_id)));
create function voltmaster_private.security_document_path(p_path text) returns boolean
language sql stable security definer set search_path='' as $$
 select public.is_foreman() and exists(select 1 from public.project_documents d where d.document_type='project'
 and d.storage_bucket='project-documents' and voltmaster_private.security_project_scope(d.project_id)
 and (d.file_path=p_path or exists(select 1 from public.project_document_versions v where v.document_id=d.id and v.file_path=p_path)));
$$;
revoke all on function voltmaster_private.security_document_path(text) from public,anon;
grant execute on function voltmaster_private.security_document_path(text) to authenticated;
create policy foreman_project_storage_read on storage.objects for select to authenticated
using(bucket_id='project-documents' and voltmaster_private.security_document_path(name));
create policy security_foreman_storage_scope on storage.objects as restrictive for all to authenticated
using(bucket_id<>'project-documents' or not public.is_foreman() or voltmaster_private.security_document_path(name))
with check(bucket_id<>'project-documents' or not public.is_foreman() or voltmaster_private.security_document_path(name));

do $test$
declare director uuid:=gen_random_uuid();f uuid:=gen_random_uuid();finance uuid:=gen_random_uuid();p uuid:=gen_random_uuid();foreign_p uuid:=gen_random_uuid();doc uuid:=gen_random_uuid();contract uuid:=gen_random_uuid();foreign_doc uuid:=gen_random_uuid();denied boolean;
begin
 begin
 insert into auth.users(id) values(director),(f),(finance);
 insert into public.profiles(id,role,is_active) values(director,'director',true),(f,'foreman',true),(finance,'finance',true);
 insert into public.agent_director_access(user_id) values(director);
 insert into public.projects(id,name) values(p,'TEST team document'),(foreign_p,'TEST foreign document');
 insert into public.project_team_members(project_id,user_id,assigned_by) values(p,f,director);
 insert into public.project_documents(id,project_id,document_type,title,file_name,file_path,storage_bucket,uploaded_by) values
 (doc,p,'project','TEST Project','project.pdf','TEST-security-team/project.pdf','project-documents',director),
 (contract,p,'contract','TEST Contract','contract.pdf','TEST-security-team/contract.pdf','project-documents',director),
 (foreign_doc,foreign_p,'project','TEST Foreign','foreign.pdf','TEST-security-team/foreign.pdf','project-documents',director);
 insert into storage.objects(bucket_id,name) values('project-documents','TEST-security-team/project.pdf'),('project-documents','TEST-security-team/contract.pdf'),('project-documents','TEST-security-team/foreign.pdf');
 if not public.agent_project_scope(f,p) or public.agent_project_scope(f,foreign_p) then raise exception 'Service project scope mismatch';end if;
 if (select count(*) from public.agent_allowed_projects(f,'',0))<>1 then raise exception 'Service list leaks foreign object';end if;
 perform set_config('request.jwt.claim.sub',f::text,true);execute 'set local role authenticated';
 if not exists(select 1 from public.project_documents where id=doc) or exists(select 1 from public.project_documents where id in(contract,foreign_doc)) then raise exception 'Document type/project scope mismatch';end if;
 if (select count(*) from storage.objects where name like 'TEST-security-team/%')<>1 then raise exception 'Storage reveals contract or foreign project';end if;
 denied:=false;begin perform public.agent_project_scope(director,foreign_p);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Client impersonation through service RPC';end if;
 execute 'reset role';update public.project_team_members set is_active=false where project_id=p and user_id=f;
 if public.agent_project_scope(f,p) then raise exception 'Service stale assignment';end if;
 execute 'set local role authenticated';if exists(select 1 from storage.objects where name like 'TEST-security-team/%') then raise exception 'Storage stale assignment';end if;
 execute 'reset role';raise exception using errcode='P0993',message='ROLLBACK_TEAM_DOCUMENTS';
 exception when sqlstate 'P0993' then null;end;
end $test$;
select 'assigned production documents/storage allowed; contracts, foreign objects, revoked assignments and client impersonation denied' as result;

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



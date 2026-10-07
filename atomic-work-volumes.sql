-- Additive RPC. Existing tables, policies, financial formulas and facts are preserved.
-- CLI is unavailable on this workstation; tracked SQL follows the existing project convention.
create schema voltmaster_private;
revoke all on schema voltmaster_private from public, anon, authenticated;
grant usage on schema voltmaster_private to authenticated;

create table voltmaster_private.volume_requests (
 actor_id uuid not null references public.profiles(id), request_id uuid not null,
 payload jsonb not null, result jsonb not null, created_at timestamptz not null default now(),
 primary key(actor_id,request_id)
);
alter table voltmaster_private.volume_requests enable row level security;
revoke all on voltmaster_private.volume_requests from public,anon,authenticated;

create function voltmaster_private.volume_command(p_request uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
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
  p.responsible_user_id=actor or exists(select 1 from public.agent_director_access a
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
end $$;
revoke all on function voltmaster_private.volume_command(uuid,jsonb) from public,anon,authenticated;
grant execute on function voltmaster_private.volume_command(uuid,jsonb) to authenticated;
create function public.submit_work_volumes(p_request uuid,p_payload jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select voltmaster_private.volume_command(p_request,p_payload); $$;
revoke all on function public.submit_work_volumes(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.submit_work_volumes(uuid,jsonb) to authenticated;

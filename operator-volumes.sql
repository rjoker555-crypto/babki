-- Agent adapter reuses the existing manual atomic volume command verbatim.
create or replace function voltmaster_private.volume_plan_preview(p_owner uuid,p_payload jsonb)
returns jsonb language plpgsql set search_path='' as $$
declare project uuid:=(p_payload->>'project_id')::uuid; sid uuid:=(p_payload->>'submission_id')::uuid; workids uuid[]; snapshot jsonb;
begin
 if not exists(select 1 from public.profiles where id=p_owner and is_active) then raise exception 'Active account required';end if;
 if not exists(select 1 from public.projects p where p.id=project and (p.responsible_user_id=p_owner or exists(select 1 from public.project_team_members m where m.project_id=p.id and m.user_id=p_owner and m.is_active) or exists(select 1 from public.agent_director_access a join public.profiles u on u.id=a.user_id where a.user_id=p_owner and u.role='director' and u.is_active))) then raise exception 'Project access denied';end if;
 perform 1 from public.projects where id=project for update;
 select array_agg(distinct id order by id) into workids from (
  select work_item_id as id from public.work_volume_submission_items where submission_id=sid
  union select (e->>'work_item_id')::uuid from jsonb_array_elements(case when p_payload->>'operation'='save' then p_payload->'items' else '[]'::jsonb end) e
 ) x;
 perform 1 from public.project_work_items where id=any(workids) order by id for update;
 snapshot:=jsonb_build_object('payload',p_payload,'submission',(select to_jsonb(x) from public.work_volume_submissions x where id=sid),'items',coalesce((select jsonb_agg(to_jsonb(x) order by id) from public.work_volume_submission_items x where submission_id=sid),'[]'::jsonb),'works',coalesce((select jsonb_agg(to_jsonb(x) order by id) from public.project_work_items x where id=any(workids)),'[]'::jsonb),'progress',coalesce((select jsonb_agg(to_jsonb(x) order by id) from public.project_work_progress x where work_item_id=any(workids)),'[]'::jsonb));
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 -- Validate using the exact atomic command in a rollback-only savepoint. Its tables,
 -- receipts, audit records and notifications all roll back; no network/model call.
 begin
  perform voltmaster_private.volume_command(gen_random_uuid(),p_payload);
  raise exception using errcode='P0993',message='ROLLBACK_VOLUME_PREVIEW';
 exception when sqlstate 'P0993' then null;end;
 return snapshot;
end $$;
revoke all on function voltmaster_private.volume_plan_preview(uuid,jsonb) from public,anon,authenticated;
grant execute on function voltmaster_private.volume_plan_preview(uuid,jsonb) to service_role;
alter table public.agent_operator_plans drop constraint if exists agent_operator_plans_kind_check;
alter table public.agent_operator_plans add constraint agent_operator_plans_kind_check check(kind in ('operation_write','project_create','credit_write','obligation_write','project_card_write','volume_write'));

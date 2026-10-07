-- NOT APPLIED. Requires owner approval: narrows existing employee permissions.
-- No deletion or financial recalculation. Existing broad policies stay in place,
-- restrictive policies enforce the object boundary for foremen.
begin;
create function voltmaster_private.security_trusted_director() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p join public.agent_director_access a on a.user_id=p.id
 where p.id=auth.uid() and p.is_active and p.role='director');
$$;
revoke all on function voltmaster_private.security_trusted_director() from public,anon;
grant execute on function voltmaster_private.security_trusted_director() to authenticated;
create function voltmaster_private.guard_profile_authority() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 -- Maintenance/service operations remain server-side; no client can select these DB roles.
 if current_user in ('postgres','service_role','supabase_admin') then
  if TG_OP='DELETE' then return OLD;else return NEW;end if;
 end if;
 if TG_OP in ('INSERT','DELETE') or (NEW.id,NEW.role,NEW.is_active) is distinct from (OLD.id,OLD.role,OLD.is_active) then
  if not voltmaster_private.security_trusted_director() then raise exception 'Only trusted director may change account authority' using errcode='42501';end if;
 end if;
 if TG_OP='DELETE' then return OLD;else return NEW;end if;
end $$;
revoke all on function voltmaster_private.guard_profile_authority() from public,anon,authenticated;
create trigger security_guard_profile_authority before insert or update or delete on public.profiles
for each row execute function voltmaster_private.guard_profile_authority();
create function voltmaster_private.security_project_scope(p_project uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_active and
 (p.role in ('director','finance','accountant','manager') or (p.role='foreman' and exists(
 select 1 from public.projects j where j.id=p_project and j.responsible_user_id=p.id))));
$$;
revoke all on function voltmaster_private.security_project_scope(uuid) from public,anon;
grant execute on function voltmaster_private.security_project_scope(uuid) to authenticated;
do $$declare t text;begin
 foreach t in array array['project_work_items','project_work_sections','project_work_tasks','work_volume_submissions','project_customer_contacts','pto_documents'] loop
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
using(exists(select 1 from public.work_volume_submissions s where s.id=submission_id and voltmaster_private.security_project_scope(s.project_id)))
with check(exists(select 1 from public.work_volume_submissions s where s.id=submission_id and voltmaster_private.security_project_scope(s.project_id)));
-- Old plan logs include raw JSON and may contain financial project fields.
create policy security_raw_plan_scope on public.agent_protocol_entries as restrictive for select to authenticated
using(plan_id is null or actor_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_active and p.role in ('director','finance','accountant')));
create policy security_activity_scope on public.agent_activity_events as restrictive for select to authenticated
using(actor_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_active and
(p.role in ('director','finance','accountant','manager') or (p.role='foreman' and project_id is not null and voltmaster_private.security_project_scope(project_id)))));
create or replace function public.foreman_projects()
returns table(id uuid,name text,customer text,contract_number text,contract_date date,start_date date,end_date date,status text,responsible_user_id uuid,comment text,contractor_company text)
language sql stable security definer set search_path='' as $$
 select j.id,j.name,j.customer,j.contract_number,j.contract_date,j.start_date,j.end_date,j.status,j.responsible_user_id,j.comment,j.contractor_company
 from public.projects j where exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_active
 and (p.role='manager' or (p.role='foreman' and j.responsible_user_id=p.id)));
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
commit;

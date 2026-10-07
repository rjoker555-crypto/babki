-- APPLIED in migration 20261006144652 after the owner confirmed assignment-based access.
-- Existing permissive policies cannot bypass these restrictive policies.
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

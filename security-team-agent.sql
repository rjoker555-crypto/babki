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

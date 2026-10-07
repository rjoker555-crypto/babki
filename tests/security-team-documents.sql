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

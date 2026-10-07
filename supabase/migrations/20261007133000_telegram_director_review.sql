alter table voltmaster_private.telegram_submission_files drop constraint if exists telegram_submission_files_status_check;
alter table voltmaster_private.telegram_submission_files add constraint telegram_submission_files_status_check check(status in ('received','reviewing','approved','rejected','failed'));
alter table voltmaster_private.telegram_submission_files add column if not exists review_lease timestamptz;
alter table voltmaster_private.telegram_submission_files add column if not exists reviewed_by uuid references auth.users(id) on delete set null;

create or replace function public.telegram_review_claim(p_director uuid,p_file uuid) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare f voltmaster_private.telegram_submission_files;s voltmaster_private.telegram_submissions;
begin
 if auth.role()<>'service_role' or not exists(select 1 from public.profiles where id=p_director and role='director' and is_active) or not exists(select 1 from public.agent_director_access where user_id=p_director) then raise exception 'Trusted director required';end if;
 select * into f from voltmaster_private.telegram_submission_files where id=p_file for update;
 if not found then raise exception 'File not found';end if;
 select * into s from voltmaster_private.telegram_submissions where id=f.submission_id;
 if s.status not in ('pending_review','partial') or s.project_id is null or not exists(select 1 from public.projects where id=s.project_id) or f.status not in ('received','reviewing') or f.status='reviewing' and f.review_lease>now() then raise exception 'Submission not ready or under review';end if;
 update voltmaster_private.telegram_submission_files set status='reviewing',review_lease=now()+interval '3 minutes',reviewed_by=p_director where id=f.id;
 return jsonb_build_object('file_id',f.id,'owner_id',s.owner_id,'project_id',s.project_id,'project_name',s.project_name,'file_name',f.file_name,'mime_type',f.mime_type,'file_size',f.file_size,'storage_path',f.storage_path,'sha256',f.sha256,'explanation',s.explanation);
end $fn$;
revoke all on function public.telegram_review_claim(uuid,uuid) from public,anon,authenticated;
grant execute on function public.telegram_review_claim(uuid,uuid) to service_role;

create or replace function public.telegram_review_finish(p_director uuid,p_file uuid,p_document uuid,p_error text default null) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare f voltmaster_private.telegram_submission_files;s voltmaster_private.telegram_submissions;remaining int;approved int;
begin
 if auth.role()<>'service_role' or not exists(select 1 from public.profiles where id=p_director and role='director' and is_active) or not exists(select 1 from public.agent_director_access where user_id=p_director) then raise exception 'Trusted director required';end if;
 select * into f from voltmaster_private.telegram_submission_files where id=p_file for update;
 if not found or f.status<>'reviewing' or f.reviewed_by is distinct from p_director or f.review_lease<now() then raise exception 'Review lease changed';end if;
 select * into s from voltmaster_private.telegram_submissions where id=f.submission_id for update;
 if p_document is not null and not exists(select 1 from public.project_documents where id=p_document and project_id=s.project_id and uploaded_by=p_director) then raise exception 'Verified document missing';end if;
 update voltmaster_private.telegram_submission_files set status=case when p_document is not null then 'approved' when p_error is not null then 'failed' else 'rejected' end,document_id=p_document,error=left(p_error,300),review_lease=null where id=p_file;
 select count(*) filter(where status in ('received','reviewing')),count(*) filter(where status='approved') into remaining,approved from voltmaster_private.telegram_submission_files where submission_id=s.id;
 update voltmaster_private.telegram_submissions set status=case when remaining>0 then 'partial' when approved>0 then 'approved' else 'rejected' end,reviewed_at=now(),reviewed_by=p_director where id=s.id;
 return jsonb_build_object('status',case when p_document is not null then 'approved' when p_error is not null then 'failed' else 'rejected' end,'submission_id',s.id,'remaining',remaining,'approved',approved);
end $fn$;
revoke all on function public.telegram_review_finish(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.telegram_review_finish(uuid,uuid,uuid,text) to service_role;

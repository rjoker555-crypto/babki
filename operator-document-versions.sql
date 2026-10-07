alter table public.project_document_versions add column if not exists storage_bucket text not null default 'project-documents';
update public.project_document_versions v set storage_bucket='agent-files' where exists(select 1 from public.agent_file_assets a where a.storage_path=v.file_path) and exists(select 1 from public.project_documents d where d.id=v.document_id and d.storage_bucket='agent-files');
alter table public.project_document_versions drop constraint if exists project_document_versions_storage_bucket_check;
alter table public.project_document_versions add constraint project_document_versions_storage_bucket_check check(storage_bucket in ('project-documents','agent-files'));

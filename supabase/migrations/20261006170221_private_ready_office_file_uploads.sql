alter table public.agent_file_assets drop constraint if exists agent_file_assets_mime_type_check;
alter table public.agent_file_assets add constraint agent_file_assets_mime_type_check check(mime_type in ('application/pdf','text/plain','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'));
update storage.buckets set allowed_mime_types=array['application/pdf','text/plain','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'] where id='agent-files';



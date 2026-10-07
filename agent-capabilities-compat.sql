-- Compatibility for replacement/deletion of a newly linked project document; assets survive.
alter table public.agent_file_project_links drop constraint agent_file_project_links_project_id_fkey;
alter table public.agent_file_project_links add constraint agent_file_project_links_project_id_fkey foreign key(project_id) references public.projects(id) on delete cascade;
alter table public.agent_file_project_links drop constraint agent_file_project_links_document_id_fkey;
alter table public.agent_file_project_links add constraint agent_file_project_links_document_id_fkey foreign key(document_id) references public.project_documents(id) on delete cascade;
create table public.agent_tool_runs(
 message_id uuid not null,step_index integer not null,owner_id uuid not null references public.profiles(id),chat_id uuid not null,
 tool_name text not null,arguments_json jsonb not null,result_json jsonb not null,created_at timestamptz not null default now(),
 primary key(message_id,step_index)
);
alter table public.agent_tool_runs enable row level security;
revoke all on public.agent_tool_runs from public,anon,authenticated;
grant all on public.agent_tool_runs to service_role;

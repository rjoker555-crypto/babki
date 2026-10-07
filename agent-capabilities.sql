-- Additive agent capabilities. Existing roles, financial formulas and data are unchanged.
alter table public.project_documents drop constraint project_documents_document_type_check;
alter table public.project_documents add constraint project_documents_document_type_check check(document_type in ('contract','estimate','addendum','other','project'));
alter table public.project_documents add column storage_bucket text not null default 'project-documents' check(storage_bucket in ('project-documents','agent-files'));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('agent-files','agent-files',false,8388608,array['application/pdf','text/plain']) on conflict(id) do nothing;

create table public.agent_file_assets(
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references public.profiles(id),chat_id uuid not null,
 file_name text not null check(length(file_name) between 1 and 200),storage_path text not null unique,
 mime_type text not null check(mime_type in ('application/pdf','text/plain')),file_size bigint not null check(file_size between 1 and 8388608),
 sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'),page_count integer check(page_count between 1 and 40),
 created_at timestamptz not null default now()
);
create table public.agent_background_jobs(
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references public.profiles(id),chat_id uuid not null,
 file_id uuid not null references public.agent_file_assets(id),request_id uuid not null,instruction text not null check(length(instruction) between 1 and 2000),
 status text not null default 'queued' check(status in ('queued','running','completed','failed','cancelled','needs_attention')),
 step_cursor integer not null default 0,step_count integer not null check(step_count between 1 and 20),
 lease_id uuid,lease_until timestamptz,attempts integer not null default 0,error text,
 input_tokens bigint not null default 0,output_tokens bigint not null default 0,model text,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(owner_id,request_id,file_id)
);
create index agent_jobs_queue on public.agent_background_jobs(status,lease_until,created_at);
create table public.agent_job_steps(
 job_id uuid not null references public.agent_background_jobs(id),step_index integer not null,
 status text not null check(status in ('attempting','completed')),result jsonb,provider_response_id text,
 input_tokens bigint not null default 0,output_tokens bigint not null default 0,created_at timestamptz not null default now(),
 primary key(job_id,step_index)
);
create table public.agent_file_action_plans(
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references public.profiles(id),chat_id uuid not null,
 kind text not null check(kind in ('create_project','attach_project')),file_id uuid not null references public.agent_file_assets(id),
 file_sha256 text not null,values_json jsonb not null,status text not null default 'pending' check(status in ('pending','completed','cancelled')),
 result_json jsonb,created_at timestamptz not null default now(),expires_at timestamptz not null default now()+interval '30 minutes'
);
create table public.agent_file_project_links(
 file_id uuid not null references public.agent_file_assets(id),project_id uuid not null references public.projects(id) on delete cascade,
 document_id uuid not null references public.project_documents(id) on delete cascade,primary key(file_id,project_id)
);
alter table public.agent_file_assets enable row level security;
alter table public.agent_background_jobs enable row level security;
alter table public.agent_job_steps enable row level security;
alter table public.agent_file_action_plans enable row level security;
alter table public.agent_file_project_links enable row level security;
revoke all on public.agent_file_assets,public.agent_background_jobs,public.agent_job_steps,public.agent_file_action_plans,public.agent_file_project_links from public,anon,authenticated;
grant all on public.agent_file_assets,public.agent_background_jobs,public.agent_job_steps,public.agent_file_action_plans,public.agent_file_project_links to service_role;
grant select on public.agent_file_assets,public.agent_background_jobs to authenticated;
create policy agent_assets_own on public.agent_file_assets for select to authenticated using(owner_id=(select auth.uid()) and exists(select 1 from public.profiles where id=(select auth.uid()) and is_active));
create policy agent_jobs_own on public.agent_background_jobs for select to authenticated using(owner_id=(select auth.uid()) and exists(select 1 from public.profiles where id=(select auth.uid()) and is_active));

create function public.agent_queue_analysis(p_owner uuid,p_chat uuid,p_file uuid,p_instruction text,p_request uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare asset public.agent_file_assets; job public.agent_background_jobs;
begin
 if not exists(select 1 from public.profiles where id=p_owner and is_active) or
    not exists(select 1 from public.agent_conversations where id=p_chat and owner_id=p_owner) then raise exception 'Owner/chat access denied'; end if;
 select * into asset from public.agent_file_assets where id=p_file and owner_id=p_owner;
 if not found then raise exception 'Own file required'; end if;
 if length(btrim(p_instruction)) not between 1 and 2000 then raise exception 'Analysis instruction required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_owner::text,614));
 select * into job from public.agent_background_jobs where owner_id=p_owner and request_id=p_request and file_id=p_file;
 if found then
  if job.instruction<>p_instruction then raise exception 'Request instruction mismatch'; end if;
  return jsonb_build_object('job_id',job.id,'status',job.status,'file_id',job.file_id);
 end if;
 if (select count(*) from public.agent_background_jobs where owner_id=p_owner and status in ('queued','running'))>=3 then raise exception 'At most three active analyses'; end if;
 if (select count(*) from public.agent_background_jobs where owner_id=p_owner and created_at>=date_trunc('day',now()))>=10 then raise exception 'Daily analysis limit: 10'; end if;
 if (select count(*) from public.agent_background_jobs where created_at>=date_trunc('month',now()))>=200 then raise exception 'Monthly analysis limit: 200'; end if;
 insert into public.agent_background_jobs(owner_id,chat_id,file_id,request_id,instruction,step_count)
  values(p_owner,p_chat,p_file,p_request,p_instruction,case when asset.mime_type='application/pdf' then (asset.page_count+1)/2 else 1 end) returning * into job;
 return jsonb_build_object('job_id',job.id,'status',job.status,'file_id',job.file_id,'limits','PDF: 40 pages, two pages per step; TXT: 120000 characters; 10/day, 200/month');
end $$;
create function public.agent_list_chat_files(p_owner uuid,p_chat uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where id=p_owner and is_active) or not exists(select 1 from public.agent_conversations where id=p_chat and owner_id=p_owner) then raise exception 'Owner/chat access denied'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'file_name',a.file_name,'mime_type',a.mime_type,'file_size',a.file_size,'page_count',a.page_count,
  'jobs',coalesce((select jsonb_agg(jsonb_build_object('id',j.id,'status',j.status,'step_cursor',j.step_cursor,'step_count',j.step_count,'error',j.error)) from public.agent_background_jobs j where j.file_id=a.id and j.owner_id=p_owner),'[]'::jsonb)))
  from public.agent_file_assets a where a.owner_id=p_owner),'[]'::jsonb);
end $$;
create function public.agent_get_job(p_owner uuid,p_job uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
declare job public.agent_background_jobs;
begin
 if not exists(select 1 from public.profiles where id=p_owner and is_active) then raise exception 'Active owner required'; end if;
 select * into job from public.agent_background_jobs where id=p_job and owner_id=p_owner;
 if not found then raise exception 'Job access denied'; end if;
 return to_jsonb(job)-array['lease_id','lease_until','request_id']||jsonb_build_object('steps',coalesce((select jsonb_agg(jsonb_build_object('step_index',s.step_index,'result',s.result) order by s.step_index)
  from public.agent_job_steps s where s.job_id=p_job and s.status='completed'),'[]'::jsonb));
end $$;
create function public.agent_cancel_job(p_owner uuid,p_job uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where id=p_owner and is_active) then raise exception 'Active owner required'; end if;
 update public.agent_background_jobs set status='cancelled',lease_id=null,lease_until=null,updated_at=now() where id=p_job and owner_id=p_owner and status in ('queued','running','needs_attention');
 return public.agent_get_job(p_owner,p_job);
end $$;

create function public.agent_claim_analysis(p_job uuid default null) returns jsonb language plpgsql security invoker set search_path='' as $$
declare job public.agent_background_jobs; asset public.agent_file_assets;
begin
 select j.* into job from public.agent_background_jobs j join public.profiles p on p.id=j.owner_id and p.is_active
  where (j.status='queued' or (j.status='running' and j.lease_until<now())) and (p_job is null or j.id=p_job) order by j.created_at for update of j skip locked limit 1;
 if not found then return null; end if;
 if exists(select 1 from public.agent_job_steps where job_id=job.id and step_index=job.step_cursor and status='attempting') then
  update public.agent_background_jobs set status='needs_attention',error='Previous API request outcome is unknown. No automatic paid repeat.',lease_id=null,lease_until=null,updated_at=now() where id=job.id;
  return jsonb_build_object('status','needs_attention','job_id',job.id);
 end if;
 if job.attempts>=3 or job.input_tokens>150000 or job.output_tokens>40000 then
  update public.agent_background_jobs set status='needs_attention',error='Analysis budget/recovery limit reached',updated_at=now() where id=job.id;
  return jsonb_build_object('status','needs_attention','job_id',job.id);
 end if;
 update public.agent_background_jobs set status='running',lease_id=gen_random_uuid(),lease_until=now()+interval '3 minutes',attempts=attempts+1,updated_at=now() where id=job.id returning * into job;
 select * into asset from public.agent_file_assets where id=job.file_id;
 return jsonb_build_object('job',to_jsonb(job),'file',to_jsonb(asset));
end $$;
create function public.agent_begin_step(p_job uuid,p_lease uuid,p_model text) returns boolean language plpgsql security invoker set search_path='' as $$
declare job public.agent_background_jobs;
begin
 select * into job from public.agent_background_jobs where id=p_job and lease_id=p_lease and status='running' and lease_until>now() for update;
 if not found then return false; end if;
 insert into public.agent_job_steps(job_id,step_index,status) values(p_job,job.step_cursor,'attempting');
 update public.agent_background_jobs set model=p_model where id=p_job;return true;
end $$;
create function public.agent_finish_step(p_job uuid,p_lease uuid,p_result jsonb,p_response text,p_input bigint,p_output bigint) returns boolean language plpgsql security invoker set search_path='' as $$
declare job public.agent_background_jobs;
begin
 select * into job from public.agent_background_jobs where id=p_job and lease_id=p_lease and status='running' and lease_until>now() for update;
 if not found then return false; end if;
 if pg_column_size(p_result)>120000 or jsonb_typeof(p_result) is distinct from 'object' or p_input<0 or p_output<0 then raise exception 'Invalid result'; end if;
 update public.agent_job_steps set status='completed',result=p_result,provider_response_id=p_response,input_tokens=p_input,output_tokens=p_output where job_id=p_job and step_index=job.step_cursor and status='attempting';
 if not found then raise exception 'Unreserved step'; end if;
 update public.agent_background_jobs set step_cursor=step_cursor+1,status=case when step_cursor+1=step_count then 'completed' else 'queued' end,
  attempts=0,lease_id=null,lease_until=null,input_tokens=input_tokens+p_input,output_tokens=output_tokens+p_output,updated_at=now() where id=p_job;
 return true;
end $$;
create function public.agent_fail_analysis(p_job uuid,p_lease uuid,p_error text,p_uncertain boolean) returns boolean language plpgsql security invoker set search_path='' as $$
begin
 update public.agent_background_jobs set status=case when p_uncertain then 'needs_attention' else 'failed' end,error=left(p_error,1000),lease_id=null,lease_until=null,updated_at=now()
  where id=p_job and lease_id=p_lease and status='running';return found;
end $$;

create function public.agent_propose_file_action(p_owner uuid,p_chat uuid,p_kind text,p_file uuid,p_values jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare asset public.agent_file_assets; plan public.agent_file_action_plans;
begin
 if not exists(select 1 from public.agent_director_access a join public.profiles p on p.id=a.user_id where a.user_id=p_owner and p.role='director' and p.is_active) then raise exception 'Trusted director required'; end if;
 if not exists(select 1 from public.agent_conversations where id=p_chat and owner_id=p_owner) then raise exception 'Own chat required'; end if;
 select * into asset from public.agent_file_assets where id=p_file and owner_id=p_owner;
 if not found then raise exception 'Own file required'; end if;
 if p_kind='create_project' then
  if p_values is null or jsonb_typeof(p_values) is distinct from 'object' or p_values - array['name','customer']<>'{}'::jsonb or p_values->>'name' is null or length(btrim(p_values->>'name')) not between 1 and 200 or length(coalesce(p_values->>'customer',''))>500 then raise exception 'Invalid project fields'; end if;
 elsif p_kind='attach_project' then
  if p_values - array['project_id']<>'{}'::jsonb or not exists(select 1 from public.projects where id=(p_values->>'project_id')::uuid) then raise exception 'Project not found'; end if;
 else raise exception 'Unknown action'; end if;
 select * into plan from public.agent_file_action_plans where owner_id=p_owner and chat_id=p_chat and kind=p_kind and file_id=p_file and values_json=p_values and status='pending' and expires_at>now() order by created_at desc limit 1;
 if not found then insert into public.agent_file_action_plans(owner_id,chat_id,kind,file_id,file_sha256,values_json) values(p_owner,p_chat,p_kind,p_file,asset.sha256,p_values) returning * into plan; end if;
 return jsonb_build_object('status','awaiting_confirmation','plan_id',plan.id,'action',p_kind,'values',p_values,'file_name',asset.file_name,'file_sha256',asset.sha256,'confirmation','ПОДТВЕРЖДАЮ '||plan.id::text,'cancel','ОТМЕНЯЮ '||plan.id::text,'expires_at',plan.expires_at);
end $$;
create function public.agent_execute_file_action(p_owner uuid,p_plan uuid,p_message uuid,p_cancel boolean) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare plan public.agent_file_action_plans; asset public.agent_file_assets; project uuid; doc uuid;
begin
 if not exists(select 1 from public.agent_director_access a join public.profiles p on p.id=a.user_id where a.user_id=p_owner and p.role='director' and p.is_active) then raise exception 'Trusted director required'; end if;
 select * into plan from public.agent_file_action_plans where id=p_plan and owner_id=p_owner for update;
 if not found then raise exception 'Plan not found'; end if;
 if not exists(select 1 from public.agent_chat_messages where id=p_message and owner_id=p_owner and chat_id=plan.chat_id and kind='user'
  and content=(case when p_cancel then 'ОТМЕНЯЮ ' else 'ПОДТВЕРЖДАЮ ' end)||p_plan::text) then raise exception 'Exact confirmation in own thread required'; end if;
 if plan.status<>'pending' then return jsonb_build_object('status',plan.status,'result',plan.result_json); end if;
 if p_cancel then update public.agent_file_action_plans set status='cancelled' where id=p_plan;return '{"status":"cancelled"}'::jsonb;end if;
 if plan.expires_at<now() then raise exception 'Plan expired'; end if;
 select * into asset from public.agent_file_assets where id=plan.file_id and owner_id=p_owner;
 if not found or asset.sha256<>plan.file_sha256 then raise exception 'Source file changed'; end if;
 if plan.kind='create_project' then
  insert into public.projects(name,customer,status) values(plan.values_json->>'name',plan.values_json->>'customer','planned') returning id into project;
 else project:=(plan.values_json->>'project_id')::uuid;
 end if;
 select document_id into doc from public.agent_file_project_links where file_id=asset.id and project_id=project;
 if doc is null then
  insert into public.project_documents(project_id,document_type,title,file_name,file_path,mime_type,file_size,version_no,is_current,uploaded_by,storage_bucket)
   values(project,'project',asset.file_name,asset.file_name,asset.storage_path,asset.mime_type,asset.file_size,1,true,p_owner,'agent-files') returning id into doc;
  insert into public.project_document_versions(document_id,version_no,file_name,file_path,mime_type,file_size,uploaded_by)
   values(doc,1,asset.file_name,asset.storage_path,asset.mime_type,asset.file_size,p_owner);
  insert into public.agent_file_project_links(file_id,project_id,document_id) values(asset.id,project,doc);
 end if;
 update public.agent_file_action_plans set status='completed',result_json=jsonb_build_object('project_id',project,'document_id',doc,'file_id',asset.id) where id=p_plan returning * into plan;
 return jsonb_build_object('status','completed','result',plan.result_json);
end $$;
create function public.agent_cash_summary(p_owner uuid,p_project uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.agent_director_access a join public.profiles p on p.id=a.user_id where a.user_id=p_owner and p.role='director' and p.is_active) then raise exception 'Financial access denied'; end if;
 if not exists(select 1 from public.projects where id=p_project) then raise exception 'Project not found'; end if;
 return (select jsonb_build_object('project_id',p_project,'as_of',now(),'method','cash_operations_v1','income',coalesce(sum(amount) filter(where operation_type='income'),0)::text,
  'expense',coalesce(sum(amount) filter(where operation_type='expense'),0)::text,'credit',coalesce(sum(amount) filter(where operation_type='credit'),0)::text,
  'operation_count',count(*),'limitations',array['Cash flow is not production profit or recognized revenue.','Margin, VAT and budget comparison require agreed methodology.']) from public.operations where project_id=p_project);
end $$;

-- All these p_owner/worker commands are server-only; clients cannot impersonate an owner.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in
  ('agent_queue_analysis','agent_list_chat_files','agent_get_job','agent_cancel_job','agent_claim_analysis','agent_begin_step','agent_finish_step','agent_fail_analysis','agent_propose_file_action','agent_execute_file_action','agent_cash_summary') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  execute format('grant execute on function %s to service_role',f.signature);
 end loop;
end $$;

-- Scheduled worker uses a new scoped dispatch credential, generated and retained only in the database.
-- No existing secret is changed or returned. Custom edge authentication verifies this token via service-only RPC.
create extension if not exists pg_net with schema extensions;
create table voltmaster_private.agent_worker_auth(token text not null default encode(extensions.gen_random_bytes(32),'hex'));
alter table voltmaster_private.agent_worker_auth enable row level security;
revoke all on voltmaster_private.agent_worker_auth from public,anon,authenticated,service_role;
insert into voltmaster_private.agent_worker_auth default values;
create function public.agent_check_worker_token(p_token text) returns boolean language sql security definer set search_path='' as $$
 select exists(select 1 from voltmaster_private.agent_worker_auth where token=p_token); $$;
revoke all on function public.agent_check_worker_token(text) from public,anon,authenticated;
grant execute on function public.agent_check_worker_token(text) to service_role;
create function voltmaster_private.dispatch_agent_worker() returns bigint language plpgsql security definer set search_path='' as $$
declare request bigint;
begin
 if not exists(select 1 from public.agent_background_jobs where status='queued' or (status='running' and lease_until<now())) then return null; end if;
 select net.http_post(url:='https://tkoxgvftneoereukiomr.supabase.co/functions/v1/agent-worker',headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',token),body:='{}'::jsonb,timeout_milliseconds:=10000)
  into request from voltmaster_private.agent_worker_auth;return request;
end $$;
revoke all on function voltmaster_private.dispatch_agent_worker() from public,anon,authenticated,service_role;
select cron.schedule('voltmaster-agent-worker','* * * * *','select voltmaster_private.dispatch_agent_worker();');

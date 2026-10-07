-- Additive server accounting; no company data, credentials or existing roles changed.
create table public.agent_api_budget_events (
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references auth.users(id),
 scope text not null check(scope in ('chat','voice','analysis')),request_id uuid not null,step integer not null check(step between 0 and 30),
 created_at timestamptz not null default now(),input_tokens bigint,output_tokens bigint,
 unique(scope,request_id,step)
);
alter table public.agent_api_budget_events enable row level security;
revoke all on public.agent_api_budget_events from public,anon,authenticated;
grant all on public.agent_api_budget_events to service_role;
create index agent_api_budget_created on public.agent_api_budget_events(created_at);
create function public.agent_reserve_api_call(p_owner uuid,p_scope text,p_request uuid,p_step integer) returns boolean
language plpgsql security invoker set search_path='' as $$
begin
 perform pg_advisory_xact_lock(73198429);
 if p_scope not in ('chat','voice','analysis') or p_step not between 0 and 30 or p_request is null
 or not exists(select 1 from public.profiles where id=p_owner and is_active and role in ('director','finance','accountant','manager','foreman')) then return false; end if;
 if exists(select 1 from public.agent_api_budget_events where scope=p_scope and request_id=p_request and step=p_step) then return false; end if;
 -- Cross-mode, cross-user hard call counts, including failed/uncertain attempts.
 if (select count(*) from public.agent_api_budget_events where created_at>=date_trunc('day',now()))>=100
 or (select count(*) from public.agent_api_budget_events where created_at>=date_trunc('month',now()))>=500
 or (select count(*) from public.agent_api_budget_events where owner_id=p_owner and created_at>=date_trunc('day',now()))>=80 then return false; end if;
 insert into public.agent_api_budget_events(owner_id,scope,request_id,step) values(p_owner,p_scope,p_request,p_step);
 return true;
end $$;
create function public.agent_record_api_usage(p_owner uuid,p_scope text,p_request uuid,p_step integer,p_input bigint,p_output bigint) returns void
language sql security invoker set search_path='' as $$
 update public.agent_api_budget_events set input_tokens=case when p_input is null then null else greatest(0,p_input) end,output_tokens=case when p_output is null then null else greatest(0,p_output) end
 where owner_id=p_owner and scope=p_scope and request_id=p_request and step=p_step;
$$;
revoke all on function public.agent_reserve_api_call(uuid,text,uuid,integer),public.agent_record_api_usage(uuid,text,uuid,integer,bigint,bigint) from public,anon,authenticated;
grant execute on function public.agent_reserve_api_call(uuid,text,uuid,integer),public.agent_record_api_usage(uuid,text,uuid,integer,bigint,bigint) to service_role;

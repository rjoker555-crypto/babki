-- Additive migration. Server-only request accounting and duplicate prevention.
create table public.agent_request_runs (
 message_id uuid primary key references public.agent_chat_messages(id),
 owner_id uuid not null references auth.users(id),
 status text not null default 'pending' check(status in ('pending','completed','failed')),
 created_at timestamptz not null default now(),
 input_tokens integer, output_tokens integer
);
alter table public.agent_request_runs enable row level security;
revoke all on public.agent_request_runs from public, anon, authenticated;
grant all on public.agent_request_runs to service_role;
create index agent_request_runs_created on public.agent_request_runs(created_at);
create function public.agent_reserve_request(p_message uuid,p_owner uuid) returns text
language plpgsql security invoker set search_path='' as $$
declare existing text;
begin
 perform pg_advisory_xact_lock(73198421);
 select status into existing from public.agent_request_runs where message_id=p_message;
 if existing is not null then return existing; end if;
 if exists(select 1 from public.agent_request_runs where owner_id=p_owner and status='pending' and created_at > now()-interval '90 seconds') then return 'pending'; end if;
 if not exists(select 1 from public.agent_chat_messages where id=p_message and owner_id=p_owner and kind='user') then return 'invalid'; end if;
 if (select count(*) from public.agent_request_runs where created_at >= date_trunc('month',now())) >= 1500 then return 'monthly_limit'; end if;
 if (select count(*) from public.agent_request_runs where owner_id=p_owner and created_at >= date_trunc('day',now())) >= 60 then return 'daily_limit'; end if;
 if exists(select 1 from public.agent_request_runs where owner_id=p_owner and created_at > now()-interval '10 seconds') then return 'rate_limit'; end if;
 insert into public.agent_request_runs(message_id,owner_id) values(p_message,p_owner);
 return 'reserved';
end $$;
revoke all on function public.agent_reserve_request(uuid,uuid) from public,anon,authenticated;
grant execute on function public.agent_reserve_request(uuid,uuid) to service_role;

create table if not exists public.agent_report_assets(
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references public.profiles(id),request_id uuid not null,
 kind text not null check(kind in ('statement','organization_month','production','proposals')),args jsonb not null,
 status text not null default 'pending' check(status in ('pending','completed')),file_path text,file_name text,file_size bigint,sha256 text,
 created_at timestamptz not null default now(),unique(owner_id,request_id,kind)
);
alter table public.agent_report_assets enable row level security;
revoke all on public.agent_report_assets from public,anon,authenticated;grant select on public.agent_report_assets to authenticated;grant all on public.agent_report_assets to service_role;
create policy own_report_assets on public.agent_report_assets for select to authenticated using(owner_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_active and (p.role in ('director','finance','accountant') or p.role='manager' and kind in ('production','proposals') or p.role='foreman' and kind='production' and voltmaster_private.security_project_scope((args->>'project_id')::uuid))));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('operator-reports','operator-reports',false,1500000,array['text/html']) on conflict(id) do update set public=false,file_size_limit=1500000,allowed_mime_types=array['text/html'];
create or replace function public.agent_claim_report(p_owner uuid,p_request uuid,p_kind text,p_args jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text;a public.agent_report_assets;pid uuid:=(p_args->>'project_id')::uuid;
begin
 select role into actor from public.profiles where id=p_owner and is_active;
 if actor is null or p_kind not in ('statement','organization_month','production','proposals') or p_kind is null or not(actor in ('director','finance','accountant') or actor='manager' and p_kind in ('production','proposals') or actor='foreman' and p_kind='production') then raise exception 'Report access denied';end if;
 if actor='director' and not exists(select 1 from public.agent_director_access where user_id=p_owner) then raise exception 'Trusted director required';end if;
 if not exists(select 1 from public.agent_chat_messages where id=p_request and owner_id=p_owner and kind='user') then raise exception 'Own report request required';end if;
 if p_kind in ('statement','production') and (pid is null or not exists(select 1 from public.projects p where p.id=pid and (actor<>'foreman' or p.responsible_user_id=p_owner or exists(select 1 from public.project_team_members t where t.project_id=pid and t.user_id=p_owner and t.is_active)))) then raise exception 'Project report access denied';end if;
 perform pg_advisory_xact_lock(hashtextextended('voltmaster.reports.'||p_owner,0));
 select * into a from public.agent_report_assets where owner_id=p_owner and request_id=p_request and kind=p_kind;
 if found then if a.args is distinct from p_args then raise exception 'Report request parameters changed';end if;return to_jsonb(a);end if;
 if (select count(*) from public.agent_report_assets where owner_id=p_owner and created_at>now()-interval '1 day')>=20 then raise exception 'Report quota: 20 per day';end if;
 insert into public.agent_report_assets(owner_id,request_id,kind,args) values(p_owner,p_request,p_kind,p_args) returning * into a;return to_jsonb(a);
end $$;
revoke all on function public.agent_claim_report(uuid,uuid,text,jsonb) from public,anon,authenticated;grant execute on function public.agent_claim_report(uuid,uuid,text,jsonb) to service_role;



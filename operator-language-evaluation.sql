-- Closed one-off model evaluation. No client grants and no application data input.
create table if not exists voltmaster_private.operator_language_evaluation (
 id uuid primary key default gen_random_uuid(), enabled boolean not null default false,
 reserved_micro_usd integer not null default 0 check(reserved_micro_usd between 0 and 480000),
 calls integer not null default 0 check(calls between 0 and 48),
 results jsonb not null default '[]', created_at timestamptz not null default now(),finished_at timestamptz
);
alter table voltmaster_private.operator_language_evaluation enable row level security;
revoke all on voltmaster_private.operator_language_evaluation from public,anon,authenticated;
grant all on voltmaster_private.operator_language_evaluation to service_role;
create or replace function public.operator_eval_claim() returns uuid language plpgsql security definer set search_path='' as $$
declare rid uuid;
begin select id into rid from voltmaster_private.operator_language_evaluation where enabled and finished_at is null order by created_at for update skip locked limit 1;
 if rid is not null then update voltmaster_private.operator_language_evaluation set enabled=false where id=rid;end if;return rid;end $$;
create or replace function public.operator_eval_reserve(p_run uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('voltmaster.operator.eval.budget',0));
 if (select coalesce(sum(reserved_micro_usd),0) from voltmaster_private.operator_language_evaluation)+10000>480000 then return false;end if;
 update voltmaster_private.operator_language_evaluation set calls=calls+1,reserved_micro_usd=reserved_micro_usd+10000 where id=p_run and finished_at is null and calls<48 and reserved_micro_usd+10000<=480000;return found;end $$;
create or replace function public.operator_eval_result(p_run uuid,p_result jsonb,p_finish boolean default false) returns void language plpgsql security definer set search_path='' as $$
begin update voltmaster_private.operator_language_evaluation set results=results||jsonb_build_array(p_result),finished_at=case when p_finish then now() else finished_at end where id=p_run;end $$;
revoke all on function public.operator_eval_claim(),public.operator_eval_reserve(uuid),public.operator_eval_result(uuid,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.operator_eval_claim(),public.operator_eval_reserve(uuid),public.operator_eval_result(uuid,jsonb,boolean) to service_role;
-- Custom worker authentication stays private; the token is never returned to a client.
create or replace function voltmaster_private.dispatch_operator_eval() returns bigint language plpgsql security definer set search_path='' as $$
declare secret text;
begin select token into secret from voltmaster_private.agent_worker_auth limit 1;
 return net.http_post(url:='https://tkoxgvftneoereukiomr.supabase.co/functions/v1/operator-evaluation',headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',secret),body:='{}'::jsonb,timeout_milliseconds:=10000);
end $$;
revoke all on function voltmaster_private.dispatch_operator_eval() from public,anon,authenticated,service_role;

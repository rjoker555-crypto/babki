-- Emergency restoration only: reopens the audited vulnerability. No data is removed.
begin;
drop policy if exists security_raw_plan_scope on public.agent_protocol_entries;
drop trigger if exists security_guard_profile_authority on public.profiles;
drop function if exists voltmaster_private.guard_profile_authority();
-- Retain the trusted-director helper: the team-management policy depends on it.
grant truncate,references,trigger on public.profiles to anon,authenticated;
commit;

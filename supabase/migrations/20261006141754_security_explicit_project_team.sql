-- Additive assignment mechanism. No users or projects are assigned automatically.
create table public.project_team_members (
 project_id uuid not null references public.projects(id), user_id uuid not null references public.profiles(id),
 team_role text not null default 'foreman' check(team_role in ('foreman','pto','approver','participant')),
 is_active boolean not null default true, assigned_by uuid not null default auth.uid() references public.profiles(id),
 created_at timestamptz not null default now(), primary key(project_id,user_id)
);
alter table public.project_team_members enable row level security;
revoke all on public.project_team_members from public,anon,authenticated;
grant select,insert,update on public.project_team_members to authenticated;
grant all on public.project_team_members to service_role;
create policy team_director_admin on public.project_team_members for all to authenticated
using(voltmaster_private.security_trusted_director())
with check(voltmaster_private.security_trusted_director() and assigned_by=auth.uid());
create policy team_self_read on public.project_team_members for select to authenticated
using(user_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_active));
create index project_team_user_active on public.project_team_members(user_id,project_id) where is_active;



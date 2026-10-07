-- Keep assignments for recovery. Revoke writes instead of dropping data.
revoke insert,update on public.project_team_members from authenticated;

-- Explicit project access and existing volume regulations; no generic role editor.
create or replace function voltmaster_private.project_settings_command(p_owner uuid,p_request uuid,p_command jsonb,p_preview boolean default false)
returns jsonb language plpgsql set search_path='' as $$
declare kind text:=p_command->>'kind';pid uuid:=(p_command->>'project_id')::uuid; uid uuid; snapshot jsonb; result jsonb; stored jsonb; config jsonb; rec jsonb;
begin
 if not exists(select 1 from public.profiles p join public.agent_director_access a on a.user_id=p.id where p.id=p_owner and p.is_active and p.role='director') then raise exception 'Trusted director required';end if;
 if p_request is null or kind not in ('assignment','responsible','volume_rule') or kind is null or exists(select 1 from jsonb_object_keys(p_command) k where k not in ('kind','project_id','user_id','is_active','expected','config')) then raise exception 'Invalid project settings command';end if;
 perform pg_advisory_xact_lock(hashtextextended('voltmaster.financial.commands',0));
 if not p_preview then
  select result_json,command_json into result,stored from voltmaster_private.financial_command_receipts where owner_id=p_owner and request_id=p_request;
  if found then if stored is distinct from p_command then raise exception 'Request reused with different command';end if;return result;end if;
 end if;
 perform 1 from public.projects where id=pid for update;if not found then raise exception 'Project not found';end if;
 select jsonb_build_object('project_id',p.id,'responsible_user_id',p.responsible_user_id,
  'members',coalesce((select jsonb_agg(to_jsonb(m) order by user_id) from public.project_team_members m where project_id=pid),'[]'),
  'rule',(select to_jsonb(r) from voltmaster_private.volume_rules r where project_id=pid)) into snapshot from public.projects p where id=pid;
 if snapshot is distinct from p_command->'expected' then raise exception 'Project settings changed; reload';end if;
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 uid:=(p_command->>'user_id')::uuid;
 if kind='assignment' then
  if p_command ? 'config' or jsonb_typeof(p_command->'is_active') is distinct from 'boolean' or not exists(select 1 from public.profiles where id=uid and is_active and role='foreman') then raise exception 'Active foreman and explicit assignment required';end if;
 elsif kind='responsible' then
  if p_command ? 'config' or p_command ? 'is_active' or not p_command ? 'user_id' or uid is not null and not exists(select 1 from public.profiles where id=uid and is_active) then raise exception 'Active responsible account or explicit null required';end if;
 else
  if p_command ? 'user_id' or p_command ? 'is_active' or jsonb_typeof(p_command->'config') is distinct from 'object' or (p_command->'config'->>'project_id')::uuid is distinct from pid then raise exception 'Explicit regulation configuration required';end if;
  config:=p_command->'config';
 end if;
 if p_preview then
  -- The existing regulation validates all authority and schedule constraints. Roll back its preview.
  if kind='volume_rule' then begin rec:=voltmaster_private.configure_volume_rule(config);raise exception using errcode='P0993',message='preview';exception when sqlstate 'P0993' then null;end;end if;
  return jsonb_build_object('before',snapshot,'command',p_command,'validated_rule',config,'access_remains',kind='assignment' and not (p_command->>'is_active')::boolean and snapshot->>'responsible_user_id'=uid::text);
 end if;
 if kind='assignment' then
  insert into public.project_team_members(project_id,user_id,team_role,is_active,assigned_by) values(pid,uid,'foreman',(p_command->>'is_active')::boolean,p_owner)
  on conflict(project_id,user_id) do update set team_role='foreman',is_active=excluded.is_active,assigned_by=p_owner returning to_jsonb(project_team_members.*) into rec;
 elsif kind='responsible' then update public.projects set responsible_user_id=uid where id=pid returning jsonb_build_object('project_id',id,'responsible_user_id',responsible_user_id) into rec;
 else rec:=voltmaster_private.configure_volume_rule(config);end if;
 result:=jsonb_build_object('status','completed','kind',kind,'record',rec,'verified',true);
 insert into voltmaster_private.financial_command_receipts values(p_owner,p_request,p_command,result,now());return result;
end $$;
revoke all on function voltmaster_private.project_settings_command(uuid,uuid,jsonb,boolean) from public,anon,authenticated;
grant execute on function voltmaster_private.project_settings_command(uuid,uuid,jsonb,boolean) to service_role;
create or replace function public.execute_project_settings(p_request uuid,p_command jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.project_settings_command(auth.uid(),p_request,p_command,false);end $$;
revoke all on function public.execute_project_settings(uuid,jsonb) from public,anon;grant execute on function public.execute_project_settings(uuid,jsonb) to authenticated;
create or replace function public.get_project_settings(p_project uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if not exists(select 1 from public.profiles p join public.agent_director_access a on a.user_id=p.id where p.id=auth.uid() and p.is_active and p.role='director') then raise exception 'Trusted director required';end if;
 select jsonb_build_object('project_id',p.id,'responsible_user_id',p.responsible_user_id,'members',coalesce((select jsonb_agg(to_jsonb(m) order by user_id) from public.project_team_members m where project_id=p.id),'[]'),'rule',(select to_jsonb(r) from voltmaster_private.volume_rules r where project_id=p.id)) into result from public.projects p where id=p_project;
 if result is null then raise exception 'Project not found';end if;return result;
end $$;
revoke all on function public.get_project_settings(uuid) from public,anon;grant execute on function public.get_project_settings(uuid) to authenticated;

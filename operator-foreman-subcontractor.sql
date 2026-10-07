create or replace function voltmaster_private.foreman_subcontractor_command(p_owner uuid,p_request uuid,p_command jsonb,p_preview boolean default false) returns jsonb language plpgsql set search_path='' as $$
declare pid uuid:=(p_command->'values'->>'project_id')::uuid;rid uuid;result jsonb;stored jsonb;snapshot jsonb;
begin
 if not exists(select 1 from public.profiles where id=p_owner and role='foreman' and is_active) then raise exception 'Foreman account required';end if;
 if p_request is null or p_command->>'kind' is distinct from 'foreman_subcontractor' or p_command->>'action' is distinct from 'create' or exists(select 1 from jsonb_object_keys(p_command) k where k not in ('kind','action','values')) or jsonb_typeof(p_command->'values') is distinct from 'object' or exists(select 1 from jsonb_object_keys(p_command->'values') k where k not in ('project_id','name','comment')) then raise exception 'Only basic subcontractor name/comment allowed';end if;
 perform pg_advisory_xact_lock(hashtextextended('voltmaster.financial.commands',0));
 if not p_preview then
  select result_json,command_json into result,stored from voltmaster_private.financial_command_receipts where owner_id=p_owner and request_id=p_request;
  if found then if stored is distinct from p_command then raise exception 'Request reused with different command';end if;return result;end if;
 end if;
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 if p_preview then
  begin rid:=public.foreman_add_subcontractor(pid,p_command->'values'->>'name',p_command->'values'->>'comment');raise exception using errcode='P0993',message='preview';exception when sqlstate 'P0993' then null;end;
  select jsonb_build_object('project',jsonb_build_object('id',p.id,'name',p.name),'values',p_command->'values') into snapshot from public.projects p where p.id=pid;return snapshot;
 end if;
 rid:=public.foreman_add_subcontractor(pid,p_command->'values'->>'name',p_command->'values'->>'comment');
 select jsonb_build_object('id',s.id,'project_id',s.project_id,'name',s.name,'comment',s.comment) into result from public.subcontractors s where id=rid;
 result:=jsonb_build_object('status','completed','kind','foreman_subcontractor','action','create','record',result,'verified',true);
 insert into voltmaster_private.financial_command_receipts values(p_owner,p_request,p_command,result,now());return result;
end $$;
revoke all on function voltmaster_private.foreman_subcontractor_command(uuid,uuid,jsonb,boolean) from public,anon,authenticated;grant execute on function voltmaster_private.foreman_subcontractor_command(uuid,uuid,jsonb,boolean) to service_role;

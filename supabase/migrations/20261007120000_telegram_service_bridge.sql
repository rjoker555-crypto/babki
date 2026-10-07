-- The private schema is intentionally absent from PostgREST. This narrowly
-- dispatched RPC is executable only with the existing server service role.
create or replace function public.telegram_bridge(p_action text,p_payload jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare l voltmaster_private.telegram_links;p public.profiles; s voltmaster_private.telegram_submissions;c voltmaster_private.telegram_callbacks;out jsonb;pid uuid; owner uuid; tg bigint; gen integer; z record;
begin
 if auth.role()<>'service_role' then raise exception 'Service only';end if;
 if p_action='consume' then return voltmaster_private.telegram_consume_link(p_payload->>'hash',(p_payload->>'telegram_user_id')::bigint);end if;
 if p_action='enqueue' then return voltmaster_private.telegram_enqueue((p_payload->>'update_id')::bigint,(p_payload->>'telegram_user_id')::bigint,p_payload->'update',p_payload->>'event');end if;
 if p_action='claim' then return voltmaster_private.telegram_claim();end if;
 if p_action='finish' then return voltmaster_private.telegram_finish((p_payload->>'update_id')::bigint,p_payload->'result',p_payload->'answer',(p_payload->>'retry_seconds')::integer);end if;
 if p_action='claim_outbox' then return voltmaster_private.telegram_claim_outbox();end if;
 if p_action='finish_outbox' then perform voltmaster_private.telegram_finish_outbox((p_payload->>'id')::uuid,p_payload->>'state',(p_payload->>'telegram_message_id')::bigint,(p_payload->>'retry_seconds')::integer);return '{}'::jsonb;end if;
 if p_action='get_link' then
  select * into l from voltmaster_private.telegram_links where telegram_user_id=(p_payload->>'telegram_user_id')::bigint;
  if not found then return null;end if;
  select * into p from public.profiles where id=l.owner_id and is_active;
  if p.id is null or p.role not in ('director','foreman') or p.role='director' and not exists(select 1 from public.agent_director_access where user_id=p.id) then return null;end if;
  if l.current_chat_id is null or not exists(select 1 from public.agent_conversations where id=l.current_chat_id and owner_id=p.id) then return null;end if;
  if p.role='foreman' and l.selected_project_id is not null and not exists(select 1 from public.project_team_members where user_id=p.id and project_id=l.selected_project_id and is_active) and not exists(select 1 from public.projects where id=l.selected_project_id and responsible_user_id=p.id) then update voltmaster_private.telegram_links set selected_project_id=null where owner_id=p.id;l.selected_project_id:=null;end if;
  return jsonb_build_object('owner_id',p.id,'role',p.role,'chat_id',l.current_chat_id,'mode',l.mode,'generation',l.generation,'project_id',l.selected_project_id);
 end if;
 if p_action='projects' then
  owner:=(p_payload->>'owner_id')::uuid;select * into p from public.profiles where id=owner and is_active;
  if p.role='director' and exists(select 1 from public.agent_director_access where user_id=owner) then
   return coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from (select id,name from public.projects order by name limit 50) q),'[]'::jsonb);
  elsif p.role='foreman' then
   return coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from (select distinct pr.id,pr.name from public.projects pr where pr.responsible_user_id=owner or exists(select 1 from public.project_team_members tm where tm.project_id=pr.id and tm.user_id=owner and tm.is_active) order by pr.name limit 50) q),'[]'::jsonb);
  end if;return '[]'::jsonb;
 end if;
 if p_action='choose_project' then return to_jsonb(voltmaster_private.telegram_choose_project((p_payload->>'owner_id')::uuid,(p_payload->>'telegram_user_id')::bigint,(p_payload->>'project_id')::uuid,(p_payload->>'generation')::integer));end if;
 if p_action='callback_create' then
  owner:=(p_payload->>'owner_id')::uuid;tg:=(p_payload->>'telegram_user_id')::bigint;gen:=(p_payload->>'generation')::integer;
  select * into l from voltmaster_private.telegram_links where owner_id=owner and telegram_user_id=tg and generation=gen;
  if not found then raise exception 'Link changed';end if;
  insert into voltmaster_private.telegram_callbacks(owner_id,telegram_user_id,chat_id,generation,action,plan_id,plan_revision,project_id,expires_at)
  values(owner,tg,l.current_chat_id,gen,p_payload->>'callback_action',(p_payload->>'plan_id')::uuid,(p_payload->>'plan_revision')::uuid,(p_payload->>'project_id')::uuid,now()+interval '30 minutes') returning * into c;
  return jsonb_build_object('id',c.id);
 end if;
 if p_action='callback_consume' then
  select * into c from voltmaster_private.telegram_callbacks where id=(p_payload->>'id')::uuid and telegram_user_id=(p_payload->>'telegram_user_id')::bigint for update;
  if not found or c.used_at is not null or c.expires_at<=now() then return null;end if;
  select * into l from voltmaster_private.telegram_links where owner_id=c.owner_id and telegram_user_id=c.telegram_user_id;
  if not found or l.current_chat_id is distinct from c.chat_id or l.generation<>c.generation then return null;end if;
  select * into p from public.profiles where id=c.owner_id and is_active;
  if p.id is null or p.role not in ('director','foreman') or p.role='director' and not exists(select 1 from public.agent_director_access where user_id=p.id) then return null;end if;
  update voltmaster_private.telegram_callbacks set used_at=now() where id=c.id;
  return to_jsonb(c);
 end if;
 if p_action='message_context' then
  insert into voltmaster_private.telegram_message_context(message_id,mode,kind,telegram_update_id)
  values((p_payload->>'message_id')::uuid,p_payload->>'mode',p_payload->>'kind',(p_payload->>'update_id')::bigint)
  on conflict(message_id) do nothing;return '{}'::jsonb;
 end if;
 if p_action='draft' then
  owner:=(p_payload->>'owner_id')::uuid;pid:=(p_payload->>'project_id')::uuid;
  select * into l from voltmaster_private.telegram_links where owner_id=owner and current_chat_id=(p_payload->>'chat_id')::uuid and selected_project_id=pid for update;
  if not found then raise exception 'Project selection changed';end if;
  select * into p from public.profiles where id=owner and is_active;
  if p.id is null or p.role not in ('director','foreman') or p.role='director' and not exists(select 1 from public.agent_director_access where user_id=owner) then raise exception 'Role changed';end if;
  if p.role='foreman' and not exists(select 1 from public.project_team_members where project_id=pid and user_id=owner and is_active) and not exists(select 1 from public.projects where id=pid and responsible_user_id=owner) then raise exception 'Project scope changed';end if;
  select * into s from voltmaster_private.telegram_submissions where owner_id=owner and chat_id=l.current_chat_id and project_id=pid and status='draft' order by created_at desc limit 1 for update;
  if not found then insert into voltmaster_private.telegram_submissions(owner_id,chat_id,project_id,project_name) select owner,l.current_chat_id,id,name from public.projects where id=pid returning * into s;end if;
  return to_jsonb(s);
 end if;
 if p_action='append_file' then
  select * into s from voltmaster_private.telegram_submissions where id=(p_payload->>'submission_id')::uuid and status='draft' for update;
  if not found or s.owner_id is distinct from (p_payload->>'owner_id')::uuid then raise exception 'Draft changed';end if;
  if (select count(*) from voltmaster_private.telegram_submission_files where submission_id=s.id)>=5 then raise exception 'Five files per submission maximum';end if;
  insert into voltmaster_private.telegram_submission_files(submission_id,telegram_file_id,file_name,mime_type,file_size,storage_path,sha256)
  values(s.id,p_payload->>'telegram_file_id',p_payload->>'file_name',p_payload->>'mime_type',(p_payload->>'file_size')::integer,p_payload->>'storage_path',p_payload->>'sha256') on conflict(submission_id,telegram_file_id) do nothing;
  return (select jsonb_build_object('files',count(*),'submission_id',s.id) from voltmaster_private.telegram_submission_files where submission_id=s.id);
 end if;
 if p_action='explain' then
  select * into s from voltmaster_private.telegram_submissions where owner_id=(p_payload->>'owner_id')::uuid and chat_id=(p_payload->>'chat_id')::uuid and status='draft' order by created_at desc limit 1 for update;
  if not found then return null;end if;
  update voltmaster_private.telegram_submissions set explanation=left(trim(concat_ws(' ',nullif(explanation,''),p_payload->>'text')),2000) where id=s.id;
  return jsonb_build_object('submission_id',s.id);
 end if;
 if p_action='submission_preview' then
  select * into s from voltmaster_private.telegram_submissions where owner_id=(p_payload->>'owner_id')::uuid and chat_id=(p_payload->>'chat_id')::uuid and status='draft' order by created_at desc limit 1;
  if not found then return null;end if;
  return jsonb_build_object('id',s.id,'project_id',s.project_id,'project_name',s.project_name,'explanation',s.explanation,'files',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'file_size',file_size,'status',status)),'[]'::jsonb) from voltmaster_private.telegram_submission_files where submission_id=s.id));
 end if;
 if p_action='submit' then return voltmaster_private.telegram_submit((p_payload->>'owner_id')::uuid,(p_payload->>'chat_id')::uuid,(p_payload->>'project_id')::uuid,p_payload->>'explanation');end if;
 if p_action='status' then
  owner:=(p_payload->>'owner_id')::uuid;
  if not exists(select 1 from voltmaster_private.telegram_links where owner_id=owner and telegram_user_id=(p_payload->>'telegram_user_id')::bigint) then return '[]'::jsonb;end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'project_name',project_name,'status',status,'submitted_at',submitted_at) order by created_at desc) from (select * from voltmaster_private.telegram_submissions where owner_id=owner order by created_at desc limit 10) q),'[]'::jsonb);
 end if;
 raise exception 'Unknown Telegram bridge action';
end $fn$;
revoke all on function public.telegram_bridge(text,jsonb) from public,anon,authenticated;
grant execute on function public.telegram_bridge(text,jsonb) to service_role;

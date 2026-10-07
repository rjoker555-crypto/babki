alter table voltmaster_private.telegram_links add column if not exists document_type text check(document_type in ('contract','project','estimate','addendum','other'));
alter table voltmaster_private.telegram_submissions add column if not exists document_type text not null default 'other' check(document_type in ('contract','project','estimate','addendum','other'));
alter table voltmaster_private.telegram_submission_files add column if not exists agent_file_id uuid references public.agent_file_assets(id) on delete set null;
alter table voltmaster_private.telegram_callbacks drop constraint if exists telegram_callbacks_action_check;
alter table voltmaster_private.telegram_callbacks add constraint telegram_callbacks_action_check check(action in ('confirm','cancel','project','doc_type','finish','review'));

create or replace function public.telegram_select_document_type(p_owner uuid,p_telegram bigint,p_chat uuid,p_generation integer,p_type text) returns boolean language plpgsql security definer set search_path='' as $fn$
declare l voltmaster_private.telegram_links;
begin
 if auth.role()<>'service_role' or p_type not in ('contract','project','estimate','addendum','other') then return false;end if;
 select * into l from voltmaster_private.telegram_links where owner_id=p_owner and telegram_user_id=p_telegram and current_chat_id=p_chat and generation=p_generation and selected_project_id is not null for update;
 if not found then return false;end if;
 update voltmaster_private.telegram_links set document_type=p_type,updated_at=now() where owner_id=p_owner;
 update voltmaster_private.telegram_submissions set document_type=p_type where owner_id=p_owner and chat_id=p_chat and status='draft';
 return true;
end $fn$;
revoke all on function public.telegram_select_document_type(uuid,bigint,uuid,integer,text) from public,anon,authenticated;
grant execute on function public.telegram_select_document_type(uuid,bigint,uuid,integer,text) to service_role;

create or replace function public.telegram_link_document_type(p_owner uuid,p_telegram bigint) returns text language sql security definer set search_path='' as $fn$
 select document_type from voltmaster_private.telegram_links where auth.role()='service_role' and owner_id=p_owner and telegram_user_id=p_telegram
$fn$;
revoke all on function public.telegram_link_document_type(uuid,bigint) from public,anon,authenticated;
grant execute on function public.telegram_link_document_type(uuid,bigint) to service_role;

create or replace function public.telegram_set_asset(p_submission uuid,p_telegram_file text,p_asset uuid) returns uuid language plpgsql security definer set search_path='' as $fn$
declare f voltmaster_private.telegram_submission_files;s voltmaster_private.telegram_submissions;a public.agent_file_assets;
begin
 if auth.role()<>'service_role' then raise exception 'Service only';end if;
 select * into f from voltmaster_private.telegram_submission_files where submission_id=p_submission and telegram_file_id=p_telegram_file for update;
 select * into s from voltmaster_private.telegram_submissions where id=p_submission and status='draft';
 select * into a from public.agent_file_assets where id=p_asset and owner_id=s.owner_id and chat_id=s.chat_id;
 if f.id is null or s.id is null or a.id is null or f.file_size is distinct from a.file_size or f.sha256 is distinct from a.sha256 then raise exception 'Prepared personal file changed';end if;
 update voltmaster_private.telegram_submission_files set agent_file_id=p_asset where id=f.id;
 return f.id;
end $fn$;
revoke all on function public.telegram_set_asset(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.telegram_set_asset(uuid,text,uuid) to service_role;

create or replace function public.telegram_submission_preview(p_owner uuid,p_chat uuid) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare s voltmaster_private.telegram_submissions;candidate jsonb;
begin
 if auth.role()<>'service_role' then raise exception 'Service only';end if;
 select * into s from voltmaster_private.telegram_submissions where owner_id=p_owner and chat_id=p_chat and status='draft' order by created_at desc limit 1;
 if not found then return null;end if;
 select jsonb_build_object('submission_id',s.id,'project_id',s.project_id,'document_type',s.document_type,'explanation',s.explanation,'files',coalesce(jsonb_agg(jsonb_build_object('id',id,'sha256',sha256,'agent_file_id',agent_file_id) order by id),'[]'::jsonb)) into candidate from voltmaster_private.telegram_submission_files where submission_id=s.id;
 return jsonb_build_object('id',s.id,'project_id',s.project_id,'project_name',s.project_name,'document_type',s.document_type,'explanation',s.explanation,'digest',encode(extensions.digest(candidate::text,'sha256'),'hex'),'files',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'file_size',file_size,'agent_file_id',agent_file_id)),'[]'::jsonb) from voltmaster_private.telegram_submission_files where submission_id=s.id));
end $fn$;
revoke all on function public.telegram_submission_preview(uuid,uuid) from public,anon,authenticated;
grant execute on function public.telegram_submission_preview(uuid,uuid) to service_role;

create or replace function public.telegram_create_callback(p_owner uuid,p_telegram bigint,p_generation integer,p_action text,p_plan uuid default null,p_revision text default null,p_project uuid default null) returns uuid language plpgsql security definer set search_path='' as $fn$
declare l voltmaster_private.telegram_links; callback_id uuid;
begin
 if auth.role()<>'service_role' then raise exception 'Service only';end if;
 select * into l from voltmaster_private.telegram_links where owner_id=p_owner and telegram_user_id=p_telegram and generation=p_generation;
 if not found or p_action not in ('confirm','cancel','project','doc_type','finish','review') then raise exception 'Telegram link changed';end if;
 if p_action in ('confirm','cancel') and (p_plan is null or p_revision is null) then raise exception 'Plan identity required';end if;
 if p_action='project' and p_project is null then raise exception 'Project required';end if;
 if p_action='doc_type' and p_revision not in ('contract','project','estimate','addendum','other') then raise exception 'Document type required';end if;
 insert into voltmaster_private.telegram_callbacks(owner_id,telegram_user_id,chat_id,generation,action,plan_id,plan_revision,project_id)
 values(p_owner,p_telegram,l.current_chat_id,p_generation,p_action,p_plan,p_revision,p_project) returning id into callback_id;
 return callback_id;
end $fn$;
revoke all on function public.telegram_create_callback(uuid,bigint,integer,text,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.telegram_create_callback(uuid,bigint,integer,text,uuid,text,uuid) to service_role;

create or replace function voltmaster_private.telegram_choose_project(p_owner uuid,p_telegram bigint,p_project uuid,p_generation integer) returns boolean language plpgsql security definer set search_path='' as $fn$
declare l voltmaster_private.telegram_links;p public.profiles;
begin
 select * into l from voltmaster_private.telegram_links where owner_id=p_owner and telegram_user_id=p_telegram and generation=p_generation for update;
 if l.owner_id is null then return false;end if;
 select * into p from public.profiles where id=p_owner and is_active;
 if p.id is null or p.role not in ('director','foreman') then return false;end if;
 if p.role='director' and not exists(select 1 from public.agent_director_access where user_id=p_owner) then return false;end if;
 if not exists(select 1 from public.projects where id=p_project) then return false;end if;
 if p.role='foreman' and not exists(select 1 from public.project_team_members where project_id=p_project and user_id=p_owner and is_active) and not exists(select 1 from public.projects where id=p_project and responsible_user_id=p_owner) then return false;end if;
 update voltmaster_private.telegram_links set selected_project_id=p_project,document_type=null,updated_at=now() where owner_id=p_owner;
 return true;
end $fn$;
revoke all on function voltmaster_private.telegram_choose_project(uuid,bigint,uuid,integer) from public,anon,authenticated;
grant execute on function voltmaster_private.telegram_choose_project(uuid,bigint,uuid,integer) to service_role;

create or replace function public.telegram_attach_batch(p_owner uuid,p_chat uuid,p_submission uuid,p_confirm uuid,p_expected text) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare s voltmaster_private.telegram_submissions;l voltmaster_private.telegram_links;f voltmaster_private.telegram_submission_files;candidate jsonb;digest text;item jsonb;result jsonb:='[]'::jsonb;n int;
begin
 if auth.role()<>'service_role' or not exists(select 1 from public.profiles where id=p_owner and role='director' and is_active) or not exists(select 1 from public.agent_director_access where user_id=p_owner) then raise exception 'Trusted director required';end if;
 select * into s from voltmaster_private.telegram_submissions where id=p_submission and owner_id=p_owner and chat_id=p_chat for update;
 select * into l from voltmaster_private.telegram_links where owner_id=p_owner and current_chat_id=p_chat and selected_project_id=s.project_id;
 if s.id is null or l.owner_id is null or s.status<>'draft' or s.project_id is null or s.document_type<>l.document_type then raise exception 'Submission changed';end if;
 if not exists(select 1 from public.agent_chat_messages where id=p_confirm and owner_id=p_owner and chat_id=p_chat and kind='user' and source='telegram' and content='ПОДТВЕРЖДАЮ ПОДАЧУ '||p_submission::text) then raise exception 'Exact Telegram confirmation required';end if;
 select jsonb_build_object('submission_id',s.id,'project_id',s.project_id,'document_type',s.document_type,'explanation',s.explanation,'files',coalesce(jsonb_agg(jsonb_build_object('id',id,'sha256',sha256,'agent_file_id',agent_file_id) order by id),'[]'::jsonb)) into candidate
 from voltmaster_private.telegram_submission_files where submission_id=s.id;
 digest:=encode(extensions.digest(candidate::text,'sha256'),'hex');
 if digest is distinct from p_expected then raise exception 'Submission changed since preview';end if;
 select count(*) into n from voltmaster_private.telegram_submission_files where submission_id=s.id and status='received' and agent_file_id is not null;
 if n=0 or n<>(select count(*) from voltmaster_private.telegram_submission_files where submission_id=s.id) then raise exception 'All files must be ready';end if;
 for f in select * from voltmaster_private.telegram_submission_files where submission_id=s.id order by id loop
  item:=voltmaster_private.document_command(p_owner,f.id,jsonb_build_object('action','attach','project_id',s.project_id,'document_type',s.document_type,'file_id',f.agent_file_id,'values',jsonb_build_object('title',f.file_name,'comment','Подача Telegram '||s.id::text||'; пояснение: '||left(s.explanation,1000))),false);
  if item->>'verified'<>'true' then raise exception 'Document verification failed';end if;
  update voltmaster_private.telegram_submission_files set status='approved',document_id=(item->'document'->>'id')::uuid where id=f.id;
  result:=result||jsonb_build_array(jsonb_build_object('file_name',f.file_name,'document_id',item->'document'->>'id'));
 end loop;
 update voltmaster_private.telegram_submissions set status='approved',submitted_at=now(),reviewed_at=now(),reviewed_by=p_owner where id=s.id;
 return jsonb_build_object('status','approved','submission_id',s.id,'project_name',s.project_name,'documents',result);
end $fn$;
revoke all on function public.telegram_attach_batch(uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.telegram_attach_batch(uuid,uuid,uuid,uuid,text) to service_role;

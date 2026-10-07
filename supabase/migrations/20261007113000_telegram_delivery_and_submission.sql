create table if not exists voltmaster_private.telegram_callbacks (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 telegram_user_id bigint not null,
 chat_id uuid not null references public.agent_conversations(id) on delete cascade,
 generation integer not null,
 action text not null check(action in ('confirm','cancel','project','finish','review')),
 plan_id uuid,plan_revision uuid,project_id uuid,
 expires_at timestamptz not null default now()+interval '30 minutes',
 used_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists voltmaster_private.telegram_message_context (
 message_id uuid primary key references public.agent_chat_messages(id) on delete cascade,
 mode text not null check(mode in ('instruction','consultation','document')),
 kind text not null check(kind in ('text','voice','document','callback','system')),
 telegram_update_id bigint unique,
 created_at timestamptz not null default now()
);
alter table voltmaster_private.telegram_callbacks enable row level security;
alter table voltmaster_private.telegram_message_context enable row level security;
revoke all on voltmaster_private.telegram_callbacks,voltmaster_private.telegram_message_context from public,anon,authenticated;
grant all on voltmaster_private.telegram_callbacks,voltmaster_private.telegram_message_context to service_role;

create or replace function voltmaster_private.telegram_claim_outbox() returns jsonb language plpgsql security definer set search_path='' as $fn$
declare item voltmaster_private.telegram_outbox;
begin
 select * into item from voltmaster_private.telegram_outbox q where (q.status='pending' and q.available_at<=now() or q.status='sending' and q.lease_until<now()) order by q.available_at,q.id for update skip locked limit 1;
 if not found then return null;end if;
 update voltmaster_private.telegram_outbox set status='sending',attempts=attempts+1,lease_until=now()+interval '45 seconds' where id=item.id;
 return to_jsonb(item);
end $fn$;
revoke all on function voltmaster_private.telegram_claim_outbox() from public,anon,authenticated;
grant execute on function voltmaster_private.telegram_claim_outbox() to service_role;

create or replace function voltmaster_private.telegram_finish_outbox(p_id uuid,p_state text,p_message bigint default null,p_retry integer default null) returns void language plpgsql security definer set search_path='' as $fn$
declare item voltmaster_private.telegram_outbox;
begin
 select * into item from voltmaster_private.telegram_outbox where id=p_id for update;
 if not found then raise exception 'Missing outgoing message';end if;
 if p_state='sent' then update voltmaster_private.telegram_outbox set status='sent',telegram_message_id=p_message,sent_at=now(),lease_until=null where id=p_id;
 elsif p_state='blocked' then update voltmaster_private.telegram_outbox set status='blocked',lease_until=null where id=p_id;
 elsif item.attempts<6 then update voltmaster_private.telegram_outbox set status='pending',available_at=now()+make_interval(secs=>greatest(1,least(coalesce(p_retry,10),3600))),lease_until=null where id=p_id;
 else update voltmaster_private.telegram_outbox set status='failed',lease_until=null where id=p_id;end if;
end $fn$;
revoke all on function voltmaster_private.telegram_finish_outbox(uuid,text,bigint,integer) from public,anon,authenticated;
grant execute on function voltmaster_private.telegram_finish_outbox(uuid,text,bigint,integer) to service_role;

create or replace function voltmaster_private.telegram_choose_project(p_owner uuid,p_telegram bigint,p_project uuid,p_generation integer) returns boolean language plpgsql security definer set search_path='' as $fn$
declare l voltmaster_private.telegram_links;p public.profiles;
begin
 select * into l from voltmaster_private.telegram_links where owner_id=p_owner and telegram_user_id=p_telegram and generation=p_generation for update;
 select * into p from public.profiles where id=p_owner and is_active;
 if not found or p.role not in ('director','foreman') then return false;end if;
 if p.role='director' and not exists(select 1 from public.agent_director_access where user_id=p_owner) then return false;end if;
 if not exists(select 1 from public.projects where id=p_project) then return false;end if;
 if p.role='foreman' and not exists(select 1 from public.project_team_members where project_id=p_project and user_id=p_owner and is_active) and not exists(select 1 from public.projects where id=p_project and responsible_user_id=p_owner) then return false;end if;
 update voltmaster_private.telegram_links set selected_project_id=p_project,updated_at=now() where owner_id=p_owner;
 return true;
end $fn$;
revoke all on function voltmaster_private.telegram_choose_project(uuid,bigint,uuid,integer) from public,anon,authenticated;
grant execute on function voltmaster_private.telegram_choose_project(uuid,bigint,uuid,integer) to service_role;

create or replace function voltmaster_private.telegram_submit(p_owner uuid,p_chat uuid,p_project uuid,p_explanation text) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare p public.profiles;s voltmaster_private.telegram_submissions; count_files int;
begin
 select * into p from public.profiles where id=p_owner and is_active;
 if p.role not in ('director','foreman') or p.role='director' and not exists(select 1 from public.agent_director_access where user_id=p_owner) then raise exception 'Telegram access denied';end if;
 if not exists(select 1 from voltmaster_private.telegram_links where owner_id=p_owner and current_chat_id=p_chat and selected_project_id=p_project) then raise exception 'Selected project changed';end if;
 if p.role='foreman' and not exists(select 1 from public.project_team_members where project_id=p_project and user_id=p_owner and is_active) and not exists(select 1 from public.projects where id=p_project and responsible_user_id=p_owner) then raise exception 'Project scope changed';end if;
 select * into s from voltmaster_private.telegram_submissions where owner_id=p_owner and chat_id=p_chat and project_id=p_project and status='draft' order by created_at desc limit 1 for update;
 if not found then raise exception 'No draft';end if;
 select count(*) into count_files from voltmaster_private.telegram_submission_files where submission_id=s.id and status='received';
 if count_files=0 then raise exception 'No accepted files';end if;
 update voltmaster_private.telegram_submissions set status='pending_review',explanation=left(coalesce(p_explanation,''),2000),submitted_at=now() where id=s.id;
 return jsonb_build_object('submission_id',s.id,'files',count_files,'project_name',s.project_name,'status','pending_review');
end $fn$;
revoke all on function voltmaster_private.telegram_submit(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function voltmaster_private.telegram_submit(uuid,uuid,uuid,text) to service_role;

create or replace function public.telegram_review_submissions() returns jsonb language plpgsql security definer set search_path='' as $fn$
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and role='director' and is_active) or not exists(select 1 from public.agent_director_access where user_id=auth.uid()) then raise exception 'Trusted director required';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'owner_id',s.owner_id,'project_id',s.project_id,'project_name',s.project_name,'explanation',s.explanation,'status',s.status,'submitted_at',s.submitted_at,'files',(select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'file_name',f.file_name,'file_size',f.file_size,'mime_type',f.mime_type,'status',f.status,'error',f.error)),'[]'::jsonb) from voltmaster_private.telegram_submission_files f where f.submission_id=s.id))) from (select * from voltmaster_private.telegram_submissions where status in ('pending_review','partial') order by submitted_at desc limit 100) s),'[]'::jsonb);
end $fn$;
revoke all on function public.telegram_review_submissions() from public,anon;
grant execute on function public.telegram_review_submissions() to authenticated;

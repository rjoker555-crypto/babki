-- Telegram is an additional transport. All tables below are service-only.
create table if not exists voltmaster_private.telegram_links (
 owner_id uuid primary key references auth.users(id) on delete cascade,
 telegram_user_id bigint unique not null check (telegram_user_id>0),
 current_chat_id uuid references public.agent_conversations(id) on delete set null,
 mode text not null default 'instruction' check (mode in ('instruction','consultation','document')),
 selected_project_id uuid references public.projects(id) on delete set null,
 generation integer not null default 1,
 linked_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists voltmaster_private.telegram_link_tickets (
 owner_id uuid primary key references auth.users(id) on delete cascade,
 code_hash text unique not null check(code_hash ~ '^[0-9a-f]{64}$'),
 expires_at timestamptz not null,
 attempts integer not null default 0 check(attempts between 0 and 5),
 created_at timestamptz not null default now()
);
create table if not exists voltmaster_private.telegram_link_attempts (
 telegram_user_id bigint primary key,
 attempts integer not null default 0,
 first_at timestamptz not null default now()
);
create table if not exists voltmaster_private.telegram_updates (
 update_id bigint primary key,
 telegram_user_id bigint not null,
 owner_id uuid references auth.users(id) on delete cascade,
 chat_id uuid references public.agent_conversations(id) on delete set null,
 mode text,
 generation integer,
 payload jsonb not null,
 status text not null default 'pending' check(status in ('pending','processing','completed','failed')),
 attempts integer not null default 0,
 available_at timestamptz not null default now(), lease_until timestamptz,
 result jsonb,
 received_at timestamptz not null default now(), completed_at timestamptz
);
create index if not exists telegram_updates_ready_idx on voltmaster_private.telegram_updates(status,available_at,update_id);
create table if not exists voltmaster_private.telegram_outbox (
 id uuid primary key default gen_random_uuid(),
 update_id bigint references voltmaster_private.telegram_updates(update_id) on delete set null,
 telegram_user_id bigint not null,
 body jsonb not null,
 status text not null default 'pending' check(status in ('pending','sending','sent','blocked','failed')),
 attempts integer not null default 0,
 available_at timestamptz not null default now(), lease_until timestamptz,
 sent_at timestamptz, telegram_message_id bigint,
 unique(update_id)
);
create table if not exists voltmaster_private.telegram_submissions (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 chat_id uuid not null references public.agent_conversations(id) on delete cascade,
 project_id uuid references public.projects(id) on delete set null,
 project_name text not null,
 explanation text not null default '',
 status text not null default 'draft' check(status in ('draft','pending_review','approved','rejected','partial','cancelled')),
 created_at timestamptz not null default now(), submitted_at timestamptz,
 reviewed_at timestamptz, reviewed_by uuid references auth.users(id) on delete set null
);
create table if not exists voltmaster_private.telegram_submission_files (
 id uuid primary key default gen_random_uuid(),
 submission_id uuid not null references voltmaster_private.telegram_submissions(id) on delete cascade,
 telegram_file_id text not null,
 file_name text not null,
 mime_type text not null,
 file_size integer not null check(file_size>0 and file_size<=8388608),
 storage_path text unique not null,
 sha256 text not null,
 status text not null default 'received' check(status in ('received','approved','rejected','failed')),
 document_id uuid references public.project_documents(id) on delete set null,
 error text,
 unique(submission_id,telegram_file_id)
);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('telegram-inbox','telegram-inbox',false,8388608,array['application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','text/plain','image/jpeg','image/png'])
 on conflict(id) do update set public=false,file_size_limit=8388608,allowed_mime_types=excluded.allowed_mime_types;
alter table voltmaster_private.telegram_links enable row level security;
alter table voltmaster_private.telegram_link_tickets enable row level security;
alter table voltmaster_private.telegram_link_attempts enable row level security;
alter table voltmaster_private.telegram_updates enable row level security;
alter table voltmaster_private.telegram_outbox enable row level security;
alter table voltmaster_private.telegram_submissions enable row level security;
alter table voltmaster_private.telegram_submission_files enable row level security;
revoke all on all tables in schema voltmaster_private from public,anon,authenticated;
grant all on voltmaster_private.telegram_links,voltmaster_private.telegram_link_tickets,voltmaster_private.telegram_link_attempts,voltmaster_private.telegram_updates,voltmaster_private.telegram_outbox,voltmaster_private.telegram_submissions,voltmaster_private.telegram_submission_files to service_role;

alter table public.agent_chat_messages drop constraint if exists agent_chat_messages_source_check;
alter table public.agent_chat_messages add constraint agent_chat_messages_source_check check(source in ('text','voice','telegram'));

create or replace function public.telegram_begin_link(p_hash text) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare actor uuid:=auth.uid(); p public.profiles; existing voltmaster_private.telegram_links;
begin
 if actor is null or p_hash !~ '^[0-9a-f]{64}$' then raise exception 'Invalid link request';end if;
 select * into p from public.profiles where id=actor and is_active;
 if p.role not in ('director','foreman') or p.role='director' and not exists(select 1 from public.agent_director_access where user_id=actor) then raise exception 'Telegram role denied';end if;
 delete from voltmaster_private.telegram_link_tickets where owner_id=actor;
 insert into voltmaster_private.telegram_link_tickets(owner_id,code_hash,expires_at) values(actor,p_hash,now()+interval '10 minutes');
 select * into existing from voltmaster_private.telegram_links where owner_id=actor;
 return jsonb_build_object('expires_at',(select expires_at from voltmaster_private.telegram_link_tickets where owner_id=actor),'linked',found);
end $fn$;
revoke all on function public.telegram_begin_link(text) from public,anon;
grant execute on function public.telegram_begin_link(text) to authenticated;

create or replace function public.telegram_disconnect() returns boolean language plpgsql security definer set search_path='' as $fn$
declare actor uuid:=auth.uid();
begin
 if actor is null or not exists(select 1 from public.profiles where id=actor and is_active) then raise exception 'Active account required';end if;
 delete from voltmaster_private.telegram_link_tickets where owner_id=actor;
 delete from voltmaster_private.telegram_links where owner_id=actor;
 update voltmaster_private.telegram_updates set status='failed',result='{"error":"disconnected"}'::jsonb where owner_id=actor and status in ('pending','processing');
 return true;
end $fn$;
revoke all on function public.telegram_disconnect() from public,anon;
grant execute on function public.telegram_disconnect() to authenticated;

create or replace function public.telegram_link_status() returns jsonb language sql security definer set search_path='' as $fn$
 select jsonb_build_object('linked',exists(select 1 from voltmaster_private.telegram_links where owner_id=auth.uid()),'role',(select role from public.profiles where id=auth.uid() and is_active),'expires_at',(select expires_at from voltmaster_private.telegram_link_tickets where owner_id=auth.uid()))
$fn$;
revoke all on function public.telegram_link_status() from public,anon;
grant execute on function public.telegram_link_status() to authenticated;

create or replace function voltmaster_private.telegram_consume_link(p_hash text,p_telegram bigint) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare ticket voltmaster_private.telegram_link_tickets; p public.profiles; n int; chat uuid;
begin
 if p_hash !~ '^[0-9a-f]{64}$' or p_telegram is null or p_telegram<=0 then return jsonb_build_object('linked',false);end if;
 insert into voltmaster_private.telegram_link_attempts(telegram_user_id,attempts) values(p_telegram,1)
 on conflict(telegram_user_id) do update set attempts=case when telegram_link_attempts.first_at<now()-interval '1 hour' then 1 else telegram_link_attempts.attempts+1 end,first_at=case when telegram_link_attempts.first_at<now()-interval '1 hour' then now() else telegram_link_attempts.first_at end
 returning attempts into n;
 if n>8 then return jsonb_build_object('linked',false,'rate_limited',true);end if;
 select * into ticket from voltmaster_private.telegram_link_tickets where code_hash=p_hash for update;
 if not found or ticket.expires_at<=now() or ticket.attempts>=5 then return jsonb_build_object('linked',false);end if;
 update voltmaster_private.telegram_link_tickets set attempts=attempts+1 where owner_id=ticket.owner_id;
 select * into p from public.profiles where id=ticket.owner_id and is_active;
 if p.role not in ('director','foreman') or p.role='director' and not exists(select 1 from public.agent_director_access where user_id=p.id) then return jsonb_build_object('linked',false);end if;
 if exists(select 1 from voltmaster_private.telegram_links where telegram_user_id=p_telegram and owner_id<>p.id) then return jsonb_build_object('linked',false);end if;
 select id into chat from public.agent_conversations where owner_id=p.id and title='Telegram' order by last_message_at desc limit 1;
 if chat is null then insert into public.agent_conversations(owner_id,title) values(p.id,'Telegram') returning id into chat;end if;
 insert into voltmaster_private.telegram_links(owner_id,telegram_user_id,current_chat_id,mode) values(p.id,p_telegram,chat,case when p.role='foreman' then 'document' else 'instruction' end)
 on conflict(owner_id) do update set telegram_user_id=excluded.telegram_user_id,current_chat_id=excluded.current_chat_id,mode=excluded.mode,generation=telegram_links.generation+1,updated_at=now();
 delete from voltmaster_private.telegram_link_tickets where owner_id=p.id;
 return jsonb_build_object('linked',true,'role',p.role);
end $fn$;
revoke all on function voltmaster_private.telegram_consume_link(text,bigint) from public,anon,authenticated;
grant execute on function voltmaster_private.telegram_consume_link(text,bigint) to service_role;

create or replace function voltmaster_private.telegram_enqueue(p_update_id bigint,p_telegram bigint,p_payload jsonb,p_event text) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare l voltmaster_private.telegram_links;p public.profiles; chat uuid; m text; project uuid;
begin
 if p_update_id<0 or p_telegram<=0 or octet_length(p_payload::text)>65536 then raise exception 'Invalid Telegram update';end if;
 select * into l from voltmaster_private.telegram_links where telegram_user_id=p_telegram for update;
 if not found then return jsonb_build_object('accepted',false,'reason','unlinked');end if;
 if exists(select 1 from voltmaster_private.telegram_updates where update_id=p_update_id) then return jsonb_build_object('accepted',true,'duplicate',true);end if;
 select * into p from public.profiles where id=l.owner_id and is_active;
 if p.role not in ('director','foreman') or p.role='director' and not exists(select 1 from public.agent_director_access where user_id=p.id) then return jsonb_build_object('accepted',false,'reason','role_changed');end if;
 chat:=l.current_chat_id;m:=l.mode;project:=l.selected_project_id;
 if chat is null or not exists(select 1 from public.agent_conversations where id=chat and owner_id=p.id) or p_event in ('new_chat','new_submission') then
  insert into public.agent_conversations(owner_id,title) values(p.id,case when p.role='foreman' then 'Telegram: подача' else 'Telegram' end) returning id into chat;
  project:=null;
 end if;
 if p.role='director' then
  if p_event='consultation' then m:='consultation';elsif p_event='instruction' then m:='instruction';elsif p_event='document' then m:='document';end if;
 else m:='document';end if;
 update voltmaster_private.telegram_links set current_chat_id=chat,mode=m,selected_project_id=project,generation=case when chat is distinct from l.current_chat_id then generation+1 else generation end,updated_at=now() where owner_id=p.id;
 insert into voltmaster_private.telegram_updates(update_id,telegram_user_id,owner_id,chat_id,mode,generation,payload)
 values(p_update_id,p_telegram,p.id,chat,m,case when chat is distinct from l.current_chat_id then l.generation+1 else l.generation end,p_payload)
 on conflict(update_id) do nothing;
 return jsonb_build_object('accepted',true,'duplicate',not found,'owner_id',p.id,'chat_id',chat,'mode',m);
end $fn$;
revoke all on function voltmaster_private.telegram_enqueue(bigint,bigint,jsonb,text) from public,anon,authenticated;
grant execute on function voltmaster_private.telegram_enqueue(bigint,bigint,jsonb,text) to service_role;

create or replace function voltmaster_private.telegram_claim() returns jsonb language plpgsql security definer set search_path='' as $fn$
declare u voltmaster_private.telegram_updates;
begin
 select * into u from voltmaster_private.telegram_updates q where (q.status='pending' and q.available_at<=now() or q.status='processing' and q.lease_until<now())
 and not exists(select 1 from voltmaster_private.telegram_updates prior where prior.telegram_user_id=q.telegram_user_id and prior.update_id<q.update_id and prior.status in ('pending','processing'))
 order by q.update_id for update skip locked limit 1;
 if not found then return null;end if;
 update voltmaster_private.telegram_updates set status='processing',attempts=attempts+1,lease_until=now()+interval '90 seconds' where update_id=u.update_id;
 return to_jsonb(u);
end $fn$;
revoke all on function voltmaster_private.telegram_claim() from public,anon,authenticated;
grant execute on function voltmaster_private.telegram_claim() to service_role;

create or replace function voltmaster_private.telegram_finish(p_update bigint,p_result jsonb,p_answer jsonb,p_retry_seconds integer default null) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare u voltmaster_private.telegram_updates;
begin
 select * into u from voltmaster_private.telegram_updates where update_id=p_update for update;
 if not found then raise exception 'Update not found';end if;
 if p_retry_seconds is not null and u.attempts<4 then
  update voltmaster_private.telegram_updates set status='pending',available_at=now()+make_interval(secs=>greatest(1,least(p_retry_seconds,3600))),lease_until=null,result=p_result where update_id=p_update;
  return jsonb_build_object('status','pending');
 end if;
 update voltmaster_private.telegram_updates set status=case when p_retry_seconds is null then 'completed' else 'failed' end,result=p_result,completed_at=now(),lease_until=null where update_id=p_update;
 if p_answer is not null then insert into voltmaster_private.telegram_outbox(update_id,telegram_user_id,body) values(p_update,u.telegram_user_id,p_answer) on conflict(update_id) do nothing;end if;
 return jsonb_build_object('status',case when p_retry_seconds is null then 'completed' else 'failed' end);
end $fn$;
revoke all on function voltmaster_private.telegram_finish(bigint,jsonb,jsonb,integer) from public,anon,authenticated;
grant execute on function voltmaster_private.telegram_finish(bigint,jsonb,jsonb,integer) to service_role;

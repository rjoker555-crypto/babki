create table public.agent_conversations (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
 title text not null default 'Новый чат' check(length(title) between 1 and 100),
 created_at timestamptz not null default now(), last_message_at timestamptz not null default now(), unique(id,owner_id)
);
alter table public.agent_conversations enable row level security;
revoke all on public.agent_conversations from public,anon,authenticated;
grant select on public.agent_conversations to authenticated;
grant insert(id,owner_id,title) on public.agent_conversations to authenticated;
grant all on public.agent_conversations to service_role;
create policy conversation_own_read on public.agent_conversations for select to authenticated using(owner_id=(select auth.uid()) and last_message_at+interval '14 days'>now() and exists(select 1 from public.profiles where id=(select auth.uid()) and is_active));
create policy conversation_own_insert on public.agent_conversations for insert to authenticated with check(owner_id=(select auth.uid()) and exists(select 1 from public.profiles where id=(select auth.uid()) and is_active));
insert into public.agent_conversations(owner_id,title,last_message_at) select owner_id,'Первый чат',max(created_at) from public.agent_chat_messages group by owner_id;
alter table public.agent_chat_messages add column chat_id uuid, add column source text not null default 'text' check(source in ('text','voice'));
update public.agent_chat_messages m set chat_id=c.id from public.agent_conversations c where c.owner_id=m.owner_id;
alter table public.agent_chat_messages alter column chat_id set not null;
alter table public.agent_chat_messages add constraint messages_chat_owner_fk foreign key(chat_id,owner_id) references public.agent_conversations(id,owner_id) on delete cascade;
alter table public.agent_request_runs drop constraint agent_request_runs_message_id_fkey;
alter table public.agent_action_plans add column chat_id uuid references public.agent_conversations(id) on delete set null;
update public.agent_action_plans p set chat_id=c.id from public.agent_conversations c where c.owner_id=p.owner_id;
create index agent_messages_chat_time on public.agent_chat_messages(chat_id,created_at desc,id desc);
create index agent_conversations_owner_time on public.agent_conversations(owner_id,last_message_at desc);
revoke insert on public.agent_chat_messages from authenticated;
grant insert(id,owner_id,chat_id,kind,content,source) on public.agent_chat_messages to authenticated;
drop policy chat_read_own on public.agent_chat_messages;
drop policy chat_insert_own_user on public.agent_chat_messages;
create policy chat_read_own on public.agent_chat_messages for select to authenticated using(owner_id=(select auth.uid()) and exists(select 1 from public.agent_conversations c where c.id=chat_id and c.owner_id=(select auth.uid())));
create policy chat_insert_own_user on public.agent_chat_messages for insert to authenticated with check(owner_id=(select auth.uid()) and kind='user' and exists(select 1 from public.agent_conversations c where c.id=chat_id and c.owner_id=(select auth.uid())));
create function agent_private.touch_conversation() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public.agent_conversations set last_message_at=greatest(last_message_at,NEW.created_at),title=case when title='Новый чат' and NEW.kind='user' then left(NEW.content,70) else title end where id=NEW.chat_id and owner_id=NEW.owner_id;
 return NEW;
end $$;
revoke all on function agent_private.touch_conversation() from public,anon,authenticated;
create trigger agent_touch_conversation after insert on public.agent_chat_messages for each row execute function agent_private.touch_conversation();

create table public.agent_protocol_entries (
 id uuid primary key default gen_random_uuid(), actor_id uuid, actor_name text not null,
 entry_type text not null check(entry_type in ('instruction','action')), summary text not null,
 financial boolean not null default false, plan_id uuid, created_at timestamptz not null default now()
);
alter table public.agent_protocol_entries enable row level security;
revoke all on public.agent_protocol_entries from public,anon,authenticated;
grant select on public.agent_protocol_entries to authenticated;
grant all on public.agent_protocol_entries to service_role;
create policy protocol_visible_roles on public.agent_protocol_entries for select to authenticated using(created_at+interval '1 month'>now() and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_active and (p.role in ('director','finance','accountant') or (not financial and p.role in ('manager','foreman')))));
drop policy activity_visible_roles on public.agent_activity_events;
create policy activity_visible_roles on public.agent_activity_events for select to authenticated using(created_at+interval '1 month'>now() and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_active and (p.role in ('director','finance','accountant') or (not financial and p.role in ('manager','foreman')))));
create function agent_private.log_plan() returns trigger language plpgsql security definer set search_path='' as $$
declare actor text; description text;
begin
 if NEW.action='read' then return NEW; end if;
 if TG_OP='UPDATE' and (NEW.status is not distinct from OLD.status or NEW.status not in ('completed','cancelled')) then return NEW; end if;
 select full_name into actor from public.profiles where id=NEW.owner_id;
 description:=case when TG_OP='INSERT' then 'Поручение: ' when NEW.status='cancelled' then 'Отменено: ' else 'Выполнено: ' end||NEW.action||' · '||NEW.table_name||case when NEW.row_id is not null then ' · запись '||NEW.row_id::text else '' end||' · значения '||NEW.values_json::text;
 insert into public.agent_protocol_entries(actor_id,actor_name,entry_type,summary,financial,plan_id) values(NEW.owner_id,coalesce(actor,'Пользователь'),case when TG_OP='INSERT' then 'instruction' else 'action' end,description,NEW.table_name in ('operations','receivables','payables','org_employees','org_expenses','creditors','project_price_history','commercial_proposals','project_materials','project_other_expenses'),NEW.id);
 return NEW;
end $$;
revoke all on function agent_private.log_plan() from public,anon,authenticated;
create trigger agent_log_plan after insert or update on public.agent_action_plans for each row execute function agent_private.log_plan();

create table public.agent_voice_runs(id uuid primary key,owner_id uuid not null references auth.users(id),created_at timestamptz not null default now());
alter table public.agent_voice_runs enable row level security;
revoke all on public.agent_voice_runs from public,anon,authenticated;
grant all on public.agent_voice_runs to service_role;
create function public.agent_reserve_voice(p_id uuid,p_owner uuid) returns boolean language plpgsql security invoker set search_path='' as $$
begin
 perform pg_advisory_xact_lock(73198422);
 if exists(select 1 from public.agent_voice_runs where id=p_id) or (select count(*) from public.agent_voice_runs where created_at>=date_trunc('month',now()))>=300 or (select count(*) from public.agent_voice_runs where owner_id=p_owner and created_at>=date_trunc('day',now()))>=20 or exists(select 1 from public.agent_voice_runs where owner_id=p_owner and created_at>now()-interval '10 seconds') then return false; end if;
 insert into public.agent_voice_runs(id,owner_id) values(p_id,p_owner);return true;
end $$;
revoke all on function public.agent_reserve_voice(uuid,uuid) from public,anon,authenticated;
grant execute on function public.agent_reserve_voice(uuid,uuid) to service_role;

create function agent_private.prune_chat_data() returns void language plpgsql security definer set search_path='' as $$
begin
 delete from public.agent_conversations where last_message_at+interval '14 days'<=now();
 delete from public.agent_activity_events where created_at+interval '1 month'<=now();
 delete from public.agent_protocol_entries where created_at+interval '1 month'<=now();
 delete from public.agent_action_plans where created_at+interval '1 month'<=now();
 delete from public.agent_request_runs where created_at<date_trunc('month',now())-interval '1 month';
 delete from public.agent_voice_runs where created_at<date_trunc('month',now())-interval '1 month';
end $$;
revoke all on function agent_private.prune_chat_data() from public,anon,authenticated;
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('agent-retention-cleanup','17 * * * *','select agent_private.prune_chat_data()');

create or replace function public.agent_execute_plan(p_plan uuid,p_owner uuid,p_confirmation uuid,p_cancel boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare p public.agent_action_plans; c record; current_row jsonb; result jsonb; cols text; vals text; sets text; predicate text:='true';
begin
 if not exists(select 1 from public.agent_director_access a join public.profiles u on u.id=a.user_id where a.user_id=p_owner and u.role='director' and u.is_active) then raise exception 'Director access denied'; end if;
 select * into p from public.agent_action_plans where id=p_plan and owner_id=p_owner for update;
 if not found then raise exception 'Plan not found'; end if;
 if not exists(select 1 from public.agent_chat_messages where id=p_confirmation and owner_id=p_owner and chat_id=p.chat_id and kind='user' and content=(case when p_cancel then 'ОТМЕНЯЮ ' else 'ПОДТВЕРЖДАЮ ' end)||p_plan::text) then raise exception 'Exact chat confirmation required'; end if;
 if p.status<>'pending' then return jsonb_build_object('status',p.status,'result',p.result_json); end if;
 if p.expires_at<now() then raise exception 'Plan expired'; end if;
 if p_cancel then update public.agent_action_plans set status='cancelled' where id=p.id; return jsonb_build_object('status','cancelled'); end if;
 if p.table_name not in ('profiles','projects','operations','receivables','payables','events','project_subcontractors','subcontractors','project_materials','project_other_expenses','creditors','org_employees','org_expenses','pto_documents','project_customer_contacts','work_catalog','material_catalog','work_catalog_materials','project_work_items','project_work_materials','project_work_progress','project_work_sections','project_work_tasks','work_material_options','project_documents','project_document_versions','project_price_history','commercial_proposals','project_work_section_templates','project_work_section_template_items','project_work_section_template_materials','work_volume_submissions','work_volume_submission_items') then raise exception 'Table not allowed'; end if;
 if jsonb_typeof(p.values_json)<>'object' or jsonb_typeof(p.filters_json)<>'object' then raise exception 'Invalid fields'; end if;
 for c in select key from jsonb_object_keys(p.values_json || p.filters_json) key loop
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name=p.table_name and column_name=c.key) then raise exception 'Unknown field'; end if;
 end loop;
 if p.action='read' then
  for c in select key from jsonb_object_keys(p.filters_json) key loop
   predicate:=predicate||format(' AND to_jsonb(t)->%L = $1->%L',c.key,c.key);
  end loop;
  execute format('select coalesce(jsonb_agg(row),''[]''::jsonb) from (select to_jsonb(t) row from public.%I t where %s order by id limit 30) s',p.table_name,predicate) into result using p.filters_json;
 else
  if p.table_name='profiles' then raise exception 'Account management requires a dedicated tool'; end if;
  if p.values_json ?| array['id','created_at','created_by','uploaded_by','updated_at'] then raise exception 'System fields cannot be supplied'; end if;
  perform set_config('request.jwt.claim.sub',p_owner::text,true);
  if p.action in ('update','delete') then
   execute format('select to_jsonb(t) from public.%I t where id=$1 for update',p.table_name) into current_row using p.row_id;
   if current_row is null or current_row is distinct from p.before_json then raise exception 'Record changed; create a new approval'; end if;
  end if;
  select string_agg(format('%I',key),','), string_agg(format('r.%I',key),','),string_agg(format('%I=r.%I',key,key),',') into cols,vals,sets from jsonb_object_keys(p.values_json) key;
  if p.action in ('insert','update') and cols is null then raise exception 'Empty values'; end if;
  if p.action='insert' then
   -- Only supplied columns are inserted, so database defaults remain effective.
   if exists(select 1 from information_schema.columns where table_schema='public' and table_name=p.table_name and column_name='created_by') then
    p.values_json:=p.values_json||jsonb_build_object('created_by',p_owner);cols:=cols||',created_by';vals:=vals||',r.created_by';
   end if;
   execute format('with x as (insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I,$1) r returning *) select to_jsonb(x) from x',p.table_name,cols,vals,p.table_name) into result using p.values_json;
  elsif p.action='update' then
   execute format('with x as (update public.%I t set %s from jsonb_populate_record(null::public.%I,$1) r where t.id=$2 returning t.*) select to_jsonb(x) from x',p.table_name,sets,p.table_name) into result using p.values_json,p.row_id;
  elsif p.action='delete' then
   -- Do not silently cascade deletes into records not included in the approval.
   for c in select n.nspname as ns,t.relname as tbl,a.attname as col from pg_catalog.pg_constraint fk join pg_catalog.pg_class t on t.oid=fk.conrelid join pg_catalog.pg_namespace n on n.oid=t.relnamespace join pg_catalog.pg_attribute a on a.attrelid=fk.conrelid and a.attnum=fk.conkey[1] where fk.contype='f' and fk.confrelid=pg_catalog.to_regclass('public.'||p.table_name) and cardinality(fk.conkey)=1 loop
    execute format('select to_jsonb(t) from %I.%I t where %I=$1 limit 1',c.ns,c.tbl,c.col) into current_row using p.row_id;
    if current_row is not null then raise exception 'Dependent records require separate approvals'; end if;
   end loop;
   execute format('with x as (delete from public.%I where id=$1 returning *) select to_jsonb(x) from x',p.table_name) into result using p.row_id;
  end if;
 end if;
 update public.agent_action_plans set status='completed',result_json=result where id=p.id;
 return jsonb_build_object('status','completed','result',result);
end $$;

create or replace function public.agent_reserve_request(p_message uuid,p_owner uuid) returns text
language plpgsql security invoker set search_path='' as $$
declare existing text;
begin
 perform pg_advisory_xact_lock(73198421);
 select status into existing from public.agent_request_runs where message_id=p_message;
 if existing is not null then return existing; end if;
 if exists(select 1 from public.agent_request_runs where owner_id=p_owner and status='pending' and created_at > now()-interval '300 seconds') then return 'pending'; end if;
 if not exists(select 1 from public.agent_chat_messages where id=p_message and owner_id=p_owner and kind='user') then return 'invalid'; end if;
 if (select count(*) from public.agent_request_runs where created_at >= date_trunc('month',now())) >= 1500 then return 'monthly_limit'; end if;
 if (select count(*) from public.agent_request_runs where owner_id=p_owner and created_at >= date_trunc('day',now())) >= 60 then return 'daily_limit'; end if;
 if exists(select 1 from public.agent_request_runs where owner_id=p_owner and created_at > now()-interval '10 seconds') then return 'rate_limit'; end if;
 insert into public.agent_request_runs(message_id,owner_id) values(p_message,p_owner);
 return 'reserved';
end $$;

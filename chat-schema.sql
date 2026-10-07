-- Additive schema: private messages and minimal activity records. No historical backfill.
create table public.agent_chat_messages (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check (kind in ('user','assistant')),
 content text not null check (length(btrim(content)) between 1 and 8000),
 created_at timestamptz not null default now()
);
create index agent_chat_messages_owner_time on public.agent_chat_messages(owner_id,created_at desc,id desc);
alter table public.agent_chat_messages enable row level security;
revoke all on public.agent_chat_messages from anon,authenticated;
grant select,insert on public.agent_chat_messages to authenticated;
grant all on public.agent_chat_messages to service_role;
create policy chat_read_own on public.agent_chat_messages for select to authenticated
 using (owner_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_active));
create policy chat_insert_own_user on public.agent_chat_messages for insert to authenticated
 with check (owner_id=(select auth.uid()) and kind='user' and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_active));

create table public.agent_activity_events (
 id uuid primary key default gen_random_uuid(),
 project_id uuid,
 project_name text,
 actor_id uuid,
 actor_name text not null,
 entity_table text not null,
 entity_id uuid,
 summary text not null,
 financial boolean not null default false,
 created_at timestamptz not null default now()
);
create index agent_activity_events_time on public.agent_activity_events(created_at desc,id desc);
alter table public.agent_activity_events enable row level security;
revoke all on public.agent_activity_events from anon,authenticated;
grant select on public.agent_activity_events to authenticated;
grant all on public.agent_activity_events to service_role;
create policy activity_visible_roles on public.agent_activity_events for select to authenticated
 using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_active
 and (p.role in ('director','finance','accountant') or (not financial and p.role in ('manager','foreman')))));

-- Trigger needs privileges to append an event; it has no callable public RPC endpoint.
create schema if not exists agent_private;
revoke all on schema agent_private from public,anon,authenticated;
create function agent_private.capture_activity() returns trigger language plpgsql security definer set search_path='' as $$
declare r jsonb; project uuid; project_title text; actor text; label text; verb text;
begin
 if TG_OP='UPDATE' and to_jsonb(NEW)=to_jsonb(OLD) then return NEW; end if;
 if TG_OP='DELETE' then r=to_jsonb(OLD); else r=to_jsonb(NEW); end if;
 project=case when TG_TABLE_NAME='projects' then (r->>'id')::uuid else (r->>'project_id')::uuid end;
 if project is null then return null; end if;
 select p.name into project_title from public.projects p where p.id=project;
 if TG_TABLE_NAME='projects' then project_title=r->>'name'; end if;
 select p.full_name into actor from public.profiles p where p.id=auth.uid();
 actor=coalesce(nullif(actor,''),case when auth.uid() is null then 'Системный процесс' else 'Пользователь' end);
 label=case TG_TABLE_NAME when 'projects' then 'карточка объекта' when 'subcontractors' then 'субподрядчик'
 when 'operations' then 'финансовая операция' when 'receivables' then 'дебиторка' when 'payables' then 'кредиторка'
 when 'project_materials' then 'позиция материалов' when 'project_other_expenses' then 'позиция расходов'
 when 'project_documents' then 'документ' when 'pto_documents' then 'документ ПТО'
 when 'project_work_items' then 'работа' when 'project_work_progress' then 'факт выполнения'
 when 'project_work_sections' then 'раздел работ' when 'project_work_tasks' then 'задача'
 when 'work_volume_submissions' then 'подача объёмов' else 'запись' end;
 verb=case TG_OP when 'INSERT' then 'Добавлена запись' when 'UPDATE' then 'Изменена запись' else 'Удалена запись' end;
 insert into public.agent_activity_events(project_id,project_name,actor_id,actor_name,entity_table,entity_id,summary,financial)
 values(project,project_title,auth.uid(),actor,TG_TABLE_NAME,(r->>'id')::uuid,verb||': '||label,
 TG_TABLE_NAME in ('operations','receivables','payables','project_materials','project_other_expenses'));
 return null;
end $$;
revoke all on function agent_private.capture_activity() from public,anon,authenticated;
do $$ declare t text; begin
 foreach t in array array['projects','subcontractors','operations','receivables','payables','project_materials','project_other_expenses','project_documents','pto_documents','project_work_items','project_work_progress','project_work_sections','project_work_tasks','work_volume_submissions'] loop
 execute format('create trigger agent_capture_activity after insert or update or delete on public.%I for each row execute function agent_private.capture_activity()',t);
 end loop;
end $$;

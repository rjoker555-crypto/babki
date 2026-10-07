create or replace function public.telegram_create_callback(p_owner uuid,p_telegram bigint,p_generation integer,p_action text,p_plan uuid default null,p_revision text default null,p_project uuid default null) returns uuid language plpgsql security definer set search_path='' as $fn$
declare l voltmaster_private.telegram_links; callback_id uuid;
begin
 if auth.role()<>'service_role' then raise exception 'Service only';end if;
 select * into l from voltmaster_private.telegram_links where owner_id=p_owner and telegram_user_id=p_telegram and generation=p_generation;
 if not found or p_action not in ('confirm','cancel','project','finish','review') then raise exception 'Telegram link changed';end if;
 if p_action in ('confirm','cancel') and (p_plan is null or p_revision is null) then raise exception 'Plan identity required';end if;
 if p_action='project' and p_project is null then raise exception 'Project required';end if;
 insert into voltmaster_private.telegram_callbacks(owner_id,telegram_user_id,chat_id,generation,action,plan_id,plan_revision,project_id)
 values(p_owner,p_telegram,l.current_chat_id,p_generation,p_action,p_plan,p_revision,p_project) returning id into callback_id;
 return callback_id;
end $fn$;
revoke all on function public.telegram_create_callback(uuid,bigint,integer,text,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.telegram_create_callback(uuid,bigint,integer,text,uuid,text,uuid) to service_role;

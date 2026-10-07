create or replace function public.telegram_verify_update(p_update_id bigint,p_owner uuid,p_chat uuid,p_mode text,p_message uuid) returns boolean language sql security definer set search_path='' as $fn$
 select auth.role()='service_role'
 and exists(select 1 from voltmaster_private.telegram_updates u join voltmaster_private.telegram_links l on l.owner_id=u.owner_id and l.telegram_user_id=u.telegram_user_id join public.profiles p on p.id=u.owner_id
 where u.update_id=p_update_id and u.owner_id=p_owner and u.chat_id=p_chat and u.mode=p_mode and u.status='processing' and p.role='director' and p.is_active and exists(select 1 from public.agent_director_access where user_id=p.id))
 and exists(select 1 from public.agent_chat_messages m where m.id=p_message and m.owner_id=p_owner and m.chat_id=p_chat and m.kind='user' and m.source='telegram')
$fn$;
revoke all on function public.telegram_verify_update(bigint,uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.telegram_verify_update(bigint,uuid,uuid,text,uuid) to service_role;

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
 update voltmaster_private.telegram_links set selected_project_id=p_project,updated_at=now() where owner_id=p_owner;
 return true;
end $fn$;
revoke all on function voltmaster_private.telegram_choose_project(uuid,bigint,uuid,integer) from public,anon,authenticated;
grant execute on function voltmaster_private.telegram_choose_project(uuid,bigint,uuid,integer) to service_role;

create or replace function voltmaster_private.telegram_claim() returns jsonb language plpgsql security definer set search_path='' as $fn$
declare u voltmaster_private.telegram_updates;
begin
 select * into u from voltmaster_private.telegram_updates q where (q.status='pending' and q.available_at<=now() or q.status='processing' and q.lease_until<now())
 and not exists(select 1 from voltmaster_private.telegram_updates prior where prior.telegram_user_id=q.telegram_user_id and prior.update_id<q.update_id and prior.status in ('pending','processing'))
 order by q.update_id for update skip locked limit 1;
 if not found then return null;end if;
 update voltmaster_private.telegram_updates set status='processing',attempts=attempts+1,lease_until=now()+interval '10 minutes' where update_id=u.update_id;
 return to_jsonb(u);
end $fn$;
revoke all on function voltmaster_private.telegram_claim() from public,anon,authenticated;
grant execute on function voltmaster_private.telegram_claim() to service_role;

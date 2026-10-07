alter table voltmaster_private.telegram_updates add column if not exists transport_answer_id uuid references public.agent_chat_messages(id) on delete set null;
create or replace function public.telegram_save_transport_answer(p_update bigint,p_owner uuid,p_chat uuid,p_content text) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare u voltmaster_private.telegram_updates;msg public.agent_chat_messages;
begin
 if auth.role()<>'service_role' then raise exception 'Service only';end if;
 select * into u from voltmaster_private.telegram_updates where update_id=p_update for update;
 if not found or u.owner_id is distinct from p_owner or u.chat_id is distinct from p_chat or u.status<>'processing' then raise exception 'Telegram update scope changed';end if;
 if u.transport_answer_id is not null then return to_jsonb((select m from public.agent_chat_messages m where m.id=u.transport_answer_id));end if;
 if not exists(select 1 from voltmaster_private.telegram_message_context where telegram_update_id=p_update) then raise exception 'Incoming message missing';end if;
 if length(trim(p_content))<1 then raise exception 'Empty Telegram answer';end if;
 insert into public.agent_chat_messages(owner_id,chat_id,kind,source,content) values(p_owner,p_chat,'assistant','telegram',left(p_content,8000)) returning * into msg;
 update voltmaster_private.telegram_updates set transport_answer_id=msg.id where update_id=p_update;
 return to_jsonb(msg);
end $fn$;
revoke all on function public.telegram_save_transport_answer(bigint,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.telegram_save_transport_answer(bigint,uuid,uuid,text) to service_role;

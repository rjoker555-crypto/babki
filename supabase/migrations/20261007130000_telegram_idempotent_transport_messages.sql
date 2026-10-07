create or replace function public.telegram_save_incoming(p_update bigint,p_owner uuid,p_chat uuid,p_mode text,p_kind text,p_content text) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare u voltmaster_private.telegram_updates; existing uuid;msg public.agent_chat_messages;
begin
 if auth.role()<>'service_role' then raise exception 'Service only';end if;
 select * into u from voltmaster_private.telegram_updates where update_id=p_update for update;
 if not found or u.owner_id is distinct from p_owner or u.chat_id is distinct from p_chat or u.mode is distinct from p_mode or u.status<>'processing' then raise exception 'Telegram update scope changed';end if;
 select message_id into existing from voltmaster_private.telegram_message_context where telegram_update_id=p_update;
 if existing is not null then return to_jsonb((select m from public.agent_chat_messages m where m.id=existing));end if;
 if p_kind not in ('text','voice','document','callback','system') or length(trim(p_content))<1 or length(p_content)>8000 then raise exception 'Invalid Telegram message';end if;
 insert into public.agent_chat_messages(owner_id,chat_id,kind,source,content) values(p_owner,p_chat,'user','telegram',p_content) returning * into msg;
 insert into voltmaster_private.telegram_message_context(message_id,mode,kind,telegram_update_id) values(msg.id,p_mode,p_kind,p_update);
 return to_jsonb(msg);
end $fn$;
revoke all on function public.telegram_save_incoming(bigint,uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.telegram_save_incoming(bigint,uuid,uuid,text,text,text) to service_role;

create or replace function public.telegram_save_transport_answer(p_update bigint,p_owner uuid,p_chat uuid,p_content text) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare u voltmaster_private.telegram_updates;msg public.agent_chat_messages;existing public.agent_chat_messages;
begin
 if auth.role()<>'service_role' then raise exception 'Service only';end if;
 select * into u from voltmaster_private.telegram_updates where update_id=p_update for update;
 if not found or u.owner_id is distinct from p_owner or u.chat_id is distinct from p_chat or u.status<>'processing' then raise exception 'Telegram update scope changed';end if;
 select m.* into existing from public.agent_chat_messages m join voltmaster_private.telegram_message_context c on c.message_id=m.id where c.telegram_update_id=p_update;
 if not found then raise exception 'Incoming message missing';end if;
 -- A model response is written by main-agent and returned to the worker. This
 -- function is used only for transport-only menu, status, and document receipts.
 if length(trim(p_content))<1 then raise exception 'Empty Telegram answer';end if;
 insert into public.agent_chat_messages(owner_id,chat_id,kind,source,content) values(p_owner,p_chat,'assistant','telegram',left(p_content,8000)) returning * into msg;
 return to_jsonb(msg);
end $fn$;
revoke all on function public.telegram_save_transport_answer(bigint,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.telegram_save_transport_answer(bigint,uuid,uuid,text) to service_role;

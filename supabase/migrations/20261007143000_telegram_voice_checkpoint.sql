alter table voltmaster_private.telegram_updates add column if not exists transcript text;
create or replace function public.telegram_store_transcript(p_update bigint,p_owner uuid,p_text text) returns boolean language plpgsql security definer set search_path='' as $fn$
begin
 if auth.role()<>'service_role' or length(trim(p_text))<1 or length(p_text)>7800 then raise exception 'Invalid transcript';end if;
 update voltmaster_private.telegram_updates set transcript=p_text where update_id=p_update and owner_id=p_owner and status='processing' and (transcript is null or transcript=p_text);
 return found;
end $fn$;
revoke all on function public.telegram_store_transcript(bigint,uuid,text) from public,anon,authenticated;
grant execute on function public.telegram_store_transcript(bigint,uuid,text) to service_role;

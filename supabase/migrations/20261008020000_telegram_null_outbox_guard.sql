create or replace function voltmaster_private.telegram_finish(
  p_update bigint,
  p_result jsonb,
  p_answer jsonb,
  p_retry_seconds integer default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  u voltmaster_private.telegram_updates;
begin
  select * into u from voltmaster_private.telegram_updates where update_id=p_update for update;
  if not found then raise exception 'Update not found';end if;
  if p_retry_seconds is not null and u.attempts<4 then
    update voltmaster_private.telegram_updates
       set status='pending',available_at=now()+make_interval(secs=>greatest(1,least(p_retry_seconds,3600))),lease_until=null,result=p_result
     where update_id=p_update;
    return jsonb_build_object('status','pending');
  end if;
  update voltmaster_private.telegram_updates
     set status=case when p_retry_seconds is null then 'completed' else 'failed' end,
         result=p_result,completed_at=now(),lease_until=null
   where update_id=p_update;
  if p_answer is not null and p_answer <> 'null'::jsonb and jsonb_typeof(p_answer)='object' then
    insert into voltmaster_private.telegram_outbox(update_id,telegram_user_id,body)
    values(p_update,u.telegram_user_id,p_answer)
    on conflict(update_id) do nothing;
  end if;
  return jsonb_build_object('status',case when p_retry_seconds is null then 'completed' else 'failed' end);
end
$fn$;

revoke all on function voltmaster_private.telegram_finish(bigint,jsonb,jsonb,integer) from public,anon,authenticated;
grant execute on function voltmaster_private.telegram_finish(bigint,jsonb,jsonb,integer) to service_role;

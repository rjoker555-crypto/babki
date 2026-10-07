create or replace function public.configure_telegram_worker_cron(
  p_service_role_key text,
  p_internal_secret text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_secret_id uuid;
  v_job_id bigint;
begin
  if p_service_role_key is null or length(p_service_role_key) < 40 or length(p_service_role_key) > 4096 then
    raise exception 'Invalid service credential';
  end if;
  if p_internal_secret is null or length(p_internal_secret) < 24 or length(p_internal_secret) > 1024 then
    raise exception 'Invalid internal credential';
  end if;

  select id into v_secret_id from vault.secrets where name = 'telegram_worker_service_role_key';
  if v_secret_id is null then
    perform vault.create_secret(p_service_role_key, 'telegram_worker_service_role_key', 'VoltMaster Telegram worker server credential');
  else
    perform vault.update_secret(v_secret_id, p_service_role_key, 'telegram_worker_service_role_key', 'VoltMaster Telegram worker server credential');
  end if;

  v_secret_id := null;
  select id into v_secret_id from vault.secrets where name = 'telegram_worker_internal_secret';
  if v_secret_id is null then
    perform vault.create_secret(p_internal_secret, 'telegram_worker_internal_secret', 'VoltMaster Telegram worker internal credential');
  else
    perform vault.update_secret(v_secret_id, p_internal_secret, 'telegram_worker_internal_secret', 'VoltMaster Telegram worker internal credential');
  end if;

  select cron.schedule(
    'voltmaster-telegram-worker',
    '* * * * *',
    $job$
    select net.http_post(
      url := 'https://tkoxgvftneoereukiomr.supabase.co/functions/v1/telegram-worker',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'telegram_worker_service_role_key'),
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'telegram_worker_service_role_key'),
        'X-Voltmaster-Internal', (select decrypted_secret from vault.decrypted_secrets where name = 'telegram_worker_internal_secret')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 20000
    );
    $job$
  ) into v_job_id;

  return jsonb_build_object('ok', true, 'job_id', v_job_id, 'schedule', '* * * * *');
end;
$function$;

revoke all on function public.configure_telegram_worker_cron(text, text) from public, anon, authenticated;
grant execute on function public.configure_telegram_worker_cron(text, text) to service_role;

comment on function public.configure_telegram_worker_cron(text, text) is
  'Stores Telegram worker credentials in Vault and upserts the minute worker job. Service role only.';

-- Резервной ручной способ. В обычном запуске директор нажимает «Настроить очередь»:
-- telegram-admin безопасно переносит серверные secrets в Vault и создаёт это расписание.
-- Значения секретов здесь не записываются. В Dashboard Cron проверить успешные вызовы.
select cron.schedule(
  'voltmaster-telegram-worker',
  '* * * * *',
  $job$
  select net.http_post(
    url := 'https://tkoxgvftneoereukiomr.supabase.co/functions/v1/telegram-worker',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', (select decrypted_secret from vault.decrypted_secrets where name='telegram_worker_service_role_key'),
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name='telegram_worker_service_role_key'),
      'X-Voltmaster-Internal', (select decrypted_secret from vault.decrypted_secrets where name='telegram_worker_internal_secret')
    ),
    body := '{}'::jsonb
  );
  $job$
);

-- Остановка периодических вызовов: select cron.unschedule('voltmaster-telegram-worker');

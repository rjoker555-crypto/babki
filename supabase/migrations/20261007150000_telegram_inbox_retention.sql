-- Keep submission receipts after the agent chat's independent retention expires.
alter table voltmaster_private.telegram_submissions drop constraint if exists telegram_submissions_chat_id_fkey;
alter table voltmaster_private.telegram_submissions alter column chat_id drop not null;
alter table voltmaster_private.telegram_submissions add constraint telegram_submissions_chat_id_fkey foreign key(chat_id) references public.agent_conversations(id) on delete set null;
alter table voltmaster_private.telegram_submission_files add column if not exists cleaned_at timestamptz;

create or replace function public.telegram_cleanup_candidates(p_limit integer default 20) returns jsonb language sql security definer set search_path='' as $fn$
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'storage_path',storage_path)),'[]'::jsonb)
 from (
  select f.id,f.storage_path
  from voltmaster_private.telegram_submission_files f
  join voltmaster_private.telegram_submissions s on s.id=f.submission_id
  where f.cleaned_at is null
    and ((s.status='draft' and s.created_at<now()-interval '7 days')
      or (s.status in ('approved','rejected','cancelled') and coalesce(s.reviewed_at,s.submitted_at,s.created_at)<now()-interval '7 days'))
  order by s.created_at,f.id limit least(greatest(p_limit,1),20)
 ) q;
$fn$;
revoke all on function public.telegram_cleanup_candidates(integer) from public,anon,authenticated;
grant execute on function public.telegram_cleanup_candidates(integer) to service_role;

create or replace function public.telegram_mark_cleaned(p_file uuid) returns void language plpgsql security definer set search_path='' as $fn$
begin
 update voltmaster_private.telegram_submission_files f set cleaned_at=now()
 from voltmaster_private.telegram_submissions s
 where f.id=p_file and s.id=f.submission_id and f.cleaned_at is null
   and ((s.status='draft' and s.created_at<now()-interval '7 days')
     or (s.status in ('approved','rejected','cancelled') and coalesce(s.reviewed_at,s.submitted_at,s.created_at)<now()-interval '7 days'));
end;$fn$;
revoke all on function public.telegram_mark_cleaned(uuid) from public,anon,authenticated;
grant execute on function public.telegram_mark_cleaned(uuid) to service_role;

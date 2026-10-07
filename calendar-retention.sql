-- A calendar month follows the user's Asia/Krasnoyarsk dates, including month ends.
alter policy protocol_visible_roles on public.agent_protocol_entries using(
 ((created_at at time zone 'Asia/Krasnoyarsk')+interval '1 month') at time zone 'Asia/Krasnoyarsk'>now()
 and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_active
 and (actor_id=(select auth.uid()) or p.role in ('director','finance','accountant') or (not financial and p.role in ('manager','foreman')))));
alter policy activity_visible_roles on public.agent_activity_events using(
 ((created_at at time zone 'Asia/Krasnoyarsk')+interval '1 month') at time zone 'Asia/Krasnoyarsk'>now()
 and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_active
 and (p.role in ('director','finance','accountant') or (not financial and p.role in ('manager','foreman')))));
create or replace function agent_private.prune_chat_data() returns void language plpgsql security definer set search_path='' as $$
begin
 delete from public.agent_conversations where last_message_at+interval '14 days'<=now();
 delete from public.agent_activity_events where ((created_at at time zone 'Asia/Krasnoyarsk')+interval '1 month') at time zone 'Asia/Krasnoyarsk'<=now();
 delete from public.agent_protocol_entries where ((created_at at time zone 'Asia/Krasnoyarsk')+interval '1 month') at time zone 'Asia/Krasnoyarsk'<=now();
 delete from public.agent_action_plans where ((created_at at time zone 'Asia/Krasnoyarsk')+interval '1 month') at time zone 'Asia/Krasnoyarsk'<=now();
 delete from public.agent_request_runs where created_at<date_trunc('month',now())-interval '1 month';
 delete from public.agent_voice_runs where created_at<date_trunc('month',now())-interval '1 month';
end $$;

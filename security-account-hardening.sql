create function voltmaster_private.security_trusted_director() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p join public.agent_director_access a on a.user_id=p.id
 where p.id=auth.uid() and p.is_active and p.role='director');
$$;
revoke all on function voltmaster_private.security_trusted_director() from public,anon;
grant execute on function voltmaster_private.security_trusted_director() to authenticated;
create function voltmaster_private.guard_profile_authority() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 -- Maintenance/service operations remain server-side; no client can select these DB roles.
 if current_user in ('postgres','service_role','supabase_admin') then
  if TG_OP='DELETE' then return OLD;else return NEW;end if;
 end if;
 if TG_OP in ('INSERT','DELETE') or (NEW.id,NEW.role,NEW.is_active) is distinct from (OLD.id,OLD.role,OLD.is_active) then
  if not voltmaster_private.security_trusted_director() then raise exception 'Only trusted director may change account authority' using errcode='42501';end if;
 end if;
 if TG_OP='DELETE' then return OLD;else return NEW;end if;
end $$;
revoke all on function voltmaster_private.guard_profile_authority() from public,anon,authenticated;
create trigger security_guard_profile_authority before insert or update or delete on public.profiles
for each row execute function voltmaster_private.guard_profile_authority();

revoke truncate, references, trigger on public.profiles from anon,authenticated;
create policy security_raw_plan_scope on public.agent_protocol_entries as restrictive for select to authenticated
using(plan_id is null or actor_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_active and p.role in ('director','finance','accountant')));


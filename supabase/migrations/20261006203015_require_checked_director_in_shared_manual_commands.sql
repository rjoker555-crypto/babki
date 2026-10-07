alter table public.profiles alter column role set default 'foreman';alter table public.profiles alter column is_active set default false;
create or replace function voltmaster_private.assert_operator_actor(p_owner uuid) returns void language plpgsql set search_path='' as $$ begin if not exists(select 1 from public.profiles where id=p_owner and is_active) then raise exception 'Active account required';end if;if exists(select 1 from public.profiles where id=p_owner and role='director') and not exists(select 1 from public.agent_director_access where user_id=p_owner) then raise exception 'Trusted director required';end if;end $$;revoke all on function voltmaster_private.assert_operator_actor(uuid) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION public.execute_credit_operation(p_request uuid, p_command jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform voltmaster_private.assert_operator_actor(auth.uid()); if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.credit_command(auth.uid(),p_request,p_command,false);end $function$
;
CREATE OR REPLACE FUNCTION public.execute_document_command(p_request uuid, p_command jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform voltmaster_private.assert_operator_actor(auth.uid()); if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.document_command(auth.uid(),p_request,p_command,false);end $function$
;
CREATE OR REPLACE FUNCTION public.execute_financial_operation(p_request uuid, p_command jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform voltmaster_private.assert_operator_actor(auth.uid());
 if auth.uid() is null then raise exception 'Authentication required';end if;
 return voltmaster_private.financial_command(auth.uid(),p_request,p_command,false);
end $function$
;
CREATE OR REPLACE FUNCTION public.execute_obligation_command(p_request uuid, p_command jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform voltmaster_private.assert_operator_actor(auth.uid()); if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.obligation_command(auth.uid(),p_request,p_command,false);end $function$
;
CREATE OR REPLACE FUNCTION public.execute_production_command(p_request uuid, p_command jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform voltmaster_private.assert_operator_actor(auth.uid()); if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.production_command(auth.uid(),p_request,p_command,false);end $function$
;
CREATE OR REPLACE FUNCTION public.execute_project_card(p_request uuid, p_command jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform voltmaster_private.assert_operator_actor(auth.uid()); if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.project_card_command(auth.uid(),p_request,p_command,false);end $function$
;
CREATE OR REPLACE FUNCTION public.execute_project_delete(p_request uuid, p_command jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform voltmaster_private.assert_operator_actor(auth.uid()); if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.project_delete_command(auth.uid(),p_request,p_command,false);end $function$
;
CREATE OR REPLACE FUNCTION public.execute_proposal_command(p_request uuid, p_command jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform voltmaster_private.assert_operator_actor(auth.uid()); if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.proposal_command(auth.uid(),p_request,p_command,false);end $function$
;


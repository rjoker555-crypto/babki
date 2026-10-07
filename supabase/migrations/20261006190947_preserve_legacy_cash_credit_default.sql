CREATE OR REPLACE FUNCTION public.agent_cash_summary(p_owner uuid, p_project uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if not exists(select 1 from public.agent_director_access a join public.profiles p on p.id=a.user_id where a.user_id=p_owner and p.role='director' and p.is_active) then raise exception 'Financial access denied'; end if;
 if not exists(select 1 from public.projects where id=p_project) then raise exception 'Project not found'; end if;
 return (select jsonb_build_object('project_id',p_project,'as_of',now(),'method','cash_operations_v2_manual_dashboard','income',coalesce(sum(amount) filter(where operation_type='income'),0)::text,
  'expense',coalesce(sum(amount) filter(where operation_type='expense' and not(article='ТМЦ' and coalesce(credit_kind,'')='material')),0)::text,'credit',coalesce(sum(amount) filter(where operation_type='credit' and coalesce(credit_kind,'money')='money'),0)::text,
  'operation_count',count(*),'limitations',array['Cash flow is not production profit or recognized revenue.','Margin, VAT and budget comparison require agreed methodology.']) from public.operations where project_id=p_project);
end $function$


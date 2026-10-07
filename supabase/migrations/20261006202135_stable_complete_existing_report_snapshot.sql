-- One stable database snapshot, user JWT/RLS, explicit report semantics and completeness checks.
create or replace function public.get_existing_report_data(p_kind text,p_project uuid default null) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare actor text;result jsonb:='{}';rows jsonb;t text;k text;predicate text;
begin
 select role into actor from public.profiles where id=auth.uid() and is_active;
 if actor is null or p_kind not in ('statement','organization_month','production','proposals','financial_metrics') or p_kind is null or not(actor in ('director','finance','accountant') or actor='manager' and p_kind in ('production','proposals') or actor='foreman' and p_kind='production') then raise exception 'Report access denied';end if;
 -- Director's closed agent allowlist is additionally enforced by the Edge caller/claimer.
 if p_kind in ('statement','production','financial_metrics') and p_project is null then raise exception 'Project required';end if;
 if p_kind='proposals' then
  select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') into rows from (select * from public.commercial_proposals order by id limit 10001) x;
  if jsonb_array_length(rows)>10000 then raise exception 'Too many proposals; incomplete report refused';end if;return jsonb_build_object('proposals',rows);
 end if;
 if actor='foreman' then select coalesce(jsonb_agg(to_jsonb(x)),'[]') into rows from public.foreman_projects() x where id=p_project;
 else select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') into rows from (select * from public.projects where p_kind='organization_month' or id=p_project order by id limit 10001) x;end if;
 if jsonb_array_length(rows)>10000 or p_kind<>'organization_month' and jsonb_array_length(rows)<>1 then raise exception 'Project report access/size denied';end if;result:=jsonb_build_object('projects',rows);
 foreach k in array case when p_kind='production' then array['projectWorkItems','projectWorkProgress','projectWorkMaterials'] when p_kind='financial_metrics' then array['ops','ars','aps','subcontractors','projectMaterials','projectOtherExpenses'] else array['ops','ars','aps','subcontractors','projectMaterials','projectOtherExpenses','ptoDocuments','ptoContacts','projectWorkItems','projectWorkSections','projectWorkProgress','projectPriceHistory']||case when p_kind='organization_month' then array['orgEmployees','orgExpenses','events'] else '{}'::text[] end end loop
  t:=case k when 'ops' then 'operations' when 'ars' then 'receivables' when 'aps' then 'payables' when 'subcontractors' then 'subcontractors' when 'projectMaterials' then 'project_materials' when 'projectOtherExpenses' then 'project_other_expenses' when 'ptoDocuments' then 'pto_documents' when 'ptoContacts' then 'project_customer_contacts' when 'projectWorkItems' then 'project_work_items' when 'projectWorkSections' then 'project_work_sections' when 'projectWorkProgress' then 'project_work_progress' when 'projectWorkMaterials' then 'project_work_materials' when 'projectPriceHistory' then 'project_price_history' when 'orgEmployees' then 'org_employees' when 'orgExpenses' then 'org_expenses' when 'events' then 'events' end;
  predicate:=case when p_kind='organization_month' then 'true' when k in ('projectWorkProgress','projectWorkMaterials') then 'work_item_id in(select id from public.project_work_items where project_id=$1)' else 'project_id=$1' end;
  execute format('select coalesce(jsonb_agg(to_jsonb(x) order by id),''[]'') from (select * from public.%I where %s order by id limit 10001) x',t,predicate) into rows using p_project;
  if jsonb_array_length(rows)>10000 then raise exception 'Too many % rows; incomplete report refused',t;end if;result:=result||jsonb_build_object(k,rows);
 end loop;
 return result;
end $$;
revoke all on function public.get_existing_report_data(text,uuid) from public,anon;grant execute on function public.get_existing_report_data(text,uuid) to authenticated;



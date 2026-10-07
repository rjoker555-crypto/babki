CREATE OR REPLACE FUNCTION public.agent_execute_plan(p_plan uuid, p_owner uuid, p_confirmation uuid, p_cancel boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare p public.agent_action_plans; c record; current_row jsonb; result jsonb; cols text; vals text; sets text; predicate text:='true';
begin
 if not exists(select 1 from public.agent_director_access a join public.profiles u on u.id=a.user_id where a.user_id=p_owner and u.role='director' and u.is_active) then raise exception 'Director access denied'; end if;
 select * into p from public.agent_action_plans where id=p_plan and owner_id=p_owner for update;
 if not found then raise exception 'Plan not found'; end if;
 if not exists(select 1 from public.agent_chat_messages where id=p_confirmation and owner_id=p_owner and chat_id=p.chat_id and kind='user' and content=(case when p_cancel then 'ОТМЕНЯЮ ' else 'ПОДТВЕРЖДАЮ ' end)||p_plan::text) then raise exception 'Exact chat confirmation required'; end if;
 if p.status<>'pending' then return jsonb_build_object('status',p.status,'result',p.result_json); end if;
 if p.expires_at<now() then raise exception 'Plan expired'; end if;
 if p_cancel then update public.agent_action_plans set status='cancelled' where id=p.id; return jsonb_build_object('status','cancelled'); end if;
 if p.table_name not in ('profiles','projects','operations','receivables','payables','events','project_subcontractors','subcontractors','project_materials','project_other_expenses','creditors','org_employees','org_expenses','pto_documents','project_customer_contacts','work_catalog','material_catalog','work_catalog_materials','project_work_items','project_work_materials','project_work_progress','project_work_sections','project_work_tasks','work_material_options','project_documents','project_document_versions','project_price_history','commercial_proposals','project_work_section_templates','project_work_section_template_items','project_work_section_template_materials','work_volume_submissions','work_volume_submission_items') then raise exception 'Table not allowed'; end if;
 if jsonb_typeof(p.values_json)<>'object' or jsonb_typeof(p.filters_json)<>'object' then raise exception 'Invalid fields'; end if;
 for c in select key from jsonb_object_keys(p.values_json || p.filters_json) key loop
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name=p.table_name and column_name=c.key) then raise exception 'Unknown field'; end if;
 end loop;
 if p.action='read' then
  for c in select key from jsonb_object_keys(p.filters_json) key loop
   predicate:=predicate||format(' AND to_jsonb(t)->%L = $1->%L',c.key,c.key);
  end loop;
  execute format('select coalesce(jsonb_agg(row),''[]''::jsonb) from (select to_jsonb(t) row from public.%I t where %s order by id limit 30) s',p.table_name,predicate) into result using p.filters_json;
 else
  if p.table_name='profiles' then raise exception 'Account management requires a dedicated tool'; end if;
  if p.table_name='operations' or p.table_name='projects' and p.action='insert' then raise exception 'Use checked operator command'; end if;
  if p.values_json ?| array['id','created_at','created_by','uploaded_by','updated_at'] then raise exception 'System fields cannot be supplied'; end if;
  perform set_config('request.jwt.claim.sub',p_owner::text,true);
  if p.action in ('update','delete') then
   execute format('select to_jsonb(t) from public.%I t where id=$1 for update',p.table_name) into current_row using p.row_id;
   if current_row is null or current_row is distinct from p.before_json then raise exception 'Record changed; create a new approval'; end if;
  end if;
  select string_agg(format('%I',key),','), string_agg(format('r.%I',key),','),string_agg(format('%I=r.%I',key,key),',') into cols,vals,sets from jsonb_object_keys(p.values_json) key;
  if p.action in ('insert','update') and cols is null then raise exception 'Empty values'; end if;
  if p.action='insert' then
   -- Only supplied columns are inserted, so database defaults remain effective.
   if exists(select 1 from information_schema.columns where table_schema='public' and table_name=p.table_name and column_name='created_by') then
    p.values_json:=p.values_json||jsonb_build_object('created_by',p_owner);cols:=cols||',created_by';vals:=vals||',r.created_by';
   end if;
   execute format('with x as (insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I,$1) r returning *) select to_jsonb(x) from x',p.table_name,cols,vals,p.table_name) into result using p.values_json;
  elsif p.action='update' then
   execute format('with x as (update public.%I t set %s from jsonb_populate_record(null::public.%I,$1) r where t.id=$2 returning t.*) select to_jsonb(x) from x',p.table_name,sets,p.table_name) into result using p.values_json,p.row_id;
  elsif p.action='delete' then
   -- Do not silently cascade deletes into records not included in the approval.
   for c in select n.nspname as ns,t.relname as tbl,a.attname as col from pg_catalog.pg_constraint fk join pg_catalog.pg_class t on t.oid=fk.conrelid join pg_catalog.pg_namespace n on n.oid=t.relnamespace join pg_catalog.pg_attribute a on a.attrelid=fk.conrelid and a.attnum=fk.conkey[1] where fk.contype='f' and fk.confrelid=pg_catalog.to_regclass('public.'||p.table_name) and cardinality(fk.conkey)=1 loop
    execute format('select to_jsonb(t) from %I.%I t where %I=$1 limit 1',c.ns,c.tbl,c.col) into current_row using p.row_id;
    if current_row is not null then raise exception 'Dependent records require separate approvals'; end if;
   end loop;
   execute format('with x as (delete from public.%I where id=$1 returning *) select to_jsonb(x) from x',p.table_name) into result using p.row_id;
  end if;
 end if;
 update public.agent_action_plans set status='completed',result_json=result where id=p.id;
 return jsonb_build_object('status','completed','result',result);
end $function$

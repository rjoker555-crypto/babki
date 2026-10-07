-- Project card and its three cost lists commit together.
create or replace function voltmaster_private.project_card_command(p_owner uuid,p_request uuid,p_command jsonb,p_preview boolean default false)
returns jsonb language plpgsql set search_path='' as $fn$
declare act text:=p_command->>'action'; v jsonb:=p_command->'values'; old public.projects; pr public.projects; pid uuid; result jsonb; stored jsonb; child jsonb; proposal jsonb; child_result jsonb; previews jsonb:='[]'; linked jsonb; cols text; vals text; k text; idx integer:=0; cid uuid; typ text; fields text[];
begin
 if not exists(select 1 from public.profiles where id=p_owner and is_active and role in ('director','finance','accountant')) then raise exception 'Project card access denied';end if;
 if p_request is null or act is null or act not in ('create','update') or jsonb_typeof(p_command)<>'object' or exists(select 1 from jsonb_object_keys(p_command) x where x not in ('action','id','expected','values','cost_changes')) then raise exception 'Invalid project card command';end if;
 if jsonb_typeof(v) is distinct from 'object' or exists(select 1 from jsonb_object_keys(v) x where x not in ('name','contractor_company','customer','contract_number','contract_date','start_date','end_date','planned_revenue','status','comment')) then raise exception 'Unsupported project fields';end if;
 perform pg_advisory_xact_lock(hashtextextended('voltmaster.financial.commands',0));
 if not p_preview then
  select result_json,command_json into result,stored from voltmaster_private.financial_command_receipts where owner_id=p_owner and request_id=p_request;
  if found then if stored is distinct from p_command then raise exception 'Request reused with different command';end if;return result;end if;
 end if;
 if act='update' then
  select * into old from public.projects where id=(p_command->>'id')::uuid for update;
  if not found or to_jsonb(old) is distinct from p_command->'expected' then raise exception 'Record changed; create a new approval';end if;pr:=old;pid:=old.id;
 else
  if p_command ? 'id' or p_command ? 'expected' then raise exception 'Create cannot set identity';end if;
  pr.planned_revenue:=0;pr.status:='active';
 end if;
 pr:=jsonb_populate_record(pr,v);
 if nullif(btrim(pr.name),'') is null or length(pr.name)>500 or pr.contractor_company not in ('ООО','ИП') or pr.contractor_company is null or pr.planned_revenue is null or pr.planned_revenue<0 or pr.planned_revenue::text in ('NaN','Infinity','-Infinity') or pr.planned_revenue<>round(pr.planned_revenue,2) or pr.status not in ('planned','active','completed','closed') or pr.status is null or pr.end_date<pr.start_date then raise exception 'Invalid project card values';end if;
 if exists(select 1 from public.projects where lower(replace(btrim(name),'ё','е'))=lower(replace(btrim(pr.name),'ё','е')) and id is distinct from pid) then raise exception 'Possible duplicate project; inspect existing card';end if;
 if jsonb_typeof(coalesce(p_command->'cost_changes','[]')) is distinct from 'array' or jsonb_array_length(coalesce(p_command->'cost_changes','[]'))>200 then raise exception 'Invalid cost change list';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') into linked from public.operations x where project_id=pid;
 if not p_preview then
  perform set_config('request.jwt.claim.sub',p_owner::text,true);
  select string_agg(format('%I',key),','),string_agg(format('r.%I',key),','),string_agg(format('%I=r.%I',key,key),',') into cols,vals,k from jsonb_object_keys(v) key;
  if act='create' then execute format('insert into public.projects (%s) select %s from jsonb_populate_record(null::public.projects,$1) r returning *',cols,vals) into pr using v;pid:=pr.id;
  elsif v<>'{}' then execute format('update public.projects x set %s from jsonb_populate_record(null::public.projects,$1) r where x.id=$2 returning x.*',k) into pr using v,pid;end if;
 end if;
 for child in select value from jsonb_array_elements(coalesce(p_command->'cost_changes','[]')) loop
  idx:=idx+1;typ:=child->>'kind';
  if typ is null or typ not in ('subcontractor','material','other_expense') or jsonb_typeof(child)<>'object' or child->>'action' is null then raise exception 'Invalid card cost command';end if;
  proposal:=child;
  if child->>'action'<>'delete' then proposal:=jsonb_set(proposal,'{values}',child->'values'||jsonb_build_object('project_id',pid));end if;
  if child->>'action'<>'create' and (child->'expected'->>'project_id')::uuid is distinct from pid then raise exception 'Cost belongs to another project';end if;
  if p_preview and act='create' then
   if child->>'action'<>'create' or child ? 'id' or child ? 'expected' then raise exception 'New card costs must be new';end if;
   fields:=case when typ='subcontractor' then array['name','planned_amount','has_vat','comment'] else array['name','planned_amount','actual_amount','expense_date','comment'] end;
   if jsonb_typeof(child->'values') is distinct from 'object' or nullif(btrim(child->'values'->>'name'),'') is null or exists(select 1 from jsonb_object_keys(child->'values') x where not(x=any(fields))) then raise exception 'Invalid new card cost fields';end if;
   for k in select unnest(array['planned_amount','actual_amount']) loop if child->'values' ? k and ((child->'values'->>k)::numeric is null or (child->'values'->>k)::numeric<0 or (child->'values'->>k)::numeric::text in ('NaN','Infinity','-Infinity')) then raise exception 'Invalid new card cost amount';end if;end loop;
   previews:=previews||jsonb_build_array(child);
  else
   cid:=md5(p_owner::text||p_request::text||'cardcost'||idx)::uuid;
   child_result:=voltmaster_private.obligation_command(p_owner,cid,proposal,p_preview);
   previews:=previews||jsonb_build_array(child_result);
  end if;
 end loop;
 if p_preview then return jsonb_build_object('before',case when old.id is null then null else to_jsonb(old) end,'values',v,'cost_changes',previews,'linked_operations',linked);end if;
 result:=jsonb_build_object('status','completed','action',act,'project',to_jsonb(pr),'cost_changes',previews,'verified',exists(select 1 from public.projects where id=pid));
 insert into voltmaster_private.financial_command_receipts values(p_owner,p_request,p_command,result,now());return result;
end $fn$;
revoke all on function voltmaster_private.project_card_command(uuid,uuid,jsonb,boolean) from public,anon,authenticated;
grant execute on function voltmaster_private.project_card_command(uuid,uuid,jsonb,boolean) to service_role;
create or replace function public.execute_project_card(p_request uuid,p_command jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.project_card_command(auth.uid(),p_request,p_command,false);end $$;
revoke all on function public.execute_project_card(uuid,jsonb) from public,anon;
grant execute on function public.execute_project_card(uuid,jsonb) to authenticated;
alter table public.agent_operator_plans drop constraint if exists agent_operator_plans_kind_check;
alter table public.agent_operator_plans add constraint agent_operator_plans_kind_check check(kind in ('operation_write','project_create','credit_write','obligation_write','project_card_write'));



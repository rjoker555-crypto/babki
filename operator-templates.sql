create or replace function voltmaster_private.production_template_command(p_owner uuid,p_request uuid,p_command jsonb,p_preview boolean default false)
returns jsonb language plpgsql set search_path='' as $$
declare kind text:=p_command->>'kind';v jsonb:=p_command->'values';pid uuid:=(v->>'project_id')::uuid;actor text;t public.project_work_section_templates;ti public.project_work_section_template_items;
 items jsonb;materials jsonb;entry jsonb;work jsonb;works jsonb:='[]';cmd jsonb;snapshot jsonb;result jsonb;stored jsonb;n integer:=0;m jsonb;
begin
 select role into actor from public.profiles where id=p_owner and is_active;
 if actor is null or actor not in ('director','finance','accountant','manager','foreman') then raise exception 'Production access denied';end if;
 if p_request is null or kind not in ('save_template','apply_template') or kind is null or jsonb_typeof(v) is distinct from 'object' or exists(select 1 from jsonb_object_keys(p_command) x where x not in ('kind','values','items','template_id')) then raise exception 'Invalid template command';end if;
 if pid is null or not exists(select 1 from public.projects p where p.id=pid and (actor<>'foreman' or p.responsible_user_id=p_owner or exists(select 1 from public.project_team_members tm where tm.project_id=pid and tm.user_id=p_owner and tm.is_active))) then raise exception 'Project access denied';end if;
 perform pg_advisory_xact_lock(hashtextextended('voltmaster.financial.commands',0));
 select result_json,command_json into result,stored from voltmaster_private.financial_command_receipts where owner_id=p_owner and request_id=p_request;
 if found and not p_preview then if stored is distinct from p_command then raise exception 'Request reused with different command';end if;return result;end if;
 if kind='save_template' then
  if exists(select 1 from jsonb_object_keys(v) x where x not in ('project_id','name','comment')) or p_command ? 'template_id' or nullif(btrim(v->>'name'),'') is null or length(v->>'name')>500 or exists(select 1 from public.project_work_section_templates where project_id=pid and lower(btrim(name))=lower(btrim(v->>'name'))) then raise exception 'Unique template name required';end if;
  items:=p_command->'items';
 else
  if exists(select 1 from jsonb_object_keys(v) x where x not in ('project_id','name','comment','start_date','end_date')) or p_command ? 'items' then raise exception 'Invalid template application';end if;
  select * into t from public.project_work_section_templates where id=(p_command->>'template_id')::uuid and project_id=pid for update;if not found then raise exception 'Template access denied';end if;
  select coalesce(jsonb_agg((to_jsonb(x)-'id'-'template_id'-'sort_order')||jsonb_build_object('materials',coalesce((select jsonb_agg(to_jsonb(mm)-'id'-'template_item_id'-'sort_order' order by sort_order,id) from public.project_work_section_template_materials mm where template_item_id=x.id),'[]')) order by sort_order,id),'[]') into items from public.project_work_section_template_items x where template_id=t.id;
 end if;
 if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items) not between 1 and 200 then raise exception 'Template requires 1 to 200 works';end if;
 for entry in select value from jsonb_array_elements(items) loop
  if jsonb_typeof(entry)<>'object' or exists(select 1 from jsonb_object_keys(entry) x where x not in ('work_catalog_id','work_name','unit','planned_volume','comment','materials')) then raise exception 'Unsupported template item';end if;
  work:=jsonb_build_object('kind','work','action','create','values',entry-'materials','materials',coalesce(entry->'materials','[]'));
  works:=works||jsonb_build_array(work);
 end loop;
 cmd:=jsonb_build_object('kind','section','action','create','values',jsonb_build_object('project_id',pid,'name',coalesce(nullif(v->>'name',''),t.name),'comment',coalesce(v->>'comment',t.comment),'start_date',v->'start_date','end_date',v->'end_date'),'works',works);
 -- Validate the whole chosen composition through the actual manual command, with no writes.
 snapshot:=voltmaster_private.production_command(p_owner,p_request,cmd,true)||jsonb_build_object('command',p_command,'template',case when t.id is null then null else to_jsonb(t) end,'template_items',items);
 if p_preview then return snapshot;end if;
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 if kind='apply_template' then result:=voltmaster_private.production_command(p_owner,gen_random_uuid(),cmd,false);
 else
  insert into public.project_work_section_templates(project_id,name,comment,created_by) values(pid,v->>'name',v->>'comment',p_owner) returning * into t;
  for entry in select value from jsonb_array_elements(items) loop
   insert into public.project_work_section_template_items(template_id,work_catalog_id,work_name,unit,planned_volume,comment,sort_order) values(t.id,(entry->>'work_catalog_id')::uuid,entry->>'work_name',entry->>'unit',(entry->>'planned_volume')::numeric,entry->>'comment',n) returning * into ti;n:=n+1;
   for m in select value from jsonb_array_elements(coalesce(entry->'materials','[]')) loop
    insert into public.project_work_section_template_materials(template_item_id,material_catalog_id,material_name,unit,quantity,comment,material_role,dependency_group,option_group,sort_order) values(ti.id,(m->>'material_catalog_id')::uuid,m->>'material_name',m->>'unit',(m->>'quantity')::numeric,m->>'comment',coalesce(m->>'material_role','secondary'),m->>'dependency_group',m->>'option_group',0);
   end loop;
  end loop;result:=jsonb_build_object('template',to_jsonb(t));
 end if;
 result:=result||jsonb_build_object('status','completed','kind',kind,'verified',true);
 insert into voltmaster_private.financial_command_receipts values(p_owner,p_request,p_command,result,now());return result;
end $$;
revoke all on function voltmaster_private.production_template_command(uuid,uuid,jsonb,boolean) from public,anon,authenticated;

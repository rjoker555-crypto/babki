-- Subject production commands; the existing volume command remains unchanged.
create or replace function voltmaster_private.production_command(p_owner uuid,p_request uuid,p_command jsonb,p_preview boolean default false)
returns jsonb language plpgsql set search_path='' as $fn$
declare kind text:=p_command->>'kind';act text:=p_command->>'action';v jsonb:=coalesce(p_command->'values','{}');
 pid uuid;wid uuid;sid uuid;rid uuid;old jsonb;result jsonb;stored jsonb;snapshot jsonb;actor text;
 w public.project_work_items;s public.project_work_sections;g public.project_work_progress;m public.project_work_materials;cat public.work_catalog;
 item jsonb;child jsonb;amount numeric;baseline numeric;total numeric;k text;allowed text[];
begin
 if kind='foreman_subcontractor' then return voltmaster_private.foreman_subcontractor_command(p_owner,p_request,p_command,p_preview);end if;
 if kind in ('save_template','apply_template') then return voltmaster_private.production_template_command(p_owner,p_request,p_command,p_preview);end if;
 select role into actor from public.profiles where id=p_owner and is_active;
 if actor is null or actor not in ('director','finance','accountant','manager','foreman') then raise exception 'Production access denied';end if;
 if p_request is null or kind not in ('work','section','manual_fact') or kind is null or act not in ('create','update','delete','complete') or act is null or jsonb_typeof(p_command)<>'object' or exists(select 1 from jsonb_object_keys(p_command) x where x not in ('kind','action','id','expected','values','materials','works')) then raise exception 'Invalid production command';end if;
 if jsonb_typeof(v) is distinct from 'object' then raise exception 'Values must be an object';end if;
 perform pg_advisory_xact_lock(hashtextextended('voltmaster.financial.commands',0));
 if not p_preview then
  select result_json,command_json into result,stored from voltmaster_private.financial_command_receipts where owner_id=p_owner and request_id=p_request;
  if found then if stored is distinct from p_command then raise exception 'Request reused with different command';end if;return result;end if;
 end if;
 if kind='work' then
  if act<>'create' then select * into w from public.project_work_items where id=(p_command->>'id')::uuid for update;old:=case when w.id is null then null else to_jsonb(w) end;end if;
  allowed:=array['project_id','section_id','work_catalog_id','work_name','unit','planned_volume','start_date','end_date','status','comment','primary_material_catalog_id'];
  if exists(select 1 from jsonb_object_keys(v) x where not(x=any(allowed))) then raise exception 'Unsupported work fields';end if;
  if act='create' then w.status:='planned';w.completed_volume:=0;w.planned_volume:=0;w.unit:='шт';end if;
  w:=jsonb_populate_record(w,v);pid:=w.project_id;wid:=w.id;
 elsif kind='section' then
  if act<>'create' then select * into s from public.project_work_sections where id=(p_command->>'id')::uuid for update;old:=case when s.id is null then null else to_jsonb(s) end;end if;
  allowed:=array['project_id','name','start_date','end_date','status','comment'];
  if exists(select 1 from jsonb_object_keys(v) x where not(x=any(allowed))) then raise exception 'Unsupported section fields';end if;
  if act='create' then s.status:='planned';end if;s:=jsonb_populate_record(s,v);pid:=s.project_id;sid:=s.id;
 else
  if act='complete' or p_command ? 'materials' or p_command ? 'works' then raise exception 'Invalid manual fact command';end if;
  if act<>'create' then select * into g from public.project_work_progress where id=(p_command->>'id')::uuid for update;old:=case when g.id is null then null else to_jsonb(g) end;end if;
  allowed:=array['work_item_id','progress_date','completed_volume','comment'];
  if exists(select 1 from jsonb_object_keys(v) x where not(x=any(allowed))) then raise exception 'Unsupported fact fields';end if;
  g:=jsonb_populate_record(g,v);wid:=g.work_item_id;
  select * into w from public.project_work_items where id=wid for update;pid:=w.project_id;
  if w.id is null or g.submission_item_id is not null or old is not null and old->>'work_item_id'<>wid::text then raise exception 'Use volume submission command for submitted facts';end if;
 end if;
 if act='create' then if p_command ? 'id' or p_command ? 'expected' then raise exception 'Create cannot set identity';end if;
 elsif old is null or old is distinct from p_command->'expected' then raise exception 'Record changed; create a new approval';end if;
 if act<>'create' and kind in ('work','section') and old->>'project_id' is distinct from pid::text then raise exception 'Project cannot move';end if;
 if pid is null or not exists(select 1 from public.projects p where p.id=pid and (actor<>'foreman' or p.responsible_user_id=p_owner or exists(select 1 from public.project_team_members t where t.project_id=p.id and t.user_id=p_owner and t.is_active))) then raise exception 'Project access denied';end if;
 perform 1 from public.projects where id=pid for update;
 -- Full affected project snapshot includes submitted facts, preventing stale cascade approvals.
 snapshot:=jsonb_build_object('command',p_command,'before',old,'project',(select jsonb_build_object('id',id,'name',name) from public.projects where id=pid),
  'sections',coalesce((select jsonb_agg(to_jsonb(x) order by id) from public.project_work_sections x where project_id=pid),'[]'),
  'works',coalesce((select jsonb_agg(to_jsonb(x) order by id) from public.project_work_items x where project_id=pid),'[]'),
  'materials',coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from public.project_work_materials x join public.project_work_items y on y.id=x.work_item_id where y.project_id=pid),'[]'),
  'progress',coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from public.project_work_progress x join public.project_work_items y on y.id=x.work_item_id where y.project_id=pid),'[]'),
  'submission_items',coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from public.work_volume_submission_items x join public.project_work_items y on y.id=x.work_item_id where y.project_id=pid),'[]'));
 if p_preview then
  begin perform voltmaster_private.production_command(p_owner,p_request,p_command,false);raise exception using errcode='P0993',message='ROLLBACK_PRODUCTION_PREVIEW';exception when sqlstate 'P0993' then null;end;
  return snapshot;
 end if;
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 if kind='work' then
  if act='delete' then
   if v<>'{}' or p_command ? 'materials' or exists(select 1 from public.work_volume_submission_items where work_item_id=wid) then raise exception 'Remove linked volume submissions with their own confirmed command first';end if;
   delete from public.project_work_progress where work_item_id=wid;delete from public.project_work_materials where work_item_id=wid;delete from public.project_work_items where id=wid;
  else
   if w.work_catalog_id is null then raise exception 'Work catalog selection required';end if;
   select * into cat from public.work_catalog where id=w.work_catalog_id;if not found then raise exception 'Work catalog not found';end if;
   if nullif(btrim(w.work_name),'') is null or nullif(btrim(w.unit),'') is null or w.planned_volume is null or w.planned_volume<=0 or w.planned_volume::text in ('NaN','Infinity','-Infinity') or w.start_date>w.end_date or w.status is null or w.status not in ('planned','in_progress','completed') then raise exception 'Invalid work values';end if;
   if w.section_id is not null then select * into s from public.project_work_sections where id=w.section_id and project_id=pid;if not found then raise exception 'Section belongs to another project';end if;w.start_date:=s.start_date;w.end_date:=s.end_date;end if;
   if act='create' then
    insert into public.project_work_items(project_id,section_id,work_catalog_id,work_name,unit,planned_volume,start_date,end_date,status,comment,primary_material_catalog_id,created_by) values(pid,w.section_id,w.work_catalog_id,w.work_name,w.unit,w.planned_volume,w.start_date,w.end_date,'planned',w.comment,w.primary_material_catalog_id,p_owner) returning * into w;wid:=w.id;
   else
    update public.project_work_items set section_id=w.section_id,work_catalog_id=w.work_catalog_id,work_name=w.work_name,unit=w.unit,planned_volume=w.planned_volume,start_date=w.start_date,end_date=w.end_date,status=w.status,comment=w.comment,primary_material_catalog_id=w.primary_material_catalog_id,updated_at=now() where id=wid;
   end if;
   if act='complete' or v->>'status'='completed' or w.status='completed' then
    amount:=greatest(0,w.planned_volume-coalesce(w.completed_volume,0));
    if amount>0 then insert into public.project_work_progress(work_item_id,progress_date,completed_volume,comment,created_by) values(wid,(now() at time zone 'Asia/Krasnoyarsk')::date,amount,'Работа отмечена как завершённая',p_owner);end if;
    update public.project_work_items set completed_volume=greatest(coalesce(w.completed_volume,0),w.planned_volume),status='completed',updated_at=now() where id=wid;
   end if;
   if p_command ? 'materials' then
    if jsonb_typeof(p_command->'materials')<>'array' or jsonb_array_length(p_command->'materials')>200 then raise exception 'Invalid material list';end if;
    delete from public.project_work_materials where work_item_id=wid;
    for item in select value from jsonb_array_elements(p_command->'materials') loop
     if jsonb_typeof(item)<>'object' or exists(select 1 from jsonb_object_keys(item) x where x not in ('rule_id','material_catalog_id','material_name','unit','quantity','comment','material_role','dependency_group','option_group','is_auto_generated','is_manual_override')) then raise exception 'Unsupported work material';end if;
     m:=jsonb_populate_record(null::public.project_work_materials,jsonb_build_object('material_role','secondary','is_auto_generated',true,'is_manual_override',false)||item);
     if nullif(btrim(m.material_name),'') is null or nullif(btrim(m.unit),'') is null or m.quantity is null or m.quantity<=0 or m.quantity::text in ('NaN','Infinity','-Infinity') or m.material_role not in ('primary','secondary') or m.material_catalog_id is not null and not exists(select 1 from public.material_catalog where id=m.material_catalog_id) or m.rule_id is not null and not exists(select 1 from public.work_catalog_materials where id=m.rule_id and work_catalog_id=w.work_catalog_id) then raise exception 'Invalid work material/norm';end if;
     insert into public.project_work_materials(work_item_id,rule_id,material_catalog_id,material_name,unit,quantity,comment,material_role,dependency_group,option_group,is_auto_generated,is_manual_override) values(wid,m.rule_id,m.material_catalog_id,m.material_name,m.unit,m.quantity,m.comment,m.material_role,m.dependency_group,m.option_group,m.is_auto_generated,m.is_manual_override);
    end loop;
   end if;
   select * into w from public.project_work_items where id=wid;result:=jsonb_build_object('work',to_jsonb(w));
  end if;
 elsif kind='section' then
  if act='complete' or p_command ? 'materials' then raise exception 'Invalid section command';end if;
  if act='delete' then
   if v<>'{}' or p_command ? 'works' or exists(select 1 from public.work_volume_submission_items x join public.project_work_items y on y.id=x.work_item_id where y.section_id=sid) then raise exception 'Remove linked volume submissions with their own confirmed command first';end if;
   delete from public.project_work_progress where work_item_id in(select id from public.project_work_items where section_id=sid);
   delete from public.project_work_materials where work_item_id in(select id from public.project_work_items where section_id=sid);
   delete from public.project_work_items where section_id=sid;delete from public.project_work_sections where id=sid;
  else
   if nullif(btrim(s.name),'') is null or s.start_date>s.end_date or s.status is null or s.status not in ('planned','in_progress','completed') then raise exception 'Invalid section values';end if;
   if act='create' then insert into public.project_work_sections(project_id,name,start_date,end_date,status,comment,created_by) values(pid,s.name,s.start_date,s.end_date,s.status,s.comment,p_owner) returning * into s;sid:=s.id;
   else update public.project_work_sections set name=s.name,start_date=s.start_date,end_date=s.end_date,status=s.status,comment=s.comment,updated_at=now() where id=sid;end if;
   if p_command ? 'works' then
    if jsonb_typeof(p_command->'works')<>'array' or jsonb_array_length(p_command->'works')>200 then raise exception 'Invalid section works';end if;
    for child in select value from jsonb_array_elements(p_command->'works') loop
     if child->>'kind' is distinct from 'work' or child->>'action' not in ('create','update') or child->>'action' is null then raise exception 'Invalid section child command';end if;
     if child->>'action'='update' and not exists(select 1 from public.project_work_items where id=(child->>'id')::uuid and section_id=sid) then raise exception 'Child work not in section';end if;
     child:=jsonb_set(child,'{values}',coalesce(child->'values','{}')||jsonb_build_object('project_id',pid,'section_id',sid));
     perform voltmaster_private.production_command(p_owner,gen_random_uuid(),child,false);
    end loop;
   end if;
   update public.project_work_items set start_date=s.start_date,end_date=s.end_date,updated_at=now() where section_id=sid and (start_date is distinct from s.start_date or end_date is distinct from s.end_date);
   select * into s from public.project_work_sections where id=sid;result:=jsonb_build_object('section',to_jsonb(s));
  end if;
 else
  select coalesce(sum(completed_volume),0) into total from public.project_work_progress where work_item_id=wid;baseline:=greatest(0,coalesce(w.completed_volume,0)-total);
  if act='delete' then if v<>'{}' then raise exception 'Delete cannot change fact';end if;delete from public.project_work_progress where id=g.id;
  else
   if g.progress_date is null or g.completed_volume is null or g.completed_volume<=0 or g.completed_volume::text in ('NaN','Infinity','-Infinity') then raise exception 'Valid fact date/volume required';end if;
   if act='create' then insert into public.project_work_progress(work_item_id,progress_date,completed_volume,comment,created_by) values(wid,g.progress_date,g.completed_volume,g.comment,p_owner) returning * into g;
   else update public.project_work_progress set progress_date=g.progress_date,completed_volume=g.completed_volume,comment=g.comment where id=g.id returning * into g;end if;
  end if;
  select baseline+coalesce(sum(completed_volume),0) into total from public.project_work_progress where work_item_id=wid;
  update public.project_work_items set completed_volume=total,status=case when total>=planned_volume and planned_volume>0 then 'completed' when total>0 then 'in_progress' else 'planned' end,updated_at=now() where id=wid returning * into w;
  result:=jsonb_build_object('fact',case when act='delete' then null else to_jsonb(g) end,'work',to_jsonb(w));
 end if;
 result:=coalesce(result,'{}')||jsonb_build_object('status','completed','kind',kind,'action',act,'verified',case when act='delete' then case kind when 'work' then not exists(select 1 from public.project_work_items where id=wid) when 'section' then not exists(select 1 from public.project_work_sections where id=sid) else not exists(select 1 from public.project_work_progress where id=g.id) end else true end);
 insert into voltmaster_private.financial_command_receipts values(p_owner,p_request,p_command,result,now());return result;
end $fn$;
revoke all on function voltmaster_private.production_command(uuid,uuid,jsonb,boolean) from public,anon,authenticated;
create or replace function public.execute_production_command(p_request uuid,p_command jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.production_command(auth.uid(),p_request,p_command,false);end $$;
revoke all on function public.execute_production_command(uuid,jsonb) from public,anon;
grant execute on function public.execute_production_command(uuid,jsonb) to authenticated;

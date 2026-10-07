do $test$
declare actor uuid:=gen_random_uuid();p uuid:=gen_random_uuid();catalog uuid:=gen_random_uuid();r jsonb;cmd jsonb;tid uuid;denied boolean;preview jsonb;
begin begin
 insert into auth.users(id) values(actor);insert into public.profiles(id,role,is_active) values(actor,'foreman',true);perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into public.projects(id,name,responsible_user_id) values(p,'TEST template',actor);insert into public.work_catalog(id,name,unit) values(catalog,'TEST template work','м');
 cmd:=jsonb_build_object('kind','save_template','values',jsonb_build_object('project_id',p,'name','TEST saved composition'),
 'items',jsonb_build_array(jsonb_build_object('work_catalog_id',catalog,'work_name','TEST chosen work','unit','м','planned_volume',10,'materials',jsonb_build_array(jsonb_build_object('material_name','TEST chosen material','unit','м','quantity',1.5)))));
 preview:=voltmaster_private.production_command(actor,gen_random_uuid(),cmd,true);
 if exists(select 1 from public.project_work_section_templates where project_id=p) or exists(select 1 from public.project_work_sections where project_id=p) then raise exception 'Template preview wrote data';end if;
 execute 'set local role authenticated';r:=public.execute_production_command(gen_random_uuid(),cmd);execute 'reset role';tid:=(r->'template'->>'id')::uuid;
 if (select count(*) from public.project_work_section_template_items where template_id=tid)<>1 then raise exception 'Partial template';end if;
 cmd:=jsonb_build_object('kind','apply_template','template_id',tid,'values',jsonb_build_object('project_id',p,'start_date','2026-10-01','end_date','2026-10-31'));
 r:=public.execute_production_command(gen_random_uuid(),cmd);
 if (select count(*) from public.project_work_items where project_id=p and completed_volume=0 and planned_volume=10)<>1 or not exists(select 1 from public.project_work_materials m join public.project_work_items w on w.id=m.work_item_id where w.project_id=p and m.quantity=1.5) then raise exception 'Wrong template application quantities';end if;
 denied:=false;begin perform public.execute_production_command(gen_random_uuid(),jsonb_build_object('kind','save_template','values',jsonb_build_object('project_id',p,'name','TEST invalid'),
 'items',jsonb_build_array(jsonb_build_object('work_catalog_id',catalog,'work_name','TEST first valid','unit','м','planned_volume',10),jsonb_build_object('work_catalog_id',catalog,'work_name','TEST second invalid','unit','м','planned_volume',-1))));exception when others then denied:=true;end;
 if not denied or exists(select 1 from public.project_work_section_templates where project_id=p and name='TEST invalid') or (select count(*) from public.project_work_items where project_id=p)<>1 then raise exception 'Partial invalid composition';end if;
 raise exception using errcode='P0992',message='ROLLBACK_TEMPLATE_TEST';exception when sqlstate 'P0992' then null;end;end $test$;
select 'PASS: save/application use checked composition, no preview writes, real selected norms/volumes preserved, invalid second work rolls back; fixtures rolled back' as result;

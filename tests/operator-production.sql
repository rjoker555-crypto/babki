do $test$
declare actor uuid:=gen_random_uuid();p uuid:=gen_random_uuid();other uuid:=gen_random_uuid();catalog uuid:=gen_random_uuid();r jsonb;s jsonb;w jsonb;g jsonb;cmd jsonb;preview jsonb;denied boolean;request uuid;child jsonb;chat uuid:=gen_random_uuid();msg uuid:=gen_random_uuid();confirm_id uuid:=gen_random_uuid();plan jsonb;
begin
 begin
 insert into auth.users(id) values(actor);insert into public.profiles(id,role,is_active) values(actor,'foreman',true);perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into public.projects(id,name,responsible_user_id) values(p,'TEST production command',actor),(other,'TEST foreign production',null);
 insert into public.work_catalog(id,name,unit) values(catalog,'TEST synthetic work','м');
 cmd:=jsonb_build_object('kind','section','action','create','values',jsonb_build_object('project_id',p,'name','TEST section','start_date','2026-10-01','end_date','2026-10-31'),
  'works',jsonb_build_array(jsonb_build_object('kind','work','action','create','values',jsonb_build_object('work_catalog_id',catalog,'work_name','TEST work','unit','м','planned_volume',100),'materials',jsonb_build_array(jsonb_build_object('material_name','TEST material','unit','м','quantity',2)))));
 preview:=voltmaster_private.production_command(actor,gen_random_uuid(),cmd,true);
 if exists(select 1 from public.project_work_sections where project_id=p) then raise exception 'Preview wrote section';end if;
 execute 'set local role authenticated';r:=public.execute_production_command(gen_random_uuid(),cmd);execute 'reset role';s:=r->'section';select to_jsonb(x) into w from public.project_work_items x where section_id=(s->>'id')::uuid;
 if (select count(*) from public.project_work_materials where work_item_id=(w->>'id')::uuid)<>1 then raise exception 'Materials not atomic';end if;
 -- A manual base not represented by history must survive addition/edit/removal.
 update public.project_work_items set completed_volume=3 where id=(w->>'id')::uuid;
 cmd:=jsonb_build_object('kind','manual_fact','action','create','values',jsonb_build_object('work_item_id',w->>'id','progress_date','2026-10-06','completed_volume',20));
 request:=gen_random_uuid();r:=public.execute_production_command(request,cmd);g:=r->'fact';w:=r->'work';if w->>'completed_volume'<>'23' then raise exception 'Manual baseline lost %',w;end if;
 if public.execute_production_command(request,cmd) is distinct from r then raise exception 'Replay differed';end if;
 r:=public.execute_production_command(gen_random_uuid(),jsonb_build_object('kind','manual_fact','action','update','id',g->>'id','expected',g,'values',jsonb_build_object('completed_volume',10)));g:=r->'fact';w:=r->'work';if (w->>'completed_volume')::numeric<>13 then raise exception 'Manual fact edit double counted';end if;
 -- Invalid material after updating the header must roll back all earlier changes.
 denied:=false;begin
  perform public.execute_production_command(gen_random_uuid(),jsonb_build_object('kind','work','action','update','id',w->>'id','expected',w,'values',jsonb_build_object('work_name','TEST SHOULD ROLLBACK'),'materials',jsonb_build_array(jsonb_build_object('material_name','TEST invalid','unit','м','quantity',-1))));
 exception when others then denied:=sqlerrm='Invalid work material/norm';end;
 if not denied or (select work_name from public.project_work_items where id=(w->>'id')::uuid)<>'TEST work' or (select count(*) from public.project_work_materials where work_item_id=(w->>'id')::uuid)<>1 then raise exception 'Partial work write';end if;
 insert into public.agent_conversations(id,owner_id,title) values(chat,actor,'TEST production');insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(msg,actor,chat,'user','TEST complete');
 cmd:=jsonb_build_object('kind','work','action','complete','id',w->>'id','expected',w,'values','{}'::jsonb);
 execute 'set local role service_role';plan:=public.agent_prepare_operator_plan(actor,chat,msg,'production_write',cmd);execute 'reset role';
 insert into public.agent_chat_messages(id,owner_id,chat_id,kind,content) values(confirm_id,actor,chat,'user','ПОДТВЕРЖДАЮ '||(plan->>'id'));
 execute 'set local role service_role';r:=public.agent_execute_operator_plan(actor,(plan->>'id')::uuid,(plan->>'revision')::uuid,confirm_id);execute 'reset role';
 if (r->'result'->'work'->>'completed_volume')::numeric<>100 or (select sum(completed_volume) from public.project_work_progress where work_item_id=(w->>'id')::uuid)<>97 then raise exception 'Completion lost baseline or existing facts';end if;
 -- Check real authenticated RLS, not privileged fixture reads.
 insert into public.project_work_items(project_id,work_catalog_id,work_name,planned_volume) values(other,catalog,'TEST hidden foreign',100);
 execute 'set local role authenticated';if exists(select 1 from public.project_work_items where project_id=other) then raise exception 'Foreign production RLS leaked';end if;execute 'reset role';
 denied:=false;begin perform public.execute_production_command(gen_random_uuid(),jsonb_build_object('kind','section','action','create','values',jsonb_build_object('project_id',other,'name','TEST denied')));exception when others then denied:=sqlerrm='Project access denied';end;if not denied then raise exception 'Foreign section created';end if;
 select to_jsonb(x) into s from public.project_work_sections x where id=(s->>'id')::uuid;
 perform public.execute_production_command(gen_random_uuid(),jsonb_build_object('kind','section','action','delete','id',s->>'id','expected',s,'values','{}'::jsonb));
 if exists(select 1 from public.project_work_items where project_id=p) or exists(select 1 from public.project_work_progress where work_item_id=(w->>'id')::uuid) then raise exception 'Incomplete approved cascade';end if;
 raise exception using errcode='P0992',message='ROLLBACK_PRODUCTION_TEST';exception when sqlstate 'P0992' then null;end;
end $test$;
select 'PASS: atomic section/work/materials, rollback on invalid material, preserved manual base, exact confirmed completion, authenticated foreign project RLS refusal, approved cascade; fixtures rolled back' as result;

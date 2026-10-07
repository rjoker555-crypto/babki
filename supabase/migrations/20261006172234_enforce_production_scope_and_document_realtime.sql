do $$ declare t text; begin
 foreach t in array array['project_work_items','project_work_sections','project_work_tasks','project_customer_contacts'] loop
 execute format('drop policy if exists enforced_project_scope on public.%I',t);
 execute format('create policy enforced_project_scope on public.%I as restrictive for all to authenticated using (voltmaster_private.security_project_scope(project_id)) with check (voltmaster_private.security_project_scope(project_id))',t);
 end loop;
 foreach t in array array['project_work_materials','project_work_progress'] loop
 execute format('drop policy if exists enforced_project_scope on public.%I',t);
 execute format('create policy enforced_project_scope on public.%I as restrictive for all to authenticated using (exists(select 1 from public.project_work_items w where w.id=work_item_id and voltmaster_private.security_project_scope(w.project_id))) with check (exists(select 1 from public.project_work_items w where w.id=work_item_id and voltmaster_private.security_project_scope(w.project_id)))',t);
 end loop;
 foreach t in array array['project_documents','project_document_versions','project_price_history','project_team_members','commercial_proposals','work_volume_submissions','work_volume_submission_items','project_work_section_templates','project_work_section_template_items','project_work_section_template_materials'] loop
 if to_regclass('public.'||t) is not null and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then execute format('alter publication supabase_realtime add table public.%I',t);end if;
 end loop;
 end $$;

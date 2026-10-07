-- Cover all current application sections, including changes outside an object card.
create or replace function agent_private.capture_activity() returns trigger language plpgsql security definer set search_path='' as $$
declare r jsonb; project uuid; project_title text; actor text; label text; verb text;
begin
 if TG_OP='UPDATE' and to_jsonb(NEW)=to_jsonb(OLD) then return NEW; end if;
 if TG_OP='DELETE' then r=to_jsonb(OLD); else r=to_jsonb(NEW); end if;
 project=case when TG_TABLE_NAME='projects' then (r->>'id')::uuid else (r->>'project_id')::uuid end;
 if project is null and r ? 'work_item_id' then select project_id into project from public.project_work_items where id=(r->>'work_item_id')::uuid; end if;
 if project is null and r ? 'submission_id' then select project_id into project from public.work_volume_submissions where id=(r->>'submission_id')::uuid; end if;
 if project is null and r ? 'document_id' then select project_id into project from public.project_documents where id=(r->>'document_id')::uuid; end if;
 if project is not null then select name into project_title from public.projects where id=project; end if;
 if TG_TABLE_NAME='projects' then project_title=r->>'name'; end if;
 select full_name into actor from public.profiles where id=auth.uid();
 actor=coalesce(nullif(actor,''),case when auth.uid() is null then 'Системный процесс' else 'Пользователь' end);
 label=case TG_TABLE_NAME
 when 'profiles' then 'профиль пользователя' when 'projects' then 'карточка объекта' when 'subcontractors' then 'субподрядчик' when 'project_subcontractors' then 'субподрядчик объекта'
 when 'operations' then 'финансовая операция' when 'receivables' then 'дебиторка' when 'payables' then 'кредиторка' when 'creditors' then 'кредитор'
 when 'project_materials' then 'позиция материалов' when 'project_other_expenses' then 'позиция расходов' when 'org_employees' then 'сотрудник и зарплата' when 'org_expenses' then 'организационный расход' when 'events' then 'событие'
 when 'project_documents' then 'документ' when 'project_document_versions' then 'версия документа' when 'pto_documents' then 'документ ПТО' when 'project_customer_contacts' then 'контакт заказчика'
 when 'project_work_items' then 'работа' when 'project_work_progress' then 'факт выполнения' when 'project_work_materials' then 'материал работы' when 'project_work_sections' then 'раздел работ' when 'project_work_tasks' then 'задача'
 when 'work_volume_submissions' then 'подача объёмов' when 'work_volume_submission_items' then 'строка поданных объёмов'
 when 'commercial_proposals' then 'коммерческое предложение' when 'project_price_history' then 'история цены договора'
 when 'work_catalog' then 'каталог работ' when 'material_catalog' then 'каталог материалов' when 'work_catalog_materials' then 'норма материалов' when 'work_material_options' then 'вариант материалов'
 when 'project_work_section_templates' then 'шаблон раздела' when 'project_work_section_template_items' then 'работа шаблона' when 'project_work_section_template_materials' then 'материал шаблона' else 'запись' end;
 verb=case TG_OP when 'INSERT' then 'Добавлена запись' when 'UPDATE' then 'Изменена запись' else 'Удалена запись' end;
 insert into public.agent_activity_events(project_id,project_name,actor_id,actor_name,entity_table,entity_id,summary,financial)
 values(project,project_title,auth.uid(),actor,TG_TABLE_NAME,(r->>'id')::uuid,verb||': '||label||' · запись '||(r->>'id'),TG_TABLE_NAME in ('profiles','operations','receivables','payables','creditors','org_employees','org_expenses','events','commercial_proposals','project_price_history','project_materials','project_other_expenses'));
 return null;
end $$;
do $$ declare t text; begin
 foreach t in array array['profiles','events','project_subcontractors','creditors','org_employees','org_expenses','project_customer_contacts','work_catalog','material_catalog','work_catalog_materials','project_work_materials','work_material_options','project_document_versions','project_price_history','commercial_proposals','project_work_section_templates','project_work_section_template_items','project_work_section_template_materials','work_volume_submission_items'] loop
 execute format('create trigger agent_capture_activity after insert or update or delete on public.%I for each row execute function agent_private.capture_activity()',t);
 end loop;
end $$;

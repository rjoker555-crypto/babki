do $test$
declare actor uuid:=gen_random_uuid();p uuid:=gen_random_uuid();mat uuid:=gen_random_uuid();r jsonb;receipt jsonb;debt uuid;snapshot jsonb;cash jsonb;
begin begin
 insert into auth.users(id) values(actor);insert into public.profiles(id,role,is_active) values(actor,'director',true);insert into public.agent_director_access values(actor);perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into public.projects(id,name,contractor_company,planned_revenue) values(p,'TEST deferred financial numbers','ООО',10000);
 insert into public.project_materials(id,project_id,name,planned_amount,actual_amount) values(mat,p,'TEST existing manual base',700,75);
 r:=public.execute_credit_operation(gen_random_uuid(),jsonb_build_object('action','create','values',jsonb_build_object('operation_type','expense','article','ТМЦ','amount',250,'project_id',p,'cost_item_id',mat,'cost_item_type','material','credit_kind','material','counterparty','TEST supplier','vat_included',true),'credit',jsonb_build_object('due_date','2026-11-01','full_repayment_date','2026-11-02')));receipt:=r->'operation';debt:=(r->'credit'->>'id')::uuid;
 perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','create','values',jsonb_build_object('operation_type','expense','article','Погашение кредиторки','amount',100,'project_id',p,'payable_id',debt)));
 perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','create','values',jsonb_build_object('operation_type','income','article','Аванс заказчика','amount',500,'project_id',p)));
 cash:=public.agent_cash_summary(actor,p);
 if (cash->>'income')::numeric<>500 or (cash->>'expense')::numeric<>100 or (select actual_amount from public.project_materials where id=mat)<>325 or (select paid_amount from public.payables where id=debt)<>100 then raise exception 'Wrong deferred cash/material/debt numbers';end if;
 snapshot:=jsonb_build_object('projects',(select jsonb_agg(to_jsonb(x)) from public.projects x where id=p),'ops',(select jsonb_agg(to_jsonb(x)) from public.operations x where created_by=actor),'ars','[]'::jsonb,'aps',(select jsonb_agg(to_jsonb(x)) from public.payables x where id=debt),'subcontractors','[]'::jsonb,'projectMaterials',(select jsonb_agg(to_jsonb(x)) from public.project_materials x where id=mat),'projectOtherExpenses','[]'::jsonb,'agent_cash',cash);
 raise exception using errcode='P0992',message='ROLLBACK_DEFERRED_NUMBERS';exception when sqlstate 'P0992' then null;end;
 perform set_config('voltmaster.deferred_test',snapshot::text,true);
end $test$;
select current_setting('voltmaster.deferred_test')::jsonb as snapshot,'PASS: real shared deferred receipt + repayment: material fact 325, cash expense 100, AP paid 100; fixtures rolled back' as result;

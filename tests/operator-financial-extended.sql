-- No production row is changed: the entire synthetic fixture is rolled back.
do $test$
declare actor uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); ip uuid:=gen_random_uuid(); sub uuid:=gen_random_uuid(); oth uuid:=gen_random_uuid(); oth2 uuid:=gen_random_uuid(); org uuid:=gen_random_uuid(); org2 uuid:=gen_random_uuid(); ar uuid:=gen_random_uuid(); ar2 uuid:=gen_random_uuid(); ap uuid:=gen_random_uuid(); ap2 uuid:=gen_random_uuid(); r jsonb; original jsonb; oid uuid; snapshot jsonb; denied boolean;
begin
 begin
 insert into auth.users(id) values(actor);insert into public.profiles(id,role,is_active) values(actor,'director',true);insert into public.agent_director_access values(actor);
 perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into public.projects(id,name,contractor_company) values(p,'TEST extended ООО','ООО'),(ip,'TEST extended ИП','ИП');
 insert into public.subcontractors(id,project_id,name,planned_amount) values(sub,p,'TEST subcontractor',300);
 insert into public.project_other_expenses(id,project_id,name,actual_amount,planned_amount) values(oth,p,'TEST other',90,100),(oth2,p,'TEST other 2',20,100);
 insert into public.org_expenses(id,name,company,monthly_amount) values(org,'TEST org','ООО',500),(org2,'TEST org 2','ООО',600);
 insert into public.receivables(id,project_id,customer,amount,paid_amount) values(ar,p,'TEST AR',1000,100),(ar2,p,'TEST AR 2',1000,50);
 insert into public.payables(id,project_id,counterparty,amount) values(ap,p,'TEST AP',500),(ap2,p,'TEST AP 2',600);
 r:=public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','create','values',jsonb_build_object('operation_type','expense','article','Субподрядчики','project_id',p,'subcontractor_id',sub,'amount',200,'vat_included',true)));
 if (select sum(amount) from public.operations where subcontractor_id=sub)<>200 then raise exception 'Subcontractor fact';end if;
 r:=public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','create','values',jsonb_build_object('operation_type','expense','article','Прочие расходы','project_id',p,'cost_item_id',oth,'cost_item_type','other','amount',70,'vat_included',true)));oid:=(r->'operation'->>'id')::uuid;
 if (select actual_amount from public.project_other_expenses where id=oth)<>160 then raise exception 'Other baseline';end if;
 select to_jsonb(o) into original from public.operations o where id=oid;
 perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','update','id',oid,'expected',original,'values',jsonb_build_object('cost_item_id',oth2,'amount',40)));
 if (select actual_amount from public.project_other_expenses where id=oth)<>90 or (select actual_amount from public.project_other_expenses where id=oth2)<>60 then raise exception 'Other link transfer';end if;
 select to_jsonb(o) into original from public.operations o where id=oid;
 perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','delete','id',oid,'expected',original,'values','{}'::jsonb));
 if (select actual_amount from public.project_other_expenses where id=oth2)<>20 then raise exception 'Other delete';end if;
 r:=public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','create','values',jsonb_build_object('operation_type','expense','article','Орг. расходы','payer_company','ООО','org_expense_id',org,'amount',80)));oid:=(r->'operation'->>'id')::uuid;
 select to_jsonb(o) into original from public.operations o where id=oid;
 perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','update','id',oid,'expected',original,'values',jsonb_build_object('org_expense_id',org2,'amount',60)));
 if exists(select 1 from public.operations where org_expense_id=org) or (select sum(amount) from public.operations where org_expense_id=org2)<>60 then raise exception 'Org transfer';end if;
 r:=public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','create','values',jsonb_build_object('operation_type','income','article','Аванс заказчика','project_id',p,'receivable_id',ar,'amount',200)));oid:=(r->'operation'->>'id')::uuid;
 select to_jsonb(o) into original from public.operations o where id=oid;
 perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','update','id',oid,'expected',original,'values',jsonb_build_object('receivable_id',ar2,'amount',130)));
 if (select paid_amount from public.receivables where id=ar)<>100 or (select paid_amount from public.receivables where id=ar2)<>180 then raise exception 'AR link transfer';end if;
 r:=public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','create','values',jsonb_build_object('operation_type','expense','article','Погашение кредиторки','project_id',p,'payable_id',ap,'amount',250)));oid:=(r->'operation'->>'id')::uuid;
 select to_jsonb(o) into original from public.operations o where id=oid;
 perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','update','id',oid,'expected',original,'values',jsonb_build_object('payable_id',ap2,'amount',130)));
 if (select paid_amount from public.payables where id=ap)<>0 or (select paid_amount from public.payables where id=ap2)<>130 then raise exception 'AP link transfer';end if;
 perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','create','values',jsonb_build_object('operation_type','expense','article','НДС','project_id',p,'amount',20)));
 perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','create','values',jsonb_build_object('operation_type','income','article','Аванс заказчика','project_id',ip,'amount',1000)));
 perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','create','values',jsonb_build_object('operation_type','expense','article','Налог ИП','project_id',ip,'amount',50)));
 denied:=false;begin perform public.execute_financial_operation(gen_random_uuid(),jsonb_build_object('action','create','values',jsonb_build_object('operation_type','expense','article','НДС','project_id',ip,'amount',50)));exception when others then denied:=sqlerrm='Tax company mismatch';end;if not denied then raise exception 'Wrong tax accepted';end if;
 snapshot:=jsonb_build_object('projects',(select jsonb_agg(to_jsonb(x)) from public.projects x where id in (p,ip)),'ops',(select jsonb_agg(to_jsonb(x)) from public.operations x where created_by=actor),'ars',(select jsonb_agg(to_jsonb(x)) from public.receivables x where id in (ar,ar2)),'aps',(select jsonb_agg(to_jsonb(x)) from public.payables x where id in (ap,ap2)),'subcontractors',(select jsonb_agg(to_jsonb(x)) from public.subcontractors x where id=sub),'projectMaterials','[]'::jsonb,'projectOtherExpenses',(select jsonb_agg(to_jsonb(x)) from public.project_other_expenses x where id in (oth,oth2)));
 raise exception using errcode='P0992',message='ROLLBACK_EXTENDED_TEST';
 exception when sqlstate 'P0992' then null;end;
 perform set_config('voltmaster.extended_test',snapshot::text,true);
end $test$;
select current_setting('voltmaster.extended_test')::jsonb as snapshot, 'PASS: subcontractor/other/org/taxes, AR/AP/cost/consumer link transfer; fixtures rolled back' as result;

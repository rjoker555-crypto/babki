do $test$
declare actor uuid:=gen_random_uuid(); request uuid:=gen_random_uuid();denied boolean;
begin
 begin
 insert into auth.users(id) values(actor);insert into public.profiles(id,role,is_active) values(actor,'foreman',true);
 if not public.agent_reserve_api_call(actor,'chat',request,0) then raise exception 'Initial reservation denied';end if;
 if public.agent_reserve_api_call(actor,'chat',request,0) then raise exception 'Paid replay allowed';end if;
 perform public.agent_record_api_usage(actor,'chat',request,0,12,4);
 if not exists(select 1 from public.agent_api_budget_events where request_id=request and input_tokens=12 and output_tokens=4) then raise exception 'Usage missing';end if;
 insert into public.agent_api_budget_events(owner_id,scope,request_id,step) select actor,'chat',gen_random_uuid(),0 from generate_series(1,79);
 if public.agent_reserve_api_call(actor,'voice',gen_random_uuid(),0) or public.agent_reserve_api_call(actor,'analysis',gen_random_uuid(),0) then raise exception 'Cross-mode limit bypass';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);execute 'set local role authenticated';
 denied:=false;begin perform public.agent_reserve_api_call(actor,'chat',gen_random_uuid(),0);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Client budget API exposed';end if;
 denied:=false;begin perform count(*) from public.agent_api_budget_events;exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Client budget ledger exposed';end if;
 execute 'reset role';raise exception using errcode='P0999',message='ROLLBACK_SECURITY_BUDGET';
 exception when sqlstate 'P0999' then null;end;
end $test$;

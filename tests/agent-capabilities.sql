do $test$
declare actor uuid:=gen_random_uuid(); other_user uuid:=gen_random_uuid(); chat uuid:=gen_random_uuid(); other_chat uuid:=gen_random_uuid();
 file uuid:=gen_random_uuid(); other_file uuid:=gen_random_uuid(); request uuid:=gen_random_uuid(); job uuid; result jsonb; claimed jsonb; plan uuid; confirmation uuid; project uuid; rejected boolean;
begin
 begin
  insert into auth.users(id) values(actor),(other_user);
  insert into public.profiles(id,role,is_active) values(actor,'director',true),(other_user,'foreman',true);
  insert into public.agent_director_access(user_id) values(actor);
  insert into public.agent_conversations(id,owner_id,title) values(chat,actor,'TEST agent capabilities'),(other_chat,other_user,'TEST foreign chat');
  insert into public.agent_file_assets(id,owner_id,chat_id,file_name,storage_path,mime_type,file_size,sha256,page_count)
   values(file,actor,chat,'TEST project.pdf','TEST/'||file::text,'application/pdf',100,repeat('0',64),2),
         (other_file,other_user,other_chat,'TEST other.pdf','TEST/'||other_file::text,'application/pdf',100,repeat('1',64),2);
  result:=public.agent_queue_analysis(actor,chat,file,'Извлечь ведомость',request);job:=(result->>'job_id')::uuid;
  if public.agent_queue_analysis(actor,chat,file,'Извлечь ведомость',request)->>'job_id'<>job::text or
   (select count(*) from public.agent_background_jobs where owner_id=actor and request_id=request)<>1 then raise exception 'Queue retry duplicated job'; end if;
  rejected:=false;begin perform public.agent_queue_analysis(actor,chat,other_file,'Разобрать чужой файл',gen_random_uuid());exception when others then rejected:=true;end;
  if not rejected then raise exception 'Foreign file allowed'; end if;
  rejected:=false;begin perform public.agent_get_job(other_user,job);exception when others then rejected:=true;end;
  if not rejected then raise exception 'Foreign job leaked'; end if;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  execute 'set local role authenticated';
  if exists(select 1 from public.agent_file_assets where id=other_file) or not exists(select 1 from public.agent_file_assets where id=file) then raise exception 'Asset RLS failed'; end if;
  rejected:=false;begin perform public.agent_get_job(other_user,job);exception when insufficient_privilege then rejected:=true;end;
  if not rejected then raise exception 'Client can impersonate RPC owner'; end if;
  execute 'reset role';
  claimed:=public.agent_claim_analysis(job);
  if claimed->'job'->>'id'<>job::text then raise exception 'Claim failed'; end if;
  if not public.agent_begin_step(job,(claimed->'job'->>'lease_id')::uuid,'TEST model') then raise exception 'Begin failed'; end if;
  update public.agent_background_jobs set lease_until=now()-interval '1 minute' where id=job;
  result:=public.agent_claim_analysis(job);
  if result->>'status'<>'needs_attention' then raise exception 'Unknown provider result automatically retried'; end if;
  -- A fresh job completes exactly once; replayed/cancelled leases cannot write results.
  result:=public.agent_queue_analysis(actor,chat,file,'Извлечь ведомость',gen_random_uuid());job:=(result->>'job_id')::uuid;
  claimed:=public.agent_claim_analysis(job);perform public.agent_begin_step(job,(claimed->'job'->>'lease_id')::uuid,'TEST model');
  if not public.agent_finish_step(job,(claimed->'job'->>'lease_id')::uuid,'{"summary":"TEST","rows":[]}',null,10,5) then raise exception 'Finish failed'; end if;
  if public.agent_finish_step(job,(claimed->'job'->>'lease_id')::uuid,'{}',null,10,5) then raise exception 'Stale lease completed twice'; end if;
  result:=public.agent_get_job(actor,job);
  if result->>'status'<>'completed' or (result->>'input_tokens')::integer<>10 then raise exception 'Result/usage not persisted'; end if;
  result:=public.agent_propose_file_action(actor,chat,'create_project',file,'{"name":"TEST project from analysis","customer":"TEST customer"}');plan:=(result->>'plan_id')::uuid;
  if exists(select 1 from public.projects where name='TEST project from analysis') then raise exception 'Proposal executed before confirmation'; end if;
  insert into public.agent_chat_messages(owner_id,chat_id,kind,content) values(actor,chat,'user','да') returning id into confirmation;
  rejected:=false;begin perform public.agent_execute_file_action(actor,plan,confirmation,false);exception when others then rejected:=true;end;
  if not rejected then raise exception 'Vague confirmation allowed'; end if;
  insert into public.agent_chat_messages(owner_id,chat_id,kind,content) values(actor,chat,'user','ПОДТВЕРЖДАЮ '||plan::text) returning id into confirmation;
  result:=public.agent_execute_file_action(actor,plan,confirmation,false);project:=(result->'result'->>'project_id')::uuid;
  if not exists(select 1 from public.project_documents where project_id=project and document_type='project' and storage_bucket='agent-files') then raise exception 'Project file not attached'; end if;
  if public.agent_execute_file_action(actor,plan,confirmation,false)<>result then raise exception 'Confirmation replay duplicated project'; end if;
  result:=public.agent_propose_file_action(actor,chat,'attach_project',file,jsonb_build_object('project_id',project));plan:=(result->>'plan_id')::uuid;
  insert into public.agent_chat_messages(owner_id,chat_id,kind,content) values(actor,chat,'user','ПОДТВЕРЖДАЮ '||plan::text) returning id into confirmation;
  perform public.agent_execute_file_action(actor,plan,confirmation,false);
  if (select count(*) from public.project_documents where project_id=project)<>1 then raise exception 'Same file attached twice'; end if;
  if has_function_privilege('authenticated','public.agent_execute_file_action(uuid,uuid,uuid,boolean)','EXECUTE') or
   has_function_privilege('authenticated','public.agent_claim_analysis(uuid)','EXECUTE') or
   has_table_privilege('authenticated','public.agent_job_steps','UPDATE') then raise exception 'Unexpected client worker grants'; end if;
  -- Deleting chat history does not remove ongoing jobs, files or attached project documents.
  delete from public.agent_conversations where id=chat;
  if not exists(select 1 from public.agent_file_assets where id=file) or not exists(select 1 from public.agent_background_jobs where id=job) or
   not exists(select 1 from public.project_documents where project_id=project) then raise exception 'Chat deletion destroyed artifacts'; end if;
  raise exception using errcode='ZX001',message='Tests passed; rollback isolated data';
 exception when sqlstate 'ZX001' then null;
 end;
 if exists(select 1 from auth.users where id in(actor,other_user)) then raise exception 'Test data leaked'; end if;
end $test$;

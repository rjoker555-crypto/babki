do $test$
declare actor uuid:=gen_random_uuid();project uuid:=gen_random_uuid();chat uuid:=gen_random_uuid();submission uuid:=gen_random_uuid();asset uuid:=gen_random_uuid();file uuid:=gen_random_uuid();confirmation uuid:=gen_random_uuid();update_id bigint:=7000042;preview jsonb;result jsonb;path text;code text:=repeat('c',64);
begin begin
 insert into auth.users(id) values(actor);insert into public.profiles(id,role,is_active) values(actor,'director',true);insert into public.agent_director_access values(actor);
 insert into public.projects(id,name) values(project,'TEST Telegram batch');insert into public.agent_conversations(id,owner_id,title) values(chat,actor,'Telegram');
 insert into voltmaster_private.telegram_links(owner_id,telegram_user_id,current_chat_id,mode,selected_project_id,document_type) values(actor,912345670,chat,'document',project,'project');
 insert into voltmaster_private.telegram_submissions(id,owner_id,chat_id,project_id,project_name,document_type,explanation) values(submission,actor,chat,project,'TEST Telegram batch','project','TEST notes');
 path:=actor::text||'/'||asset::text||'.txt';
 insert into storage.objects(bucket_id,name,metadata) values('agent-files',path,'{"size":12}'::jsonb);
 insert into public.agent_file_assets(id,owner_id,chat_id,file_name,storage_path,mime_type,file_size,sha256) values(asset,actor,chat,'TEST.txt',path,'text/plain',12,repeat('d',64));
 insert into voltmaster_private.telegram_submission_files(id,submission_id,telegram_file_id,file_name,mime_type,file_size,storage_path,sha256,agent_file_id) values(file,submission,'TEST telegram file','TEST.txt','text/plain',12,actor::text||'/inbox.txt',repeat('d',64),asset);
 perform set_config('request.jwt.claim.role','service_role',true);execute 'set local role service_role';
 preview:=public.telegram_submission_preview(actor,chat);
 if preview->>'document_type'<>'project' or preview->>'digest' is null then raise exception 'Batch preview invalid';end if;
 result:=public.telegram_bridge('enqueue',jsonb_build_object('update_id',update_id,'telegram_user_id',912345670,'event',null,'update',jsonb_build_object('update_id',update_id,'message',jsonb_build_object('chat',jsonb_build_object('id',912345670,'type','private'),'from',jsonb_build_object('id',912345670),'text','TEST confirm'))));
 result:=public.telegram_bridge('claim');
 result:=public.telegram_save_incoming(update_id,actor,chat,'document','callback','ПОДТВЕРЖДАЮ ПОДАЧУ '||submission::text);confirmation:=(result->>'id')::uuid;
 result:=public.telegram_attach_batch(actor,chat,submission,confirmation,preview->>'digest');
 if result->>'status'<>'approved' or jsonb_array_length(result->'documents')<>1 or not exists(select 1 from public.project_documents where id=(result->'documents'->0->>'document_id')::uuid and project_id=project) then raise exception 'Director batch did not attach verified document';end if;
 if not exists(select 1 from public.project_document_versions where document_id=(result->'documents'->0->>'document_id')::uuid) then raise exception 'Document version missing';end if;
 execute 'reset role';
 raise exception using errcode='P0996',message='ROLLBACK_TELEGRAM_BATCH';exception when sqlstate 'P0996' then null;end;
end $test$;
select 'PASS: director exact Telegram confirmation attaches prepared personal file through existing document command, verifies document/version atomically; fixtures rolled back' result;

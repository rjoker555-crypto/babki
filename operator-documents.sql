create table if not exists voltmaster_private.document_cleanup_jobs(
 owner_id uuid not null,request_id uuid not null,document_id uuid not null,items jsonb not null,
 status text not null default 'pending' check(status in ('pending','completed')),outcomes jsonb,
 created_at timestamptz not null default now(),primary key(owner_id,request_id)
);
alter table voltmaster_private.document_cleanup_jobs enable row level security;
revoke all on voltmaster_private.document_cleanup_jobs from public,anon,authenticated;
create or replace function voltmaster_private.guard_document_cleanup_path() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from voltmaster_private.document_cleanup_jobs j,jsonb_array_elements(j.items) x where j.status='pending' and x->>'bucket'=new.storage_bucket and x->>'path'=new.file_path and (x->>'remove_allowed')::boolean) then raise exception 'File pending deletion';end if;return new;
end $$;
revoke all on function voltmaster_private.guard_document_cleanup_path() from public,anon,authenticated;
drop trigger if exists guard_document_cleanup_path on public.project_documents;
create trigger guard_document_cleanup_path before insert or update on public.project_documents for each row execute function voltmaster_private.guard_document_cleanup_path();
drop trigger if exists guard_document_cleanup_path on public.project_document_versions;
create trigger guard_document_cleanup_path before insert or update on public.project_document_versions for each row execute function voltmaster_private.guard_document_cleanup_path();
create or replace function voltmaster_private.document_command(p_owner uuid,p_request uuid,p_command jsonb,p_preview boolean default false)
returns jsonb language plpgsql set search_path='' as $fn$
declare act text:=p_command->>'action'; v jsonb:=coalesce(p_command->'values','{}'); old public.project_documents; doc public.project_documents; asset public.agent_file_assets; pr public.projects;
 versions jsonb; source jsonb; object_row jsonb; paths jsonb:='[]'; path record; result jsonb; stored jsonb; price jsonb:=p_command->'price_change'; new_amount numeric; change_day date;
 pid uuid; bucket text; fname text; fpath text; mime text; fsize bigint; n integer; k text; history jsonb;
begin
 if not exists(select 1 from public.profiles where id=p_owner and is_active and role in ('director','manager')) then raise exception 'Document write access denied';end if;
 if p_request is null or act is null or act not in ('attach','replace','metadata','delete') or jsonb_typeof(p_command)<>'object' or exists(select 1 from jsonb_object_keys(p_command) x where x not in ('action','id','expected','project_id','document_type','file_id','uploaded_file','values','price_change')) then raise exception 'Invalid document command';end if;
 if jsonb_typeof(v) is distinct from 'object' or exists(select 1 from jsonb_object_keys(v) x where x not in ('title','document_number','document_date','comment')) then raise exception 'Unsupported document fields';end if;
 perform pg_advisory_xact_lock(hashtextextended('voltmaster.financial.commands',0));
 if not p_preview then
  select result_json,command_json into result,stored from voltmaster_private.financial_command_receipts where owner_id=p_owner and request_id=p_request;
  if found then if stored is distinct from p_command then raise exception 'Request reused with different command';end if;return result;end if;
 end if;
 if act='attach' then
  if p_command ? 'id' or p_command ? 'expected' then raise exception 'Attach cannot set identity';end if;
  doc.project_id:=(p_command->>'project_id')::uuid;doc.document_type:=p_command->>'document_type';doc.version_no:=1;doc.is_current:=true;
 else
  select * into old from public.project_documents where id=(p_command->>'id')::uuid for update;
  if not found or to_jsonb(old) is distinct from p_command->'expected' then raise exception 'Record changed; create a new approval';end if;
  if p_command ? 'project_id' or p_command ? 'document_type' then raise exception 'Document project/type cannot move';end if;doc:=old;
 end if;
 pid:=doc.project_id;select * into pr from public.projects where id=pid for update;if not found then raise exception 'Project not found';end if;
 if doc.document_type not in ('contract','project','estimate','addendum','other') or doc.document_type is null then raise exception 'Invalid document type';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by version_no,id),'[]') into versions from public.project_document_versions x where document_id=old.id;
 select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') into history from public.project_price_history x where reason_document_id=old.id;
 if act in ('attach','replace') then
  if num_nonnulls(nullif(p_command->>'file_id',''),nullif(p_command->>'uploaded_file','null'))<>1 then raise exception 'Exactly one prepared file required';end if;
  if p_command ? 'file_id' then
   select * into asset from public.agent_file_assets where id=(p_command->>'file_id')::uuid and owner_id=p_owner;
   if not found then raise exception 'Own prepared file required';end if;
   source:=to_jsonb(asset);bucket:='agent-files';fpath:=asset.storage_path;fname:=asset.file_name;mime:=asset.mime_type;fsize:=asset.file_size;
  else
   source:=p_command->'uploaded_file';
   if jsonb_typeof(source) is distinct from 'object' or exists(select 1 from jsonb_object_keys(source) x where x not in ('storage_bucket','file_path','file_name','mime_type','file_size')) then raise exception 'Invalid uploaded file metadata';end if;
   bucket:=source->>'storage_bucket';fpath:=source->>'file_path';fname:=source->>'file_name';mime:=source->>'mime_type';fsize:=(source->>'file_size')::bigint;
   if bucket<>'project-documents' or bucket is null or split_part(fpath,'/',1)<>pid::text then raise exception 'Uploaded file must belong to this project';end if;
  end if;
  if bucket not in ('project-documents','agent-files') or fpath is null or length(fpath)>2048 or fpath ~ E'(^|/)(\\.\\.?)(/|$)|\\\\|[[:cntrl:]]' or fname is null or length(fname) not between 1 and 200 or fsize is null or fsize<=0 then raise exception 'Invalid document file';end if;
  select to_jsonb(x) into object_row from storage.objects x where bucket_id=bucket and name=fpath;
  if object_row is null or asset.id is null and object_row->>'owner_id' is distinct from p_owner::text or (object_row->'metadata'->>'size')::bigint is distinct from fsize then raise exception 'Prepared storage object missing/changed';end if;
  if exists(select 1 from voltmaster_private.document_cleanup_jobs j,jsonb_array_elements(j.items) x where j.status='pending' and x->>'bucket'=bucket and x->>'path'=fpath and (x->>'remove_allowed')::boolean) then raise exception 'File pending deletion';end if;
  if act='replace' and old.storage_bucket=bucket and old.file_path=fpath then raise exception 'Replacement must be a new immutable file';end if;
  doc.file_name:=fname;doc.file_path:=fpath;doc.mime_type:=mime;doc.file_size:=fsize;doc.storage_bucket:=bucket;
  if act='attach' then doc.title:=fname;end if;
  doc.version_no:=case when act='attach' then 1 else greatest(old.version_no,coalesce((select max(version_no) from public.project_document_versions where document_id=old.id),0))+1 end;
 elsif p_command ? 'file_id' or p_command ? 'uploaded_file' then raise exception 'This action cannot change the file';end if;
 doc:=jsonb_populate_record(doc,v);
 if act<>'delete' and (nullif(btrim(doc.title),'') is null or length(doc.title)>500) then raise exception 'Document title required';end if;
 if price is not null and price<>'null' then
  if act='delete' or doc.document_type<>'addendum' or jsonb_typeof(price)<>'object' or exists(select 1 from jsonb_object_keys(price) x where x not in ('expected_project','new_amount','change_date','reason_text')) or price->'expected_project' is distinct from to_jsonb(pr) then raise exception 'Exact addendum price approval required';end if;
  new_amount:=(price->>'new_amount')::numeric;change_day:=(price->>'change_date')::date;
  if new_amount is null or new_amount<0 or new_amount::text in ('NaN','Infinity','-Infinity') or new_amount<>round(new_amount,2) or change_day is null or nullif(btrim(price->>'reason_text'),'') is null then raise exception 'Invalid approved contract amount';end if;
 end if;
 if act='delete' then
  if v<>'{}' then raise exception 'Delete cannot change metadata';end if;
  for path in select distinct storage_bucket as b,file_path as p from public.project_document_versions where document_id=old.id union select old.storage_bucket,old.file_path loop
   if path.p is not null then paths:=paths||jsonb_build_array(jsonb_build_object('bucket',path.b,'path',path.p,'remove_allowed',not(exists(select 1 from public.project_documents where id<>old.id and storage_bucket=path.b and file_path=path.p) or exists(select 1 from public.project_document_versions where document_id<>old.id and storage_bucket=path.b and file_path=path.p) or exists(select 1 from public.commercial_proposals where letter_storage_bucket=path.b and letter_file_path=path.p) or path.b='agent-files' and exists(select 1 from public.agent_file_assets where storage_path=path.p))));end if;
  end loop;
 end if;
 if p_preview then return jsonb_build_object('before',case when old.id is null then null else to_jsonb(old) end,'document',to_jsonb(doc),'versions',versions,'source',source,'storage_object',object_row,'files',paths,'price_history',history,'price_change',price,'project',to_jsonb(pr));end if;
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 if act='delete' then
  insert into voltmaster_private.document_cleanup_jobs(owner_id,request_id,document_id,items) values(p_owner,p_request,old.id,paths);
  delete from public.project_documents where id=old.id;
 else
  if act='attach' then
   insert into public.project_documents(project_id,document_type,title,file_name,file_path,mime_type,file_size,storage_bucket,document_number,document_date,comment,version_no,is_current,uploaded_by) values(pid,doc.document_type,doc.title,doc.file_name,doc.file_path,doc.mime_type,doc.file_size,doc.storage_bucket,doc.document_number,doc.document_date,doc.comment,1,true,p_owner) returning * into doc;
  else
   if act='replace' and not exists(select 1 from public.project_document_versions where document_id=old.id and version_no=old.version_no) then
    insert into public.project_document_versions(document_id,version_no,file_name,file_path,mime_type,file_size,storage_bucket,uploaded_by) values(old.id,old.version_no,old.file_name,old.file_path,old.mime_type,old.file_size,old.storage_bucket,old.uploaded_by);
   end if;
   update public.project_documents set title=doc.title,document_number=doc.document_number,document_date=doc.document_date,comment=doc.comment,file_name=doc.file_name,file_path=doc.file_path,mime_type=doc.mime_type,file_size=doc.file_size,storage_bucket=doc.storage_bucket,version_no=doc.version_no,uploaded_by=case when act='replace' then p_owner else old.uploaded_by end,updated_at=now() where id=old.id returning * into doc;
  end if;
  if act in ('attach','replace') then insert into public.project_document_versions(document_id,version_no,file_name,file_path,mime_type,file_size,storage_bucket,uploaded_by) values(doc.id,doc.version_no,doc.file_name,doc.file_path,doc.mime_type,doc.file_size,doc.storage_bucket,p_owner);end if;
  if asset.id is not null then insert into public.agent_file_project_links(file_id,project_id,document_id) values(asset.id,pid,doc.id) on conflict(file_id,project_id) do nothing;end if;
  if new_amount is not null then
   insert into public.project_price_history(project_id,change_date,previous_amount,change_amount,new_amount,reason_type,reason_document_id,reason_text,created_by) values(pid,change_day,pr.planned_revenue,new_amount-pr.planned_revenue,new_amount,'addendum',doc.id,price->>'reason_text',p_owner);
   update public.projects set planned_revenue=new_amount,updated_at=now() where id=pid;
  end if;
 end if;
 result:=jsonb_build_object('status','completed','action',act,'document',to_jsonb(doc),'file_cleanup_pending',act='delete','cleanup_request_id',case when act='delete' then p_request else null end,'verified',case when act='delete' then not exists(select 1 from public.project_documents where id=old.id) and not exists(select 1 from public.project_document_versions where document_id=old.id) else exists(select 1 from public.project_documents where id=doc.id and version_no=doc.version_no) end);
 if result->>'verified'<>'true' then raise exception 'Document verification failed';end if;
 insert into voltmaster_private.financial_command_receipts values(p_owner,p_request,p_command,result,now());return result;
end $fn$;
revoke all on function voltmaster_private.document_command(uuid,uuid,jsonb,boolean) from public,anon,authenticated;
create or replace function public.execute_document_command(p_request uuid,p_command jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.document_command(auth.uid(),p_request,p_command,false);end $$;
revoke all on function public.execute_document_command(uuid,jsonb) from public,anon;
grant execute on function public.execute_document_command(uuid,jsonb) to authenticated;
create or replace function public.agent_document_cleanup(p_owner uuid,p_request uuid,p_outcomes jsonb default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare job voltmaster_private.document_cleanup_jobs;
begin
 select * into job from voltmaster_private.document_cleanup_jobs where owner_id=p_owner and request_id=p_request for update;if not found then raise exception 'Own document cleanup job required';end if;
 if not exists(select 1 from public.profiles where id=p_owner and is_active and (role in ('director','manager') or job.domain='proposal' and role in ('finance','accountant'))) then raise exception 'Document access denied';end if;
 if p_outcomes is not null then
  if jsonb_typeof(p_outcomes)<>'array' or jsonb_array_length(p_outcomes)<>jsonb_array_length(job.items) or exists(select 1 from jsonb_array_elements(job.items) x where not exists(select 1 from jsonb_array_elements(p_outcomes) y where x->>'bucket'=y->>'bucket' and x->>'path'=y->>'path' and (y->>'status'='removed' and (x->>'remove_allowed')::boolean or y->>'status'='retained' and not(x->>'remove_allowed')::boolean))) then raise exception 'Incomplete cleanup outcomes';end if;
  update voltmaster_private.document_cleanup_jobs set status='completed',outcomes=p_outcomes where owner_id=p_owner and request_id=p_request returning * into job;
 end if;return jsonb_build_object('status',job.status,'items',job.items,'outcomes',job.outcomes);
end $$;
revoke all on function public.agent_document_cleanup(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.agent_document_cleanup(uuid,uuid,jsonb) to service_role;
alter table public.agent_operator_plans drop constraint if exists agent_operator_plans_kind_check;
alter table public.agent_operator_plans add constraint agent_operator_plans_kind_check check(kind in ('operation_write','project_create','credit_write','obligation_write','project_card_write','volume_write','team_record_write','document_write'));

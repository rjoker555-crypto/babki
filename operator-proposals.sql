alter table public.commercial_proposals add column if not exists letter_storage_bucket text not null default 'project-documents' check(letter_storage_bucket in ('project-documents','agent-files'));
alter table voltmaster_private.document_cleanup_jobs add column if not exists domain text not null default 'document' check(domain in ('document','proposal'));
create or replace function voltmaster_private.guard_proposal_cleanup_path() returns trigger language plpgsql security definer set search_path='' as $$
begin if exists(select 1 from voltmaster_private.document_cleanup_jobs j,jsonb_array_elements(j.items) x where j.status='pending' and x->>'bucket'=new.letter_storage_bucket and x->>'path'=new.letter_file_path and (x->>'remove_allowed')::boolean) then raise exception 'File pending deletion';end if;return new;end $$;
revoke all on function voltmaster_private.guard_proposal_cleanup_path() from public,anon,authenticated;
drop trigger if exists guard_proposal_cleanup_path on public.commercial_proposals;
create trigger guard_proposal_cleanup_path before insert or update on public.commercial_proposals for each row execute function voltmaster_private.guard_proposal_cleanup_path();
create or replace function voltmaster_private.proposal_command(p_owner uuid,p_request uuid,p_command jsonb,p_preview boolean default false) returns jsonb language plpgsql set search_path='' as $$
declare act text:=p_command->>'action';v jsonb:=coalesce(p_command->'values','{}');actor text;old public.commercial_proposals;c public.commercial_proposals;asset public.agent_file_assets;source jsonb;object_row jsonb;files jsonb:='[]';result jsonb;stored jsonb;
begin
 select role into actor from public.profiles where id=p_owner and is_active;
 if actor is null or actor not in ('director','finance','accountant','manager') or act='delete' and actor='manager' then raise exception 'Proposal write access denied';end if;
 if p_request is null or act is null or act not in ('create','update','delete') or jsonb_typeof(p_command)<>'object' or exists(select 1 from jsonb_object_keys(p_command) x where x not in ('action','id','expected','values','file_id','uploaded_file','remove_letter')) or jsonb_typeof(v) is distinct from 'object' or exists(select 1 from jsonb_object_keys(v) x where x not in ('name','city','customer','amount','status','segment','source','sent_date','expected_review_date','review_deadline','lost_reason','comment')) then raise exception 'Invalid proposal command';end if;
 perform pg_advisory_xact_lock(hashtextextended('voltmaster.financial.commands',0));
 if not p_preview then select result_json,command_json into result,stored from voltmaster_private.financial_command_receipts where owner_id=p_owner and request_id=p_request;if found then if stored is distinct from p_command then raise exception 'Request reused with different command';end if;return result;end if;end if;
 if act='create' then if p_command ? 'id' or p_command ? 'expected' then raise exception 'Create cannot set identity';end if;c.amount:=0;c.status:='review';c.segment:='commercial';c.letter_storage_bucket:='project-documents';
 else select * into old from public.commercial_proposals where id=(p_command->>'id')::uuid for update;if old.id is null or to_jsonb(old) is distinct from p_command->'expected' then raise exception 'Record changed; create a new approval';end if;c:=old;end if;
 c:=jsonb_populate_record(c,v);
 if act='delete' then if v<>'{}' or p_command ? 'file_id' or p_command ? 'uploaded_file' or p_command ? 'remove_letter' then raise exception 'Delete cannot change proposal';end if;
 elsif nullif(btrim(c.name),'') is null or length(c.name)>500 or c.amount is null or c.amount<0 or c.amount::text in ('NaN','Infinity','-Infinity') or c.amount<>round(c.amount,2) or c.status is null or c.status not in ('review','won','lost') or c.segment is null or c.segment not in ('commercial','government') or c.status='lost' and nullif(btrim(c.lost_reason),'') is null or c.expected_review_date>c.review_deadline then raise exception 'Invalid proposal values';end if;
 if act<>'delete' and (p_command ? 'file_id' or p_command ? 'uploaded_file') then
  if num_nonnulls(nullif(p_command->>'file_id',''),nullif(p_command->>'uploaded_file','null'))<>1 or coalesce((p_command->>'remove_letter')::boolean,false) then raise exception 'Choose one prepared letter';end if;
  if p_command ? 'file_id' then select * into asset from public.agent_file_assets where id=(p_command->>'file_id')::uuid and owner_id=p_owner;if not found then raise exception 'Own prepared letter required';end if;source:=to_jsonb(asset);c.letter_storage_bucket:='agent-files';c.letter_file_path:=asset.storage_path;c.letter_file_name:=asset.file_name;
  else source:=p_command->'uploaded_file';if jsonb_typeof(source) is distinct from 'object' or exists(select 1 from jsonb_object_keys(source) x where x not in ('storage_bucket','file_path','file_name','mime_type','file_size')) or source->>'storage_bucket' is distinct from 'project-documents' or split_part(source->>'file_path','/',1)<>'kps' then raise exception 'Own uploaded proposal letter required';end if;c.letter_storage_bucket:='project-documents';c.letter_file_path:=source->>'file_path';c.letter_file_name:=source->>'file_name';end if;
  if c.letter_file_path is null or length(c.letter_file_path)>2048 or c.letter_file_path ~ E'(^|/)(\\.\\.?)(/|$)|\\\\|[[:cntrl:]]' or nullif(btrim(c.letter_file_name),'') is null then raise exception 'Invalid letter path';end if;
  select to_jsonb(x) into object_row from storage.objects x where bucket_id=c.letter_storage_bucket and name=c.letter_file_path;
  if object_row is null or asset.id is null and object_row->>'owner_id' is distinct from p_owner::text or (object_row->'metadata'->>'size')::bigint is distinct from coalesce(asset.file_size,(source->>'file_size')::bigint) then raise exception 'Prepared letter missing/changed';end if;
 elsif act<>'delete' and coalesce((p_command->>'remove_letter')::boolean,false) then c.letter_file_path:=null;c.letter_file_name:=null;end if;
 if old.letter_file_path is not null and (act='delete' or old.letter_file_path is distinct from c.letter_file_path or old.letter_storage_bucket is distinct from c.letter_storage_bucket) then
  files:=jsonb_build_array(jsonb_build_object('bucket',old.letter_storage_bucket,'path',old.letter_file_path,'remove_allowed',not(
   exists(select 1 from public.commercial_proposals where id<>old.id and letter_storage_bucket=old.letter_storage_bucket and letter_file_path=old.letter_file_path)
   or exists(select 1 from public.project_documents where storage_bucket=old.letter_storage_bucket and file_path=old.letter_file_path)
   or exists(select 1 from public.project_document_versions where storage_bucket=old.letter_storage_bucket and file_path=old.letter_file_path)
   or old.letter_storage_bucket='agent-files' and exists(select 1 from public.agent_file_assets where storage_path=old.letter_file_path))));
 end if;
 if p_preview then return jsonb_build_object('before',case when old.id is null then null else to_jsonb(old) end,'proposal',to_jsonb(c),'source',source,'storage_object',object_row,'files',files);end if;
 perform set_config('request.jwt.claim.sub',p_owner::text,true);
 if files<>'[]' then insert into voltmaster_private.document_cleanup_jobs(owner_id,request_id,document_id,items,domain) values(p_owner,p_request,old.id,files,'proposal');end if;
 if act='create' then insert into public.commercial_proposals(name,city,customer,amount,status,segment,source,sent_date,expected_review_date,review_deadline,lost_reason,comment,letter_file_path,letter_file_name,letter_storage_bucket,created_by) values(c.name,c.city,c.customer,c.amount,c.status,c.segment,c.source,c.sent_date,c.expected_review_date,c.review_deadline,c.lost_reason,c.comment,c.letter_file_path,c.letter_file_name,c.letter_storage_bucket,p_owner) returning * into c;
 elsif act='update' then update public.commercial_proposals set name=c.name,city=c.city,customer=c.customer,amount=c.amount,status=c.status,segment=c.segment,source=c.source,sent_date=c.sent_date,expected_review_date=c.expected_review_date,review_deadline=c.review_deadline,lost_reason=c.lost_reason,comment=c.comment,letter_file_path=c.letter_file_path,letter_file_name=c.letter_file_name,letter_storage_bucket=c.letter_storage_bucket,updated_at=now() where id=c.id returning * into c;
 else delete from public.commercial_proposals where id=c.id;end if;
 result:=jsonb_build_object('status','completed','action',act,'proposal',to_jsonb(c),'verified',case when act='delete' then not exists(select 1 from public.commercial_proposals where id=c.id) else exists(select 1 from public.commercial_proposals where id=c.id and updated_at=c.updated_at) end,'file_cleanup_pending',files<>'[]','cleanup_request_id',case when files<>'[]' then p_request else null end);
 if result->>'verified'<>'true' then raise exception 'Proposal verification failed';end if;
 insert into voltmaster_private.financial_command_receipts values(p_owner,p_request,p_command,result,now());return result;
end $$;
revoke all on function voltmaster_private.proposal_command(uuid,uuid,jsonb,boolean) from public,anon,authenticated;
create or replace function public.execute_proposal_command(p_request uuid,p_command jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin if auth.uid() is null then raise exception 'Authentication required';end if;return voltmaster_private.proposal_command(auth.uid(),p_request,p_command,false);end $$;
revoke all on function public.execute_proposal_command(uuid,jsonb) from public,anon;
grant execute on function public.execute_proposal_command(uuid,jsonb) to authenticated;

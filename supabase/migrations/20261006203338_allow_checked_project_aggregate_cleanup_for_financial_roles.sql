alter table voltmaster_private.document_cleanup_jobs drop constraint document_cleanup_jobs_domain_check;alter table voltmaster_private.document_cleanup_jobs add constraint document_cleanup_jobs_domain_check check(domain in('document','proposal','project'));
CREATE OR REPLACE FUNCTION public.agent_document_cleanup(p_owner uuid, p_request uuid, p_outcomes jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare job voltmaster_private.document_cleanup_jobs;
begin
 select * into job from voltmaster_private.document_cleanup_jobs where owner_id=p_owner and request_id=p_request for update;if not found then raise exception 'Own document cleanup job required';end if;
 if not exists(select 1 from public.profiles where id=p_owner and is_active and (role in ('director','manager') or job.domain in ('proposal','project') and role in ('finance','accountant'))) then raise exception 'Document access denied';end if;
 if p_outcomes is not null then
  if jsonb_typeof(p_outcomes)<>'array' or jsonb_array_length(p_outcomes)<>jsonb_array_length(job.items) or exists(select 1 from jsonb_array_elements(job.items) x where not exists(select 1 from jsonb_array_elements(p_outcomes) y where x->>'bucket'=y->>'bucket' and x->>'path'=y->>'path' and (y->>'status'='removed' and (x->>'remove_allowed')::boolean or y->>'status'='retained' and not(x->>'remove_allowed')::boolean))) then raise exception 'Incomplete cleanup outcomes';end if;
  update voltmaster_private.document_cleanup_jobs set status='completed',outcomes=p_outcomes where owner_id=p_owner and request_id=p_request returning * into job;
 end if;return jsonb_build_object('status',job.status,'items',job.items,'outcomes',job.outcomes);
end $function$
;

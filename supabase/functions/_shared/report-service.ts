import { renderExistingReport } from './report-renderers.js';
import { storage,rest,sha256 } from './http.ts';
export async function buildExistingReport(args,ctx,actor){
 const date=value=>/^\d{4}-\d{2}-\d{2}$/.test(value||'')&&new Date(value+'T00:00:00Z').toISOString().slice(0,10)===value;
 if(args.kind==='production'&&(!date(args.from)||!date(args.to)||args.from>args.to))throw new Error('Укажите точный период производственного отчёта.');
 if(args.kind==='organization_month'&&!/^\d{4}-(0[1-9]|1[0-2])$/.test(args.month||''))throw new Error('Укажите месяц отчёта YYYY-MM.');
 const job=await ctx.db('rpc/agent_claim_report',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_request:ctx.message,p_kind:args.kind,p_args:args})},true);
 async function signed(asset){const body=await(await storage('object/sign/operator-reports/'+asset.file_path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({expiresIn:60})})).json();return {report_id:asset.id,kind:asset.kind,url:Deno.env.get('SUPABASE_URL')+'/storage/v1'+body.signedURL,file_name:asset.file_name,mime_type:asset.kind==='statement_text'?'text/plain':'text/html',sha256:asset.sha256,file_size:asset.file_size,verified:true,format:asset.kind==='statement_text'?'TXT существующей выписки':'HTML существующего отчёта; откройте файл и используйте печать / сохранить в PDF',expires_in_seconds:60};}
 if(job.status==='completed')return signed(job);
 const data=await ctx.db('rpc/get_existing_report_data',{method:'POST',body:JSON.stringify({p_kind:args.kind==='statement_text'?'statement':args.kind,p_project:args.project_id})});
 const html=renderExistingReport(args.kind,data,args),bytes=new TextEncoder().encode(html);if(bytes.length>1500000)throw new Error('Отчёт превышает 1.5 МБ; сузьте выборку.');
 const extension=args.kind==='statement_text'?'.txt':'.html',mime=args.kind==='statement_text'?'text/plain':'text/html',path=ctx.owner+'/'+job.id+extension,hash=await sha256(bytes);
 try{await storage('object/operator-reports/'+path,{method:'POST',headers:{'Content-Type':mime,'x-upsert':'false'},body:bytes});}
 catch(error){const old=new Uint8Array(await(await storage('object/operator-reports/'+path)).arrayBuffer());if(await sha256(old)!==hash)throw new Error('Файл предыдущей попытки отличается. Создайте новый запрос отчёта.');}
 const assets=await rest('agent_report_assets?id=eq.'+job.id+'&owner_id=eq.'+ctx.owner,{method:'PATCH',body:JSON.stringify({status:'completed',file_path:path,file_name:args.kind+'-'+job.id+extension,file_size:bytes.length,sha256:hash})});
 if(assets.length!==1||assets[0].sha256!==hash)throw new Error('Report metadata verification failed');return signed(assets[0]);
}

export async function getExistingFinancialMetrics(args,ctx){
 const data=await ctx.db('rpc/get_existing_report_data',{method:'POST',body:JSON.stringify({p_kind:'financial_metrics',p_project:args.project_id})});
 return {...renderExistingReport('financial_metrics',data,args),cash:await ctx.db('rpc/agent_cash_summary',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_project:args.project_id})},true),verified:true};
}

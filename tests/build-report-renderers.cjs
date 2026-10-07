const fs=require('fs'),source=fs.readFileSync('index.html','utf8'),matches=[...source.matchAll(/^(?:async )?function\s+(\w+)\(/gm)],map=new Map(matches.map((m,i)=>[m[1],source.slice(m.index,matches[i+1]?.index??source.length).trim()]));
const roots=['buildStatementReportHtml','exportOrgMonthPdf','printWorkReport','exportProposalsPdf','projectStats','vatHistoryData','buildStatementText','taxQuarterKey'],names=new Set(roots);let changed=true;
while(changed){changed=false;for(const name of [...names])for(const [candidate] of map)if(!names.has(candidate)&&new RegExp('\\b'+candidate+'\\s*\\(').test(map.get(name))){names.add(candidate);changed=true;}}
const helpers=['esc','money'].map(name=>{const m=source.match(new RegExp('^const '+name+'=[\\s\\S]*?;\\r?\\n','m'));if(!m)throw Error('Missing '+name);return m[0]});
const css=source.match(/<style>([\s\S]*?)<\/style>/)[1];
const pre=`// Generated from actual manual report functions. Regenerate after shared formula changes.
export function renderExistingReport(kind,data,args){
 const Date=class extends globalThis.Date{toLocaleDateString(locale,options){return super.toLocaleDateString(locale,{timeZone:'Asia/Krasnoyarsk',...options});}toLocaleString(locale,options){return super.toLocaleString(locale,{timeZone:'Asia/Krasnoyarsk',...options});}};
 const {projects=[],ops=[],ars=[],aps=[],subcontractors=[],projectMaterials=[],projectOtherExpenses=[],orgEmployees=[],orgExpenses=[],events=[],ptoDocuments=[],ptoContacts=[],projectWorkItems=[],projectWorkMaterials=[],projectWorkProgress=[],projectWorkSections=[],projectPriceHistory=[],workVolumeSubmissions=[],workVolumeSubmissionItems=[],proposals=[]}=data;
 let captured='',currentWorkProjectId=args.project_id,currentStatementProjectName='',taxVatPeriod=null,taxIpPeriod=null;
 const values={orgMonth:args.month,orgCompanyFilter:args.company||'all',workReportFrom:args.from,workReportTo:args.to};
 const $=id=>({value:values[id]||'',innerHTML:'',textContent:''});
 const alert=message=>{throw new Error(message);};
 const window={open:()=>({document:{open(){},write(html){captured+=html},close(){}},focus(){},print(){}})};
 const setTimeout=fn=>{fn();return 0;};
 const document={querySelector:()=>({innerHTML:${JSON.stringify(css)}})};
`;
const end=`
 if(kind==='statement_text')return buildStatementText(args.project_id);
 if(kind==='financial_metrics')return {project:projects.find(p=>p.id===args.project_id),card:projectStats(args.project_id),vat_registers:[...new Set(ops.map(o=>taxQuarterKey(o.operation_date)).filter(Boolean))].sort().map(period=>({period,...vatHistoryData(period)})),method:'existing_manual_projectStats_vatHistoryData'};
 if(kind==='statement')captured='<!doctype html><html><head><meta charset="utf-8"><title>Выписка</title><style>'+document.querySelector('style').innerHTML+'</style></head><body>'+buildStatementReportHtml(args.project_id)+'</body></html>';
 else if(kind==='organization_month')exportOrgMonthPdf();else if(kind==='production')printWorkReport();else if(kind==='proposals')exportProposalsPdf();else throw new Error('Unknown existing report');
 if(!captured||captured.length>1500000)throw new Error('Report empty/too large');
 return captured.replace(/<script\\b[^>]*>[\\s\\S]*?<\\/script>/gi,'').replace('<head>',${JSON.stringify('<head><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'; img-src data:; base-uri \'none\'; form-action \'none\'">')});
}
`;
fs.writeFileSync('supabase/functions/_shared/report-renderers.js',pre+helpers.join('\n')+'\n'+[...names].map(n=>map.get(n)).join('\n')+end);
fs.copyFileSync('supabase/functions/_shared/report-renderers.js','report-renderers.js');
fs.writeFileSync('tests/artifacts/report-renderer-functions.json',JSON.stringify([...names]));console.log(JSON.stringify({functions:names.size,names:[...names]}));

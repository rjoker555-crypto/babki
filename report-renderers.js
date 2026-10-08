// Generated from actual manual report functions. Regenerate after shared formula changes.
export function renderExistingReport(kind,data,args){
 const Date=class extends globalThis.Date{toLocaleDateString(locale,options){return super.toLocaleDateString(locale,{timeZone:'Asia/Krasnoyarsk',...options});}toLocaleString(locale,options){return super.toLocaleString(locale,{timeZone:'Asia/Krasnoyarsk',...options});}};
 const {projects=[],ops=[],ars=[],aps=[],subcontractors=[],projectMaterials=[],projectOtherExpenses=[],orgEmployees=[],orgExpenses=[],events=[],ptoDocuments=[],ptoContacts=[],projectWorkItems=[],projectWorkMaterials=[],projectWorkProgress=[],projectWorkSections=[],projectPriceHistory=[],workVolumeSubmissions=[],workVolumeSubmissionItems=[],proposals=[]}=data;
 let captured='',currentWorkProjectId=args.project_id,currentStatementProjectName='',taxVatPeriod=null,taxIpPeriod=null;
 const values={orgMonth:args.month,orgCompanyFilter:args.company||'all',workReportFrom:args.from,workReportTo:args.to};
 const $=id=>({value:values[id]||'',innerHTML:'',textContent:''});
 const alert=message=>{throw new Error(message);};
 const window={open:()=>({document:{open(){},write(html){captured+=html},close(){}},focus(){},print(){}})};
 const setTimeout=fn=>{fn();return 0;};
 const document={querySelector:()=>({innerHTML:"\r\n:root{\r\n--navy:#0e2a44;\r\n--navy-dk:#0a1f33;\r\n--amber:#e8a324;\r\n--amber-dk:#c8890f;\r\n--copper:#b5651d;\r\n--wire:#5b6b7d;\r\n--bg:#f3f5f8;\r\n--card:#ffffff;\r\n--line:#e3e8ef;\r\n--green:#1a8a4a;\r\n--red:#d5393c;\r\n--orange:#d47b00;\r\n--blue:#1e65b7;\r\n}\r\n*{box-sizing:border-box}\r\nbody{margin:0;font-family:-apple-system,BlinkMacSystemFont,\"Segoe UI\",sans-serif;background:var(--bg);color:#172033;-webkit-text-size-adjust:100%}\r\n.app{max-width:760px;margin:auto;min-height:100vh;padding-bottom:96px;width:100%}\r\n.top{padding:24px 18px 12px;position:relative}\r\n.top h1{margin:0;font-size:26px;letter-spacing:.2px;color:var(--navy)}\r\n.top h1:before{content:\"\";display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--amber);margin-right:9px;box-shadow:0 0 0 3px #e8a32422;vertical-align:middle}\r\n.muted{color:#738096;font-size:14px}\r\n.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px;padding:0 14px}\r\n.card{background:var(--card);border-radius:16px;padding:16px;box-shadow:0 2px 12px #1720330d;border:1px solid var(--line)}\r\n.metric{position:relative;overflow:hidden}\r\n.metric:before{content:\"\";position:absolute;left:0;top:0;bottom:0;width:4px;background:var(--amber)}\r\n.metric .label{font-size:12.5px;color:#738096;text-transform:uppercase;letter-spacing:.4px}\r\n.metric .value{font-size:19px;font-weight:750;margin-top:7px;word-break:break-word}\r\n.green{color:var(--green)}\r\n.red{color:var(--red)}\r\n.orange{color:var(--orange)}\r\n.blue{color:var(--blue)}\r\n.section{padding:18px 14px 0;max-width:100%}\r\n.section h2{font-size:17px;margin:0 0 10px;color:var(--navy);display:flex;align-items:center;gap:8px}\r\n.section h2:before{content:\"\";width:14px;height:2px;background:var(--amber)}\r\n.wide{margin:0 14px}\r\n.row{display:flex;justify-content:space-between;gap:12px;align-items:center;flex-wrap:wrap}\r\n.action{padding:14px 0;border-bottom:1px solid #edf0f4}\r\n.action:last-child{border:0}\r\n.icon{width:40px;height:40px;border-radius:12px;background:#0e2a4412;display:grid;place-items:center;font-size:19px;flex-shrink:0}\r\n.nav{position:fixed;bottom:0;left:0;right:0;background:#fff;border-top:1px solid #e7ebf0;display:flex;justify-content:center;z-index:5;padding-bottom:env(safe-area-inset-bottom,0)}\r\n.navin{max-width:760px;width:100%;display:grid;grid-template-columns:repeat(7,1fr)}\r\n#obligationForm label{display:block;margin:14px 0;font-weight:700}\r\n#obligationForm input:not([type=checkbox]),#obligationForm select,#obligationForm textarea{display:block;width:100%;box-sizing:border-box;margin-top:6px;padding:10px;border:1px solid #dce2ea;border-radius:9px;background:#fff;color:var(--navy);font:inherit;font-weight:400}\r\n#obligationForm textarea{min-height:90px;resize:vertical}\r\n#obligationForm button{padding:12px;border:0;border-radius:10px;font-weight:700;width:100%}\r\n#obligationModal h3{margin:20px 0 10px}\r\n.userbar{flex-wrap:wrap}\r\n.nav button{border:0;background:transparent;padding:10px 2px 12px;color:#718096;font-size:10.5px}\r\n.nav button.active{color:var(--navy);font-weight:700}\r\n.nav button.active span{color:var(--amber-dk)}\r\n.nav span{display:block;font-size:20px;margin-bottom:3px}\r\n.page{display:none}\r\n.page.active{display:block}\r\n.fab{position:fixed;right:16px;bottom:calc(78px + env(safe-area-inset-bottom,0));border:0;border-radius:16px;background:var(--navy);color:white;padding:14px 18px;font-weight:700;box-shadow:0 8px 25px #0e2a4450;z-index:4}\r\n.list{padding:0 14px;max-width:100%}\r\n.item{background:var(--card);border-radius:14px;padding:14px;margin-bottom:9px;border:1px solid var(--line);max-width:100%;overflow:hidden}\r\n.project-compact{padding:0}.project-compact>summary{list-style:none;cursor:pointer;padding:13px 14px}.project-compact>summary::-webkit-details-marker{display:none}.project-compact .compact-name{font-size:16px;font-weight:900;color:#0e2a44;letter-spacing:.15px}.project-compact .compact-body{padding:0 14px 14px}.filter-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}.filter-grid input,.filter-grid select{width:100%;padding:11px;border:1px solid #dce2ea;border-radius:10px;background:#fff;font-size:14px}.proposal-stats{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}.proposal-stat{background:#f5f7fa;border:1px solid var(--line);border-radius:12px;padding:10px}.proposal-stat b{font-size:19px;display:block}.proposal-form-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}.proposal-form-grid input,.proposal-form-grid select,.proposal-form-grid textarea{width:100%;padding:11px;border:1px solid #dce2ea;border-radius:10px;font-size:14px;background:white}.proposal-form-grid .full{grid-column:1/-1}\r\n@media(max-width:420px){.filter-grid,.proposal-form-grid{grid-template-columns:1fr}}\r\n.pill{display:inline-block;padding:5px 9px;border-radius:20px;background:#eef3f8;font-size:12px;max-width:100%;overflow:hidden;text-overflow:ellipsis}\r\n.pill.tag-red{background:#fdeceb;color:var(--red)}\r\n.pill.tag-orange{background:#fdf1de;color:var(--orange)}\r\n.pill.tag-green{background:#e8f5ed;color:var(--green)}\r\n.pill.tag-blue{background:#e9f1fb;color:var(--blue)}\r\n.amount{font-weight:800;font-size:17px}\r\n.modal{position:fixed;inset:0;background:#0006;display:none;align-items:flex-end;z-index:10}\r\n.modal.open{display:flex}\r\n.sheet{background:#fff;border-radius:20px 20px 0 0;width:100%;max-height:92vh;overflow:auto;padding:20px;padding-bottom:calc(20px + env(safe-area-inset-bottom,0))}\r\n.sheet h2{margin:0 0 16px;color:var(--navy)}\r\n.field{margin-bottom:12px;max-width:100%}\r\n.field label{display:block;font-size:13px;color:#738096;margin-bottom:5px}\r\n.field input,.field select{width:100%;padding:13px;border:1px solid #dce2ea;border-radius:12px;font-size:16px;background:#fff;max-width:100%}\r\n.btn{width:100%;border:0;border-radius:13px;padding:14px;font-size:16px;font-weight:700}\r\n.primary{background:var(--navy);color:#fff}\r\n.secondary{background:#edf1f5;color:#172033;margin-top:8px}\r\n.empty{padding:25px;text-align:center;color:#738096}\r\n.auth{min-height:100vh;display:grid;place-items:center;padding:20px}\r\n.auth-card{width:min(430px,100%);background:#fff;border-radius:24px;padding:24px;box-shadow:0 10px 40px #17203314;border-top:4px solid var(--amber)}\r\n.auth-card h1{margin:0 0 6px;font-size:26px;color:var(--navy)}\r\n.auth-card .field{margin-top:18px}\r\n.auth-error{background:#fff0f0;color:#b42318;padding:12px;border-radius:12px;font-size:14px;margin:12px 0;display:none}\r\n.userbar{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:10px 14px;flex-wrap:wrap}\r\n.smallbtn{border:0;background:#edf1f5;border-radius:10px;padding:8px 10px;font-size:13px}\r\n.status{font-size:12px;color:#738096;margin-top:5px}\r\n.logout{white-space:nowrap}\r\n.progress{height:9px;background:#edf1f5;border-radius:10px;overflow:hidden;margin-top:8px;position:relative}\r\n.progress>div{height:100%;background:var(--navy);border-radius:10px;transition:width .3s}\r\n.progress>div.p-green{background:var(--green)}\r\n.progress>div.p-orange{background:var(--orange)}\r\n.progress>div.p-red{background:var(--red)}\r\n.progress>div.p-blue{background:var(--blue)}\r\n.progress-label{display:flex;justify-content:space-between;align-items:center;margin-top:5px;gap:8px;flex-wrap:wrap}\r\n.status-tag{font-size:11.5px;font-weight:700;padding:2px 8px;border-radius:20px;white-space:nowrap}\r\n.status-tag.p-green{background:#e8f5ed;color:var(--green)}\r\n.status-tag.p-orange{background:#fdf1de;color:var(--orange)}\r\n.status-tag.p-red{background:#fdeceb;color:var(--red)}\r\n.status-tag.p-blue{background:#e9f1fb;color:var(--blue)}\r\n.subrow{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:10px;border:1px dashed #d7dee8;border-radius:12px;margin-bottom:8px;background:#fafbfd}\r\n.subrow .subname{font-weight:600;word-break:break-word}\r\n.subrow .subactions{display:flex;gap:6px;flex-shrink:0}\r\n.subrow .subactions button{border:0;background:#edf1f5;border-radius:8px;padding:6px 9px;font-size:12px}\r\n.sub-add{display:flex;flex-direction:column;gap:8px;margin-top:6px;padding:12px;background:#f6f8fb;border-radius:12px;border:1px solid var(--line)}\r\n.sub-add-row{display:flex;gap:8px}\r\n.sub-add-row input{flex:1;min-width:0;padding:11px;border:1px solid #dce2ea;border-radius:10px;font-size:15px}\r\n.sub-add button{border:0;background:var(--navy);color:#fff;border-radius:10px;padding:11px;font-weight:700;font-size:14px}\r\n.sub-total{font-size:13px;color:#495a70;margin-top:6px;padding-top:6px;border-top:1px dashed #d7dee8}\r\n.event-item{background:var(--card);border-radius:14px;padding:13px;margin-bottom:8px;border:1px solid var(--line);border-left:4px solid var(--wire)}\r\n.event-item.upcoming{border-left-color:var(--amber)}\r\n.event-item.overdue{border-left-color:var(--red)}\r\n.pto-tab{border:1px solid #dce2ea;background:#f6f8fb;color:var(--navy);border-radius:11px;padding:10px 13px;font-weight:800;font-size:13px;cursor:pointer}\r\n.pto-tabbar{display:flex;gap:6px;margin-top:14px;padding:4px;background:#f3f6fa;border:1px solid var(--line);border-radius:12px}\r\n.pto-tabbar button{flex:1;border:0;background:transparent;color:var(--muted);border-radius:9px;padding:9px 10px;font-weight:800;font-size:12px;cursor:pointer}\r\n.pto-tabbar button.active{background:#fff;color:var(--navy);box-shadow:0 1px 4px rgba(0,0,0,.08)}\r\n.pto-score{display:inline-flex;align-items:center;gap:6px;padding:5px 9px;border-radius:999px;font-size:12px;font-weight:900;white-space:nowrap}\r\n.pto-score.s1{background:#fdeceb;color:var(--red)}\r\n.pto-score.s2{background:#fff3d9;color:#b56a00}\r\n.pto-score.s3{background:#fff3d9;color:#a85d00}\r\n.pto-score.s4{background:#e9f1fb;color:var(--blue)}\r\n.pto-score.s5{background:#e8f5ed;color:var(--green)}\r\n.pto-tab:hover{background:#edf2f7}\r\n.pto-head{padding:12px;border:1px solid var(--line);border-radius:14px;background:#f8fafc;margin-bottom:10px}\r\n.pto-doc{background:#fff;border:1px solid var(--line);border-radius:14px;padding:13px;margin-bottom:9px}\r\n.pto-status{display:inline-flex;align-items:center;gap:5px;padding:5px 9px;border-radius:20px;font-size:12px;font-weight:800}\r\n.pto-status.requested{background:#fdeceb;color:var(--red)}\r\n.pto-status.in_progress{background:#fff3d9;color:#b56a00}\r\n.pto-status.signing{background:#e9f1fb;color:var(--blue)}\r\n.pto-status.signed{background:#e8f5ed;color:var(--green)}\r\n.pto-progress.requested{background:var(--red)}\r\n.pto-progress.in_progress{background:#d89a16}\r\n.pto-progress.signing{background:var(--blue)}\r\n.pto-progress.signed{background:var(--green)}\r\n.pto-contact{display:flex;justify-content:space-between;gap:10px;align-items:flex-start;padding:10px;border:1px dashed #d7dee8;border-radius:12px;margin-bottom:8px;background:#fafbfd}\r\n.pto-contact-actions{display:flex;gap:6px;flex-shrink:0}\r\n.pto-contact-actions button{border:0;background:#edf1f5;border-radius:8px;padding:6px 9px;font-size:12px}\r\n\r\n\r\n.work-section-card{padding:12px;border:1px solid var(--line);border-radius:14px;background:#fff;margin-bottom:10px}\r\n.work-section-head{display:flex;justify-content:space-between;gap:10px;align-items:flex-start}\r\n.work-section-title{font-weight:900;color:var(--navy)}\r\n.work-calendar{border:1px solid var(--line);border-radius:14px;background:#fff;overflow:hidden}\r\n.work-calendar-head{display:grid;grid-template-columns:repeat(7,1fr);background:#f4f7fa;border-bottom:1px solid var(--line)}\r\n.work-calendar-head div{padding:8px 4px;text-align:center;font-size:11px;font-weight:800;color:var(--muted)}\r\n.work-calendar-grid{display:grid;grid-template-columns:repeat(7,1fr)}\r\n.work-calendar-day{min-height:72px;border-right:1px solid #edf0f4;border-bottom:1px solid #edf0f4;padding:6px;cursor:pointer;background:#fff}\r\n.work-calendar-day:nth-child(7n){border-right:0}.work-calendar-day.muted-day{background:#fafbfd;color:#a2adbc}.work-calendar-day.today{box-shadow:inset 0 0 0 2px #b7c9df}.work-calendar-day.selected{background:#eef4fb;box-shadow:inset 0 0 0 2px var(--blue)}\r\n.work-calendar-num{font-weight:800;font-size:12px}.work-calendar-dot{display:block;margin-top:4px;font-size:10px;line-height:1.25;padding:2px 4px;border-radius:5px;background:#eef2f6;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}\r\n.work-calendar-detail{margin-top:9px;padding:11px;border:1px solid var(--line);border-radius:12px;background:#f8fafc}\r\n.work-task{padding:10px;border:1px solid var(--line);border-radius:12px;background:#fff;margin-bottom:8px}.work-task.done{opacity:.65}.work-task-actions{display:flex;gap:6px;flex-wrap:wrap;margin-top:7px}\r\n.work-date-progress{position:absolute;top:0;bottom:0;width:2px;background:#d64545;z-index:3}.work-date-progress:after{content:'Сегодня';position:absolute;top:2px;left:4px;font-size:9px;font-weight:800;color:#b42318;white-space:nowrap}\r\n.work-bar-track{position:absolute;top:18px;height:26px;border-radius:8px;background:#e9edf3;overflow:hidden;left:0;right:0}\r\n.work-bar-plan{position:absolute;top:0;height:100%;border-radius:8px;background:#dfe8f3}.work-bar-fact{position:absolute;top:0;height:100%;border-radius:8px;background:var(--blue);opacity:.9}\r\n.work-bar-label{position:absolute;top:5px;left:8px;right:8px;color:#172033;font-size:10px;font-weight:800;z-index:4;white-space:nowrap;overflow:hidden}\r\n@media(max-width:650px){.work-calendar-day{min-height:60px;padding:4px}.work-calendar-dot{font-size:9px}.work-calendar-head div{font-size:10px}}\r\n.work-tabbar{display:flex;gap:6px;margin-top:14px;padding:4px;background:#f3f6fa;border:1px solid var(--line);border-radius:12px}\r\n.work-tabbar button{flex:1;border:0;background:transparent;color:var(--muted);border-radius:9px;padding:9px 10px;font-weight:800;font-size:12px;cursor:pointer}\r\n.work-tabbar button.active{background:#fff;color:var(--navy);box-shadow:0 1px 4px rgba(0,0,0,.08)}\r\n.work-summary{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;margin-bottom:12px}\r\n.work-kpi{padding:10px;border:1px solid var(--line);border-radius:12px;background:#f8fafc}\r\n.work-kpi b{font-size:18px}\r\n.work-gantt{border:1px solid var(--line);border-radius:14px;background:#fff;overflow:auto}\r\n.work-gantt-row{display:grid;grid-template-columns:minmax(190px,28%) minmax(420px,1fr);border-bottom:1px solid #edf0f4;min-height:62px}\r\n.work-gantt-name{padding:10px;border-right:1px solid #edf0f4}\r\n.work-gantt-track{position:relative;min-height:62px;background:repeating-linear-gradient(90deg,#fff 0,#fff calc(10% - 1px),#edf0f4 calc(10% - 1px),#edf0f4 10%)}\r\n.work-bar{position:absolute;top:18px;height:26px;border-radius:8px;padding:5px 8px;color:#fff;font-size:11px;font-weight:800;overflow:hidden;white-space:nowrap;box-sizing:border-box}\r\n.work-bar.planned{background:var(--blue)}\r\n.work-bar.in_progress{background:var(--amber)}\r\n.work-bar.completed{background:var(--green)}\r\n.work-item{padding:12px;border:1px solid var(--line);border-radius:14px;background:#fff;margin-bottom:9px}\r\n.work-material-row{display:grid;grid-template-columns:minmax(0,1fr) 110px 70px auto;gap:7px;align-items:center;margin-bottom:7px}\r\n.work-material-row select,.work-material-row input{width:100%;min-width:0}\r\n.work-report-note{padding:10px;border-radius:10px;background:#f8fafc;border:1px solid var(--line);font-size:12px;color:var(--muted)}\r\n@media(max-width:650px){.work-summary{grid-template-columns:1fr 1fr}.work-gantt-row{grid-template-columns:minmax(150px,38%) minmax(380px,1fr)}.work-material-row{grid-template-columns:minmax(0,1fr) 90px 55px auto}}\r\n.statement-pre{white-space:pre-wrap;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12.5px;line-height:1.55;background:#f6f8fb;border-radius:12px;padding:14px;border:1px solid var(--line);margin-bottom:14px;max-height:60vh;overflow:auto}\r\ndetails summary::-webkit-details-marker{color:var(--amber-dk)}\r\ndetails summary{list-style:revert;padding:4px 0}\r\n.scroll-x{overflow-x:auto;max-width:100%;-webkit-overflow-scrolling:touch}\r\n@media(min-width:700px){\r\n.nav{bottom:12px;background:transparent;border:0}\r\n.navin{background:#fff;border:1px solid #e7ebf0;border-radius:18px;box-shadow:0 8px 30px #17203312}\r\n.fab{right:calc(50% - 350px)}\r\n}\r\n@media(max-width:480px){\r\n.top{padding:18px 14px 10px}\r\n.top h1{font-size:22px}\r\n.grid{gap:8px;padding:0 12px}\r\n.section{padding:14px 12px 0}\r\n.list{padding:0 12px}\r\n.wide{margin:0 12px}\r\n.card{padding:13px;border-radius:14px}\r\n.sheet{padding:16px;border-radius:16px 16px 0 0}\r\n.btn{padding:13px;font-size:15px}\r\n.field input,.field select{padding:12px;font-size:16px}\r\n.metric .value{font-size:17px}\r\n.amount{font-size:15px}\r\n.sub-add-row{flex-direction:column}\r\n.userbar{padding:10px 12px}\r\n}\r\n\r\n/* PDF statement */\r\n.statement-pre{max-height:65vh;overflow:auto}.pdf-report{font-family:Arial,sans-serif;background:#fff;color:#172033;padding:4px;max-width:900px;margin:0 auto}.pdf-cover{padding:18px 20px 20px;border-bottom:3px solid #e8a324;margin-bottom:14px}.pdf-brand{font-size:11px;font-weight:800;letter-spacing:1.4px;color:#738096}.pdf-cover h1{font-size:26px;color:#0e2a44;margin:8px 0 4px}.pdf-cover h2{font-size:21px;margin:0 0 8px;color:#172033}.pdf-meta{font-size:11px;color:#738096}.pdf-section{border:1px solid #dfe5ec;border-radius:12px;padding:14px;margin:0 0 12px;break-inside:avoid}.pdf-section h3{font-size:15px;color:#0e2a44;margin:0 0 11px;padding-bottom:7px;border-bottom:2px solid #e8a324}.pdf-info-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}.pdf-info-grid>div{background:#f7f9fb;border-radius:8px;padding:9px}.pdf-info-grid span,.pdf-kpis span{display:block;font-size:9px;color:#738096;text-transform:uppercase;letter-spacing:.3px;margin-bottom:3px}.pdf-info-grid b{font-size:11px}.pdf-status{display:inline-block}.pdf-kpis{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-bottom:10px}.pdf-kpis>div{border:1px solid #e3e8ef;border-radius:9px;padding:10px;background:#fff}.pdf-kpis strong{font-size:15px}.pdf-chart-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}.pdf-chart{border:1px solid #e3e8ef;border-radius:9px;padding:10px}.pdf-chart h4{font-size:11px;margin:0 0 8px;color:#0e2a44}.pdf-bar-row{margin:7px 0 10px}.pdf-bar-head,.pdf-bar-foot{display:flex;justify-content:space-between;gap:8px;font-size:9px}.pdf-bar-head b{font-size:10px}.pdf-bar-foot{color:#738096;margin-top:3px}.pdf-bar{height:7px;background:#edf1f5;border-radius:8px;overflow:hidden;margin-top:4px}.pdf-bar span{display:block;height:100%;border-radius:8px;background:#1e65b7}.pdf-bar span.green{background:#1a8a4a}.pdf-bar span.orange{background:#d47b00}.pdf-bar span.blue{background:#1e65b7}.pdf-finance-strip{display:flex;gap:8px;flex-wrap:wrap;margin-top:8px}.pdf-finance-strip span{background:#f7f9fb;border-radius:8px;padding:8px;font-size:10px}.pdf-item{border:1px solid #e5e9ef;border-radius:9px;padding:9px;margin:7px 0;background:#fff;break-inside:avoid}.pdf-item-head{display:flex;justify-content:space-between;gap:8px;align-items:flex-start;font-size:10px}.pdf-item-head span{color:#738096;text-align:right}.pdf-small{font-size:9px;color:#68778a;margin-top:5px;line-height:1.4}.pdf-total{background:#f5f7fa;border-radius:8px;padding:9px;margin-top:8px;font-size:10px}.pdf-empty{font-size:10px;color:#738096;padding:8px}.pdf-score{display:grid;grid-template-columns:75px 1fr;gap:12px;align-items:center;background:#f7f9fb;border-radius:10px;padding:10px;margin-bottom:9px}.pdf-score-value{font-size:24px;font-weight:800;color:#0e2a44}.pdf-score-value small{font-size:10px;color:#738096}.pdf-scale{height:8px;background:#e9edf2;border-radius:8px;overflow:hidden;margin-top:7px}.pdf-scale i{display:block;height:100%;background:#1a8a4a;border-radius:8px}.pdf-contact{font-size:9px;padding:6px 8px;border-bottom:1px solid #edf0f4}.pdf-footer{font-size:8px;color:#8a95a5;text-align:center;padding:8px 0}.pdf-report *{box-sizing:border-box}@media(max-width:650px){.pdf-info-grid,.pdf-chart-grid{grid-template-columns:1fr}.pdf-kpis{grid-template-columns:1fr 1fr}.pdf-cover h1{font-size:22px}}\r\n#taxVatPeriod,#taxIpPeriod{position:relative;z-index:2;pointer-events:auto;cursor:pointer;display:block;width:100%;min-height:46px;padding:11px 38px 11px 12px;margin-top:6px;border:1px solid #cbd5e1;border-radius:11px;background-color:#fff;color:#172033;font-size:16px;line-height:1.3;box-sizing:border-box;appearance:auto;-webkit-appearance:menulist}\r\n.tax-period-control{flex:1 1 220px;min-width:0;max-width:100%}\r\n.tax-period-control label{display:block;font-size:13px;color:#738096;margin-bottom:2px}\r\n.chat-layout{padding:0 14px}.chat-messages{height:clamp(180px,40vh,400px);overflow:auto;display:flex;flex-direction:column;gap:12px;padding:12px 2px}.chat-message{max-width:94%;padding:12px 14px;border:1px solid var(--line);border-radius:14px;background:#fff;align-self:flex-start}.chat-user{align-self:flex-end;background:#e9f1fb}.chat-activity{max-width:100%;background:#f8fafc;border-left:3px solid var(--amber)}.chat-message-meta{font-size:11px;color:#66758a;margin-bottom:6px}.chat-message-body{white-space:pre-wrap;overflow-wrap:anywhere;font-size:14px;line-height:1.5}.chat-composer{display:flex;gap:8px;align-items:flex-end;margin:12px 0}.chat-composer textarea{flex:1;min-width:0;resize:vertical;padding:12px;border:1px solid var(--line);border-radius:12px;font:inherit}.chat-composer button{width:auto;font-size:14px}.chat-notice{font-size:13px;line-height:1.5;color:#66758a}.chat-more{margin-top:10px}\r\n.chat-tabs{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}.chat-tabs button[aria-pressed=\"true\"]{background:#e9f1fb;border-color:#245a91}.chat-history-list{display:flex;flex-direction:column;gap:8px;max-height:55vh;overflow:auto;margin:12px 0}.chat-history-item{text-align:left;padding:12px;border:1px solid var(--line);border-radius:10px;background:#fff;white-space:normal;overflow-wrap:anywhere}.chat-sr-only{position:absolute;width:1px;height:1px;overflow:hidden}.chat-layout [hidden]{display:none!important}@media(max-width:540px){.chat-composer{flex-wrap:wrap}.chat-composer textarea{flex-basis:100%}.chat-composer button{margin-left:auto}.chat-tabs .smallbtn{font-size:12px;padding:8px}}\r\n"})};
const esc=s=>
String(s??'').replace(
/[&<>"']/g,
c=>({
'&':'&amp;',
'<':'&lt;',
'>':'&gt;',
'"':'&quot;',
"'":'&#39;'
}[c])
);

const money=n =>
new Intl.NumberFormat('ru-RU',{
style:'currency',
currency:'RUB',
maximumFractionDigits:0
}).format(Number(n)||0);

function buildStatementReportHtml(projectId){
const p=projects.find(x=>x.id===projectId); if(!p)return '<div>Объект не найден.</div>';
const s=projectStats(projectId);
const subRows=subcontractors.filter(x=>x.project_id===projectId);
const matRows=projectMaterials.filter(x=>x.project_id===projectId);
const othRows=projectOtherExpenses.filter(x=>x.project_id===projectId);
const ptoRows=ptoDocuments.filter(x=>x.project_id===projectId).sort((a,b)=>String(a.final_date||'').localeCompare(String(b.final_date||'')));
const ptoContactsRows=ptoContacts.filter(x=>x.project_id===projectId);
const ptoState=ptoOverallState(projectId);
const workRows=projectWorkItems.filter(x=>x.project_id===projectId).sort((a,b)=>String(a.start_date||'').localeCompare(String(b.start_date||'')));
const nowStr=new Date().toLocaleString('ru-RU');
const revenuePlan=statementNum(p.planned_revenue), revenueFact=statementNum(s.income);
const costPlan=statementNum(s.plannedCostTotal), costFact=statementNum(s.expense);
const revenuePct=revenuePlan>0?revenueFact/revenuePlan*100:0;
const costPct=costPlan>0?costFact/costPlan*100:0;
const margin=revenueFact>0?s.profit/revenueFact*100:0;
const workPlan=workRows.reduce((a,x)=>a+statementNum(x.planned_volume),0);
const workFact=workRows.reduce((a,x)=>a+workCompletedTotal(x.id),0);
const workPct=workPlan>0?workFact/workPlan*100:0;

let html=`<div id="pdfStatement" class="pdf-report">
<header class="pdf-cover">
<div class="pdf-brand">ФИНАНСЫ КОМПАНИИ</div>
<h1>Выписка по объекту</h1>
<h2>${statementEsc(p.name)}</h2>
<div class="pdf-meta">Сформирована: ${statementEsc(nowStr)}</div>
</header>
<section class="pdf-section"><h3>1. Основная информация</h3><div class="pdf-info-grid">
<div><span>Компания-подрядчик</span><b>${statementEsc(p.contractor_company||'—')}</b></div>
<div><span>Заказчик</span><b>${statementEsc(p.customer||'—')}</b></div>
<div><span>Договор</span><b>№ ${statementEsc(p.contract_number||'—')} от ${statementEsc(fmtDate(p.contract_date))}</b></div>
<div><span>Срок</span><b>${statementEsc(fmtDate(p.start_date))} — ${statementEsc(fmtDate(p.end_date))}</b></div>
<div><span>Статус</span><b class="pdf-status">${statementEsc(p.status||'—')}</b></div>
<div><span>Комментарий</span><b>${statementEsc(p.comment||'—')}</b></div>
</div></section>
<section class="pdf-section"><h3>2. Финансовая картина</h3><div class="pdf-kpis">
<div><span>Выручка факт</span><strong>${statementMoney(s.income)}</strong></div><div><span>Себестоимость факт</span><strong>${statementMoney(s.expense)}</strong></div><div><span>Прибыль</span><strong>${statementMoney(s.profit)}</strong></div><div><span>Маржинальность</span><strong>${margin.toFixed(1)}%</strong></div>
<div><span>Дебиторка</span><strong>${statementMoney(s.receivable)}</strong></div><div><span>Кредиторка</span><strong>${statementMoney(s.payable)}</strong></div>
</div>
<div class="pdf-chart-grid">
<div class="pdf-chart"><h4>Выручка: план → факт</h4>${statementBar('Освоение выручки',revenuePct,statementMoney(revenueFact),'из '+statementMoney(revenuePlan),'blue')}</div>
<div class="pdf-chart"><h4>Себестоимость: план → факт</h4>${statementBar('Использование бюджета',costPct,statementMoney(costFact),'из '+statementMoney(costPlan),'orange')}</div>
</div>
<div class="pdf-finance-strip"><span>Остаток выручки до плана <b>${statementMoney(Math.max(0,revenuePlan-revenueFact))}</b></span><span>Остаток себестоимости <b>${statementMoney(Math.max(0,costPlan-costFact))}</b></span></div>
</section>
<section class="pdf-section"><h3>3. Структура себестоимости</h3><div class="pdf-chart-grid">
<div class="pdf-chart"><h4>Плановая себестоимость</h4>${statementBar('Субподрядчики',costPlan>0?s.subPlanned/costPlan*100:0,statementMoney(s.subPlanned),'план','blue')}${statementBar('ТМЦ',costPlan>0?s.materialsPlanned/costPlan*100:0,statementMoney(s.materialsPlanned),'план','green')}${statementBar('Прочие расходы',costPlan>0?s.otherPlanned/costPlan*100:0,statementMoney(s.otherPlanned),'план','orange')}</div>
<div class="pdf-chart"><h4>Фактическая себестоимость</h4>${statementBar('Субподрядчики',costFact>0?s.subActual/costFact*100:0,statementMoney(s.subActual),'факт','blue')}${statementBar('ТМЦ',costFact>0?s.materialsActual/costFact*100:0,statementMoney(s.materialsActual),'факт','green')}${statementBar('Прочие расходы',costFact>0?s.otherActual/costFact*100:0,statementMoney(s.otherActual),'факт','orange')}</div>
</div></section>
<section class="pdf-section"><h3>4. Субподрядчики (${subRows.length})</h3>`;
if(!subRows.length) html+=`<div class="pdf-empty">Нет данных.</div>`;
else for(const sub of subRows){const plan=statementNum(sub.planned_amount),paid=subcontractorPaid(sub.id),pct=plan>0?paid/plan*100:0;html+=`<div class="pdf-item"><div class="pdf-item-head"><b>${statementEsc(sub.name)}</b><span>${sub.has_vat?'С НДС':'Без НДС'}</span></div>${statementBar('Оплата',pct,statementMoney(paid),'из '+statementMoney(plan),'blue')}<div class="pdf-small">Остаток: ${statementMoney(Math.max(0,plan-paid))}${sub.comment?' · '+statementEsc(sub.comment):''}</div></div>`;}
html+=`</section><section class="pdf-section"><h3>5. ТМЦ (${matRows.length})</h3>`;
if(!matRows.length) html+=`<div class="pdf-empty">Нет данных.</div>`;
else {for(const m of matRows){const pl=statementNum(m.planned_amount),fa=statementNum(m.actual_amount);html+=`<div class="pdf-item"><div class="pdf-item-head"><b>${statementEsc(m.name)}</b><span>${m.expense_date?statementEsc(fmtDate(m.expense_date)):''}</span></div>${statementBar('Факт',pl>0?fa/pl*100:0,statementMoney(fa),'из '+statementMoney(pl),'green')}${m.comment?`<div class="pdf-small">${statementEsc(m.comment)}</div>`:''}</div>`;}}
html+=`<div class="pdf-total">Итого ТМЦ: <b>${statementMoney(s.materialsActual)}</b> факт / ${statementMoney(s.materialsPlanned)} план</div></section>
<section class="pdf-section"><h3>6. Прочие расходы (${othRows.length})</h3>`;
if(!othRows.length) html+=`<div class="pdf-empty">Нет данных.</div>`;
else for(const o of othRows){const pl=statementNum(o.planned_amount),fa=statementNum(o.actual_amount);html+=`<div class="pdf-item"><div class="pdf-item-head"><b>${statementEsc(o.name)}</b><span>${o.expense_date?statementEsc(fmtDate(o.expense_date)):''}</span></div>${statementBar('Факт',pl>0?fa/pl*100:0,statementMoney(fa),'из '+statementMoney(pl),'orange')}${o.comment?`<div class="pdf-small">${statementEsc(o.comment)}</div>`:''}</div>`;}
html+=`<div class="pdf-total">Итого прочие расходы: <b>${statementMoney(s.otherActual)}</b> факт / ${statementMoney(s.otherPlanned)} план</div></section>
<section class="pdf-section"><h3>7. ПТО</h3>`;
if(ptoState.score===null) html+=`<div class="pdf-empty">Документы ПТО не добавлены.</div>`;
else {html+=`<div class="pdf-score"><div class="pdf-score-value">${ptoState.score.toFixed(1)}<small>/ 5</small></div><div><b>${statementEsc(ptoState.label)}</b><div class="pdf-scale"><i style="width:${statementPct(ptoState.score/5*100)}%"></i></div></div></div>`;for(const doc of ptoRows){const prog=ptoProgressInfo(doc);const score=ptoDocScore(doc);html+=`<div class="pdf-item"><div class="pdf-item-head"><b>${statementEsc(ptoTypeName(doc.document_type))}</b><span>${score.toFixed(1)} / 5</span></div>${statementBar('Срок',prog.pct,prog.label,'','blue')}${doc.comment?`<div class="pdf-small">${statementEsc(doc.comment)}</div>`:''}</div>`;}}
html+=`<div class="pdf-small"><b>Контакты заказчика ПТО:</b> ${ptoContactsRows.length}</div>`;for(const c of ptoContactsRows)html+=`<div class="pdf-contact">${statementEsc(c.full_name)}${c.position?' · '+statementEsc(c.position):''}${c.phone?' · '+statementEsc(c.phone):''}</div>`;
html+=`</section><section class="pdf-section"><h3>8. Ход работ</h3><div class="pdf-score"><div class="pdf-score-value">${Math.round(workPct)}%<small> факт</small></div><div><b>${workFact} из ${workPlan} ${workRows[0]?.unit||''}</b><div class="pdf-scale"><i style="width:${statementPct(workPct)}%"></i></div></div></div>`;
if(!workRows.length) html+=`<div class="pdf-empty">Работы по объекту не добавлены.</div>`;
else for(const w of workRows){const fact=workCompletedTotal(w.id),pct=statementNum(w.planned_volume)>0?fact/statementNum(w.planned_volume)*100:0;html+=`<div class="pdf-item"><div class="pdf-item-head"><b>${statementEsc(w.work_name)}</b><span>${Math.round(statementPct(pct))}%</span></div>${statementBar('Выполнение',pct,String(fact)+' '+statementEsc(w.unit),'из '+String(w.planned_volume)+' '+statementEsc(w.unit),'blue')}<div class="pdf-small">Срок: ${statementEsc(fmtDate(w.start_date))} — ${statementEsc(fmtDate(w.end_date))}${w.comment?' · '+statementEsc(w.comment):''}</div></div>`;}
html+=`</section><section class="pdf-section"><h3>9. Налоговые показатели</h3><div class="pdf-info-grid">`;
if(s.isIp)html+=`<div><span>Налог ИП</span><b>Начислено ${statementMoney(s.taxPlanned)}</b></div><div><span>Оплачено</span><b>${statementMoney(s.taxActual)}</b></div><div><span>Остаток</span><b>${statementMoney(s.taxRemaining)}</b></div>`;
if(s.isOoo)html+=`<div><span>НДС план</span><b>${statementMoney(s.vatPlanned)}</b></div><div><span>НДС начислено</span><b>${statementMoney(s.vatAccrued)}</b></div><div><span>Входной вычет</span><b>${statementMoney(s.vatInputCredit)}</b></div><div><span>К уплате</span><b>${statementMoney(s.vatDue)}</b></div><div><span>Оплачено</span><b>${statementMoney(s.vatActual)}</b></div><div><span>Остаток</span><b>${statementMoney(s.vatRemaining)}</b></div>`;
if(!s.isIp&&!s.isOoo)html+=`<div class="pdf-empty">Налоговые показатели для этого объекта не определены.</div>`;
html+=`</div></section><footer class="pdf-footer">Выписка сформирована автоматически в системе «Финансы компании» · ${statementEsc(nowStr)}</footer></div>`;
return html;
}
function exportOrgMonthPdf(){
 if(window.renderExistingReport)return openExistingManualReport('organization_month',{month:currentOrgMonth(),company:$('orgCompanyFilter')?.value||'all'});
 const month=currentOrgMonth();
 const company=$('orgCompanyFilter')?.value||'all';
 const companyLabel=company==='all'?'ООО + ИП':company;
 if(!month) return alert('Выберите месяц.');
 const monthOps=ops.filter(x=>monthKey(x.operation_date)===month && (company==='all'||reportOperationCompany(x)===company));
 const allMonthOps=ops.filter(x=>monthKey(x.operation_date)===month);
 const income=monthOps.filter(x=>x.operation_type==='income').reduce((s,x)=>s+reportNum(x.amount),0);
 const expense=monthOps.filter(x=>x.operation_type==='expense'&&!isMaterialCreditExpense(x)).reduce((s,x)=>s+reportNum(x.amount),0);
 const creditMoney=monthOps.filter(x=>x.operation_type==='credit'&&(x.credit_kind||'money')==='money').reduce((s,x)=>s+reportNum(x.amount),0);
 const creditTmc=monthOps.filter(x=>x.operation_type==='credit'&&(x.credit_kind||'money')!=='money').reduce((s,x)=>s+reportNum(x.amount),0);
 const cashResult=income+creditMoney-expense;
 const orgOps=monthOps.filter(x=>x.operation_type==='expense'&&x.article==='Орг. расходы');
 const orgActual=orgOps.reduce((s,x)=>s+reportNum(x.amount),0);
 const planEmp=orgEmployees.filter(x=>orgScheduledForMonth(x,month)&&(company==='all'||(x.company||'ООО')===company)).reduce((s,x)=>s+reportNum(x.monthly_salary),0);
 const planFixed=orgExpenses.filter(x=>orgScheduledForMonth(x,month)&&(company==='all'||(x.company||'ООО')===company)).reduce((s,x)=>s+reportNum(x.monthly_amount),0);
 const planEvents=events.filter(x=>monthKey(x.event_date)===month&&(company==='all'||(x.company||'ООО')===company)).reduce((s,x)=>s+reportNum(x.planned_amount),0); const orgPlan=planEmp+planFixed+planEvents;
 const subPay=monthOps.filter(x=>x.article==='Субподрядчики').reduce((s,x)=>s+reportNum(x.amount),0);
 const matPay=monthOps.filter(x=>x.operation_type==='expense'&&x.article==='ТМЦ'&&!isMaterialCreditExpense(x)).reduce((s,x)=>s+reportNum(x.amount),0);
 const otherPay=monthOps.filter(x=>x.article==='Прочие расходы').reduce((s,x)=>s+reportNum(x.amount),0);
 const taxes=monthOps.filter(x=>['Налог ИП','НДС','Налоги'].includes(x.article)).reduce((s,x)=>s+reportNum(x.amount),0);
 const debtPay=monthOps.filter(x=>x.article==='Погашение кредиторки').reduce((s,x)=>s+reportNum(x.amount),0);
 const receivRemain=ars.reduce((s,x)=>s+Math.max(0,reportNum(x.amount)-reportNum(x.paid_amount)),0);
 const payRemain=aps.reduce((s,x)=>s+Math.max(0,reportNum(x.amount)-reportNum(x.paid_amount)),0);
 const overdueRec=ars.filter(x=>x.due_date&&x.due_date<month+'-01'&&reportNum(x.amount)>reportNum(x.paid_amount)).length;
 const overduePay=aps.filter(x=>x.due_date&&x.due_date<month+'-01'&&reportNum(x.amount)>reportNum(x.paid_amount)).length;
 const activeProjects=projects.filter(p=>ops.some(o=>o.project_id===p.id&&monthKey(o.operation_date)===month)).length;
 const projectRows=projects.filter(p=>ops.some(o=>o.project_id===p.id&&monthKey(o.operation_date)===month)).map(p=>{
   const po=monthOps.filter(o=>o.project_id===p.id);
   const inc=po.filter(o=>o.operation_type==='income').reduce((s,x)=>s+reportNum(x.amount),0);
   const exp=po.filter(o=>o.operation_type==='expense'&&!isMaterialCreditExpense(o)).reduce((s,x)=>s+reportNum(x.amount),0);
   const res=inc-exp;
   return `<tr><td><b>${reportEsc(p.name)}</b><div class="rmuted">${reportEsc(p.customer||'')}</div></td><td>${reportFmt(p.planned_revenue)}</td><td>${reportFmt(p.planned_cost)}</td><td>${reportFmt(inc)}</td><td>${reportFmt(exp)}</td><td class="${res>=0?'rgreen':'rred'}">${reportFmt(res)}</td><td>${reportEsc(p.status||'')}</td></tr>`;
 });
 const expenseCats={};
 monthOps.filter(x=>x.operation_type==='expense'&&!isMaterialCreditExpense(x)).forEach(x=>{const k=x.article||'Без статьи';expenseCats[k]=(expenseCats[k]||0)+reportNum(x.amount);});
 const catRows=Object.entries(expenseCats).sort((a,b)=>b[1]-a[1]);
 const catMax=catRows[0]?.[1]||1;
 const catHtml=catRows.map(([k,v])=>`<div class="rmetric"><div class="rline"><span>${reportEsc(k)}</span><b>${reportFmt(v)}</b></div>${reportBar(v,catMax)}</div>`).join('')||'<div class="rmuted">Расходов нет.</div>';
 const opRows=monthOps.slice().sort((a,b)=>String(a.operation_date||'').localeCompare(String(b.operation_date||''))).map(o=>{
   const typ=o.operation_type==='income'?'Приход':o.operation_type==='expense'?'Расход':'Кредит';
   const sign=o.operation_type==='expense'?'−':o.operation_type==='credit'&&(o.credit_kind||'money')==='money'?'+':'+';
   const subject=o.counterparty||o.article||'';
   const extra=o.operation_type==='credit'?((o.credit_kind||'money')==='money'?'Деньги':'ТМЦ'):(o.article||'');
   return `<tr><td>${reportEsc(o.operation_date)}</td><td>${typ}</td><td>${reportEsc(subject)}</td><td>${reportEsc(extra)}</td><td>${reportEsc(reportOperationCompany(o))}</td><td class="${o.operation_type==='expense'?'rred':'rgreen'}">${sign}${reportFmt(o.amount)}</td></tr>`;
 });
 const empRows=orgEmployees.filter(x=>orgScheduledForMonth(x,month)&&(company==='all'||(x.company||'ООО')===company)).map(x=>{const paid=orgOps.filter(o=>o.org_employee_id===x.id).reduce((s,o)=>s+reportNum(o.amount),0);return `<tr><td>${reportEsc(x.name)}</td><td>${reportEsc(x.position||'')}</td><td>${reportEsc(x.company||'ООО')}</td><td>${reportFmt(x.monthly_salary)}</td><td>${reportFmt(paid)}</td><td>${reportPct(x.monthly_salary?paid/x.monthly_salary*100:0)}</td></tr>`;});
 const fixedRows=orgExpenses.filter(x=>orgScheduledForMonth(x,month)&&(company==='all'||(x.company||'ООО')===company)).map(x=>{const paid=orgOps.filter(o=>o.org_expense_id===x.id).reduce((s,o)=>s+reportNum(o.amount),0);return `<tr><td>${reportEsc(x.name)}</td><td>${reportEsc(x.category||'')}</td><td>${reportEsc(x.company||'ООО')}</td><td>${reportFmt(x.monthly_amount)}</td><td>${reportFmt(paid)}</td><td>${reportPct(x.monthly_amount?paid/x.monthly_amount*100:0)}</td></tr>`;});
 const recRows=ars.map(x=>{const rem=Math.max(0,reportNum(x.amount)-reportNum(x.paid_amount));return `<tr><td>${reportEsc(x.counterparty)}</td><td>${reportEsc(x.document_type||'')}</td><td>${reportFmt(x.amount)}</td><td>${reportFmt(x.paid_amount)}</td><td>${reportFmt(rem)}</td><td>${reportEsc(x.due_date||'')}</td></tr>`;});
 const payRows=aps.map(x=>{const rem=Math.max(0,reportNum(x.amount)-reportNum(x.paid_amount));return `<tr><td>${reportEsc(x.counterparty)}</td><td>${reportEsc(x.document_type||'')}</td><td>${reportFmt(x.amount)}</td><td>${reportFmt(x.paid_amount)}</td><td>${reportFmt(rem)}</td><td>${reportEsc(x.due_date||'')}</td></tr>`;});
 const creditRows=aps.filter(x=>x.is_credit).map(x=>{const rem=Math.max(0,reportNum(x.amount)-reportNum(x.paid_amount));return `<tr><td>${reportEsc(x.counterparty)}</td><td>${reportEsc(x.owner_company||'')}</td><td>${reportEsc((x.credit_kind||'money')==='money'?'Деньги':'ТМЦ / отсрочка')}</td><td>${reportFmt(x.amount)}</td><td>${reportFmt(x.paid_amount)}</td><td>${reportFmt(rem)}</td><td>${reportEsc(x.due_date||'')}</td><td>${reportEsc(x.full_repayment_date||'')}</td></tr>`;});
 const eventRows=events.filter(e=>(monthKey(e.event_date)===month||monthOps.some(o=>o.org_event_id===e.id))&&(company==='all'||(e.company||'ООО')===company)).map(e=>{const paid=monthOps.filter(o=>o.org_event_id===e.id).reduce((s,x)=>s+reportNum(x.amount),0);const planned=reportNum(e.planned_amount);return `<tr><td>${reportEsc(e.event_date||'')}</td><td>${reportEsc(e.title||'')}</td><td>${reportEsc(e.company||'ООО')}</td><td>${reportFmt(planned)}</td><td>${reportFmt(paid)}</td><td>${reportPct(planned?paid/planned*100:0)}</td><td>${reportEsc(e.comment||'')}</td></tr>`;});
 const projectNames=projectRows.length;
 const totalExpensesForChart=Math.max(expense,1);
 const pieData=Object.entries(expenseCats).slice(0,8);
 const svgW=520,svgH=190;
 const barW=pieData.length?Math.max(24,Math.floor((svgW-40)/pieData.length)-10):30;
 const maxV=pieData[0]?.[1]||1;
 const svgBars=pieData.map(([k,v],i)=>{const h=Math.max(4,Math.round((v/maxV)*120));const x=20+i*(barW+10);const y=145-h;return `<rect x="${x}" y="${y}" width="${barW}" height="${h}" rx="4"/><text x="${x+barW/2}" y="165" text-anchor="middle" font-size="9">${reportEsc(k).slice(0,12)}</text>`;}).join('');
 const flow=[['Приход',income],['Кредит-деньги',creditMoney],['Расход',expense],['Результат',Math.max(0,cashResult)]]; const flowMax=Math.max(...flow.map(x=>x[1]),1); const flowBars=flow.map(([k,v],i)=>{const h=Math.max(4,Math.round((v/flowMax)*120));const x=25+i*120;const y=145-h;return `<rect x="${x}" y="${y}" width="70" height="${h}" rx="4"/><text x="${x+35}" y="165" text-anchor="middle" font-size="9">${reportEsc(k)}</text>`;}).join('');
 const report=`<!doctype html><html><head><meta charset="utf-8"><title>Финансовый отчёт ${reportEsc(month)}</title><style>
*{box-sizing:border-box}body{font-family:Arial,Helvetica,sans-serif;color:#18212b;margin:0;background:#fff;font-size:11px}main{max-width:1100px;margin:0 auto;padding:28px}.head{display:flex;justify-content:space-between;gap:20px;border-bottom:2px solid #0e2a44;padding-bottom:14px;margin-bottom:18px}.head h1{margin:0 0 6px;font-size:24px;color:#0e2a44}.muted,.rmuted{color:#667085}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:9px;margin:10px 0 18px}.card{border:1px solid #dfe4ea;border-radius:9px;padding:11px}.label{font-size:10px;color:#667085}.value{font-size:17px;font-weight:700;margin-top:5px}.green{color:#16803c}.red,.rred{color:#b42318}.orange{color:#b54708}.rgreen{color:#16803c}.section{margin:18px 0}.section h2{font-size:15px;color:#0e2a44;border-bottom:1px solid #dfe4ea;padding-bottom:7px}.two{display:grid;grid-template-columns:1fr 1fr;gap:12px}.rline{display:flex;justify-content:space-between;gap:10px;margin-bottom:5px}.rmetric{margin:8px 0}.rbar{height:7px;background:#eef1f4;border-radius:6px;overflow:hidden}.rbar span{display:block;height:100%;background:#0e2a44;border-radius:6px}table{width:100%;border-collapse:collapse;margin-top:8px}th,td{border-bottom:1px solid #e5e7eb;padding:7px 5px;text-align:left;vertical-align:top}th{background:#f7f9fb;color:#344054;font-size:10px}.chart{border:1px solid #dfe4ea;border-radius:9px;padding:10px}.chart svg{width:100%;height:auto}.note{background:#f7f9fb;border-left:3px solid #0e2a44;padding:9px;margin:10px 0}.pagebreak{page-break-before:always}@media print{body{font-size:10px}main{padding:10px}.no-print{display:none!important}.card{break-inside:avoid}.section{break-inside:avoid}table{font-size:9px}thead{display:table-header-group}}
</style></head><body><main>
<div class="head"><div><h1>Финансовый отчёт компании</h1><div>${reportEsc(month)} · ${reportEsc(companyLabel)}</div><div class="muted">Сформирован ${reportEsc(new Date().toLocaleDateString('ru-RU'))}</div></div><div style="text-align:right"><b>Период</b><br>${reportEsc(month)}</div></div>
<div class="grid"><div class="card"><div class="label">Приход денег</div><div class="value green">${reportFmt(income)}</div></div><div class="card"><div class="label">Расходы</div><div class="value red">${reportFmt(expense)}</div></div><div class="card"><div class="label">Кредиты — деньги</div><div class="value green">${reportFmt(creditMoney)}</div></div><div class="card"><div class="label">Денежный результат</div><div class="value ${cashResult>=0?'green':'red'}">${reportFmt(cashResult)}</div></div></div>
<div class="grid"><div class="card"><div class="label">Кредиты — ТМЦ / отсрочка</div><div class="value">${reportFmt(creditTmc)}</div></div><div class="card"><div class="label">Погашение кредиторки</div><div class="value">${reportFmt(debtPay)}</div></div><div class="card"><div class="label">Дебиторка, остаток</div><div class="value">${reportFmt(receivRemain)}</div><div class="label">Просрочено: ${overdueRec}</div></div><div class="card"><div class="label">Кредиторка, остаток</div><div class="value">${reportFmt(payRemain)}</div><div class="label">Просрочено: ${overduePay}</div></div></div>
<div class="section"><h2>Диаграммы денежного движения и расходов</h2><div class="two"><div class="chart"><div class="rmuted" style="margin-bottom:5px">Денежные потоки за месяц</div><svg viewBox="0 0 520 190" xmlns="http://www.w3.org/2000/svg"><line x1="15" y1="145" x2="500" y2="145" stroke="#cfd5dc"/>${flowBars}</svg></div><div class="chart"><div class="rmuted" style="margin-bottom:5px">Структура расходов</div><svg viewBox="0 0 ${svgW} ${svgH}" xmlns="http://www.w3.org/2000/svg"><line x1="15" y1="145" x2="510" y2="145" stroke="#cfd5dc"/>${svgBars}</svg></div></div><div class="two" style="margin-top:10px"><div>${catHtml}</div><div class="note">Денежный результат = приход + кредитные деньги − расходы. Кредиты, оформленные как ТМЦ/отсрочка, в денежный результат не включаются.</div></div></div>
<div class="section"><h2>Организационные расходы</h2><div class="grid"><div class="card"><div class="label">План</div><div class="value">${reportFmt(orgPlan)}</div></div><div class="card"><div class="label">Оплачено</div><div class="value">${reportFmt(orgActual)}</div></div><div class="card"><div class="label">Осталось</div><div class="value">${reportFmt(Math.max(0,orgPlan-orgActual))}</div></div><div class="card"><div class="label">Зарплаты / ТМЦ / прочее</div><div class="value">${reportFmt(planEmp)} / ${reportFmt(matPay)} / ${reportFmt(otherPay)}</div></div></div>
<h3>Сотрудники</h3><table><thead><tr><th>Сотрудник</th><th>Должность</th><th>Компания</th><th>План</th><th>Оплачено</th><th>%</th></tr></thead><tbody>${reportRows(empRows)}</tbody></table>
<h3>Постоянные расходы</h3><table><thead><tr><th>Расход</th><th>Категория</th><th>Компания</th><th>План</th><th>Оплачено</th><th>%</th></tr></thead><tbody>${reportRows(fixedRows)}</tbody></table></div>
<div class="section pagebreak"><h2>Объекты и деятельность</h2><div class="grid"><div class="card"><div class="label">Активных объектов в периоде</div><div class="value">${projectNames}</div></div><div class="card"><div class="label">Субподрядчики</div><div class="value">${reportFmt(subPay)}</div></div><div class="card"><div class="label">ТМЦ</div><div class="value">${reportFmt(matPay)}</div></div><div class="card"><div class="label">Налоги</div><div class="value">${reportFmt(taxes)}</div></div></div>
<table><thead><tr><th>Объект</th><th>План дохода</th><th>План себестоимости</th><th>Приход за период</th><th>Расход за период</th><th>Результат</th><th>Статус</th></tr></thead><tbody>${reportRows(projectRows)}</tbody></table></div>
<div class="section"><h2>Дебиторка и кредиторка</h2><div class="two"><div><h3>Дебиторка</h3><table><thead><tr><th>Контрагент</th><th>Документ</th><th>Сумма</th><th>Оплачено</th><th>Остаток</th><th>Срок</th></tr></thead><tbody>${reportRows(recRows)}</tbody></table></div><div><h3>Кредиторка</h3><table><thead><tr><th>Контрагент</th><th>Документ</th><th>Сумма</th><th>Оплачено</th><th>Остаток</th><th>Срок</th></tr></thead><tbody>${reportRows(payRows)}</tbody></table></div></div></div>
<div class="section"><h2>Кредитная нагрузка</h2><table><thead><tr><th>Кредитор</th><th>Получатель</th><th>Вид</th><th>Сумма</th><th>Оплачено</th><th>Остаток</th><th>Ближайшая выплата</th><th>Полное погашение</th></tr></thead><tbody>${reportRows(creditRows)}</tbody></table></div>
<div class="section"><h2>События месяца</h2><table><thead><tr><th>Дата</th><th>Событие</th><th>Компания</th><th>План</th><th>Оплачено за месяц</th><th>%</th><th>Комментарий</th></tr></thead><tbody>${reportRows(eventRows)}</tbody></table></div>
<div class="section"><h2>Все операции за период</h2><table><thead><tr><th>Дата</th><th>Тип</th><th>Получатель / контрагент</th><th>Статья / вид кредита</th><th>Компания</th><th>Сумма</th></tr></thead><tbody>${reportRows(opRows)}</tbody></table></div>
<div class="section"><h2>Сводка</h2><div class="note">За выбранный период: ${allMonthOps.length} операций; приход денег ${reportFmt(income)}; расходы ${reportFmt(expense)}; кредитные деньги ${reportFmt(creditMoney)}; кредиты в форме ТМЦ/отсрочки ${reportFmt(creditTmc)}; денежный результат ${reportFmt(cashResult)}. Остатки дебиторки и кредиторки показаны по состоянию на момент формирования отчёта.</div></div>
</main><script>window.onload=function(){setTimeout(function(){window.print()},500)};<\/script></body></html>`;
 const w=window.open('','_blank','width=1200,height=900');
 if(!w)return alert('Браузер заблокировал окно отчёта. Разрешите всплывающие окна для приложения.');
 w.document.open();w.document.write(report);w.document.close();
}
function printWorkReport(){
 if(window.renderExistingReport)return openExistingManualReport('production',{project_id:currentWorkProjectId,from:$('workReportFrom').value,to:$('workReportTo').value});
  const p=projects.find(x=>x.id===currentWorkProjectId);
  if(!p)return;
  const from=$('workReportFrom').value,to=$('workReportTo').value;
  if(!from||!to||from>to)return alert('Укажите корректный период.');

  const rows=projectWorkItems
    .filter(w=>w.project_id===p.id)
    .map(w=>{
      const logs=workProgressRowsFor(w.id).filter(x=>x.progress_date>=from&&x.progress_date<=to);
      const qty=logs.reduce((s,x)=>s+Number(x.completed_volume||0),0);
      const completionDate=(w.updated_at||'').slice(0,10);
      const completedByStatus=w.status==='completed'&&completionDate>=from&&completionDate<=to;
      const reportQty=qty>0?qty:(completedByStatus?Number(w.completed_volume||w.planned_volume||0):0);
      const reportLogs=logs.length?logs:[{progress_date:completionDate||from,comment:'Работа отмечена как завершённая'}];
      return {w,logs:reportLogs,qty:reportQty,completedByStatus};
    })
    .filter(x=>x.qty>0&&(x.logs.length>0||x.completedByStatus));

  if(!rows.length)return alert('За выбранный период завершённых или фактически выполненных работ не найдено.');

  const total=rows.reduce((s,x)=>s+x.qty,0);
  const escR=reportEsc;
  const report=`<!doctype html><html><head><meta charset="utf-8"><title>Отчёт по выполненным работам — ${escR(p.name)}</title><style>@page{size:A4;margin:14mm}body{font-family:Arial,sans-serif;color:#172033;font-size:11px}h1{font-size:19px;margin:0 0 6px}h2{font-size:14px;margin:18px 0 7px}.muted{color:#66758a}.head{display:flex;justify-content:space-between;border-bottom:2px solid #172033;padding-bottom:10px;margin-bottom:14px}.meta{line-height:1.6}table{width:100%;border-collapse:collapse;margin-top:7px}th,td{border:1px solid #bfc7d3;padding:6px;vertical-align:top}th{background:#eef2f6;text-align:left}.total{font-weight:800;margin-top:8px}.note{margin-top:16px;padding:9px;border:1px solid #d5dbe3;background:#f8fafc}footer{margin-top:24px;display:grid;grid-template-columns:1fr 1fr;gap:40px}.sign{border-top:1px solid #777;padding-top:5px;margin-top:35px}.status-done{color:#16803c;font-weight:700}</style></head><body><div class="head"><div><h1>Отчёт по выполненным электромонтажным работам</h1><div class="meta"><b>Объект:</b> ${escR(p.name)}<br><b>Заказчик:</b> ${escR(p.customer||'—')}<br><b>Период:</b> ${escR(from)} — ${escR(to)}</div></div><div class="meta"><b>Сформирован:</b><br>${escR(new Date().toLocaleDateString('ru-RU'))}</div></div><h2>Выполненные работы</h2><table><thead><tr><th style="width:28px">№</th><th>Вид работы</th><th>Ед.</th><th>Объём за период</th><th>Даты / статус</th><th>Комментарий</th></tr></thead><tbody>${rows.map((x,i)=>`<tr><td>${i+1}</td><td>${escR(x.w.work_name)}</td><td>${escR(x.w.unit)}</td><td>${x.qty.toLocaleString('ru-RU',{maximumFractionDigits:3})}</td><td>${x.logs.map(l=>escR(l.progress_date)).join('<br>')}${x.w.status==='completed'?'<br><span class="status-done">Завершено</span>':''}</td><td>${x.logs.map(l=>escR(l.comment||'')).filter(Boolean).join('<br>')}</td></tr>`).join('')}</tbody></table><div class="total">Всего позиций: ${rows.length} · Объём: ${total.toLocaleString('ru-RU',{maximumFractionDigits:3})}</div><div class="note">Отчёт учитывает фактические записи выполнения за выбранный период. Если работа отмечена статусом «Завершено» без отдельной записи факта, в отчёт также попадает её плановый/зафиксированный объём при условии, что дата изменения статуса относится к выбранному периоду.</div><footer><div><div class="sign">Производитель работ / прораб</div></div><div><div class="sign">Сметчик / проверил</div></div></footer><script>window.onload=function(){window.print();};<\/script></body></html>`;
  const w=window.open('','_blank');
  if(!w)return alert('Не удалось открыть окно отчёта. Разрешите всплывающие окна.');
  w.document.open();w.document.write(report);w.document.close();
}
function exportProposalsPdf(){if(window.renderExistingReport)return openExistingManualReport('proposals',{});const rows=proposals;const count=(v)=>rows.filter(x=>x.status===v).length;const by=(field)=>{const m={};rows.forEach(x=>{const k=x[field]||'Не указано';m[k]=(m[k]||0)+1;});return Object.entries(m).sort((a,b)=>b[1]-a[1]).map(([k,v])=>`<tr><td>${esc(k)}</td><td>${v}</td></tr>`).join('');};const html=`<!doctype html><html><head><meta charset="utf-8"><title>Статистика КП</title><style>body{font:14px Arial;padding:25px;color:#172033}table{width:100%;border-collapse:collapse;margin:12px 0 24px}td,th{border:1px solid #ccc;padding:7px;text-align:left}h1{color:#0e2a44}</style></head><body><h1>Статистика коммерческих предложений</h1><p>Всего: ${rows.length} · В рассмотрении: ${count('review')} · Выиграли: ${count('won')} · Проиграли: ${count('lost')}</p><h2>По источникам</h2><table><tr><th>Источник</th><th>Количество</th></tr>${by('source')}</table><h2>Причины проигрыша</h2><table><tr><th>Причина</th><th>Количество</th></tr>${by('lost_reason')}</table><h2>Реестр КП</h2><table><tr><th>Объект</th><th>Город</th><th>Заказчик</th><th>Сумма</th><th>Статус</th><th>Источник</th><th>Отправлено</th></tr>${rows.map(x=>`<tr><td>${esc(x.name)}</td><td>${esc(x.city||'')}</td><td>${esc(x.customer||'')}</td><td>${money(x.amount)}</td><td>${x.status==='won'?'Выиграли':x.status==='lost'?'Проиграли':'В рассмотрении'}</td><td>${esc(x.source||'')}</td><td>${esc(x.sent_date||'')}</td></tr>`).join('')}</table><script>window.onload=()=>window.print()<\/script></body></html>`;const w=window.open('','_blank');if(!w)return alert('Разрешите всплывающие окна для выгрузки PDF.');w.document.write(html);w.document.close();}
function projectStats(projectId){

const p=projects.find(x=>x.id===projectId);

const income=
ops
.filter(x=>
x.project_id===projectId &&
x.operation_type==='income'
)
.reduce((s,x)=>s+Number(x.amount||0),0);

// Операционные расходы: ТМЦ/прочие берутся из позиций, налоги добавляются ниже.
// Эти две категории по объекту ведутся отдельными списками, а факт
// конкретной позиции синхронизируется из операции, поэтому добавляем
// их ниже только один раз.
const opsExpense=
ops
.filter(x=>
x.project_id===projectId &&
x.operation_type==='expense' &&
x.article!=='Материалы' &&
x.article!=='ТМЦ' &&
x.article!=='Прочие расходы' &&
x.article!=='Налог ИП' &&
x.article!=='НДС' &&
!isDeferredMaterialRepayment(x)
)
.reduce((s,x)=>s+Number(x.amount||0),0);

const receivable=
ars
.filter(x=>x.project_id===projectId)
.reduce(
(s,x)=>
s+
Math.max(
0,
Number(x.amount||0)-
Number(x.paid_amount||0)
),
0
);

const payable=
aps
.filter(x=>x.project_id===projectId)
.reduce(
(s,x)=>
s+
Math.max(
0,
Number(x.amount||0)-
Number(x.paid_amount||0)
),
0
);

const projectSubs=subcontractors.filter(x=>x.project_id===projectId);

const subPlanned=
projectSubs.reduce((s,x)=>s+Number(x.planned_amount||0),0);

// Факт по субподрядчикам — сумма всех оплат (операций), привязанных
// к субподрядчикам этого объекта. Каждая оплата учитывается один раз.
const subActual=
ops
.filter(x=>
x.operation_type==='expense' &&
x.subcontractor_id &&
projectSubs.some(s=>s.id===x.subcontractor_id)
)
.reduce((s,x)=>s+Number(x.amount||0),0);

const projectMats=projectMaterials.filter(x=>x.project_id===projectId);
const materialsPlanned=projectMats.reduce((s,x)=>s+Number(x.planned_amount||0),0);
const materialsActual=projectMats.reduce((s,x)=>s+Number(x.actual_amount||0),0);

const projectOth=projectOtherExpenses.filter(x=>x.project_id===projectId);
const otherPlanned=projectOth.reduce((s,x)=>s+Number(x.planned_amount||0),0);
const otherActual=projectOth.reduce((s,x)=>s+Number(x.actual_amount||0),0);

// Налог ИП: для объекта ИП начисляется от фактических поступлений.
// Период начисления — календарный месяц. Плановый ориентир показываем
// отдельно, но сумма к уплате/остаток строятся от факта поступлений.
const isIp=p?.contractor_company==='ИП';
const ipTaxPlanned=isIp ? Number(p?.planned_revenue||0)*0.08 : 0;
const projectIncomeForIp=isIp ? ops.filter(x=>
  x.project_id===projectId &&
  x.operation_type==='income' &&
  operationCompanyForTax(x)==='ИП'
).reduce((s,x)=>s+Number(x.amount||0),0) : 0;
const ipTaxAccrued=isIp ? projectIncomeForIp*0.08 : 0;
const ipTaxPaid=isIp ? ops.filter(x=>
  x.project_id===projectId &&
  x.operation_type==='expense' &&
  x.article==='Налог ИП'
).reduce((s,x)=>s+Number(x.amount||0),0) : 0;
const ipTaxActual=ipTaxPaid;
const ipTaxRemaining=Math.max(0,ipTaxAccrued-ipTaxPaid);

// НДС для ООО. Это управленческая модель приложения: плановый НДС = 22%
// от суммы договора. Оплаченные ТМЦ и оплаченные субподрядчики с признаком
// «С НДС» автоматически формируют вычет 22% от фактической суммы оплаты.
// Субподрядчики без НДС в вычет не попадают.
const isOoo=p?.contractor_company==='ООО';
const vatRate=0.22;
const vatPlanned=isOoo ? Number(p?.planned_revenue||0)*vatRate : 0;
const vatIncome=isOoo ? ops.filter(x=>
  x.project_id===projectId &&
  x.operation_type==='income' &&
  operationCompanyForTax(x)==='ООО'
).reduce((s,x)=>s+Number(x.amount||0),0) : 0;
const vatAccrued=isOoo ? vatIncome*vatRate : 0;
// Входной НДС учитываем по фактически оплаченным расходам.
// Важное исключение: ТМЦ, полученные в кредит/с отсрочкой, не дают вычет
// в момент получения. Вычет по ним появляется при фактическом погашении
// связанной кредиторки. Это исключает двойной учет: при получении + при оплате.
const vatInputCreditGeneral=isOoo ? ops.filter(x=>
  x.project_id===projectId &&
  x.operation_type==='expense' &&
  operationCompanyForTax(x)==='ООО' &&
  x.article!=='НДС' && x.article!=='Налог ИП' &&
  x.article!=='Погашение кредиторки' &&
  x.article!=='ТМЦ' &&
  Boolean(x.vat_included)
).reduce((s,x)=>s+Number(x.amount||0)*vatRate,0) : 0;
const vatInputCreditTmcCash=isOoo ? ops.filter(x=>
  x.project_id===projectId &&
  x.operation_type==='expense' &&
  x.article==='ТМЦ' &&
  x.cost_item_id &&
  x.credit_kind!=='material' &&
  Boolean(x.vat_included)
).reduce((s,x)=>s+Number(x.amount||0)*vatRate,0) : 0;
const vatInputCreditTmcLegacy=isOoo ? ops.filter(x=>
  x.project_id===projectId &&
  x.operation_type==='expense' &&
  x.article==='ТМЦ' &&
  x.cost_item_id &&
  x.credit_kind!=='material' &&
  !('vat_included' in x)
).reduce((s,x)=>s+Number(x.amount||0)*vatRate,0) : 0;
const vatInputCreditPayableRepayments=isOoo ? ops.filter(x=>
  x.project_id===projectId && x.operation_type==='expense' && x.article==='Погашение кредиторки' && x.payable_id
).reduce((s,x)=>{
  const payable=aps.find(p=>String(p.id)===String(x.payable_id));
  const source=payable?.credit_kind==='material'?ops.find(o=>String(o.payable_id)===String(payable.id)&&o.article==='ТМЦ'&&o.credit_kind==='material'):null;
  return s+((Boolean(x.vat_included)||Boolean(source?.vat_included))?Number(x.amount||0)*vatRate:0);
},0) : 0;
const vatInputCreditSubcontractorsLegacy=isOoo ? ops.filter(x=>
  x.project_id===projectId &&
  x.operation_type==='expense' &&
  x.article==='Субподрядчики' &&
  x.subcontractor_id &&
  projectSubs.some(sub=>sub.id===x.subcontractor_id && Boolean(sub.has_vat)) &&
  !('vat_included' in x)
).reduce((s,x)=>s+Number(x.amount||0)*vatRate,0) : 0;
const vatInputCreditTmc=vatInputCreditTmcCash+vatInputCreditTmcLegacy+vatInputCreditPayableRepayments;
const vatInputCreditSubcontractors=vatInputCreditSubcontractorsLegacy;
const vatInputCredit=vatInputCreditGeneral+vatInputCreditTmcCash+vatInputCreditTmcLegacy+vatInputCreditPayableRepayments+vatInputCreditSubcontractorsLegacy;
const vatDue=Math.max(0,vatAccrued-vatInputCredit);
const vatActual=isOoo ? ops.filter(x=>
  x.project_id===projectId &&
  x.operation_type==='expense' &&
  x.article==='НДС'
).reduce((s,x)=>s+Number(x.amount||0),0) : 0;
const vatRemaining=Math.max(0,vatDue-vatActual);

// Плановая себестоимость = субподрядчики + ТМЦ + прочие расходы.
// Налог ИП показывается отдельным финансовым показателем и не входит
// в этот показатель себестоимости.

// Суммы субподрядчиков НЕ прибавляются сверху ни к чему — это и есть
// планируемая себестоимость целиком.
const plannedCostTotal=subPlanned+materialsPlanned+otherPlanned;

// Фактическая себестоимость = операции по объекту (кроме статей
// «Материалы»/«Прочие расходы», которые ведутся отдельно) + факт по
// ТМЦ + факт по прочим расходам. Оплаты субподрядчикам уже входят в
// opsExpense (статья «Субподрядчики» из неё не исключена), поэтому
// отдельно subActual сюда не прибавляется — иначе получится задвоение.
const operatingExpense=opsExpense+materialsActual+otherActual;
// Общий фактический расход объекта включает фактически оплаченные налог ИП и НДС.
const expense=operatingExpense+ipTaxActual+vatActual;

return {
p,
income,
expense,
operatingExpense,
profit:income-expense,
receivable,
payable,
subPlanned,
subActual,
subCount:projectSubs.length,
materialsPlanned,
materialsActual,
materialsCount:projectMats.length,
otherPlanned,
otherActual,
otherCount:projectOth.length,
isIp,
ipTaxPlanned,
ipTaxActual,
ipTaxRemaining,
isOoo,
vatRate,
vatPlanned,
vatInputCredit,
vatInputCreditTmc,
vatInputCreditSubcontractors,
vatDue,
vatActual,
vatRemaining,
ipTaxAccrued,
ipTaxPaid,
vatIncome,

// Tax UI aliases: for an IP object the relevant fact is the accrued tax
// from actual monthly income, while taxActual is the amount actually paid.
taxPlanned:ipTaxAccrued,
taxActual:ipTaxPaid,
taxRemaining:ipTaxRemaining,
plannedCostTotal
};

}

// Единая функция расчёта состояния шкалы "план / факт / финиш".
// inverseGood=true — для показателей, где перерасход/опережение плохо (себестоимость).
function vatHistoryData(period){
  const qb=quarterBounds(period);
  const qOps=qb?ops.filter(x=>taxOperationDate(x)>=qb.start&&taxOperationDate(x)<=qb.end):[];
  const vatRate=0.22;
  const incomeRows=qOps.filter(x=>x.operation_type==='income'&&operationCompanyForTax(x)==='ООО');
  const outputRows=incomeRows.map(x=>({
    kind:'output', operation:x, base:Number(x.amount||0), vat:Number(x.amount||0)*vatRate, reason:'Поступление ООО'
  }));

  const generalRows=qOps.filter(x=>x.operation_type==='expense'&&operationCompanyForTax(x)==='ООО'&&x.article!=='НДС'&&x.article!=='Налог ИП'&&x.article!=='Погашение кредиторки'&&x.article!=='ТМЦ'&&Boolean(x.vat_included));
  const tmcCashRows=qOps.filter(x=>x.operation_type==='expense'&&operationCompanyForTax(x)==='ООО'&&x.article==='ТМЦ'&&x.credit_kind!=='material'&&Boolean(x.vat_included));
  // История должна совпадать с фактическим расчётом НДС объекта, включая
  // старые операции, созданные до появления поля «С НДС». Для таких записей
  // текущая модель расчёта сохраняет отдельные legacy-правила: ТМЦ и
  // субподрядчики с НДС учитываются даже при отсутствии vat_included.
  const tmcCashLegacyRows=qOps.filter(x=>x.operation_type==='expense'&&operationCompanyForTax(x)==='ООО'&&x.article==='ТМЦ'&&x.cost_item_id&&x.credit_kind!=='material'&&!('vat_included' in x));
  const subcontractorLegacyRows=qOps.filter(x=>x.operation_type==='expense'&&operationCompanyForTax(x)==='ООО'&&x.article==='Субподрядчики'&&x.subcontractor_id&&!('vat_included' in x)&&(()=>{
    const p=projects.find(pr=>String(pr.id)===String(x.project_id));
    const subs=subcontractors.filter(sub=>String(sub.project_id)===String(x.project_id));
    return Boolean(subs.find(sub=>String(sub.id)===String(x.subcontractor_id))?.has_vat);
  })());
  // НДС по кредиторке списываем по фактической оплате, когда галочка «С НДС» стоит именно в операции погашения.
  // Для старых ТМЦ-кредитов сохраняем прежнее правило: отметка в исходной операции ТМЦ также учитывается при погашении.
  const payableRepaymentRows=qOps.filter(x=>x.operation_type==='expense'&&operationCompanyForTax(x)==='ООО'&&x.article==='Погашение кредиторки'&&x.payable_id).map(x=>{
    const payable=aps.find(p=>String(p.id)===String(x.payable_id));
    const source=payable?.credit_kind==='material'?ops.find(o=>String(o.payable_id)===String(payable.id)&&o.article==='ТМЦ'&&o.credit_kind==='material'):null;
    if(!Boolean(x.vat_included)&&!Boolean(source?.vat_included)) return null;
    return {kind:'payable_repayment',operation:x,source,base:Number(x.amount||0),vat:Number(x.amount||0)*vatRate,reason:x.vat_included?'Погашение кредиторки: в операции отмечено «С НДС»':'Погашение ТМЦ в кредит с отметкой «С НДС»',status:'Учтено при оплате'};
  }).filter(Boolean);

  const inputRows=[
    ...generalRows.map(x=>({kind:'general',operation:x,base:Number(x.amount||0),vat:Number(x.amount||0)*vatRate,reason:'Расход отмечен «С НДС»',status:'Учтено'})),
    ...tmcCashRows.map(x=>({kind:'tmc_cash',operation:x,base:Number(x.amount||0),vat:Number(x.amount||0)*vatRate,reason:'ТМЦ оплачены сразу, отмечены «С НДС»',status:'Учтено'})),
    ...tmcCashLegacyRows.map(x=>({kind:'tmc_cash_legacy',operation:x,base:Number(x.amount||0),vat:Number(x.amount||0)*vatRate,reason:'Старая операция ТМЦ: учтена по историческому правилу до появления поля «С НДС»',status:'Учтено (старая операция)'})),
    ...subcontractorLegacyRows.map(x=>({kind:'subcontractor_legacy',operation:x,base:Number(x.amount||0),vat:Number(x.amount||0)*vatRate,reason:'Старый расход субподрядчика с признаком «С НДС»: учтён по историческому правилу',status:'Учтено (старая операция)'})),
    ...payableRepaymentRows
  ];

  const inputIds=new Set(inputRows.map(r=>r.operation.id));
  const excludedRows=qOps.filter(x=>x.operation_type==='expense'&&operationCompanyForTax(x)==='ООО'&&!inputIds.has(x.id)).map(x=>{
    let reason='Без отметки «С НДС»';
    if(x.article==='НДС') reason='Оплата самого НДС — вычет не применяется';
    else if(x.article==='Налог ИП') reason='Налог ИП — вычет не применяется';
    else if(x.article==='Погашение кредиторки'){
      const payable=aps.find(p=>String(p.id)===String(x.payable_id));
      const source=payable?ops.find(o=>String(o.payable_id)===String(payable.id)&&o.article==='ТМЦ'&&o.credit_kind==='material'):null;
      reason=x.vat_included?'В операции погашения не найдено связанное начисление — проверьте организацию ООО':(payable?.credit_kind==='material'?(source?.vat_included?'Погашение ТМЦ в кредит: входной НДС учтён по отметке исходной операции':'ТМЦ в кредит без отметки «С НДС»'):'В операции погашения не установлена отметка «С НДС»');
    } else if(x.article==='ТМЦ'&&x.credit_kind==='material') reason=x.vat_included?'ТМЦ получены в кредит — вычет появится при погашении':'ТМЦ в кредит без отметки «С НДС»';
    else if(x.article==='ТМЦ'&&x.cost_item_id&&!('vat_included' in x)) reason='Старая операция ТМЦ: проверена по историческому правилу — учтена в вычете';
    else if(x.article==='Субподрядчики'&&x.subcontractor_id&&!('vat_included' in x)){
      const subs=subcontractors.filter(sub=>String(sub.project_id)===String(x.project_id));
      const sub=subs.find(sub=>String(sub.id)===String(x.subcontractor_id));
      reason=sub?.has_vat?'Старая операция субподрядчика с НДС: учтена в вычете':'У субподрядчика нет признака НДС';
    }
    return {operation:x,reason};
  });

  const pendingMaterialCredits=qOps.filter(x=>x.operation_type==='expense'&&operationCompanyForTax(x)==='ООО'&&x.article==='ТМЦ'&&x.credit_kind==='material'&&x.vat_included).map(x=>{
    const payable=aps.find(p=>String(p.id)===String(x.payable_id));
    const remaining=payable?Math.max(0,Number(payable.amount||0)-Number(payable.paid_amount||0)):0;
    return payable&&remaining>0.005?{...x,remainingBase:remaining,remainingVat:remaining*vatRate}:null;
  }).filter(Boolean);

  return {outputRows,inputRows,excludedRows,pendingMaterialCredits,outputTotal:outputRows.reduce((s,r)=>s+r.vat,0),inputTotal:inputRows.reduce((s,r)=>s+r.vat,0),incomeTotal:incomeRows.reduce((s,x)=>s+Number(x.amount||0),0),inputBase:inputRows.reduce((s,r)=>s+r.base,0)};
}
function buildStatementText(projectId){
const p=projects.find(x=>x.id===projectId); if(!p)return 'Объект не найден.';
const s=projectStats(projectId); const subRows=subcontractors.filter(x=>x.project_id===projectId); const matRows=projectMaterials.filter(x=>x.project_id===projectId); const othRows=projectOtherExpenses.filter(x=>x.project_id===projectId); const nowStr=new Date().toLocaleString('ru-RU');
let t='ВЫПИСКА ПО ОБЪЕКТУ\nСформирована: '+nowStr+'\n\nОбъект: '+p.name+'\nКомпания-подрядчик: '+(p.contractor_company||'—')+'\nЗаказчик: '+(p.customer||'—')+'\nДоговор: № '+(p.contract_number||'—')+' от '+fmtDate(p.contract_date)+'\nСрок: '+fmtDate(p.start_date)+' — '+fmtDate(p.end_date)+'\nСтатус: '+(p.status||'—')+'\n\nФИНАНСЫ\nПлановая выручка: '+money(Number(p.planned_revenue||0))+'\nФактическая выручка: '+money(s.income)+'\nПлановая себестоимость: '+money(s.plannedCostTotal)+'\nФактическая себестоимость: '+money(s.expense)+'\nПрибыль: '+money(s.profit)+'\nМаржинальность: '+(s.income>0?((s.profit/s.income)*100).toFixed(1)+'%':'—')+'\nДебиторка: '+money(s.receivable)+'\nКредиторка: '+money(s.payable)+'\n';
t+='\nСУБПОДРЯДЧИКИ ('+subRows.length+')\n';for(const sub of subRows){const plan=Number(sub.planned_amount||0),paid=subcontractorPaid(sub.id);t+='- '+sub.name+': план '+money(plan)+', оплачено '+money(paid)+', остаток '+money(Math.max(0,plan-paid))+'\n';}
t+='\nТМЦ ('+matRows.length+')\n';for(const m of matRows)t+='- '+m.name+': план '+money(Number(m.planned_amount||0))+', факт '+money(Number(m.actual_amount||0))+'\n';t+='\nПРОЧИЕ РАСХОДЫ ('+othRows.length+')\n';for(const o of othRows)t+='- '+o.name+': план '+money(Number(o.planned_amount||0))+', факт '+money(Number(o.actual_amount||0))+'\n';return t;
}
function taxQuarterKey(dateStr){
  const d=String(dateStr||'');
  if(!/^\d{4}-\d{2}-\d{2}$/.test(d)) return '';
  const y=d.slice(0,4), m=Number(d.slice(5,7));
  return y+'-Q'+(Math.floor((m-1)/3)+1);
}
function subcontractorPaid(subId){

return ops
.filter(x=>
x.subcontractor_id===subId &&
x.operation_type==='expense'
)
.reduce((s,x)=>s+Number(x.amount||0),0);

}
function ptoTypeName(type){
  return ({executive_schemes:'Исполнительные схемы',aosr:'АОСР',work_log:'Журнал производства работ',cable_log:'Кабельный журнал',other:'Прочие документы'})[type]||'Прочие документы';
}
function ptoProgressInfo(doc){
  const finalDate=doc?.final_date?new Date(doc.final_date+'T23:59:59'):null;
  const created=doc?.created_at?new Date(doc.created_at):new Date();
  const now=new Date();
  const st=ptoStatusInfo(doc.status);
  if(!finalDate||isNaN(finalDate)) return {pct:0,label:'Финальная дата не указана',cls:st.cls};
  if(doc.status==='signed') return {pct:100,label:'Подписан',cls:'signed'};
  const total=finalDate-created;
  let pct=total>0?((now-created)/total)*100:(now>=finalDate?100:0);
  pct=Math.min(100,Math.max(0,pct));
  let label=now>finalDate?'Срок истёк':(pct>=80?'Финальная дата близко':'В сроке');
  return {pct,label,cls:st.cls};
}
function ptoDocScore(doc){
  if(doc?.status==='signed') return 5;
  if(doc?.status==='signing') return 4;
  if(doc?.status==='requested') return 1;
  // Производство: 2 базовых балла + до 1 балла за приближение к финальной дате.
  const prog=ptoProgressInfo(doc);
  return 2 + Math.min(1, Math.max(0, Number(prog.pct||0)/100));
}
function ptoOverallState(projectId){
  const rows=ptoDocuments.filter(x=>x.project_id===projectId);
  if(!rows.length) return {score:null,label:'Нет документов',cls:'s2',count:0};
  const avg=rows.reduce((sum,x)=>sum+ptoDocScore(x),0)/rows.length;
  const rounded=Math.max(1,Math.min(5,Math.round(avg*10)/10));
  const level=Math.max(1,Math.min(5,Math.round(avg)));
  let label='Запрос документов';
  if(avg>=4.5) label='Почти завершено';
  else if(avg>=4) label='Все на подписании';
  else if(avg>=3) label='Производство близко к финишу';
  else if(avg>=2) label='В производстве';
  return {score:rounded,label,cls:'s'+level,count:rows.length};
}
function workCompletedTotal(id){const logs=workProgressRowsFor(id),w=projectWorkItems.find(x=>x.id===id),recorded=logs.reduce((s,x)=>s+Number(x.completed_volume||0),0),stored=Number(w?.completed_volume||(w?.status==='completed'?w.planned_volume:0)||0);return Math.max(recorded,stored);}
function fmtDate(d){
if(!d) return '—';
return d;
}
function statementEsc(v){
return String(v==null?'':v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function statementNum(v){return Number(v||0);}
function statementPct(v){return Math.max(0,Math.min(100,Number(v||0)));}
function statementBar(label,pct,left,right,cls=''){
const pc=statementPct(pct);
return `<div class="pdf-bar-row"><div class="pdf-bar-head"><span>${statementEsc(label)}</span><b>${statementEsc(left)}</b></div><div class="pdf-bar"><span class="${cls}" style="width:${pc}%"></span></div><div class="pdf-bar-foot"><span>${statementEsc(right||'')}</span><span>${Math.round(pc)}%</span></div></div>`;
}
function statementMoney(v){return money(statementNum(v));}
function monthKey(date){return String(date||'').slice(0,7);}
function currentOrgMonth(){return $('orgMonth')?.value||new Date().toISOString().slice(0,7);}
function orgScheduledForMonth(x,month){return x.active!==false && (!x.created_at || monthKey(x.created_at)<=month);}
function reportEsc(v){return esc(v==null?'':String(v));}
function reportNum(v){return Number(v||0);}
function reportFmt(v){return money(reportNum(v));}
function reportPct(v){return (Number(v||0)).toFixed(1)+'%';}
function reportBar(value,max){const p=max>0?Math.max(0,Math.min(100,value/max*100)):0;return `<div class="rbar"><span style="width:${p}%"></span></div>`;}
function reportRows(rows,empty='Нет данных'){
return rows.length?rows.join(''):`<tr><td colspan="99" class="rmuted">${empty}</td></tr>`;
}
function isMaterialCreditExpense(o){return o?.operation_type==='expense'&&o?.article==='ТМЦ'&&o?.credit_kind==='material';}
function reportOperationCompany(o){const p=o?.project_id?projects.find(x=>x.id===o.project_id):null;return o?.payer_company||o?.credit_recipient_company||p?.contractor_company||'ООО';}
function openExistingManualReport(kind,args){
 const data={projects,ops,ars,aps,subcontractors,projectMaterials,projectOtherExpenses,orgEmployees,orgExpenses,events,ptoDocuments,ptoContacts,projectWorkItems,projectWorkMaterials,projectWorkProgress,projectWorkSections,projectPriceHistory,workVolumeSubmissions,workVolumeSubmissionItems,proposals};
 let html;try{html=window.renderExistingReport(kind,data,args);}catch(e){return alert(e.message);}const w=window.open('','_blank');if(!w)return alert('Разрешите окно печати.');w.document.write(html);w.document.close();setTimeout(()=>{w.focus();w.print();},300);
}
function workProgressRowsFor(id){return projectWorkProgress.filter(x=>x.work_item_id===id).sort((a,b)=>String(a.progress_date).localeCompare(String(b.progress_date)));}
function operationCompanyForTax(x){
  const projectId=x?.project_id||null;
  if(projectId){
    const p=projects.find(p=>String(p.id)===String(projectId));
    const projectCompany=String(p?.contractor_company||'').trim();
    if(projectCompany==='ООО'||projectCompany==='ИП') return projectCompany;
  }
  const payerCompany=String(x?.payer_company||'').trim();
  return (payerCompany==='ООО'||payerCompany==='ИП')?payerCompany:'ООО';
}
function isDeferredMaterialRepayment(o){return o?.operation_type==='expense'&&o?.article==='Погашение кредиторки'&&o.payable_id&&ops.some(source=>source.payable_id===o.payable_id&&source.project_id===o.project_id&&isMaterialCreditExpense(source)&&source.cost_item_type==='material'&&projectMaterials.some(m=>m.id===source.cost_item_id&&m.project_id===source.project_id));}
function quarterBounds(key){
  const [y,q]=String(key).split('-Q').map(Number); if(!y||!q)return null;
  const startMonth=(q-1)*3+1; const endMonth=startMonth+2;
  const pad=n=>String(n).padStart(2,'0');
  const endDay=new Date(y,endMonth,0).getDate();
  return {start:`${y}-${pad(startMonth)}-01`,end:`${y}-${pad(endMonth)}-${pad(endDay)}`};
}
function taxOperationDate(x){
  const d=String(x?.operation_date||'').slice(0,10);
  return /^\d{4}-\d{2}-\d{2}$/.test(d)?d:'';
}
function ptoStatusInfo(status){
  return ({requested:{label:'🔴 Запрос документов',cls:'requested'},in_progress:{label:'🟡 В производстве',cls:'in_progress'},signing:{label:'🔵 На подписании',cls:'signing'},signed:{label:'🟢 Подписан',cls:'signed'}})[status]||{label:'🔴 Запрос документов',cls:'requested'};
}
 if(kind==='statement_text')return buildStatementText(args.project_id);
 if(kind==='financial_metrics')return {project:projects.find(p=>p.id===args.project_id),card:projectStats(args.project_id),vat_registers:[...new Set(ops.map(o=>taxQuarterKey(o.operation_date)).filter(Boolean))].sort().map(period=>({period,...vatHistoryData(period)})),method:'existing_manual_projectStats_vatHistoryData'};
 if(kind==='statement')captured='<!doctype html><html><head><meta charset="utf-8"><title>Выписка</title><style>'+document.querySelector('style').innerHTML+'</style></head><body>'+buildStatementReportHtml(args.project_id)+'</body></html>';
 else if(kind==='organization_month')exportOrgMonthPdf();else if(kind==='production')printWorkReport();else if(kind==='proposals')exportProposalsPdf();else throw new Error('Unknown existing report');
 if(!captured||captured.length>1500000)throw new Error('Report empty/too large');
 return captured.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,'').replace('<head>',"<head><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'\">");
}

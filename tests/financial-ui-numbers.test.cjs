const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('index.html','utf8');
function fn(name){const start=source.indexOf('function '+name+'(');assert(start>=0);const end=source.indexOf('\nfunction ',start+1);return source.slice(start,end<0?undefined:end);}
const ctx={projects:[{id:'ip',contractor_company:'ИП',planned_revenue:10000},{id:'ooo',contractor_company:'ООО',planned_revenue:10000}],ops:[],ars:[],aps:[],subcontractors:[],projectMaterials:[],projectOtherExpenses:[]};
vm.createContext(ctx);vm.runInContext(fn('projectStats'),ctx);
vm.runInContext(fn('isMaterialCreditExpense')+fn('isDeferredMaterialRepayment'),ctx);
ctx.operationCompanyForTax=x=>ctx.projects.find(p=>p.id===x.project_id)?.contractor_company||x.payer_company;
ctx.ops=[{project_id:'ip',operation_type:'income',amount:1000},{project_id:'ip',operation_type:'expense',article:'Налог ИП',amount:50},{project_id:'ooo',operation_type:'income',amount:2000},{project_id:'ooo',operation_type:'expense',article:'Субподрядчики',subcontractor_id:'sub',amount:200,vat_included:true},{project_id:'ooo',operation_type:'expense',article:'ТМЦ',cost_item_id:'mat',amount:100,vat_included:true},{project_id:'ooo',operation_type:'expense',article:'Прочие расходы',amount:70,vat_included:true},{project_id:'ooo',operation_type:'expense',article:'НДС',amount:20}];
ctx.subcontractors=[{id:'sub',project_id:'ooo',planned_amount:300}];ctx.projectMaterials=[{id:'mat',project_id:'ooo',actual_amount:125,planned_amount:250}];ctx.projectOtherExpenses=[{project_id:'ooo',actual_amount:90,planned_amount:100}];ctx.ars=[{project_id:'ooo',amount:1000,paid_amount:200}];ctx.aps=[{project_id:'ooo',amount:500,paid_amount:100}];
const ip=ctx.projectStats('ip'),ooo=ctx.projectStats('ooo');
assert.equal(ip.operatingExpense,0);assert.equal(ip.expense,50);assert.equal(ip.ipTaxAccrued,80);assert.equal(ip.ipTaxRemaining,30);assert.equal(ip.profit,950);
assert.equal(ooo.operatingExpense,415);assert.equal(ooo.expense,435);assert.equal(ooo.profit,1565);assert.equal(ooo.subActual,200);assert.equal(ooo.plannedCostTotal,650);assert.equal(ooo.receivable,800);assert.equal(ooo.payable,400);assert(Math.abs(ooo.vatInputCredit-81.4)<1e-8);assert(Math.abs(ooo.vatRemaining-338.6)<1e-8);
// Two independent UI states: an event received while the second session edits a form
// must flush after closing it, rather than losing the pending refresh.
for(let session=0;session<2;session++){
 let open=true,reloads=0,scheduled;const nodes=new Proxy({},{get:(_,id)=>({style:{},classList:{contains:()=>open,remove:()=>{open=false}}})});
 const state={$:id=>nodes[id],console,clearTimeout:()=>{},setTimeout:fn=>{scheduled=fn;return 1;},loadAll:async()=>{reloads++;}};vm.createContext(state);vm.runInContext('let realtimePending=false,realtimeReloadTimer=null;'+fn('scheduleRealtimeReload')+fn('closeModal'),state);
 state.scheduleRealtimeReload();(async()=>{await scheduled();assert.equal(reloads,0);state.closeModal();await scheduled();assert.equal(reloads,1);})().catch(e=>{console.error(e);process.exitCode=1});
}

console.log('PASS: existing project formulas, taxes counted once, subcontractor/material/other facts, AR/AP and deferred realtime refresh in two isolated UI states (not live sessions)');
if(fs.existsSync('tests/artifacts/financial-server-snapshot.json')){
 const live=JSON.parse(fs.readFileSync('tests/artifacts/financial-server-snapshot.json','utf8'));Object.assign(ctx,live);
 const p=live.projects.find(p=>p.contractor_company==='ООО'),ip=live.projects.find(p=>p.contractor_company==='ИП');
 const a=ctx.projectStats(p.id),b=ctx.projectStats(ip.id);
 assert.equal(a.income,130);assert.equal(a.operatingExpense,440);assert.equal(a.expense,460);assert.equal(a.subActual,200);assert.equal(a.otherActual,110);assert.equal(a.receivable,1720);assert.equal(a.payable,970);assert.equal(a.plannedCostTotal,500);assert.equal(a.vatInputCredit,44);assert.equal(a.vatActual,20);assert.equal(a.vatRemaining,0);
 assert.equal(b.income,1000);assert.equal(b.expense,50);assert.equal(b.ipTaxAccrued,80);assert.equal(b.ipTaxRemaining,30);
 const cashIncome=live.ops.filter(o=>o.operation_type==='income').reduce((s,o)=>s+o.amount,0),cashExpense=live.ops.filter(o=>o.operation_type==='expense'&&!(o.article==='ТМЦ'&&o.credit_kind==='material')).reduce((s,o)=>s+o.amount,0);
 assert.equal(cashIncome,1130);assert.equal(cashExpense,460);assert.equal(cashIncome-cashExpense,670);
 for(const name of ['quarterBounds','monthBounds','taxQuarterKey','taxMonthKey','currentQuarterKey','currentMonthKey','quarterLabel','monthLabel','taxOperationDate','operationCompanyForTax','vatHistoryData','renderTaxRegister'])vm.runInContext(fn(name),ctx);
 const nodes={taxRegister:{}};ctx.$=id=>nodes[id]||(nodes[id]={});ctx.money=x=>Number(x).toFixed(2);ctx.taxVatPeriod='2026-Q4';ctx.taxIpPeriod='2026-10';
 const register=ctx.vatHistoryData('2026-Q4');assert.equal(register.incomeTotal,130);assert.equal(register.inputTotal,44);assert.equal(register.outputTotal,28.6);
 ctx.renderTaxRegister();assert(nodes.taxRegister.innerHTML.includes('Поступило: 130.00 · начислено НДС: 28.60 · входной вычет: 44.00 · оплачено: 20.00'));assert(nodes.taxRegister.innerHTML.includes('Поступило: 1000.00 · начислено: 80.00 · оплачено: 50.00'));assert(nodes.taxRegister.innerHTML.includes('30.00'));
 console.log('PASS: actual VAT history and rendered tax register agree with real server snapshot; existing 22% and 8% management formulas retained');
 for(const name of ['dashboardProjects','dashboardOperations','dashboardReceivables','dashboardPayables','isMaterialCreditExpense','render'])vm.runInContext(fn(name),ctx);
 ctx.profile={role:'finance'};ctx.projectsTab='active';for(const name of ['renderOperations','renderReceivables','renderPayables','renderProjects','renderDashboardProjects','renderEventsInfo','renderOrgExpensesPage'])ctx[name]=()=>{};
 ctx.render();assert.equal(nodes.income.textContent,'1130.00');assert.equal(nodes.expense.textContent,'460.00');assert.equal(nodes.net.textContent,'670.00');assert.equal(nodes.receivable.textContent,'1720.00');assert.equal(nodes.payable.textContent,'970.00');assert.equal(nodes.arTotal.textContent,'1720.00');assert.equal(nodes.apTotal.textContent,'970.00');
 console.log('PASS: actual main dashboard, balance, AR/AP totals and tax refresh render real server numbers consistently');
 console.log('PASS: real deployed financial RPC snapshot → actual projectStats/UI numeric results, AR 1720/AP 970, ООО costs 440+VAT 20, ИП 80 accrued/50 paid, balance 670');
}

if(fs.existsSync('tests/artifacts/deferred-server-snapshot.json')){
 const live=JSON.parse(fs.readFileSync('tests/artifacts/deferred-server-snapshot.json','utf8'));Object.assign(ctx,live);const p=live.projects[0],a=ctx.projectStats(p.id);
 assert.equal(a.materialsActual,325);assert.equal(a.operatingExpense,325);assert.equal(a.profit,175);assert.equal(a.payable,150);assert.equal(a.vatInputCredit,22);assert.equal(a.vatRemaining,88);
 const tax=ctx.vatHistoryData('2026-Q4');assert.equal(tax.inputTotal,22);assert.equal(tax.pendingMaterialCredits[0].remainingBase,150);
 ctx.render();assert.equal(ctx.$('expense').textContent,'100.00');assert.equal(ctx.$('net').textContent,'400.00');assert.equal(Number(live.agent_cash.expense),100);
 console.log('PASS: actual deferred server numbers → project cost 325 (receipt counted once), cash payment 100/balance 400, AP 150, input VAT 22 only on repayment; formulas preserved');
}

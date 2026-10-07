const vm=require('node:vm'),assert=require('node:assert/strict'),{plain}=require('./load-edge.cjs');const ctx={};vm.createContext(ctx);vm.runInContext(plain('supabase/functions/agent-worker/analysis.ts')+'\nthis.validate=validateExtraction;',ctx);
function sample(){return {summary:'Спецификация',pages:[{number:3,readable:true,notes:''},{number:4,readable:false,notes:'Не читается'}],rows:[{name:'Кабель',unit:'м',quantity:'10.5',kind:'material',provenance:'extracted',source_page:3,source_quote:'Кабель 10,5 м',formula:null,questions:[]}],risks:[]};}
let data=ctx.validate(sample(),3,4);assert.equal(data.rows[0].kind,'material');assert.equal(data.rows[0].review_status,'needs_review');assert.deepEqual(Array.from(data.coverage.unreadable),[4]);
data=sample();data.rows[0].source_page=4;assert.equal(ctx.validate(data,3,4).rows[0].quantity,null);
data=sample();data.rows[0].quantity='NaN';assert.throws(()=>ctx.validate(data,3,4));
data=sample();data.pages.pop();assert.throws(()=>ctx.validate(data,3,4));
data=sample();data.rows[0].provenance='derived';assert.throws(()=>ctx.validate(data,3,4));
data=sample();data.rows[0].source_page=1;assert.throws(()=>ctx.validate(data,3,4));
console.log('PASS: source page coverage, unreadable quantities unknown, material/work distinction, draft review, invalid arithmetic/provenance');

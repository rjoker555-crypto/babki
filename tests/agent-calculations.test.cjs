const vm=require('node:vm'),assert=require('node:assert/strict'),{plain}=require('./load-edge.cjs');const ctx={};vm.createContext(ctx);vm.runInContext(plain('supabase/functions/main-agent/calculations.ts')+'\nthis.calculate=calculateEstimate;',ctx);
const result=ctx.calculate([{name:'Кабель',unit:'м',quantity:'12.5',unit_price:'13.37',price_source:'Прайс, предоставленный владельцем'},{name:'Монтаж',unit:'м',quantity:'12.5',unit_price:'10',price_source:'Согласованная ставка'}]);
assert.equal(result.rows[0].amount,'167.13');assert.equal(result.total,'292.13');
assert.equal(ctx.calculate([{name:'Тест',unit:'шт',quantity:'0.1',unit_price:'0.2',price_source:'Тест'}]).total,'0.02');
assert.throws(()=>ctx.calculate([{name:'Тест',unit:'шт',quantity:'NaN',unit_price:'1',price_source:'Тест'}]));
assert.throws(()=>ctx.calculate([{name:'Тест',unit:'шт',quantity:'1',unit_price:'1',price_source:''}]));
console.log('PASS: exact decimal estimate, per-line half-up rounding, missing sources and invalid quantities');

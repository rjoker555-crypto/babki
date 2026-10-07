// Exact decimal arithmetic for a draft estimate. This does not define company margin/tax methodology.
function decimal(value){
 if(typeof value!=='string'||!/^\d{1,12}(?:\.\d{1,6})?$/.test(value))throw new Error('Expected non-negative exact decimal string');
 const [whole,fraction='']=value.split('.');return BigInt(whole)*1000000n+BigInt(fraction.padEnd(6,'0'));
}
function money(cents){return (cents/100n).toString()+'.'+(cents%100n).toString().padStart(2,'0');}
export function calculateEstimate(lines){
 if(!Array.isArray(lines)||!lines.length||lines.length>100)throw new Error('Expected 1..100 estimate lines');let total=0n;
 const rows=lines.map(line=>{
  if(!line||typeof line.name!=='string'||!line.name.trim()||typeof line.unit!=='string'||!line.unit.trim()||typeof line.price_source!=='string'||!line.price_source.trim())throw new Error('Name, unit and explicit price source required');
  const quantity=decimal(line.quantity),price=decimal(line.unit_price);const cents=(quantity*price+5000000000n)/10000000000n;total+=cents;
  return {...line,amount:money(cents)};
 });
 return {rows,total:money(total),currency:'RUB',method:'quantity_times_unit_price_v1',rounding:'half_up_each_line_2_decimals',limitations:['Draft arithmetic on the provided inputs. Price sources must be verified separately.','VAT, logistics and overhead are included only if explicitly present in the supplied prices.','This is not market validation, an approved budget or contractual price.']};
}

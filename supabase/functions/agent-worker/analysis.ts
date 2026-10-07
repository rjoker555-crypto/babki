export const extractionSchema={type:'object',properties:{summary:{type:'string'},pages:{type:'array',items:{type:'object',properties:{number:{type:'integer'},readable:{type:'boolean'},notes:{type:'string'}},required:['number','readable','notes'],additionalProperties:false}},rows:{type:'array',items:{type:'object',properties:{name:{type:'string'},unit:{type:'string'},quantity:{type:['string','null']},kind:{type:'string',enum:['work','material','equipment']},provenance:{type:'string',enum:['extracted','derived','unknown']},source_page:{type:'integer'},source_quote:{type:'string'},formula:{type:['string','null']},questions:{type:'array',items:{type:'string'}}},required:['name','unit','quantity','kind','provenance','source_page','source_quote','formula','questions'],additionalProperties:false}},risks:{type:'array',items:{type:'string'}}},required:['summary','pages','rows','risks'],additionalProperties:false};
export function validateExtraction(data,start,end){
 if(!data||typeof data.summary!=='string'||data.summary.length>6000||!Array.isArray(data.rows)||data.rows.length>100||!Array.isArray(data.pages)||!Array.isArray(data.risks)||data.risks.length>40)throw new Error('Invalid extraction result');
 const expected=Array.from({length:end-start+1},(_,i)=>start+i);const observed=data.pages.map(p=>p.number);
 if(observed.length!==expected.length||new Set(observed).size!==expected.length||expected.some(n=>!observed.includes(n)))throw new Error('Page coverage not reported');
 for(const page of data.pages)if(typeof page.readable!=='boolean'||typeof page.notes!=='string'||page.notes.length>2000)throw new Error('Invalid page quality');
 for(const row of data.rows){
  if(typeof row.name!=='string'||!row.name.trim()||row.name.length>1000||typeof row.unit!=='string'||row.unit.length>100||!Number.isInteger(row.source_page)||row.source_page<start||row.source_page>end||typeof row.source_quote!=='string'||row.source_quote.length>2000||!['work','material','equipment'].includes(row.kind)||!['extracted','derived','unknown'].includes(row.provenance)||!Array.isArray(row.questions)||row.questions.length>20)throw new Error('Invalid takeoff row');
  if(row.quantity!==null&&(typeof row.quantity!=='string'||!/^\d{1,12}(?:\.\d{1,6})?$/.test(row.quantity)))throw new Error('Quantity must be an exact decimal or unknown');
  if(!data.pages.find(p=>p.number===row.source_page)?.readable||row.provenance==='unknown'){row.quantity=null;row.provenance='unknown';}
  if(row.provenance==='derived'&&(!row.formula||typeof row.formula!=='string'))throw new Error('Derived quantity requires its calculation method');
  if(row.provenance==='extracted'&&!row.source_quote.trim())throw new Error('Extracted quantity requires source evidence');
  row.review_status='needs_review'; // Model output is never an approved import.
 }
 return {...data,coverage:{from:start,to:end,unreadable:data.pages.filter(p=>!p.readable).map(p=>p.number)},limitations:['Draft extraction; human review required.','Material quantity is not automatically installation volume.','No market prices or cost total without confirmed rates.']};
}

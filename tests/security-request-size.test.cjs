const vm=require('node:vm'),assert=require('node:assert/strict'),{mainSource}=require('./load-edge.cjs');
(async()=>{
 const ctx={TextDecoder,Uint8Array,Response,AbortSignal};vm.createContext(ctx);vm.runInContext(mainSource(),ctx);
 assert.equal(await ctx.boundedRequestText(new Request('https://test',{method:'POST',body:'а'.repeat(500)}),1000),'а'.repeat(500));
 assert.equal(await ctx.boundedRequestText(new Request('https://test',{method:'POST',headers:{'Content-Length':'1'},body:'а'.repeat(501)}),1000),null);
 console.log('PASS: actual streamed UTF-8 byte limit ignores forged Content-Length');
})().catch(e=>{console.error(e);process.exit(1)});

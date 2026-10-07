const fs=require('node:fs'),assert=require('node:assert/strict'),{chromium}=require('playwright');
(async()=>{
 const html=fs.readFileSync('index.html','utf8'),source=html.slice(html.indexOf('function showUntrustedDocumentHtml('),html.indexOf('async function viewProjectDocument('));
 const browser=await chromium.launch({channel:'msedge',headless:true});const page=await browser.newPage();let external=0;
 await page.route('https://security-test.invalid/**',r=>r.fulfill({contentType:'text/html',body:'<div id="box"></div>'}));await page.route('https://attack.invalid/**',r=>{external++;return r.abort()});await page.goto('https://security-test.invalid/');
 await page.evaluate(()=>{localStorage.setItem('session-test','private');window.compromised=false});await page.addScriptTag({content:source});
 await page.evaluate(()=>showUntrustedDocumentHtml(document.getElementById('box'),'<h1>Ведомость</h1><script>parent.compromised=true</script><img src="https://attack.invalid/steal" onerror="parent.compromised=true"><a href="javascript:parent.compromised=true">click</a><form action="https://attack.invalid/steal"><input name="secret"></form>'));
 const frame=page.frames()[1];await frame.waitForSelector('h1');assert.equal(await frame.locator('h1').innerText(),'Ведомость');await frame.locator('a').click();assert.equal(await page.evaluate(()=>window.compromised),false);assert.equal(external,0);
 assert.equal(await page.locator('iframe').getAttribute('sandbox'),'');assert.equal(await frame.evaluate(()=>{try{return parent.localStorage.getItem('session-test')}catch{return 'denied'}}),'denied');
 await browser.close();console.log('PASS: Word/Excel preview keeps text while blocking scripts, parent/session access and external requests');
})().catch(e=>{console.error(e);process.exit(1)});

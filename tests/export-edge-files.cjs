const fs=require('node:fs');const shared=['_shared/http.ts'];
function files(paths){return paths.map(path=>({name:path,content:fs.readFileSync('supabase/functions/'+path,'utf8')}));}
process.stdout.write(JSON.stringify({
 main:files(['main-agent/index.ts','main-agent/schema.ts','main-agent/modules.ts','main-agent/calculations.ts','main-agent/documents.ts','main-agent/tools.ts','_shared/report-renderers.js','_shared/report-service.ts','_shared/text-revision.ts',...shared]),
 uploads:files(['agent-files/index.ts','_shared/office-file.ts',...shared]),
 worker:files(['agent-worker/index.ts','agent-worker/analysis.ts','main-agent/modules.ts',...shared])
}));

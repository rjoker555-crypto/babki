import { specializationModules } from './modules.ts';
import { schema } from './schema.ts';
import { calculateEstimate } from './calculations.ts';
import { readCompanyDocument,getCompanyDocumentFile } from './documents.ts';
import { cleanupDocumentFiles } from '../_shared/http.ts';
import { draftTextRevision } from '../_shared/text-revision.ts';
import { buildExistingReport,getExistingFinancialMetrics } from '../_shared/report-service.ts';
const str={type:'string'},nullable={type:['string','null']};
function tool(name,description,properties){return {type:'function',name,description,strict:true,parameters:{type:'object',properties,required:Object.keys(properties),additionalProperties:false}};}
const registers={receivable:'receivables',payable:'payables',material:'project_materials',other_expense:'project_other_expenses',subcontractor:'subcontractors',creditor:'creditors'};
const teamRecords={employee:'org_employees',org_expense:'org_expenses',event:'events',contact:'project_customer_contacts',task:'project_work_tasks',pto_record:'pto_documents'};
export const subjectTools=[
 tool('draft_text_revision','Подготовить настоящий новый файл UTF-8 TXT с точными заменами. changes_json=[{find,replace,expected_occurrences}]. Сначала прочитать исходник и не угадывать пункты. DOCX/PDF/XLSX — только готовая редакция пользователя через замену. Возвращает diff, файл и исходный полный expected; текущий документ пока не изменяет. Далее propose_document replace и подтверждение.',{document_id:str,changes_json:{type:'string',maxLength:30000}}),
 tool('list_foreman_subcontractors','Только базовые субподрядчики назначенных объектов: без сумм и НДС. Для прораба.',{}),
 tool('propose_foreman_subcontractor','Добавить базового субподрядчика на назначенный объект: только project_id,name,comment, без финансовых полей. Существующий foreman_add_subcontractor после точного подтверждения.',{project_id:str,name:str,comment:nullable}),
 tool('get_project_settings','Свежие назначения, ответственный и существующий регламент подачи объекта. Директор; ответственный сохраняет доступ независимо от флага члена команды. Возвращает snapshot для expected и список активных аккаунтов прорабов.',{project_id:str}),
 tool('propose_project_settings','Отдельный план назначения/снятия прораба либо ответственного и настройки существующего регламента. command_json: kind=assignment,project_id,user_id,is_active,expected=полный snapshot; kind=responsible,user_id=активный ID/null; kind=volume_rule,config={project_id,assignee_id,expected_version,due_day,reminder_time,short_month_policy=skip/last_day,period_offset=-1/0,enabled,authority_basis}. Не придумывать расписание/полномочия. Сначала get_project_settings. Только директор после точного подтверждения.',{command_json:{type:'string',maxLength:30000}}),
 tool('propose_project_delete','Согласованное атомарное удаление объекта со всеми дочерними финансовыми/производственными данными, версиями документов, назначениями и регламентами. Сначала get_project_card; expected_json — полный свежий project. Возвращает точный перечень и последствия для подтверждения. Личные файлы и общие контрагенты сохраняются; сторонние связанные операции требуют отдельного разрыва связей. Storage очищается с проверяемой очередью.',{project_id:str,expected_json:{type:'string',maxLength:16000}}),
 tool('build_existing_report','Сформировать настоящий файл существующего отчёта приложения, без новой финансовой методики: statement — HTML-выписка объекта; statement_text — настоящий TXT существующей выписки; organization_month — месячный финансовый/организационный; production — выполненные работы за точный from/to; proposals — статистика КП. Отдаёт готовый HTML-файл с текущим форматированием, ссылкой на 60 секунд и проверенным хэшем. Откройте и сохраните в PDF через штатную печать браузера; непосредственно PDF сервер не выдаёт. Объект обязателен для statement/production; month YYYY-MM для organization_month. Чтение без подтверждения. Неполные выборки не выдаются.',{kind:{type:'string',enum:['statement','statement_text','organization_month','production','proposals']},project_id:nullable,month:nullable,company:{type:'string',enum:['all','ООО','ИП']},from:nullable,to:nullable}),
 tool('list_proposals','Существующие КП с реквизитами и письмом: query/name, status=review/won/lost или null, до 30 за страницу. Полные свежие записи для точного expected перед изменением.',{query:nullable,status:{type:['string','null'],enum:['review','won','lost',null]},offset:{type:'integer',minimum:0,maximum:30000}}),
 tool('propose_proposal','КП: command_json action=create/update/delete, values={name,city,customer,amount,status=review/won/lost,segment=commercial/government,source,sent_date,expected_review_date,review_deadline,lost_reason,comment}. При lost обязательна причина. Update/delete: id и полный expected из list_proposals. file_id — своё готовое письмо из чата; replace сохраняет общие/личные файлы; remove_letter=true явно убирает письмо. Требует точного подтверждения, управляющий не удаляет КП.',{command_json:{type:'string',maxLength:30000}}),
 tool('list_work_templates','Сохранённые составы назначенного объекта. template_id=null — список до 30; точный ID возвращает состав работ и материалов для просмотра/применения. Шаблон доступен только своему объекту.',{project_id:str,template_id:nullable,offset:{type:'integer',minimum:0,maximum:30000}}),
 tool('propose_save_template','Сохранить существующий состав: command_json kind=save_template, values={project_id,name,comment}, items=[{work_catalog_id,work_name,unit,planned_volume,comment,materials:[{material_catalog_id,material_name,unit,quantity,comment,material_role,dependency_group,option_group}]}]. Полный выбранный состав, нормы не выдумывать. План и подтверждение; дубль имени отклоняется.',{command_json:{type:'string',maxLength:30000}}),
 tool('propose_apply_template','Применить сохранённый состав: command_json kind=apply_template, template_id, values={project_id,name?,comment?,start_date?,end_date?}. Читает точный сохранённый состав, создаёт новый раздел со всеми работами/материалами атомарно после подтверждения; существующий факт не переносится и не удаляется.',{command_json:{type:'string',maxLength:30000}}),
 tool('list_production_records','Свежие производственные записи назначенного объекта: sections/works/facts/materials. Для facts/materials обязателен work_item_id. Возвращает полные строки для expected, до 30 за страницу; не финансовые данные.',{project_id:str,kind:{type:'string',enum:['sections','works','facts','materials']},work_item_id:nullable,offset:{type:'integer',minimum:0,maximum:30000}}),
 tool('search_production_catalog','Существующий справочник работ/материалов/норм/вариантов. kind=works/materials/rules/options; rules/options требуют work_catalog_id. Чтение без создания новых справочников, до 30 за страницу. quantity материалов в существующей форме — выбранная норма на единицу; не умножай её повторно на planned_volume.',{kind:{type:'string',enum:['works','materials','rules','options']},query:nullable,work_catalog_id:nullable,offset:{type:'integer',minimum:0,maximum:30000}}),
 ...['work','section','manual_fact'].map(kind=>tool('propose_'+kind,({work:'Работа: create/update/delete/complete. values: project_id, section_id, work_catalog_id, work_name, unit, planned_volume, start_date/end_date, status, comment, primary_material_catalog_id. materials — полный явно согласованный список норм; отсутствие сохраняет список, [] удаляет. Не придумывай нормы; читай справочник. complete атомарно добавляет только оставшийся ручной факт. Удаление с подачей требует сначала отдельно удалить подачу.',section:'Раздел: create/update/delete. values: project_id, name, start_date/end_date, status, comment. works — список команд kind=work action=create/update; неуказанные работы сохраняются, сроки синхронизируются у всех детей. Delete согласовывает работы, материалы и историю, при подачах сначала отдельное удаление подачи.',manual_fact:'Ручной факт: create/update/delete. values: work_item_id, progress_date (обязательна), completed_volume>0, comment. Не меняет факты подачи объёмов, сохраняет прежний ручной базовый факт.'}[kind])+' command_json содержит kind='+kind+', action, values; update/delete/complete требуют id и полный expected из list_production_records. Обязателен точный план с подтверждением.',{command_json:{type:'string',maxLength:30000}})),
 tool('retry_document_cleanup','Повторить только уже согласованную очистку удалённого документа по cleanup_request_id из результата. Новое удаление не создаётся; сервер проверяет владельца исходного запроса и точный ранее согласованный перечень файлов.',{request_id:str}),
 tool('get_document_metadata','Свежая карточка документа и сохранённые версии перед заменой/удалением. Только разрешённый документ; содержимое файла не читается.',{document_id:str}),
 tool('propose_document','Настоящий план документа: command_json action=attach/replace/metadata/delete. Attach: project_id, document_type=contract/project/estimate/addendum/other, file_id своего загруженного файла, values(title/document_number/document_date/comment). Replace: id, expected из get_document_metadata, новый file_id, values только изменяемых реквизитов; старая версия сохраняется. Metadata меняет только реквизиты, не текст файла. Delete: id/expected, values={}; точный перечень версий и файлов на подтверждение, общие/личные файлы сохраняются. Для изменения содержания DOCX/PDF/XLSX подготовь готовый файл вне приложения и загрузи его — редактора с сохранением форматирования/подписей/формул сейчас нет. Для явного изменения цены по ДС price_change={expected_project,new_amount,change_date,reason_text}; это отдельные точно согласованные параметры, без чтения суммы из файла.',{command_json:{type:'string',maxLength:30000}}),
 tool('get_document_file','Получить настоящий файл текущего документа либо точной старой версии в закрытом Storage. Возвращает ссылку на 60 секунд, доступ проверяется заново. version_id=null — текущий файл; прежние версии сначала list_document_versions. Ссылка не означает чтение содержания.',{document_id:str,version_id:nullable}),
 tool('list_document_versions','Список сохранённых версий разрешённого документа для выбора файла. До 30 за страницу.',{document_id:str,offset:{type:'integer',minimum:0,maximum:30000}}),
 ...Object.keys(teamRecords).map(kind=>tool('propose_'+kind,({employee:'Сотрудник: name, position, monthly_salary, payment_date/pay_day, company, comment, active. archive выключает будущие расходы, сохраняет историю выплат.',org_expense:'Постоянный организационный расход: name, category, monthly_amount, payment_date/pay_day, company, comment, active. archive сохраняет историю оплат.',event:'Событие: title, event_type, event_date (обязательна), company, planned_amount, comment. Удаление при оплатах запрещено.',contact:'Контакт заказчика: project_id, full_name, phone, position. Прораб только читает; изменение финансовые роли/управляющий.',pto_record:'Существующая запись ПТО: project_id, document_type=executive_schemes/aosr/work_log/cable_log/other, final_date обязательна, status=requested/in_progress/signing/signed, comment. Это учёт записи и статуса, не юридическая/ПТО специализация.',task:'Производственная задача: project_id, title, due_date, priority=low/normal/high, status=open/done, comment. Прораб только назначенный объект. Сотрудника-исполнителя отдельным полем в текущем UI нет, не выдумывать.'}[kind])+' План предметного действия; подтверждение обязательно. Update/delete/archive: record_id и свежий полный expected_json из list_team_records; values_json только порученные поля. Для archive/delete values_json="{}"; create record_id=null, expected_json="null".',{action:{type:'string',enum:['employee','org_expense'].includes(kind)?['create','update','archive']:['create','update','delete']},record_id:nullable,values_json:{type:'string',maxLength:10000},expected_json:{type:'string',maxLength:16000}})),
 tool('list_team_records','Свежие сотрудники/орг. расходы/события либо контакты/задачи точного объекта. Доступ проверяется существующими RLS; для контактов/задач project_id обязателен, до 30 записей на странице.',{kind:{type:'string',enum:Object.keys(teamRecords)},project_id:nullable,offset:{type:'integer',minimum:0,maximum:30000}}),
 tool('list_work_volumes','Свежие подачи объёмов и фактические работы разрешённого производственного объекта. Прорабу только назначенный объект; страницы до 30 подач.',{project_id:str,offset:{type:'integer',minimum:0,maximum:30000}}),
 tool('propose_work_volumes','Подготовить атомарную подачу объёмов через существующую ручную команду. payload_json: operation=save/delete, project_id, submission_id/expected_updated_at при замене/удалении; save требует period_from/to, comment, items [{work_item_id,completed_volume,progress_date,unit_count,section_label}]. completed_volume уже включает количество одинаковых узлов — не умножать дважды. Сначала list_work_volumes и get_project_context. Не менять общий completed_volume работы напрямую. Все ручные факты сохраняются; план требует подтверждения.',{payload_json:{type:'string',maxLength:30000}}),
 tool('get_project_card','Свежая полная карточка и все позиции затрат для согласованного редактирования, только доверенному директору.',{project_id:str}),
 tool('propose_project_card','Изменить карточку и связанные позиции одной транзакцией. command_json: action=update, id, expected (полная свежая projects), values (только порученные поля), cost_changes (массив предметных команд kind=subcontractor/material/other_expense, action=create/update/delete, id/expected при изменении, values). Не передавай project_id в values дочерней записи, он закрепляется сервером. Перед изменением get_project_card. Не удаляет объект и не изменяет документы/ДС.',{command_json:{type:'string',maxLength:30000}}),
 ...Object.keys(registers).map(kind=>tool('propose_'+kind,({receivable:'Дебиторка: project_id, customer, amount, document_type/number/date/status, due_date, comment; paid_amount запрещён.',payable:'Кредиторка: counterparty, project_id, amount, due_date, document_type/number/date, comment. Кредит без операции требует is_credit, owner_company, credit_kind, credit_start_date, full_repayment_date. Связанный источник кредита менять через propose_credit; paid_amount запрещён.',material:'Позиция ТМЦ: project_id, name, planned_amount, actual_amount (общий ручной факт, не добавка), expense_date, comment.',other_expense:'Позиция прочих затрат: project_id, name, planned_amount, actual_amount (общий ручной факт), expense_date, comment.',subcontractor:'Субподрядчик: project_id, name, planned_amount, has_vat, comment. Оплаты — отдельные операции.',creditor:'Справочник кредиторов: name, без дубликатов.'}[kind])+' Предметный план create/update/delete. Update/delete: свежая запись из list_financial_registers и полный expected_json. Create: record_id=null, expected_json="null". values_json содержит только порученные поля; delete="{}". Удаление/перенос позиции с операциями запрещены, сумма долга не ниже оплаченного. Не исполняет до подтверждения.',{action:{type:'string',enum:['create','update','delete']},record_id:nullable,values_json:{type:'string',maxLength:10000},expected_json:{type:'string',maxLength:16000}})),
 tool('list_financial_registers','Свежие записи финансового регистра перед предметным изменением. Для material/other_expense/subcontractor/receivable нужен точный project_id. Не возвращает всю базу, до 30 записей за страницу.',{kind:{type:'string',enum:Object.keys(registers)},project_id:nullable,offset:{type:'integer',minimum:0,maximum:30000}}),
 tool('propose_credit','Проверенный атомарный план получения/изменения/удаления кредита либо ТМЦ с отсрочкой. values_json: операция; credit_json: due_date и full_repayment_date (обязательны, не выдумывать). Для update/delete сначала получить операции и get_operation_options, передать полный expected_json и expected_credit_json связанного долга. Для удаления/снятия отсрочки нужны отсутствующие погашения. Получение ТМЦ повышает факт позиции, не денежный расход; погашение отдельной propose_operation.',{action:{type:'string',enum:['create','update','delete']},operation_id:nullable,values_json:{type:'string',maxLength:10000},credit_json:{type:'string',maxLength:3000},expected_json:{type:'string',maxLength:16000},expected_credit_json:{type:'string',maxLength:10000}}),
 tool('list_operations','Актуальные финансовые операции для выбора перед изменением. sort=operation_date — последние по дате операции; sort=created_at — последние внесённые. При различии и слове «последняя» уточни смысл. Доступ только директор/финансы/бухгалтер.',{project_id:nullable,operation_type:{type:['string','null'],enum:['income','expense','credit',null]},sort:{type:'string',enum:['operation_date','created_at']},offset:{type:'integer',minimum:0,maximum:30000}}),
 tool('get_operation_options','Известные параметры финансовой операции: организация объекта, конкретные долги, субподрядчики, позиции материалов/расходов и орг. потребители. Не выбирай долг произвольно. В каждой группе максимум 30 записей.',{project_id:nullable}),
 tool('propose_operation','Подготовить проверенный план; не исполняет запись. values_json — JSON с полями operation_type (income/expense), article (например Аванс заказчика), amount (число рублей), project_id и только известными связями. Полей type/description нет. Create: operation_id=null, expected_json="null"; дату можно не передавать, сервер ставит сегодня. Update/delete: сначала list_operations, operation_id и expected_json — полный оригинал, только порученные поля; delete values_json="{}". Кредиты/ТМЦ с отсрочкой — propose_credit.',{action:{type:'string',enum:['create','update','delete']},operation_id:nullable,values_json:{type:'string',maxLength:10000},expected_json:{type:'string',maxLength:16000}}),
 tool('propose_project','Подготовить объект по известной информации. name обязательно; договорная сумма=planned_revenue, организация=contractor_company ООО/ИП. Неизвестные необязательные сведения не передавать, не придумывать даты и ответственных. Сначала list_projects для проверки похожих названий. Сервер блокирует точный дубль. Создание после подтверждения; права финансовых ролей совпадают с ручной карточкой.',{values_json:{type:'string',maxLength:10000}}),
 tool('select_specialization','Загрузить нужную специализацию единого помощника.',{module:{type:'string',enum:Object.keys(specializationModules)}}),
 tool('get_table_schema','Поля старого раздела для совместимого директорского действия; выдаётся только нужная схема.',{table:{type:'string',enum:Object.keys(schema)}}),
 tool('calculate_estimate','Точная арифметика черновой сметы по заданным количествам и ценам. JSON строк: name, unit, quantity и unit_price как decimal-строки, price_source. Не придумывай расценки. До 100 строк.',{lines_json:{type:'string',maxLength:30000}}),
 tool('list_projects','Найти разрешённые объекты по названию. Вернёт до 30; offset позволяет продолжить.',{query:str,offset:{type:'integer',minimum:0,maximum:30000}}),
 tool('get_project_context','Получить производственный контекст, работы, документы и собственные задачи объекта. Не раскрывает прорабу цены.',{project_id:str}),
 tool('get_financial_metrics','Проверенные показатели объекта по существующим projectStats и налоговому регистру ручного UI: план/факт затрат, прибыль, дебиторка/кредиторка, управленческий НДС 22%/налог ИП 8%, плюс отдельно движение денег. Денежный баланс не считать прибылью. Директор.',{project_id:str}),
 tool('search_company_documents','Метаданные разрешённых документов объекта. query — короткое название файла или документа; пустая строка показывает документы объекта. При отсутствии точного совпадения вернёт доступные документы с отметкой fallback. Содержание читай через read_company_document.',{project_id:str,query:str}),
 tool('read_company_document','Прочитать содержимое существующего документа объекта из закрытого хранилища: DOCX/TXT текст с источниками, PDF страницы. Для анализа договора обязательно вызови этот инструмент после поиска. offset=0 сначала; DOCX/TXT offset в символах, PDF в страницах с нуля; next_offset позволяет дочитать. Контракты — доверенному директору и управляющему по существующим правам ручного просмотра; прораб читает только проект назначенного объекта.',{document_id:str,offset:{type:'integer',minimum:0,maximum:500000}}),
 tool('list_chat_files','Список собственных файлов этого чата и связанных фоновых разборов.',{}),
 tool('analyze_project','Поставить собственный PDF/TXT проект в долговременную очередь разбора. Вернёт job_id, а не готовый расчёт.',{file_id:str,instruction:str}),
 tool('get_job_status','Получить статус своего разбора, проверенные фрагменты, ведомость, вопросы и неполноту.',{job_id:str}),
 tool('cancel_job','Отменить свою фоновую задачу без удаления файла или результатов.',{job_id:str}),
 tool('propose_project_from_file','Предложить создание объекта и прикрепление собственного проекта. Никакой записи объекта до точного подтверждения директора.',{file_id:str,name:str,customer:nullable}),
 tool('propose_attach_project','Предложить прикрепление собственного файла к существующему объекту. Требует точного подтверждения директора.',{file_id:str,project_id:str}),
 tool('get_my_tasks','Собственные задачи и уведомления. Прочтение не означает выполнение.',{})
];
export async function executeSubjectTool(name,args,ctx){
 const actor=await ctx.db('profiles?select=role,is_active&id=eq.'+ctx.owner,{},true);
 if(!actor[0]?.is_active)throw new Error('Active account required');
 if(ctx.director){const access=actor[0].role==='director'?await ctx.db('agent_director_access?select=user_id&user_id=eq.'+ctx.owner,{},true):[];if(access.length!==1)throw new Error('Director access revoked');}
 const contract=subjectTools.find(t=>t.name===name);if(!contract)throw new Error('Unknown subject tool');
 if(!args||typeof args!=='object'||Array.isArray(args)||Object.keys(args).some(k=>!Object.hasOwn(contract.parameters.properties,k))||contract.parameters.required.some(k=>!Object.hasOwn(args,k)))throw new Error('Invalid tool arguments');
 for(const [key,value] of Object.entries(args)){
  const shape=contract.parameters.properties[key];
  if(value===null&&Array.isArray(shape.type)&&shape.type.includes('null'))continue;
  if(shape.type==='integer'){if(!Number.isInteger(value)||value<shape.minimum||value>shape.maximum)throw new Error('Invalid '+key);}
  else if(typeof value!=='string'||value.length>(shape.maxLength||2000)||(shape.enum&&!shape.enum.includes(value)))throw new Error('Invalid '+key);
  if(key.endsWith('_id')&&!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value))throw new Error('Invalid UUID');
 }
 if(['get_project_settings','propose_project_settings','propose_project_delete'].includes(name)){
  if(name==='propose_project_delete'?(!['director','finance','accountant'].includes(actor[0].role)||actor[0].role==='director'&&!ctx.director):!ctx.director)throw new Error('Project access denied');
  if(name==='get_project_settings')return {snapshot:await ctx.db('rpc/get_project_settings',{method:'POST',body:JSON.stringify({p_project:args.project_id})}),foremen:await ctx.db('profiles?select=id,full_name,role,is_active&role=eq.foreman&is_active=eq.true&order=id&limit=200')};
  const command=name==='propose_project_delete'?{action:'delete',project_id:args.project_id,expected:JSON.parse(args.expected_json)}:JSON.parse(args.command_json);
  const plan=await ctx.db('rpc/agent_prepare_operator_plan',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_chat:ctx.chat,p_request:ctx.message,p_kind:name==='propose_project_delete'?'project_delete':'project_settings_write',p_command:command})},true);
  return {status:'awaiting_confirmation',plan_id:plan.id,revision:plan.revision,kind:plan.kind,command:plan.command_json,preview:plan.preview_json,execution_confirmed:false};
 }
 if(['list_foreman_subcontractors','propose_foreman_subcontractor'].includes(name)){
  if(actor[0].role!=='foreman')throw new Error('Foreman account required');
  if(name==='list_foreman_subcontractors')return ctx.db('rpc/foreman_subcontractors',{method:'POST',body:'{}'});
  const command={kind:'foreman_subcontractor',action:'create',values:args};
  const plan=await ctx.db('rpc/agent_prepare_operator_plan',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_chat:ctx.chat,p_request:ctx.message,p_kind:'production_write',p_command:command})},true);
  return {status:'awaiting_confirmation',plan_id:plan.id,revision:plan.revision,kind:plan.kind,command:plan.command_json,execution_confirmed:false};
 }
 if(name==='draft_text_revision'){if(!['director','manager'].includes(actor[0].role)||actor[0].role==='director'&&!ctx.director)throw new Error('Document access denied');const documents=await ctx.db('project_documents?select=*&id=eq.'+args.document_id);if(documents.length!==1)throw new Error('Document access denied');const source=await getCompanyDocumentFile({document_id:args.document_id,version_id:null},ctx);return draftTextRevision(args,ctx,source,documents[0]);}
 if(name==='build_existing_report')return buildExistingReport(args,ctx,actor[0]);
 if(['list_proposals','propose_proposal'].includes(name)){
  if(!['director','finance','accountant','manager'].includes(actor[0].role)||actor[0].role==='director'&&!ctx.director)throw new Error('Proposal access denied');
  if(name==='list_proposals'){const rows=await ctx.db('commercial_proposals?select=*&order=created_at.desc,id&limit=31&offset='+args.offset+(args.status?'&status=eq.'+args.status:'')+(args.query?'&name=ilike.'+encodeURIComponent('%'+args.query.replace(/[%*]/g,'')+'%'):''));return {records:rows.slice(0,30),has_more:rows.length>30,next_offset:rows.length>30?args.offset+30:null};}
  const command=JSON.parse(args.command_json);if(Object.hasOwn(command,'uploaded_file'))throw new Error('Use own prepared file_id');
  const plan=await ctx.db('rpc/agent_prepare_operator_plan',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_chat:ctx.chat,p_request:ctx.message,p_kind:'proposal_write',p_command:command})},true);
  return {status:'awaiting_confirmation',plan_id:plan.id,revision:plan.revision,kind:plan.kind,command:plan.command_json,execution_confirmed:false};
 }
 if(['propose_work','propose_section','propose_manual_fact','propose_save_template','propose_apply_template','list_work_templates','list_production_records','search_production_catalog'].includes(name)){
  if(!['director','finance','accountant','manager','foreman'].includes(actor[0].role))throw new Error('Production access denied');
  if(name.startsWith('propose_')){
   const command=JSON.parse(args.command_json);if(command.kind!==name.slice(8))throw new Error('Production kind mismatch');
   const plan=await ctx.db('rpc/agent_prepare_operator_plan',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_chat:ctx.chat,p_request:ctx.message,p_kind:'production_write',p_command:command})},true);
   return {status:'awaiting_confirmation',plan_id:plan.id,revision:plan.revision,kind:plan.kind,command:plan.command_json,execution_confirmed:false};
  }
  let path;
  if(name==='list_work_templates'){
   if(!await ctx.db('rpc/agent_project_scope',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_project:args.project_id})},true))throw new Error('Project access denied');
   const rows=await ctx.db('project_work_section_templates?select=*&project_id=eq.'+args.project_id+(args.template_id?'&id=eq.'+args.template_id:'')+'&order=id&limit=31&offset='+args.offset);
   if(!args.template_id)return {records:rows.slice(0,30),has_more:rows.length>30};if(rows.length!==1)throw new Error('Template access denied');
   const items=await ctx.db('project_work_section_template_items?select=*&template_id=eq.'+args.template_id+'&order=sort_order,id&limit=201');if(items.length>200)throw new Error('Template too large');
   const result=[];for(const item of items){const materials=await ctx.db('project_work_section_template_materials?select=*&template_item_id=eq.'+item.id+'&order=sort_order,id&limit=201');if(materials.length>200)throw new Error('Template materials too large');result.push({...item,materials});}
   return {template:rows[0],items:result};
  }
  if(name==='search_production_catalog'){
   const table={works:'work_catalog',materials:'material_catalog',rules:'work_catalog_materials',options:'work_material_options'}[args.kind];
   const cols={works:'id,name,unit,category',materials:'id,name,unit',rules:'id,work_catalog_id,material_catalog_id,recommended_quantity,material_role,norm_per_unit,norm_basis,option_group,dependency_group,default_option,recalc_on_primary_change,comment',options:'id,work_catalog_id,option_group,option_name,primary_material_catalog_id,secondary_material_catalog_id,norm_per_unit,norm_basis,is_default,is_active'}[args.kind];
   if(['rules','options'].includes(args.kind)&&!args.work_catalog_id)throw new Error('Work catalog selection required');
   path=table+'?select='+cols+(args.work_catalog_id&&['rules','options'].includes(args.kind)?'&work_catalog_id=eq.'+args.work_catalog_id:'')+(args.query&&['works','materials'].includes(args.kind)?'&name=ilike.'+encodeURIComponent('%'+args.query.replace(/[%*]/g,'')+'%'):'');
  }else{
   if(!await ctx.db('rpc/agent_project_scope',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_project:args.project_id})},true))throw new Error('Project access denied');
   const table={sections:'project_work_sections',works:'project_work_items',facts:'project_work_progress',materials:'project_work_materials'}[args.kind];
   if(['facts','materials'].includes(args.kind)){
    if(!args.work_item_id)throw new Error('Work item required');const works=await ctx.db('project_work_items?select=id&project_id=eq.'+args.project_id+'&id=eq.'+args.work_item_id);if(works.length!==1)throw new Error('Work access denied');
    path=table+'?select=*&work_item_id=eq.'+args.work_item_id;
   }else path=table+'?select=*&project_id=eq.'+args.project_id;
  }
  const rows=await ctx.db(path+'&order=id&limit=31&offset='+args.offset);return {records:rows.slice(0,30),has_more:rows.length>30,next_offset:rows.length>30?args.offset+30:null};
 }
 if(['list_operations','get_operation_options','propose_operation','propose_credit','list_financial_registers',...Object.keys(registers).map(k=>'propose_'+k)].includes(name)){
  if(!['director','finance','accountant'].includes(actor[0].role)&&!(actor[0].role==='manager'&&args.action==='create'&&['propose_material','propose_other_expense','propose_subcontractor'].includes(name)))throw new Error('Financial access denied');
  if(actor[0].role==='director'&&!ctx.director)throw new Error('Trusted director required');
  if(name==='list_financial_registers'){
   if(['material','other_expense','subcontractor','receivable'].includes(args.kind)&&!args.project_id)throw new Error('Project required');
   const rows=await ctx.db(registers[args.kind]+'?select=*&order=id&limit=31&offset='+args.offset+(args.kind==='creditor'?'':args.project_id?'&project_id=eq.'+args.project_id:'&project_id=is.null'));
   return {records:rows.slice(0,30),has_more:rows.length>30,next_offset:rows.length>30?args.offset+30:null};
  }
  const register=Object.keys(registers).find(k=>name==='propose_'+k);
  if(register){
   const command={kind:register,action:args.action,values:JSON.parse(args.values_json)};
   if(args.action!=='create'){command.id=args.record_id;command.expected=JSON.parse(args.expected_json);if(!command.id||!command.expected)throw new Error('Read original register first');}
   else if(args.record_id!==null||JSON.parse(args.expected_json)!==null)throw new Error('Create has no original register');
   const plan=await ctx.db('rpc/agent_prepare_operator_plan',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_chat:ctx.chat,p_request:ctx.message,p_kind:'obligation_write',p_command:command})},true);
   return {status:'awaiting_confirmation',plan_id:plan.id,revision:plan.revision,kind:plan.kind,command:plan.command_json,preview:plan.preview_json,execution_confirmed:false};
  }
  if(name==='list_operations'){
   const records=await ctx.db('operations?select=*&order='+args.sort+'.desc,created_at.desc,id.desc&limit=31&offset='+args.offset+(args.project_id?'&project_id=eq.'+args.project_id:'')+(args.operation_type?'&operation_type=eq.'+args.operation_type:''));
   return {records:records.slice(0,30),has_more:records.length>30,sort:args.sort,next_offset:records.length>30?args.offset+30:null};
  }
  if(name==='get_operation_options'){
   const scope=args.project_id?'&project_id=eq.'+args.project_id:'&project_id=is.null';const groups={};
   if(args.project_id){const project=await ctx.db('projects?select=id,name,contractor_company&id=eq.'+args.project_id);if(project.length!==1)throw new Error('Project not found');groups.project=project[0];}
   for(const table of ['receivables','payables',...(args.project_id?['subcontractors','project_materials','project_other_expenses']:['org_employees','org_expenses','events'])]){const rows=await ctx.db(table+'?select=*&order=id&limit=31'+(['org_employees','org_expenses','events'].includes(table)?'':scope));groups[table]={records:rows.slice(0,30),has_more:rows.length>30};}
   return groups;
  }
  const command={action:args.action,values:JSON.parse(args.values_json)};
  if(name==='propose_credit')command.credit=JSON.parse(args.credit_json);
  if(args.action!=='create'){command.id=args.operation_id;command.expected=JSON.parse(args.expected_json);if(!command.id||!command.expected)throw new Error('Read original operation first');}
  else if(args.operation_id!==null||JSON.parse(args.expected_json)!==null)throw new Error('Create has no original operation');
  if(name==='propose_credit'&&args.action!=='create')command.expected_credit=JSON.parse(args.expected_credit_json);
  const plan=await ctx.db('rpc/agent_prepare_operator_plan',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_chat:ctx.chat,p_request:ctx.message,p_kind:name==='propose_credit'?'credit_write':'operation_write',p_command:command})},true);
  return {status:'awaiting_confirmation',plan_id:plan.id,revision:plan.revision,kind:plan.kind,command:plan.command_json,preview:plan.preview_json,execution_confirmed:false};
 }
 if(name==='propose_project'){
  if(!['director','finance','accountant'].includes(actor[0].role)||actor[0].role==='director'&&!ctx.director)throw new Error('Financial access denied');
  const plan=await ctx.db('rpc/agent_prepare_operator_plan',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_chat:ctx.chat,p_request:ctx.message,p_kind:'project_create',p_command:JSON.parse(args.values_json)})},true);
  return {status:'awaiting_confirmation',plan_id:plan.id,revision:plan.revision,kind:plan.kind,command:plan.command_json,preview:plan.preview_json,execution_confirmed:false};
 }
 if(['get_project_card','propose_project_card'].includes(name)){
  if(!['director','finance','accountant'].includes(actor[0].role)||actor[0].role==='director'&&!ctx.director)throw new Error('Trusted director required');
  if(name==='get_project_card'){
   const rows=await ctx.db('projects?select=*&id=eq.'+args.project_id);if(rows.length!==1)throw new Error('Project not found');const result={project:rows[0]};
   for(const table of ['subcontractors','project_materials','project_other_expenses']){const rows=await ctx.db(table+'?select=*&project_id=eq.'+args.project_id+'&order=id&limit=201');result[table]={records:rows.slice(0,200),has_more:rows.length>200};}return result;
  }
  const plan=await ctx.db('rpc/agent_prepare_operator_plan',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_chat:ctx.chat,p_request:ctx.message,p_kind:'project_card_write',p_command:JSON.parse(args.command_json)})},true);
  return {status:'awaiting_confirmation',plan_id:plan.id,revision:plan.revision,kind:plan.kind,command:plan.command_json,preview:plan.preview_json,execution_confirmed:false};
 }
 if(['list_work_volumes','propose_work_volumes'].includes(name)){
  const payload=name==='propose_work_volumes'?JSON.parse(args.payload_json):null,project=payload?.project_id||args.project_id;
  if(!/^[0-9a-f-]{36}$/i.test(project||'')||!ctx.director&&await ctx.db('rpc/agent_project_scope',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_project:project})},true)!==true)throw new Error('Project access denied');
  if(name==='list_work_volumes'){
   const rows=await ctx.db('work_volume_submissions?select=*&project_id=eq.'+project+'&order=period_to.desc,id&limit=31&offset='+args.offset);const items=[];
   for(const row of rows.slice(0,30))items.push(...await ctx.db('work_volume_submission_items?select=*&submission_id=eq.'+row.id+'&order=id&limit=501'));
   return {records:rows.slice(0,30),items,has_more:rows.length>30,next_offset:rows.length>30?args.offset+30:null};
  }
  const plan=await ctx.db('rpc/agent_prepare_operator_plan',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_chat:ctx.chat,p_request:ctx.message,p_kind:'volume_write',p_command:payload})},true);
  const preview={...plan.preview_json,works:(plan.preview_json.works||[]).map(w=>Object.fromEntries(['id','project_id','work_name','unit','planned_volume','completed_volume','status','section_id','updated_at'].filter(k=>Object.hasOwn(w,k)).map(k=>[k,w[k]])))};
  return {status:'awaiting_confirmation',plan_id:plan.id,revision:plan.revision,kind:plan.kind,command:plan.command_json,preview,execution_confirmed:false};
 }
 if(name==='list_team_records'||Object.keys(teamRecords).some(k=>name==='propose_'+k)){
  if(actor[0].role==='director'&&!ctx.director)throw new Error('Trusted director required');
  if(name==='list_team_records'){
   if(['contact','task','pto_record'].includes(args.kind)&&!args.project_id)throw new Error('Project required');
   const rows=await ctx.db(teamRecords[args.kind]+'?select=*&order=id&limit=31&offset='+args.offset+(['contact','task','pto_record'].includes(args.kind)?'&project_id=eq.'+args.project_id:''));
   return {records:rows.slice(0,30),has_more:rows.length>30,next_offset:rows.length>30?args.offset+30:null};
  }
  const kind=Object.keys(teamRecords).find(k=>name==='propose_'+k),command={kind,action:args.action,values:JSON.parse(args.values_json)};
  if(args.action!=='create'){command.id=args.record_id;command.expected=JSON.parse(args.expected_json);if(!command.id||!command.expected)throw new Error('Read original team record first');}
  else if(args.record_id!==null||JSON.parse(args.expected_json)!==null)throw new Error('Create has no original team record');
  const plan=await ctx.db('rpc/agent_prepare_operator_plan',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_chat:ctx.chat,p_request:ctx.message,p_kind:'team_record_write',p_command:command})},true);
  return {status:'awaiting_confirmation',plan_id:plan.id,revision:plan.revision,kind:plan.kind,command:plan.command_json,preview:plan.preview_json,execution_confirmed:false};
 }
 if(name==='select_specialization'){ctx.modules.add(args.module);return {status:'loaded',module:args.module};}
 if(name==='get_table_schema'){if(!ctx.director)throw new Error('Director schema access required');return {table:args.table,fields:schema[args.table]};}
 if(name==='calculate_estimate')return calculateEstimate(JSON.parse(args.lines_json));
 if(name==='read_company_document')return readCompanyDocument(args,ctx);
 if(name==='get_document_file')return getCompanyDocumentFile(args,ctx);
 if(name==='retry_document_cleanup'){
  if(!['director','manager','finance','accountant'].includes(actor[0].role)||actor[0].role==='director'&&!ctx.director)throw new Error('Document access denied');
  return cleanupDocumentFiles(ctx.owner,args.request_id);
 }
 if(['get_document_metadata','propose_document'].includes(name)){
  if(name==='get_document_metadata'){
   const rows=await ctx.db('project_documents?select=*&id=eq.'+args.document_id);if(rows.length!==1)throw new Error('Document access denied');
   if(actor[0].role==='foreman'&&rows[0].document_type!=='project'||!['director','manager','foreman'].includes(actor[0].role))throw new Error('Document access denied');
   const versions=await ctx.db('project_document_versions?select=*&document_id=eq.'+args.document_id+'&order=version_no,id&limit=201');return {document:rows[0],versions:versions.slice(0,200),has_more:versions.length>200,content_read:false};
  }
  if(!['director','manager'].includes(actor[0].role)||actor[0].role==='director'&&!ctx.director)throw new Error('Document write access denied');
  const command=JSON.parse(args.command_json);if(Object.hasOwn(command,'uploaded_file'))throw new Error('Use own prepared file_id');
  const plan=await ctx.db('rpc/agent_prepare_operator_plan',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_chat:ctx.chat,p_request:ctx.message,p_kind:'document_write',p_command:command})},true);
  return {status:'awaiting_confirmation',plan_id:plan.id,revision:plan.revision,kind:plan.kind,command:plan.command_json,preview:plan.preview_json,execution_confirmed:false};
 }
 if(name==='list_document_versions'){
  const docs=await ctx.db('project_documents?select=id,document_type&id=eq.'+args.document_id);if(docs.length!==1||!['director','manager','foreman'].includes(actor[0].role)||actor[0].role==='foreman'&&docs[0].document_type!=='project')throw new Error('Document access denied');
  const rows=await ctx.db('project_document_versions?select=id,document_id,version_no,file_name,file_size,mime_type,created_at&document_id=eq.'+args.document_id+'&order=version_no.desc,id&limit=31&offset='+args.offset);
  return {records:rows.slice(0,30),has_more:rows.length>30,next_offset:rows.length>30?args.offset+30:null};
 }
 if(name==='list_projects'){
  let rows;if(ctx.director){rows=await ctx.db('projects?select=id,name,customer,status&order=name,id&limit=31&offset='+args.offset+(args.query?'&name=ilike.'+encodeURIComponent('%'+args.query.replace(/[%*]/g,'')+'%'):''),{},true);}
  else{rows=await ctx.db('rpc/agent_allowed_projects',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_query:args.query,p_offset:args.offset})},true);}
  return {records:rows.slice(0,30),has_more:rows.length>30,next_offset:rows.length>30?args.offset+30:null};
 }
 if(['get_project_context','get_financial_metrics','search_company_documents'].includes(name)){
  const rows=await ctx.db('projects?select=id,name,customer,status,responsible_user_id&id=eq.'+args.project_id,{},true);
  if(rows.length!==1||(!ctx.director&&await ctx.db('rpc/agent_project_scope',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_project:args.project_id})},true)!==true))throw new Error('Project access denied');
  if(name==='get_financial_metrics'){
   if(!ctx.director)throw new Error('Financial access denied');
   return getExistingFinancialMetrics(args,ctx);
  }
  const documentTypes=ctx.director||actor[0].role==='manager'?'':'&document_type=eq.project';
  const documentPath='project_documents?select=id,title,document_type,file_name,version_no,updated_at&project_id=eq.'+args.project_id+documentTypes+'&order=created_at.desc&limit=31';
  let documents=await ctx.db(documentPath+(name==='search_company_documents'&&args.query?'&title=ilike.'+encodeURIComponent('%'+args.query.replace(/[%*]/g,'')+'%'):''),{},true);
  let fallback=false;
  if(name==='search_company_documents'&&args.query&&!documents.length){documents=await ctx.db(documentPath,{},true);fallback=true;}
  if(name==='search_company_documents')return {documents:documents.slice(0,30),has_more:documents.length>30,content_read:false,query_matched:!fallback,limitation:fallback?'Точного совпадения названия нет. Возвращены документы этого разрешённого объекта; выбери подходящий и прочитай через read_company_document.':null};
  const works=await ctx.db('project_work_items?select=id,work_name,unit,planned_volume,completed_volume,status,section_id&project_id=eq.'+args.project_id+'&order=id&limit=101',{},true);
  return {project:rows[0],works:works.slice(0,100),has_more_works:works.length>100,documents:documents.slice(0,30),has_more_documents:documents.length>30};
 }
 if(name==='list_chat_files')return ctx.db('rpc/agent_list_chat_files',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_chat:ctx.chat})},true);
 if(name==='analyze_project'){
  const files=await ctx.db('agent_file_assets?select=mime_type&id=eq.'+args.file_id+'&owner_id=eq.'+ctx.owner+'&chat_id=eq.'+ctx.chat,{},true);
  if(files.length!==1)throw new Error('Own chat file required');
  if(!['application/pdf','text/plain'].includes(files[0].mime_type))throw new Error('Поэтапный разбор принимает PDF/TXT. DOCX можно прочитать после прикрепления к объекту; XLSX сейчас можно получить и заменить готовым файлом, редактирование формул не реализовано. Экспортируйте в PDF для разбора. Платный вызов не запускается.');
  return ctx.db('rpc/agent_queue_analysis',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_chat:ctx.chat,p_file:args.file_id,p_instruction:args.instruction,p_request:ctx.message})},true);
 }
 if(name==='get_job_status')return ctx.db('rpc/agent_get_job',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_job:args.job_id})},true);
 if(name==='cancel_job')return ctx.db('rpc/agent_cancel_job',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_job:args.job_id})},true);
 if(name==='get_my_tasks')return ctx.db('rpc/get_my_volume_obligations',{method:'POST',body:'{}'});
 if(['propose_project_from_file','propose_attach_project'].includes(name)){
  if(!ctx.director)throw new Error('Trusted director required');
  return ctx.db('rpc/agent_propose_file_action',{method:'POST',body:JSON.stringify({p_owner:ctx.owner,p_chat:ctx.chat,p_kind:name==='propose_project_from_file'?'create_project':'attach_project',p_file:args.file_id,p_values:name==='propose_project_from_file'?{name:args.name,customer:args.customer}:{project_id:args.project_id}})},true);
 }
 throw new Error('Tool not implemented');
}

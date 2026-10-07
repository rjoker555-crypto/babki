// Validate container bounds without rendering/executing uploaded Office content.
export function validateOfficeFile(bytes,ext){
 const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);let end=-1;
 for(let p=bytes.length-22;p>=Math.max(0,bytes.length-65557);p--)if(view.getUint32(p,true)===0x06054b50){end=p;break;}
 if(end<0)throw Error('Office-файл повреждён или зашифрован. Пришлите готовый незашифрованный файл.');
 const count=view.getUint16(end+10,true),directory=view.getUint32(end+16,true);if(count<1||count>5000||directory>=end)throw Error('Некорректная структура Office-файла.');
 let p=directory,total=0,main=false;
 for(let i=0;i<count;i++){
  if(p+46>end||view.getUint32(p,true)!==0x02014b50)throw Error('Повреждён каталог Office-файла.');
  const flags=view.getUint16(p+8,true),method=view.getUint16(p+10,true),compressed=view.getUint32(p+20,true),size=view.getUint32(p+24,true),nameLen=view.getUint16(p+28,true),extra=view.getUint16(p+30,true),comment=view.getUint16(p+32,true),offset=view.getUint32(p+42,true);
  if(p+46+nameLen+extra+comment>end||offset+30>directory||flags&1||![0,8].includes(method)||size>8*1024*1024||(total+=size)>32*1024*1024)throw Error('Office-файл слишком большой после распаковки или защищён.');
  const name=new TextDecoder('utf-8',{fatal:true}).decode(bytes.subarray(p+46,p+46+nameLen));
  if(name.startsWith('/')||name.includes('\\')||name.split('/').includes('..')||/vbaProject\.bin$/i.test(name))throw Error('Макросы и небезопасные пути в файле запрещены.');
  if(view.getUint32(offset,true)!==0x04034b50)throw Error('Повреждена часть Office-файла.');
  const start=offset+30+view.getUint16(offset+26,true)+view.getUint16(offset+28,true);if(start+compressed>directory)throw Error('Размер части Office-файла неверен.');
  if(name===(ext==='docx'?'word/document.xml':'xl/workbook.xml'))main=true;
  p+=46+nameLen+extra+comment;
 }
 if(!main)throw Error('Расширение файла не соответствует его содержимому.');
}

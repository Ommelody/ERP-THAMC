/* xlsx-write.js — minimal dependency-free XLSX writer.
   window.buildXlsx(sheetName, rows) -> Blob (.xlsx). rows = array of arrays (strings/numbers/null).
   Produces a valid workbook (STORE zip + CRC32) that Excel and SAP DTW read. */
(function(){
  // CRC32
  const T=(function(){const t=[];for(let n=0;n<256;n++){let c=n;for(let k=0;k<8;k++)c=c&1?0xEDB88320^(c>>>1):c>>>1;t[n]=c>>>0;}return t;})();
  function crc32(u8){let c=0xFFFFFFFF;for(let i=0;i<u8.length;i++)c=T[(c^u8[i])&0xFF]^(c>>>8);return (c^0xFFFFFFFF)>>>0;}
  const enc=new TextEncoder();
  function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
  function colRef(i){let s='';i++;while(i>0){const m=(i-1)%26;s=String.fromCharCode(65+m)+s;i=(i-m-1)/26;}return s;}
  function sheetXml(rows){
    let x='<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'+
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>';
    rows.forEach((row,r)=>{
      x+='<row r="'+(r+1)+'">';
      (row||[]).forEach((v,c)=>{
        if(v===null||v===undefined||v==='')return;
        const ref=colRef(c)+(r+1);
        if(typeof v==='number'&&isFinite(v)) x+='<c r="'+ref+'"><v>'+v+'</v></c>';
        else x+='<c r="'+ref+'" t="inlineStr"><is><t xml:space="preserve">'+esc(v)+'</t></is></c>';
      });
      x+='</row>';
    });
    return x+'</sheetData></worksheet>';
  }
  function files(sheetName,rows){
    const sn=esc(sheetName||'Sheet1').slice(0,31);
    return {
      '[Content_Types].xml':'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>',
      '_rels/.rels':'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
      'xl/workbook.xml':'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="'+sn+'" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels':'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
      'xl/worksheets/sheet1.xml':sheetXml(rows)
    };
  }
  function zip(fileMap){
    const names=Object.keys(fileMap); const chunks=[]; const central=[]; let off=0;
    function push(u8){chunks.push(u8);off+=u8.length;}
    function num(n,b){const a=new Uint8Array(b);for(let i=0;i<b;i++){a[i]=n&0xFF;n>>>=8;}return a;}
    names.forEach(name=>{
      const data=enc.encode(fileMap[name]); const crc=crc32(data); const nb=enc.encode(name); const lho=off;
      push(num(0x04034b50,4));push(num(20,2));push(num(0,2));push(num(0,2));push(num(0,2));push(num(0,2));
      push(num(crc,4));push(num(data.length,4));push(num(data.length,4));push(num(nb.length,2));push(num(0,2));
      push(nb);push(data);
      const c=[];c.push(num(0x02014b50,4),num(20,2),num(20,2),num(0,2),num(0,2),num(0,2),num(0,2),num(crc,4),num(data.length,4),num(data.length,4),num(nb.length,2),num(0,2),num(0,2),num(0,2),num(0,2),num(0,4),num(lho,4),nb);
      central.push({parts:c});
    });
    const cdStart=off;
    central.forEach(e=>e.parts.forEach(push));
    const cdSize=off-cdStart;
    push(num(0x06054b50,4));push(num(0,2));push(num(0,2));push(num(names.length,2));push(num(names.length,2));push(num(cdSize,4));push(num(cdStart,4));push(num(0,2));
    let total=0;chunks.forEach(c=>total+=c.length);const out=new Uint8Array(total);let o=0;chunks.forEach(c=>{out.set(c,o);o+=c.length;});
    return out;
  }
  window.buildXlsx=function(sheetName,rows){
    const out=zip(files(sheetName,rows));
    return new Blob([out],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'});
  };
  window.downloadXlsx=function(filename,sheetName,rows){
    const blob=window.buildXlsx(sheetName,rows);
    const url=URL.createObjectURL(blob); const a=document.createElement('a');
    a.href=url; a.download=filename; document.body.appendChild(a); a.click();
    setTimeout(()=>{document.body.removeChild(a);URL.revokeObjectURL(url);},400);
  };
})();

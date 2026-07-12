/* xlsx-lite.js — client-side XLSX reader (no deps). window.readXlsxFile(File) -> {sheets:{name:rows[][]}} */
(function(){
  function u16(d,o){return d[o]|(d[o+1]<<8);}
  function u32(d,o){return (d[o]|(d[o+1]<<8)|(d[o+2]<<16)|(d[o+3]<<24))>>>0;}
  function unzip(buf){
    var dv=buf, eocd=-1;
    for(var i=buf.length-22;i>=0;i--){ if(u32(dv,i)===0x06054b50){eocd=i;break;} }
    if(eocd<0) throw new Error('not a zip');
    var cd=u16(dv,eocd+10), p=u32(dv,eocd+16), files={};
    for(var n=0;n<cd;n++){ if(u32(dv,p)!==0x02014b50) break;
      var method=u16(dv,p+10), csize=u32(dv,p+20), nlen=u16(dv,p+28), elen=u16(dv,p+30), clen=u16(dv,p+32), lho=u32(dv,p+42);
      var name=new TextDecoder().decode(buf.subarray(p+46,p+46+nlen));
      var lnlen=u16(dv,lho+26), lelen=u16(dv,lho+28), start=lho+30+lnlen+lelen;
      files[name]={method:method,comp:buf.subarray(start,start+csize)};
      p+=46+nlen+elen+clen;
    }
    return files;
  }
  async function inflate(e){ if(e.method===0) return e.comp;
    var ds=new DecompressionStream('deflate-raw'); var w=ds.writable.getWriter(); w.write(e.comp); w.close();
    return new Uint8Array(await new Response(ds.readable).arrayBuffer()); }
  async function txt(f,n){ return f[n]? new TextDecoder().decode(await inflate(f[n])) : ''; }
  function parseSS(xml){ var out=[],re=/<si>([\s\S]*?)<\/si>/g,m; while(m=re.exec(xml)){ out.push(m[1].replace(/<[^>]+>/g,'').replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').trim()); } return out; }
  function colNum(c){ var n=0; for(var i=0;i<c.length;i++) n=n*26+(c.charCodeAt(i)-64); return n-1; }
  function parseSheet(xml,ss){ var rows=[],rowRe=/<row[^>]*>([\s\S]*?)<\/row>/g,rm;
    while(rm=rowRe.exec(xml)){ var arr=[],cre=/<c r="([A-Z]+)\d+"(?: s="\d+")?(?: t="(\w+)")?[^>]*?>\s*(?:<v>([\s\S]*?)<\/v>|<is>([\s\S]*?)<\/is>)?\s*<\/c>/g,cm;
      while(cm=cre.exec(rm[1])){ var ci=colNum(cm[1]),t=cm[2],v=cm[3]!=null?cm[3]:cm[4];
        if(v==null){arr[ci]='';continue;} if(t==='s')v=ss[+v]||''; else if(t==='str'||t==='inlineStr')v=String(v).replace(/<[^>]+>/g,'');
        arr[ci]=v; } rows.push(arr); }
    return rows; }
  async function readXlsxFile(file){
    var buf=new Uint8Array(await file.arrayBuffer()); var files=unzip(buf);
    var ss=files['xl/sharedStrings.xml']? parseSS(await txt(files,'xl/sharedStrings.xml')) : [];
    var wb=await txt(files,'xl/workbook.xml');
    var rels=await txt(files,'xl/_rels/workbook.xml.rels');
    var relMap={}; (rels.match(/<Relationship[^>]*>/g)||[]).forEach(function(r){ var id=(r.match(/Id="(rId\d+)"/)||[])[1]; var tg=(r.match(/Target="([^"]*)"/)||[])[1]; if(id&&tg) relMap[id]=tg; });
    var sheets={}, order=[];
    var re=/<sheet[^>]*name="([^"]*)"[^>]*r:id="(rId\d+)"/g, m;
    while(m=re.exec(wb)){ var nm=m[1].replace(/&amp;/g,'&'), rid=m[2], tgt=relMap[rid]||''; if(!tgt) continue;
      var path='xl/'+tgt.replace(/^\//,''); var xml=await txt(files,path);
      sheets[nm]=parseSheet(xml,ss); order.push(nm); }
    return {sheets:sheets, order:order};
  }
  window.readXlsxFile=readXlsxFile;
})();

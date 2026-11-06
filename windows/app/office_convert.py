"""Local office conversions. Imports are lazy so simple routes start quickly."""
import csv, html, os, posixpath, re, shutil, subprocess, sys, zipfile
from pathlib import Path
from urllib.parse import unquote
from xml.etree import ElementTree as ET

source, dest, scratch, office, node = map(Path,sys.argv[1:])
kind=source.suffix[1:].lower()
target=dest.suffix[1:].lower()

def executable():
    if office.suffix.lower() != '.msi':
        return office
    installed = Path(os.getenv('ProgramFiles', 'C:/Program Files'))/'LibreOffice/program/soffice.com'
    if installed.exists():
        return installed
    import tempfile
    parent = Path(os.environ['LOCALAPPDATA'])/'Clementine W'
    cache = parent/'Office-25.8.7'
    def locate(folder):
        return next(folder.rglob('soffice.com'), None)
    found = locate(cache)
    if found:
        return found
    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=parent) as stage:
        unpack = Path(stage)/'Office'
        result = subprocess.run(['msiexec.exe', '/a', str(office), '/qn', '/norestart', 'TARGETDIR='+str(unpack)], creationflags=subprocess.CREATE_NO_WINDOW)
        if result.returncode not in (0, 3010) or not locate(unpack):
            raise ValueError('Windows could not unpack the office converter. Install LibreOffice for Windows and try again.')
        try:
            unpack.rename(cache)
        except OSError:
            if not locate(cache):
                raise
    return locate(cache)

def libre(src, spec, extra=()):
    out=scratch/'office-output'
    out.mkdir(exist_ok=True)
    args=[str(executable()),'-env:UserInstallation='+(scratch/'profile').as_uri(),'--headless','--norestore','--convert-to',spec,'--outdir',str(out),*extra,str(src)]
    result=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    produced=out/(src.stem+'.'+spec.split(':')[0])
    if result.returncode or not produced.exists():
        raise ValueError('LibreOffice could not convert '+src.name+': '+(result.stderr or result.stdout).decode(errors='replace')[-350:])
    return produced

def textdoc(text):
    from docx import Document
    doc=Document()
    for line in text.splitlines():doc.add_paragraph(re.sub(r'[\x00-\x08\x0b-\x0c\x0e-\x1f]','',line))
    path=scratch/'content.docx';doc.save(path);return path

def epub_text(path):
    with zipfile.ZipFile(path) as z:
        root=ET.fromstring(z.read('META-INF/container.xml')).find('.//{*}rootfile').attrib['full-path']
        package=ET.fromstring(z.read(root))
        files={i.attrib['id']:i.attrib['href'] for i in package.findall('.//{*}manifest/{*}item')}
        parts=[]
        for ref in package.findall('.//{*}spine/{*}itemref'):
            name=posixpath.normpath(posixpath.join(posixpath.dirname(root),unquote(files[ref.attrib['idref']].split('#')[0])))
            body=ET.fromstring(z.read(name)).find('.//{*}body')
            if body is not None:
                for el in body.iter():
                    if el.tag.rsplit('}',1)[-1] in ('p','div','li','h1','h2','h3','br'):el.tail='\n'+(el.tail or '')
                parts.append(''.join(body.itertext()))
        return '\n'.join(parts)

def write_epub(src):
    from docx import Document
    from uuid import uuid4
    if src.suffix.lower()!='.docx':src=libre(src,'docx:Office Open XML Text')
    doc=Document(src); title=html.escape(source.stem)
    uid='urn:uuid:'+str(uuid4()); chunks=[];manifest=[]
    ns='http://www.w3.org/1999/xhtml'
    with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED) as z:
        z.writestr('mimetype','application/epub+zip',compress_type=zipfile.ZIP_STORED)
        z.writestr('META-INF/container.xml','<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        images={}
        for p in doc.paragraphs:
            chunks.append('<p>'+html.escape(p.text)+'</p>')
            for el in p._p.xpath('.//a:blip'):
                rid=el.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}embed')
                if not rid:continue
                part=doc.part.related_parts[rid]
                if rid not in images:
                    name='images/'+Path(str(part.partname)).name;images[rid]=name;z.writestr(name,part.blob)
                    manifest.append(f'<item id="i{len(images)}" href="{name}" media-type="{part.content_type}"/>')
                chunks.append('<img alt="" src="'+images[rid]+'"/>')
        for t in doc.tables:
            chunks.append('<table>'+''.join('<tr>'+''.join('<td>'+html.escape(c.text)+'</td>' for c in r.cells)+'</tr>' for r in t.rows)+'</table>')
        z.writestr('book.xhtml',f'<html xmlns="{ns}"><head><title>{title}</title></head><body>'+''.join(chunks)+'</body></html>')
        z.writestr('nav.xhtml',f'<html xmlns="{ns}" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="book.xhtml">{title}</a></li></ol></nav></body></html>')
        from datetime import datetime,timezone
        modified=datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        z.writestr('book.opf',f'<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">{uid}</dc:identifier><dc:title>{title}</dc:title><dc:language>und</dc:language><meta property="dcterms:modified">{modified}</meta></metadata><manifest><item id="body" href="book.xhtml" media-type="application/xhtml+xml"/><item id="nav" properties="nav" href="nav.xhtml" media-type="application/xhtml+xml"/>'+''.join(manifest)+'</manifest><spine><itemref idref="body"/></spine></package>')

def pdf_export():
    import pypdfium2 as pdfium
    pdf=pdfium.PdfDocument(source)
    if target=='pptx':
        from pptx import Presentation
        from pptx.util import Inches
        prs=Presentation();w,h=pdf[0].get_size();prs.slide_width=Inches(10);prs.slide_height=int(prs.slide_width*h/w)
        for page in pdf:
            img=scratch/'slide.png';page.render(scale=1.5).to_pil().save(img)
            slide=prs.slides.add_slide(prs.slide_layouts[6]);pw,ph=page.get_size()
            k=min(prs.slide_width/pw,prs.slide_height/ph);width,height=int(pw*k),int(ph*k)
            slide.shapes.add_picture(str(img),(prs.slide_width-width)//2,(prs.slide_height-height)//2,width,height)
        prs.save(dest);return
    if target=='xlsx':
        from openpyxl import Workbook
        import pdfplumber
        book=Workbook();book.remove(book.active)
        with pdfplumber.open(source) as parsed:
            for i,page in enumerate(parsed.pages):
                sheet=book.create_sheet('Page '+str(i+1))
                tables=page.extract_tables()
                rows=[r for t in tables for r in t] if tables else [[s] for s in (page.extract_text() or '').splitlines()]
                if not rows:
                    from openpyxl.drawing.image import Image
                    image=scratch/f'page-{i}.png';pdf[i].render(scale=1).to_pil().save(image);sheet.add_image(Image(image),'A1')
                for row in rows:
                    sheet.append(row)
                    for c in sheet[sheet.max_row]:
                        if isinstance(c.value,str):c.data_type='s'
        book.save(dest);return
    from docx import Document
    from docx.shared import Inches
    doc=Document()
    for i,page in enumerate(pdf):
        if i:doc.add_page_break()
        text=page.get_textpage().get_text_range()
        if text.strip():doc.add_paragraph(re.sub(r'[\x00-\x08\x0b-\x0c\x0e-\x1f]','',text))
        else:
            image=scratch/f'page-{i}.png';page.render(scale=1.5).to_pil().save(image);doc.add_picture(str(image),width=Inches(6))
    path=scratch/'content.docx';doc.save(path);return path

def raw_gzip():
    import gzip,tarfile
    payload=scratch/'payload';payload.mkdir()
    single=payload/(source.stem or 'data')
    with gzip.open(source,'rb') as a,single.open('wb') as b:shutil.copyfileobj(a,b)
    if target=='zip':
        with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED) as z:z.write(single,single.name)
    else:
        with tarfile.open(dest,'w') as t:t.add(single,arcname=single.name)

def run():
    if kind=='gz' and target in ('zip','tar'): return raw_gzip()
    if kind in ('xls','xlsx','ods','csv','tsv'):
        options=()
        if kind in ('csv','tsv'):options=['--infilter=Text - txt - csv (StarCalc):'+('44' if kind=='csv' else '9')+',34,76,1,,0,false,false,false,false,false,0,false,false']
        spec={'xlsx':'xlsx:Calc MS Excel 2007 XML','ods':'ods:calc8','pdf':'pdf:calc_pdf_Export','tsv':'csv:Text - txt - csv (StarCalc):9,34,76','csv':'csv:Text - txt - csv (StarCalc):44,34,76'}[target]
        shutil.copyfile(libre(source,spec,options),dest);return
    src=source
    if kind=='pdf':
        src=pdf_export()
        if src is None:return
    elif kind=='pages':
        import json
        from docx import Document
        from docx.shared import Inches
        packed=source
        if source.is_dir():
            packed=scratch/'packed.pages'
            with zipfile.ZipFile(packed,'w') as z:
                for file in source.rglob('*'):
                    if file.is_file() and not file.is_symlink():z.write(file,file.relative_to(source))
        info=scratch/'pages.json'
        subprocess.run([node,Path(__file__).with_name('pages.mjs'),'read',packed,info],check=True)
        decoded=json.loads(info.read_text());src=textdoc(decoded['text'])
        if decoded['images']:
            document=Document(src)
            for path in decoded['images']:
                from PIL import Image
                with Image.open(path) as im:
                    png=scratch/'image.png';im.convert('RGBA').save(png)
                document.add_picture(str(png),width=Inches(6))
            document.save(src)
    elif kind in ('md','txt'):
        text=source.read_text(encoding='utf-8-sig');src=textdoc(text)
    elif kind=='epub':src=textdoc(epub_text(source))
    elif kind=='textclipping':
        import plistlib
        data=plistlib.loads(source.read_bytes())['UTI-Data'];text=data.get('public.utf8-plain-text') or data.get('public.utf16-plain-text')
        if not isinstance(text,str):text=text.decode('utf-16' if 'public.utf8-plain-text' not in data else 'utf-8')
        src=textdoc(text)
    elif kind=='rtfd':
        src=libre(next(source.glob('*.rtf')), 'docx:Office Open XML Text')
    if target=='epub':return write_epub(src)
    if target in ('jpg','png'):
        import pypdfium2 as pdfium
        pdf=pdfium.PdfDocument(libre(src,'pdf'))
        dest.mkdir()
        for i,page in enumerate(pdf):page.render(scale=2).to_pil().convert('RGB').save(dest/f'Page-{i+1}.{target}')
        return
    if target in ('txt','md','pages'):
        if src.suffix=='.docx':
            from docx import Document
            doc=Document(src);text='\n'.join(p.text for p in doc.paragraphs)
            if doc.tables:text+='\n'+'\n'.join('\t'.join(c.text for c in r.cells) for table in doc.tables for r in table.rows)
        else:text=libre(src,'txt:Text (encoded):UTF8').read_text(encoding='utf-8-sig')
        if target=='pages':
            assets=[]
            if src.suffix.lower()=='.docx':
                for rel in doc.part.rels.values():
                    if rel.is_external or not rel.reltype.endswith('/image'):continue
                    image=scratch/('embed-'+str(len(assets))+Path(str(rel.target_part.partname)).suffix)
                    image.write_bytes(rel.target_part.blob);assets.append(image)
            txt=scratch/'body.txt';txt.write_text(text);subprocess.run([node,Path(__file__).with_name('pages.mjs'),'write',txt,dest,*assets],check=True)
        else:dest.write_text(text)
        return
    if target=='docx' and src.suffix=='.docx':shutil.copyfile(src,dest);return
    spec={'docx':'docx:Office Open XML Text','pdf':'pdf','epub':'epub:EPUB','html':'html:HTML (StarWriter)'}[target]
    path=libre(src,spec)
    if target=='html':
        import base64,mimetypes
        markup=path.read_text(errors='replace')
        def embed(m):
            file=(path.parent/unquote(m[1])).resolve()
            if file.parent!=path.parent or not file.is_file():return m[0]
            mime=mimetypes.guess_type(file.name)[0] or 'application/octet-stream'
            return 'src="data:'+mime+';base64,'+base64.b64encode(file.read_bytes()).decode()+'"'
        dest.write_text(re.sub('src="([^"]+)"',embed,markup,flags=re.I))
    else:shutil.copyfile(path,dest)
try:run()
except Exception as e:sys.exit(str(e))

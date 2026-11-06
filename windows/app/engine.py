from pathlib import Path
import gzip, os, re, shutil, subprocess, sys, tempfile, uuid, math, json

APP=Path(__file__).resolve().parent
TOOLS=APP.parent/'tools'
CACHE=Path(os.getenv('LOCALAPPDATA',tempfile.gettempdir()))/'Clementine W'
GROUPS={
 'Images':('JPG PNG WEBP HEIC TIFF SVG AVIF BMP','JPG PNG WEBP HEIC TIFF BMP PDF'),
 'Documents':('PDF DOCX PAGES PPT PPTX TXT MD RTF RTFD TEXTCLIPPING EPUB HTML','PDF DOCX PAGES PPTX TXT MD HTML EPUB JPG PNG XLSX'),
 'Spreadsheets':('XLSX XLS ODS CSV TSV','XLSX ODS CSV TSV PDF'),
 'Audio':('MP3 M4A WAV FLAC OGG OPUS AIFF WMA','MP3 M4A WAV FLAC OGG OPUS AIFF WMA'),
 'Video':('MP4 MOV MKV WEBM AVI WMV GIF','MP4 MOV MKV WEBM AVI WMV GIF MP3'),
 'Archives':('ZIP TAR GZIP RAR','ZIP TAR GZIP'),
 'Subtitles':('SRT VTT','SRT VTT TXT')}
ALIASES={'JPEG':'JPG','TIF':'TIFF','HEIF':'HEIC','AIF':'AIFF','M4V':'MP4','GZ':'GZIP','TGZ':'GZIP','AAC':'M4A'}
def fmt(p):
    ext=p.suffix[1:].upper()
    return ALIASES.get(ext,ext)
def group(p):
    f=fmt(p)
    return next((g for g,(inputs,_) in GROUPS.items() if f in inputs.split()),'Files')
def targets(f,g):
    options=GROUPS.get(g,('','ZIP'))[1]
    if g=='Documents':
        options={'PDF':'DOCX PAGES PPTX XLSX JPG PNG EPUB TXT MD','PPT':'PDF JPG PNG','PPTX':'PDF JPG PNG','EPUB':'PDF DOCX PAGES TXT MD HTML'}.get(f,'PDF DOCX PAGES TXT MD HTML EPUB JPG PNG')
    if f=='GIF':options='MP4 MOV MKV WEBM AVI WMV'
    return [x for x in options.split() if x!=f]
def choices(p,mode):
    g=group(p); f=fmt(p)
    if mode=='Actions':return ['Share','Float','Copy','Move','Copy path','Show in Explorer']
    if mode=='Convert':return targets(f,g)
    if g=='Images':return ['Compress','Metadata','Edit','Annotate','Add BG','Crop','Resize','Redact']
    if f=='PDF':return ['Compress','Metadata','Split','Organize','Extract text']
    if g in ('Audio','Video'):return ['Trim','Extract audio','ZIP']
    if f in ('TXT','MD','SRT','VTT','CSV','TSV','HTML'):return ['Edit text','ZIP']
    return ['ZIP','Show in Explorer']
def run(args,**kwargs):
    flags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0
    r=subprocess.run(list(map(str,args)),stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=flags,**kwargs)
    if r.returncode:raise ValueError((r.stderr or r.stdout).decode(errors='replace').strip()[-1300:] or 'The converter could not complete this file.')
    return r
def fresh(parent,name):
    path=parent/name;n=2
    while path.exists():path=parent/(Path(name).stem+f'-{n}'+Path(name).suffix);n+=1
    return path
def load_image(p):
    from PIL import Image,ImageOps
    if fmt(p)=='HEIC':
        import pillow_heif
        pillow_heif.register_heif_opener()
    if fmt(p)=='SVG':
        from PySide6.QtSvg import QSvgRenderer
        from PySide6.QtGui import QImage,QPainter
        from PySide6.QtCore import Qt
        svg=QSvgRenderer(str(p));size=svg.defaultSize()
        if not svg.isValid() or size.isEmpty() or size.width()*size.height()>100_000_000:raise ValueError('Invalid SVG dimensions.')
        im=QImage(size,QImage.Format_ARGB32_Premultiplied);im.fill(Qt.transparent)
        paint=QPainter(im);svg.render(paint);paint.end()
        im=im.convertToFormat(QImage.Format_RGBA8888)
        return Image.frombytes('RGBA',(im.width(),im.height()),bytes(im.constBits()))
    with Image.open(p) as im:return ImageOps.exif_transpose(im).convert('RGBA')
def edited(im,action,o,preview=False):
    from PIL import Image,ImageDraw,ImageEnhance,ImageFont,ImageFilter
    if action=='Resize':
        if o.get('mode','Scale')=='Scale':size=tuple(max(1,round(n*o.get('scale',100)/100)) for n in im.size)
        else:
            w=o.get('width',im.width);h=max(1,round(im.height*w/im.width)) if o.get('lock',True) else o.get('height',im.height);size=(w,h)
        if min(size)<1 or max(size)>32000 or size[0]*size[1]>100_000_000:raise ValueError('Choose an image size under 100 megapixels.')
        return im.resize(size,Image.Resampling.LANCZOS)
    if action=='Crop':
        l,t,r,b=o.get('rect',(0,0,1,1))
        return im.crop((round(l*im.width),round(t*im.height),max(round(l*im.width)+1,round(r*im.width)),max(round(t*im.height)+1,round(b*im.height))))
    if action=='Edit':
        v=lambda k:o.get(k,0)/100
        alpha=im.getchannel('A');rgb=im.convert('RGB')
        rgb=ImageEnhance.Brightness(rgb).enhance(2**(v('Exposure')*3)*(1+v('Brightness')))
        rgb=ImageEnhance.Contrast(rgb).enhance(1+v('Contrast'))
        rgb=ImageEnhance.Color(rgb).enhance(1+v('Saturation'))
        lut=[]
        for i in range(256):
            x=i/255
            y=x**(2**(-v('Gamma'))) + .30*v('Shadows')*(1-x)**2 + .30*v('Highlights')*x**2 + .22*v('Blacks')*(1-x)**4+.22*v('Whites')*x**4
            lut.append(round(255*max(0,min(1,y))))
        shifts=[v('Temperature')*24+v('Tint')*7,-v('Tint')*17,-v('Temperature')*24+v('Tint')*7]
        rgb=Image.merge('RGB',tuple(ch.point([max(0,min(255,round(y+s))) for y in lut]) for ch,s in zip(rgb.split(),shifts)))
        if v('Vibrance'):
            sat=rgb.convert('HSV').getchannel('S').point(lambda x:255-x);rgb=Image.composite(ImageEnhance.Color(rgb).enhance(1+v('Vibrance')),rgb,sat)
        if v('Hue'):
            h,s,b=rgb.convert('HSV').split();rgb=Image.merge('HSV',(h.point(lambda x:(x+round(v('Hue')*128))%256),s,b)).convert('RGB')
        if v('Sharpness'):rgb=ImageEnhance.Sharpness(rgb).enhance(1+v('Sharpness')*4)
        rgb.putalpha(alpha);return rgb
    if action=='Add BG':
        pad=int(o.get('padding',0));bg=Image.new('RGBA',(im.width+2*pad,im.height+2*pad),o.get('color','#ffffff'));bg.alpha_composite(im,(pad,pad));return bg
    if action in ('Annotate','Redact'):
        im=im.copy();unit=min(im.size);draw=ImageDraw.Draw(im)
        for m in o.get('marks',[]):
            pts=[(int(x*im.width),int(y*im.height)) for x,y in m['points']]
            a,b=pts[0],pts[-1];box=(min(a[0],b[0]),min(a[1],b[1]),max(a[0],b[0]),max(a[1],b[1]))
            typ=m['tool'];color=m.get('color','#ff3020');w=max(1,round(unit*.006))
            if typ=='Redact':draw.rectangle(box,fill='black')
            elif typ=='Rectangle':draw.rectangle(box,outline=color,width=w)
            elif typ=='Circle':draw.ellipse(box,outline=color,width=w)
            elif typ in ('Text','Number'):
                try:font=ImageFont.truetype('segoeui.ttf',max(9,round(unit*.05)))
                except OSError:font=ImageFont.load_default(size=max(9,round(unit*.05)))
                draw.text(a,m.get('text',''),font=font,fill=color,stroke_width=max(1,w//3),stroke_fill='black')
            elif typ=='Highlight':
                overlay=Image.new('RGBA',im.size);ImageDraw.Draw(overlay).line(pts,fill=color+'75',width=max(5,w*7));im.alpha_composite(overlay)
            elif typ=='Image' and box[2]>box[0] and box[3]>box[1]:
                stamp=load_image(Path(m['asset'])).resize((box[2]-box[0],box[3]-box[1]));im.alpha_composite(stamp,box[:2])
            elif typ=='Magnify' and box[2]>box[0] and box[3]>box[1]:
                w2=box[2]-box[0];h2=box[3]-box[1];crop=im.crop((box[0]+w2//4,box[1]+h2//4,box[2]-w2//4,box[3]-h2//4)).resize((w2,h2));mask=Image.new('L',crop.size);ImageDraw.Draw(mask).ellipse((0,0,w2-1,h2-1),fill=255);im.paste(crop,box[:2],mask);draw.ellipse(box,outline=color,width=w)
            else:
                draw.line(pts,fill=color,width=w,joint='curve')
                if typ=='Arrow':
                    angle=math.atan2(b[1]-a[1],b[0]-a[0]);draw.line([(b[0]-w*6*math.cos(angle-.5),b[1]-w*6*math.sin(angle-.5)),b,(b[0]-w*6*math.cos(angle+.5),b[1]-w*6*math.sin(angle+.5))],fill=color,width=w)
        return im
    return im
def save_image(im,path,fmt_,q):
    if fmt_=='HEIC':
        import pillow_heif
        pillow_heif.register_heif_opener()
    if fmt_ in ('JPG','PDF','BMP'):
        from PIL import Image
        base=Image.new('RGB',im.size,'white');base.paste(im,mask=im.getchannel('A'));im=base
    im.save(path,format={'JPG':'JPEG','HEIC':'HEIF'}.get(fmt_,fmt_),quality=q)
def pdf_pages(spec,n):
    if not spec.strip():return list(range(n))
    result=[]
    for part in spec.split(','):
        m=re.fullmatch(r'\s*(\d+)(?:\s*-\s*(\d+))?\s*',part)
        if not m:raise ValueError('Use page numbers or ranges, such as 1,3-5.')
        a=int(m[1]);b=int(m[2] or m[1])
        if not 1<=a<=b<=n:raise ValueError(f'Choose pages between 1 and {n}.')
        result.extend(range(a-1,b))
    return result
def convert(p,action,o,dest):
    from tempfile import TemporaryDirectory
    g=group(p);f=fmt(p);dest.mkdir(parents=True,exist_ok=True)
    with TemporaryDirectory(dir=dest,prefix='.working-') as tmp:
        tmp=Path(tmp);stem=p.stem+'-'+action.lower().replace(' ','-')
        def output(ext):return tmp/(stem+'.'+ext.lower())
        if action=='Edit text':
            out=output(p.suffix[1:]);out.write_text(o['text'],encoding='utf-8')
        elif action=='ZIP' and g!='Archives':
            import zipfile
            out=output('zip')
            with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
                if p.is_dir():
                    for file in p.rglob('*'):
                        if file.is_file() and not file.is_symlink():z.write(file,file.relative_to(p.parent))
                else:z.write(p,p.name)
        elif g=='Images':
            im=edited(load_image(p),action,o);ext=action if action in targets(f,g) else (o.get('format','JPG') if action=='Compress' else 'PNG')
            out=output(ext);save_image(im,out,ext,o.get('quality',85))
        elif g in ('Audio','Video'):
            audio={'MP3':'libmp3lame','M4A':'aac','WAV':'pcm_s16le','FLAC':'flac','OGG':'libvorbis','OPUS':'libopus','AIFF':'pcm_s16be','WMA':'wmav2'}
            ext=('M4A' if g=='Audio' or action=='Extract audio' else 'MP4') if action in ('Trim','Extract audio') else action
            out=output(ext);args=['-hide_banner','-loglevel','error','-nostdin','-i',p]
            if action=='Trim':
                a,b=o['start'],o['end']
                if not 0<=a<b:raise ValueError('End time must be after start time.')
                args+=['-ss',str(a),'-t',str(b-a)]
            if ext in audio:
                args+=['-map','0:a:0','-vn','-c:a',audio[ext]]
                if ext in ('WMA','MP3'):args+=['-ac','2','-ar','44100','-b:a','192k']
            elif ext=='GIF':args+=['-map','0:v:0','-an','-vf','fps=15,split[a][b];[a]palettegen[p];[b][p]paletteuse','-loop','0']
            else:
                args+=['-map','0:v:0','-map','0:a:0?','-vf','pad=ceil(iw/2)*2:ceil(ih/2)*2','-pix_fmt','yuv420p']
                args+= {'WEBM':['-c:v','libvpx-vp9','-cpu-used','6','-deadline','realtime','-c:a','libopus'],'AVI':['-c:v','mpeg4','-q:v','4','-c:a','libmp3lame'],'WMV':['-c:v','wmv2','-q:v','4','-c:a','wmav2','-ac','2','-ar','44100']}.get(ext,['-c:v','libx264','-preset','veryfast','-crf','21','-c:a','aac'])
            run([shutil.which('ffmpeg') or TOOLS/'ffmpeg.exe',*args,'-y',out])
        elif g=='Archives':
            out=output('tar.gz' if action=='GZIP' else action)
            tar=Path(os.environ.get('SystemRoot','C:/Windows'))/'System32/tar.exe'
            flags=['--format','zip'] if action=='ZIP' else (['-z'] if action=='GZIP' else [])+['--format','pax']
            try:run([tar,'-cf',out,*flags,'@'+str(p)])
            except ValueError:
                if f!='GZIP':raise
                data=tmp/'contents';data.mkdir();file=data/(p.stem or 'data')
                with gzip.open(p,'rb') as a,file.open('wb') as b:shutil.copyfileobj(a,b)
                run([tar,'-cf',out,*flags,'-C',data,file.name])
        elif g=='Subtitles':
            out=output(action);srt=tmp/'cues.srt' if action=='TXT' else out
            run([shutil.which('ffmpeg') or TOOLS/'ffmpeg.exe','-loglevel','error','-nostdin','-i',p,srt])
            if action=='TXT':
                cues=re.split(r'\n\s*\n',srt.read_text(encoding='utf-8-sig').strip())
                out.write_text('\n'.join(re.sub('<[^>]+>','','\n'.join(c.splitlines()[2:])) for c in cues),encoding='utf-8')
        elif f=='PDF' and action in ('Organize','Split','Compress','Extract text','TXT','MD','JPG','PNG'):
            from pypdf import PdfReader,PdfWriter
            r=PdfReader(p);pages=pdf_pages(o.get('pages',''),len(r.pages))
            if action in ('TXT','MD','Extract text'):
                out=output('md' if action=='MD' else 'txt');out.write_text('\n\n'.join(r.pages[i].extract_text() or '' for i in pages),encoding='utf-8')
            elif action in ('JPG','PNG'):
                import pypdfium2 as pdfium
                pdf=pdfium.PdfDocument(p);out=tmp/(stem+'-pages');out.mkdir()
                for j,i in enumerate(pages):pdf[i].render(scale=o.get('dpi',150)/72).to_pil().convert('RGB').save(out/f'Page-{j+1}.{action.lower()}')
                pdf.close()
            elif action=='Split':
                out=tmp/stem;out.mkdir();n=max(1,o.get('chunk',1))
                for j in range(0,len(pages),n):
                    w=PdfWriter();[w.add_page(r.pages[i]) for i in pages[j:j+n]];w.write(out/f'Part-{j//n+1}.pdf')
            else:
                out=output('pdf');w=PdfWriter()
                for i in pages:
                    page=w.add_page(r.pages[i])
                    if action=='Organize':page.rotate(o.get('rotate',0))
                    else:page.compress_content_streams()
                if action=='Compress':w.compress_identical_objects()
                w.write(out)
        elif g in ('Documents','Spreadsheets'):
            out=output('jpg' if action=='JPG' else action)
            run([sys.executable,'-B','-X','utf8',APP/'office_convert.py',p,out,tmp,TOOLS/'LibreOffice.msi',shutil.which('node') or TOOLS/'node.exe'])
        else:raise ValueError('Choose a supported file format.')
        if not out.exists():raise ValueError('No converted file was created.')
        result=fresh(dest,stem+'-pages' if out.is_dir() and out.suffix else out.name);shutil.move(str(out),result);return result

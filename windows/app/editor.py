from PySide6.QtCore import Qt,QRectF,QPointF
from PySide6.QtGui import QColor,QImage,QPainter,QPen
from PySide6.QtWidgets import (QWidget,QDialog,QVBoxLayout,QFormLayout,QHBoxLayout,QLabel,QSpinBox,QDoubleSpinBox,QSlider,QComboBox,QLineEdit,QTextEdit,QPushButton,QColorDialog,QDialogButtonBox,QScrollArea)
from engine import fmt,group,load_image,edited

def qimage(im):
    im=im.convert('RGBA')
    return QImage(im.tobytes(),im.width,im.height,im.width*4,QImage.Format_RGBA8888).copy()

class Canvas(QWidget):
    def __init__(self,im,action,options):
        super().__init__();self.setMinimumSize(340,220)
        im.thumbnail((640,420));self.im=im;self.img=qimage(im);self.action=action;self.options=options
        self.points=[];self.tool='Draw';self.color='#ff4c1e';self.frame=QRectF()
    def refresh(self):
        self.img=qimage(edited(self.im,self.action,self.options));self.update()
    def paintEvent(self,e):
        p=QPainter(self);p.setRenderHint(QPainter.SmoothPixmapTransform)
        s=min(self.width()/self.img.width(),self.height()/self.img.height());w=self.img.width()*s;h=self.img.height()*s
        self.frame=QRectF((self.width()-w)/2,(self.height()-h)/2,w,h)
        p.drawImage(self.frame,self.img)
        if self.points or (self.action=='Crop' and 'rect' in self.options):
            if self.points:a,b=self.points[0],self.points[-1]
            else:l,t,r,bottom=self.options['rect'];a,b=(l,t),(r,bottom)
            def view(pt):return QPointF(self.frame.x()+w*pt[0],self.frame.y()+h*pt[1])
            p.setPen(QPen(QColor('#ff761a'),2,Qt.DashLine));p.drawRect(QRectF(view(a),view(b)).normalized())
        p.end()
    def norm(self,pt):
        return tuple(max(0,min(1,x)) for x in ((pt.x()-self.frame.x())/self.frame.width(),(pt.y()-self.frame.y())/self.frame.height()))
    def mousePressEvent(self,e):
        if self.action in ('Crop','Annotate','Redact') and self.frame.contains(e.position()):self.points=[self.norm(e.position())]
    def mouseMoveEvent(self,e):
        if self.points:self.points.append(self.norm(e.position()));self.update()
    def mouseReleaseEvent(self,e):
        if not self.points:return
        self.points.append(self.norm(e.position()));a,b=self.points[0],self.points[-1]
        if self.action=='Crop':
            if abs(a[0]-b[0])>.002 and abs(a[1]-b[1])>.002:self.options['rect']=(min(a[0],b[0]),min(a[1],b[1]),max(a[0],b[0]),max(a[1],b[1]))
        else:
            self.options.setdefault('marks',[]).append(dict(tool='Redact' if self.action=='Redact' else self.tool,points=self.points,color=self.color));self.refresh()
        self.points=[];self.update()

def settings(parent,path,action):
    o={};d=QDialog(parent);d.setWindowTitle(action+' · Clementine W');layout=QVBoxLayout(d);layout.addWidget(QLabel(path.name))
    form=QFormLayout();canvas=None
    def number(label,key,low,high,value,decimal=False):
        w=QDoubleSpinBox() if decimal else QSpinBox();w.setRange(low,high);w.setValue(value);form.addRow(label,w);o[key]=value;w.valueChanged.connect(lambda v:o.update({key:v}))
    def line(label,key,value=''):
        w=QLineEdit(value);form.addRow(label,w);o[key]=value;w.textChanged.connect(lambda x:o.update({key:x}))
    def color():
        c=QColorDialog.getColor(QColor(o.get('color','#ffffff')),d)
        if c.isValid():
            o['color']=c.name();btn.setText(c.name())
            if canvas:canvas.color=c.name()
    if action in ('Crop','Annotate','Redact','Edit'):
        canvas=Canvas(load_image(path),action,o);layout.addWidget(canvas)
    if action=='Resize':number('Scale (%)','scale',1,800,75)
    elif action=='Add BG':
        o['color']='#ffffff';btn=QPushButton(o['color']);btn.clicked.connect(color);form.addRow('Background',btn);number('Padding (px)','padding',0,2048,16)
    elif action=='Edit':
        for name in 'Exposure Brightness Contrast Highlights Shadows Whites Blacks Gamma Temperature Tint Saturation Vibrance Hue Sharpness'.split():
            w=QSlider(Qt.Horizontal);w.setRange(-100,100);form.addRow(name,w)
            def adjust(v,k=name):o[k]=v;canvas.refresh()
            w.valueChanged.connect(adjust)
    elif action in ('Crop','Redact','Annotate'):
        layout.addWidget(QLabel('Drag over the image to '+{'Crop':'select the crop.','Redact':'cover an area.','Annotate':'draw a mark.'}[action]))
        if action=='Annotate':
            tool=QComboBox();tool.addItems(['Draw','Arrow','Rectangle','Circle','Highlight','Magnify']);form.addRow('Tool',tool);tool.currentTextChanged.connect(lambda t:setattr(canvas,'tool',t))
            btn=QPushButton('Choose color');btn.clicked.connect(color);form.addRow('Color',btn)
        if action!='Crop':
            undo=QPushButton('Undo last mark');form.addRow(undo)
            def undo_mark():
                if o.get('marks'):o['marks'].pop();canvas.refresh()
            undo.clicked.connect(undo_mark)
    elif action=='Compress' and group(path)=='Images':number('JPEG quality','quality',1,98,78)
    elif action=='Trim':number('Start (seconds)','start',0,86400,0,True);number('End (seconds)','end',.01,86400,10,True)
    elif action in ('Organize','Split'):
        line('Pages (blank for all)','pages')
        if action=='Split':number('Pages per part','chunk',1,10000,1)
        else:
            rotate=QComboBox();rotate.addItems(['0','90','180','270']);form.addRow('Rotate clockwise (°)',rotate);rotate.currentTextChanged.connect(lambda v:o.update(rotate=int(v)))
    elif action=='Edit text':
        w=QTextEdit();w.setPlainText(path.read_text(encoding='utf-8-sig'));layout.addWidget(w);o['text']=w.toPlainText();w.textChanged.connect(lambda:o.update(text=w.toPlainText()))
    else:return {}
    layout.addLayout(form);buttons=QDialogButtonBox(QDialogButtonBox.Ok|QDialogButtonBox.Cancel);buttons.accepted.connect(d.accept);buttons.rejected.connect(d.reject);layout.addWidget(buttons)
    return o if d.exec() else None

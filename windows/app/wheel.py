import ctypes
import math
import os
from pathlib import Path
from PySide6.QtCore import Qt, QPointF, QRectF, QTimer, Signal
from PySide6.QtGui import QColor, QCursor, QFont, QLinearGradient, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import QApplication, QWidget
from engine import APP, choices

MODES = ['Convert', 'Tools', 'Actions']
def files(mime):
    return [Path(u.toLocalFile()) for u in mime.urls() if u.isLocalFile()]

def file_size(paths):
    try:
        if any(p.is_dir() for p in paths):
            return f'{len(paths)} items' if len(paths)>1 else 'Folder'
        total=sum(p.stat().st_size for p in paths)
    except OSError:
        return 'File'
    for unit in ['B','KB','MB','GB','TB']:
        if total<1024 or unit=='TB':
            return f'{total:.0f} {unit}' if total>=10 or unit=='B' else f'{total:.1f} {unit}'
        total/=1024

def sector(center, angle, step):
    # Fillet each corner independently along the two arcs and the radial edges.
    def point(r,a):return QPointF(center+r*math.cos(a),center+r*math.sin(a))
    outer,inner=141,52
    a,b=angle-step/2+.013,angle+step/2-.013
    shape=QPainterPath()
    shape.moveTo(point(outer-8,a))
    shape.quadTo(point(outer,a),point(outer,a+8/outer))
    for i in range(1,26):shape.lineTo(point(outer,a+8/outer+(b-a-16/outer)*i/25))
    shape.quadTo(point(outer,b),point(outer-8,b))
    shape.lineTo(point(inner+6,b));shape.quadTo(point(inner,b),point(inner,b-6/inner))
    for i in range(1,26):shape.lineTo(point(inner,b-6/inner-(b-a-12/inner)*i/25))
    shape.quadTo(point(inner,a),point(inner+6,a));shape.closeSubpath()
    return shape

class Wheel(QWidget):
    chosen=Signal(object,str,object)
    def __init__(self,settings):
        super().__init__(None,Qt.Tool|Qt.FramelessWindowHint|Qt.WindowStaysOnTopHint|Qt.WindowDoesNotAcceptFocus)
        self.setAttribute(Qt.WA_TranslucentBackground);self.setAttribute(Qt.WA_ShowWithoutActivating)
        self.setAcceptDrops(True);self.setFixedSize(292,292)
        self.settings=settings;self.paths=[];self.mode='Convert';self.options=[];self.shapes=[]
        self.selected=-1;self.last=None;self.origin=None;self.dragged=False;self.done=False
        self.poll=QTimer(self);self.poll.timeout.connect(self.tick)
        if os.name=='nt':self.poll.start(32)
    def configure(self,paths,mode):
        self.paths=paths;self.mode=mode
        self.options=[a for a in choices(paths[0],mode) if all(a in choices(p,mode) for p in paths[1:])] if paths else []
        self.selected=-1;self.last=None;self.shapes=[];self.badge=file_size(paths) if paths else mode
        if self.options:
            step=2*math.pi/len(self.options)
            self.shapes=[sector(146,-math.pi/2+i*step,step) for i in range(len(self.options))]
        self.update()
    def tick(self):
        key=ctypes.windll.user32.GetAsyncKeyState
        pos=QCursor.pos()
        if not key(1)&0x8000:
            self.origin=None;self.dragged=False;self.done=False
            if self.isVisible():QTimer.singleShot(60,self.after_release)
            return
        if self.origin is None:self.origin=pos;return
        self.dragged |= (pos-self.origin).manhattanLength()>QApplication.startDragDistance()
        mode=next((m for k,m in zip((0x12,0x11,0x10),reversed(MODES)) if key(k)&0x8000),None)
        if not mode or self.done:
            self.hide();return
        if self.dragged and (not self.isVisible() or mode!=self.mode):
            self.configure(self.paths if self.isVisible() else [],mode)
            if not self.isVisible():
                self.move(pos.x()-146,pos.y()-146);self.show();self.raise_()
    def after_release(self):
        if not ctypes.windll.user32.GetAsyncKeyState(1)&0x8000:self.hide()
    def hover(self,pt):
        idx=next((i for i,path in enumerate(self.shapes) if path.contains(pt)),-1)
        if idx!=self.selected:
            if idx>=0 and idx!=self.last:
                if os.name=='nt' and self.settings.value('tap',True,type=bool):
                    import winsound
                    winsound.PlaySound(str(APP/'Tap.wav'),winsound.SND_FILENAME|winsound.SND_ASYNC|winsound.SND_NODEFAULT)
                self.last=idx
            self.selected=idx;self.update()
    def dragEnterEvent(self,e):
        paths=files(e.mimeData())
        if paths:
            if paths!=self.paths:self.configure(paths,self.mode)
            self.dragMoveEvent(e)
    def dragMoveEvent(self,e):
        self.hover(e.position());e.setDropAction(Qt.CopyAction);e.accept()
    def dragLeaveEvent(self,e):
        self.selected=-1;self.update()
    def dropEvent(self,e):
        self.hover(e.position())
        if self.selected>=0:
            paths=self.paths[:];action=self.options[self.selected];at=self.mapToGlobal(e.position().toPoint())
            e.setDropAction(Qt.CopyAction);e.accept();self.done=True;self.hide()
            QTimer.singleShot(0,lambda:self.chosen.emit(paths,action,at))
        else:e.ignore();self.done=True;self.hide()
    def paintEvent(self,e):
        p=QPainter(self);p.setRenderHint(QPainter.Antialiasing)
        p.setPen(Qt.NoPen);p.setBrush(QColor(30,30,34,72));p.drawEllipse(QRectF(3,3,286,286))
        for i,(name,path) in enumerate(zip(self.options,self.shapes)):
            fill=QLinearGradient(0,0,292,292)
            if i==self.selected:fill.setColorAt(0,QColor('#ff751c'));fill.setColorAt(1,QColor('#db4100'))
            else:fill.setColorAt(0,QColor(77,74,73,202));fill.setColorAt(1,QColor(37,35,36,192))
            p.setBrush(fill);p.setPen(QPen(QColor(255,255,255,52),.7));p.drawPath(path)
            a=-math.pi/2+2*math.pi*i/len(self.options);x=146+97*math.cos(a);y=146+97*math.sin(a)
            p.setPen(Qt.white);p.setFont(QFont('Segoe UI',9,QFont.DemiBold))
            p.drawText(QRectF(x-37,y-21,74,42),Qt.AlignCenter|Qt.TextWordWrap,name.upper())
        p.setBrush(QColor(44,42,45,213));p.setPen(QPen(QColor(255,255,255,70),1));p.drawRoundedRect(QRectF(107,132,78,28),14,14)
        p.setPen(Qt.white);p.setFont(QFont('Segoe UI',9,QFont.DemiBold));p.drawText(QRectF(107,132,78,28),Qt.AlignCenter,getattr(self,'badge','File'));p.end()

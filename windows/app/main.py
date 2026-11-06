import ctypes
import os
import shutil
import subprocess
import sys
import threading
import traceback
import uuid
from pathlib import Path
if os.name == 'nt':
    qt_dir = Path(__file__).resolve().parent.parent/'runtime/site/PySide6'
    if qt_dir.is_dir():
        qt_dll_directory = os.add_dll_directory(str(qt_dir))
        os.environ['QT_QPA_PLATFORM_PLUGIN_PATH'] = str(qt_dir/'plugins/platforms')
from PySide6.QtCore import Qt,QPoint,QSettings,QTimer,QMimeData,QUrl,Signal
from PySide6.QtGui import QIcon,QDrag,QCursor
from PySide6.QtWidgets import (QApplication,QWidget,QVBoxLayout,QHBoxLayout,QGridLayout,QLabel,QComboBox,QPushButton,QFileDialog,QSystemTrayIcon,QMenu,QDialog,QDialogButtonBox,QCheckBox,QMessageBox,QTabWidget,QTableWidget,QTableWidgetItem,QHeaderView)
from engine import APP,CACHE,GROUPS,choices,targets,convert,fresh,fmt
from wheel import Wheel,MODES,files
from editor import settings
from sharing import Sharing,storage_items

STYLE="""
QWidget {background:#242427;color:#f4f1ed;font:10pt "Segoe UI";}
QPushButton,QComboBox {background:#38383c;border:1px solid #535355;border-radius:7px;padding:6px 10px;}
QPushButton:hover {background:#594235;border-color:#ff8036;}
QPushButton:pressed {background:#b44b16;}
QMenu::item:selected {background:#814318;}
QTableWidget,QTextEdit,QLineEdit {background:#303034;selection-background-color:#915127;}
"""
def mime(paths):
    data=QMimeData();data.setUrls([QUrl.fromLocalFile(str(p)) for p in paths]);return data

class DragButton(QPushButton):
    def __init__(self,paths):
        super().__init__('Drag '+(paths[0].name if len(paths)==1 else f'{len(paths)} items'));self.paths=paths;self.start=None
    def mousePressEvent(self,e):
        self.start=e.position().toPoint();super().mousePressEvent(e)
    def mouseMoveEvent(self,e):
        if self.start is not None and (self.start-e.position().toPoint()).manhattanLength()>=QApplication.startDragDistance():
            self.start=None;drag=QDrag(self);drag.setMimeData(mime(self.paths));drag.exec(Qt.CopyAction);self.setDown(False)
        else:super().mouseMoveEvent(e)

class Shelf(QWidget):
    def __init__(self,paths):
        super().__init__(None,Qt.Tool|Qt.WindowStaysOnTopHint);self.paths=paths;self.setWindowTitle('Clementine W · Files')
        layout=QVBoxLayout(self);layout.addWidget(DragButton(paths));b=QPushButton('Save a copy to folder…');layout.addWidget(b);b.clicked.connect(self.save)
    def save(self):
        folder=QFileDialog.getExistingDirectory(self,'Choose a destination')
        if not folder:return
        try:
            for src in self.paths:
                dst=fresh(Path(folder),src.name)
                if src.is_dir():
                    if dst.resolve().is_relative_to(src.resolve()):raise ValueError('Choose a folder outside the source folder.')
                    shutil.copytree(src,dst)
                else:shutil.copy2(src,dst)
            self.close()
        except Exception as exc:QMessageBox.warning(self,'Save a copy',str(exc))

class Workspace(QWidget):
    completed=Signal(object,object,object);failed=Signal(str)
    def __init__(self):
        super().__init__();self.setWindowTitle('Clementine W');self.resize(490,270);self.setAcceptDrops(True)
        self.prefs=QSettings('Clementine','Clementine W');self.paths=[];self.shelves=[];self.jobs=0;self.sharing=Sharing()
        self.wheel=Wheel(self.prefs);self.wheel.chosen.connect(self.perform)
        self.completed.connect(self.finish);self.failed.connect(self.error)
        layout=QVBoxLayout(self);layout.setContentsMargins(20,18,20,18);layout.setSpacing(10)
        tip=QLabel('Drag a file in Explorer and hold Shift to convert, Ctrl for tools, or Alt for actions. Drop on a wheel option to use it.');tip.setWordWrap(True);layout.addWidget(tip)
        row=QHBoxLayout();self.openButton=QPushButton('Choose files…');self.openButton.clicked.connect(self.pick);row.addWidget(self.openButton)
        self.mode=QComboBox();self.mode.addItems(MODES);self.mode.currentTextChanged.connect(self.refresh);row.addWidget(self.mode);layout.addLayout(row)
        self.selection=QLabel('Or drop files here');layout.addWidget(self.selection);self.grid=QGridLayout();layout.addLayout(self.grid);layout.addStretch();self.status=QLabel();layout.addWidget(self.status)
        self.tray=QSystemTrayIcon(QIcon(str(APP/'icon.png')),self);self.tray.setToolTip('Clementine W')
        self.menu=QMenu();self.menu.addAction('Clementine W is ready').setEnabled(False);self.menu.addSeparator()
        self.menu.addAction('Open workspace…',self.open);self.menu.addAction('Settings…',self.preferences);self.menu.addSeparator();self.menu.addAction('Quit Clementine W',QApplication.quit)
        self.tray.setContextMenu(self.menu);self.tray.activated.connect(lambda reason:self.open() if reason==QSystemTrayIcon.Trigger else None);self.tray.show()
    def open(self):self.showNormal();self.raise_();self.activateWindow()
    def dragEnterEvent(self,e):
        if files(e.mimeData()):e.setDropAction(Qt.CopyAction);e.accept()
    def dropEvent(self,e):
        self.set_files(files(e.mimeData()));e.setDropAction(Qt.CopyAction);e.accept()
    def pick(self):
        paths,_=QFileDialog.getOpenFileNames(self,'Choose files')
        if paths:self.set_files([Path(p) for p in paths])
    def set_files(self,paths):
        self.paths=paths;self.selection.setText(paths[0].name if len(paths)==1 else f'{len(paths)} files');self.refresh()
    def refresh(self,*_):
        while self.grid.count():self.grid.takeAt(0).widget().deleteLater()
        if not self.paths:return
        mode=self.mode.currentText()
        for i,a in enumerate(x for x in choices(self.paths[0],mode) if all(x in choices(p,mode) for p in self.paths)):
            b=QPushButton(a);b.clicked.connect(lambda checked=False,act=a:self.perform(self.paths[:],act,QCursor.pos()));self.grid.addWidget(b,i//4,i%4)
    def preferences(self):
        d=QDialog(self);d.setWindowTitle('Clementine W Settings');d.resize(540,430);layout=QVBoxLayout(d)
        tap=QCheckBox('Play a tap when selecting a wheel option');tap.setChecked(self.prefs.value('tap',True,type=bool));layout.addWidget(tap)
        start=QCheckBox('Start in the tray when I sign in');layout.addWidget(start)
        if os.name=='nt':
            import winreg
            key=r'Software\Microsoft\Windows\CurrentVersion\Run'
            try:
                with winreg.OpenKey(winreg.HKEY_CURRENT_USER,key) as k:start.setChecked(bool(winreg.QueryValueEx(k,'Clementine W')[0]))
            except FileNotFoundError:pass
        tabs=QTabWidget();tabs.setUsesScrollButtons(True)
        for g,(sources,outputs) in GROUPS.items():
            rows=sources.split();cols=outputs.split();t=QTableWidget(len(rows),len(cols));t.setHorizontalHeaderLabels(cols);t.setVerticalHeaderLabels(rows);t.setEditTriggers(QTableWidget.NoEditTriggers)
            for i,src in enumerate(rows):
                for j,dst in enumerate(cols):
                    item=QTableWidgetItem('✓' if dst in targets(src,g) else '–');item.setTextAlignment(Qt.AlignCenter);t.setItem(i,j,item)
            t.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeToContents);tabs.addTab(t,g)
        layout.addWidget(tabs);b=QDialogButtonBox(QDialogButtonBox.Ok|QDialogButtonBox.Cancel);layout.addWidget(b);b.accepted.connect(d.accept);b.rejected.connect(d.reject)
        if d.exec():
            self.prefs.setValue('tap',tap.isChecked())
            if os.name=='nt':
                try:
                    with winreg.CreateKey(winreg.HKEY_CURRENT_USER,key) as k:
                        if start.isChecked():winreg.SetValueEx(k,'Clementine W',0,winreg.REG_SZ,subprocess.list2cmdline([sys.executable, str(APP / "start.py"), "--tray"]))
                        else:
                            try:winreg.DeleteValue(k,'Clementine W')
                            except FileNotFoundError:pass
                except OSError as e:self.error(str(e))
    def shelf(self,paths,pos):
        w=Shelf(paths);self.shelves=[s for s in self.shelves if s.isVisible()]+[w];w.adjustSize()
        screen=QApplication.screenAt(pos) or QApplication.primaryScreen();r=screen.availableGeometry()
        w.move(max(r.left(),min(pos.x()+10,r.right()-w.width())),max(r.top(),min(pos.y()+10,r.bottom()-w.height())));w.show();w.raise_()
    def error(self,text):
        self.status.setText('Action could not finish');QMessageBox.warning(self,'Clementine W',text)
    def job(self,fn,callback,pos):
        self.jobs+=1;self.status.setText('Working…');self.tray.setToolTip('Clementine W · Working…')
        def worker():
            try:result=fn()
            except Exception as e:self.completed.emit(None,(None,str(e)),pos)
            else:self.completed.emit(result,(callback,None),pos)
        threading.Thread(target=worker,daemon=True).start()
    def finish(self,result,info,pos):
        self.jobs-=1;callback,err=info
        if not self.jobs:self.tray.setToolTip('Clementine W');self.status.setText('Ready')
        if err:self.error(err);return
        try:callback(result,pos)
        except Exception as e:self.error(str(e))
    def perform(self,paths,action,pos):
        try:
            if not paths:return
            if action=='Float':self.shelf(paths,pos);return
            if action=='Copy':QApplication.clipboard().setMimeData(mime(paths));return
            if action=='Copy path':QApplication.clipboard().setText('\n'.join(map(str,paths)));return
            if action=='Show in Explorer':subprocess.Popen(['explorer.exe','/select,',str(paths[0])]);return
            if action=='Share':
                self.open()
                self.job(lambda:storage_items(paths),lambda items,_:self.sharing.show(int(self.winId()),items,paths[0].name),pos);return
            if action=='Move':
                folder=QFileDialog.getExistingDirectory(self,'Move originals to folder')
                if folder:
                    def move():
                        for p in paths:
                            dst=Path(folder)/p.name
                            if dst.exists():raise FileExistsError(str(dst)+' already exists.')
                        for p in paths:shutil.move(p,Path(folder)/p.name)
                    self.job(move,lambda *_:None,pos)
                return
            if action=='Metadata':
                for p in paths:
                    if fmt(p)=='PDF':
                        from pypdf import PdfReader
                        meta=dict(PdfReader(p).metadata or {})
                    else:
                        from PIL import Image,ExifTags
                        if fmt(p)=='SVG':meta={'Format':'SVG'}
                        else:
                            if fmt(p)=='HEIC':
                                import pillow_heif
                                pillow_heif.register_heif_opener()
                            with Image.open(p) as im:meta={'Format':im.format,'Dimensions':f'{im.width} × {im.height}',**{ExifTags.TAGS.get(k,k):v for k,v in im.getexif().items() if not isinstance(v,bytes)}}
                    QMessageBox.information(self,p.name,'\n'.join(f'{k}: {v}' for k,v in meta.items()) or 'No metadata found.')
                return
            plans=[]
            for path in paths:
                options=settings(self,path,action)
                if options is None:return
                plans.append((path,options))
            dest=CACHE/'Results'/uuid.uuid4().hex
            self.job(lambda:[convert(path,action,opts,dest) for path,opts in plans],self.shelf,pos)
        except Exception as exc:self.error(str(exc))

def main():
    if os.name=='nt':
        ctypes.windll.ole32.OleInitialize(None)
        ctypes.windll.kernel32.CreateMutexW.restype=ctypes.c_void_p
        mutex=ctypes.windll.kernel32.CreateMutexW(None,False,'Local\\ClementineW.Main')
        if mutex and ctypes.windll.kernel32.GetLastError()==183:
            if '--tray' not in sys.argv:
                hwnd=ctypes.windll.user32.FindWindowW(None,'Clementine W')
                if hwnd:ctypes.windll.user32.ShowWindow(hwnd,9);ctypes.windll.user32.SetForegroundWindow(hwnd)
            return
    app=QApplication(sys.argv);app.setApplicationName('Clementine W');app.setQuitOnLastWindowClosed(False);app.setStyle('Fusion');app.setStyleSheet(STYLE);app.setWindowIcon(QIcon(str(APP/'icon.png')))
    w=Workspace()
    if '--tray' not in sys.argv:w.open()
    sys.exit(app.exec())

if __name__=='__main__':
    try:main()
    except Exception:
        msg=traceback.format_exc()
        if os.name=='nt':ctypes.windll.user32.MessageBoxW(None,msg,'Clementine W',16)
        else:raise

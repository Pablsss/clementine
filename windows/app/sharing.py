"""Show the Windows 11 share sheet for files belonging to an HWND."""
import ctypes as c
from uuid import UUID

def storage_items(paths):
    from winrt.windows.storage import StorageFile, StorageFolder
    from winrt.runtime import init_apartment,uninit_apartment,ApartmentType
    init_apartment(ApartmentType.MULTI_THREADED)
    try:
        result=[]
        for path in paths:
            op=(StorageFolder.get_folder_from_path_async if path.is_dir() else StorageFile.get_file_from_path_async)(str(path.resolve()))
            op.wait(30.0);result.append(op.get_results())
        return result
    finally:uninit_apartment()

class Sharing:
    def show(self, hwnd, items, title):
        from winrt.runtime.interop import get_activation_factory,wrap_interface
        from winrt.windows.applicationmodel.datatransfer import DataTransferManager
        from ctypes import wintypes
        # Both capsule APIs keep the name pointer, so retain the bytes object.
        name=b'winrt.interface'
        get=c.pythonapi.PyCapsule_GetPointer;get.argtypes=[c.py_object,c.c_char_p];get.restype=c.c_void_p
        make=c.pythonapi.PyCapsule_New;make.argtypes=[c.c_void_p,c.c_char_p,c.c_void_p];make.restype=c.py_object
        factory=get_activation_factory(DataTransferManager,UUID('3a3dcd6c-3eab-43dc-bcde-45671ce800c8'))
        ptr=get(factory,name)
        def method(obj,slot,ret,*args):
            table=c.cast(obj,c.POINTER(c.POINTER(c.c_void_p))).contents
            return c.WINFUNCTYPE(ret,c.c_void_p,*args)(table[slot])
        def check(hr):
            if hr<0:raise OSError(f'Windows Share returned 0x{hr & 0xffffffff:08X}.')
        iid=c.create_string_buffer(UUID('a5caee9b-8708-49d1-8d36-67d25a8da00c').bytes_le)
        raw=c.c_void_p()
        check(method(ptr,3,c.c_long,wintypes.HWND,c.c_void_p,c.POINTER(c.c_void_p))(ptr,hwnd,iid,c.byref(raw)))
        try:manager=wrap_interface(make(raw,name,None),DataTransferManager)
        finally:method(raw,2,c.c_ulong)(raw)
        if hasattr(self,'manager'):self.manager.remove_data_requested(self.token)
        def requested(sender,event):
            data=event.request.data;data.properties.title=title
            data.set_storage_items(items,True)
        self.manager=manager;self.token=manager.add_data_requested(requested)
        check(method(ptr,4,c.c_long,wintypes.HWND)(ptr,hwnd))

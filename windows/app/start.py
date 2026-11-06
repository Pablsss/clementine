"""Report early loader errors even when launched without a console."""
import ctypes
import traceback
try:
    from main import main
    main()
except Exception:
    ctypes.windll.user32.MessageBoxW(None, traceback.format_exc(), 'Clementine W', 16)

# Clementine
Drop a file onto the macOS menu-bar app or Windows tray app to convert, edit or share it locally. The available actions depend on the file type and include image resizing, PDF splitting and media trimming.

**macOS 13 or later.** Install Xcode Command Line Tools. From `macos`, run `./build.sh` and open `Clementine.app`. For media and office conversions, install FFmpeg, Node.js and LibreOffice. For Python document helpers install Pillow, pypdfium2, pdfplumber, python-docx, python-pptx and openpyxl into your Python environment before building. The build records your local tool paths.

**Windows x64.** With Python 3.12, run `py -3.12 -m pip install -r windows/requirements.txt` and `py -3.12 windows/app/start.py`. Install FFmpeg and Node.js on PATH for media and Pages conversions. Install LibreOffice in its usual Program Files location for office conversions.

Original code is MIT licensed. The included cupertino-files library retains its own license and third-party notices alongside its source.

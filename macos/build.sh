#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build-cache Clementine.app/Contents/MacOS
cp Info.plist Clementine.app/Contents/
resources=Clementine.app/Contents/Resources
mkdir -p "$resources"
cp -R Resources/. "$resources/"
python3 - "$resources/Tools.plist" <<'PYTHON'
import plistlib, shutil, sys
paths = {name: path for name in ("python3", "node", "ffmpeg", "soffice")
         if (path := shutil.which(name))}
paths.setdefault("soffice", "/Applications/LibreOffice.app/Contents/MacOS/soffice")
with open(sys.argv[1], "wb") as output:
    plistlib.dump(paths, output)
PYTHON
swiftc -O -module-cache-path .build-cache -swift-version 5 Sources/*.swift -o Clementine.app/Contents/MacOS/Clementine -framework Cocoa -framework SwiftUI -framework PDFKit -framework AVFoundation -framework UniformTypeIdentifiers -framework ImageIO -framework AudioToolbox
codesign --force --sign - Clementine.app

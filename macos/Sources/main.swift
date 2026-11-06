import Cocoa
import SwiftUI
import PDFKit
import AVFoundation
import UniformTypeIdentifiers
import ImageIO
import AudioToolbox

func wheelSymbol(_ name:String, color:NSColor = .white) -> NSImage? {
    if name != "airdrop" { return NSImage(systemSymbolName:name,accessibilityDescription:nil) }
    return NSImage(size:NSSize(width:18,height:18),flipped:false) { rect in
        color.setStroke(); color.setFill()
        for radius:CGFloat in [3,5.5,8] {
            let ring=NSBezierPath(); ring.lineWidth=1.2; ring.lineCapStyle = .round
            ring.appendArc(withCenter:NSPoint(x:9,y:9),radius:radius,startAngle:-40,endAngle:220); ring.stroke()
        }
        let triangle=NSBezierPath(); triangle.move(to:NSPoint(x:9,y:8)); triangle.line(to:NSPoint(x:5,y:1)); triangle.line(to:NSPoint(x:13,y:1)); triangle.close(); triangle.fill()
        return true
    }
}
let orange = Color(red: 1, green: 0.55, blue: 0.25)
@MainActor enum OptionFeedback {
    static var soundID:SystemSoundID = 0
    static func prepare() {
        guard soundID == 0,let url=Bundle.main.url(forResource:"Tap",withExtension:"wav") else { return }
        AudioServicesCreateSystemSoundID(url as CFURL,&soundID)
    }
    static func play(haptics:Bool,sound enabled:Bool) {
        if haptics { NSHapticFeedbackManager.defaultPerformer.perform(.generic,performanceTime:.now) }
        if enabled && soundID != 0 { AudioServicesPlaySystemSound(soundID) }
    }
}
struct OptionTransition {
    var previous:Int?
    mutating func enter(_ index:Int?, enabled:Bool) -> Bool {
        guard let index,enabled else { return false }
        defer { previous=index }
        return previous != index
    }
    mutating func reset() { previous=nil }
}
struct Job: Identifiable { let id = UUID(); let name: String; let result: String; let url: URL? }
@MainActor final class Model: ObservableObject {
    @Published var files: [URL] = []
    @Published var wheelEnabled = UserDefaults.standard.object(forKey:"wheelEnabled") as? Bool ?? true { didSet { UserDefaults.standard.set(wheelEnabled,forKey:"wheelEnabled") } }
    @Published var hapticsEnabled = UserDefaults.standard.object(forKey:"hapticsEnabled") as? Bool ?? true { didSet { UserDefaults.standard.set(hapticsEnabled,forKey:"hapticsEnabled") } }
    @Published var soundEnabled = UserDefaults.standard.object(forKey:"soundEnabled") as? Bool ?? true { didSet { UserDefaults.standard.set(soundEnabled,forKey:"soundEnabled") } }
    @Published var mode = 0
    @Published var busy = false
    @Published var status = "Everything stays on your Mac"
    @Published var history: [Job] = []
    @Published var width = "1600"
    @Published var quality = 0.85
    @Published var start = "0"
    @Published var end = "10"
    @Published var text = ""
    @Published var output: URL?
    @Published var ready: [URL] = []
    var useDragShelf = false
    var actionStarted: (() -> Void)?
    var editorRequested: ((String,[URL],String,Bool,URL?) -> Void)?
    var conversionFinished: (([URL]) -> Void)?
    var first: URL? { files.first }
    var kind: String {
        guard let u = first else { return "image" }
        let f=Compatibility.format(u)
        if let g=Compatibility.byInput[f] {
            switch g.title {
            case "Images":return "image"
            case "Audio":return "audio"
            case "Video":return "video"
            case "Archives":return "archive"
            case "Subtitles":return "subtitle"
            case "Spreadsheets":return "spreadsheet"
            default:return f=="PDF" ? "pdf" : "document"
            }
        }
        let type = inputType(u)
        if type?.conforms(to: .image) == true { return "image" }
        if u.pathExtension.lowercased() == "pdf" { return "pdf" }
        if type?.conforms(to: .movie) == true { return "video" }
        if type?.conforms(to: .audio) == true { return "audio" }
        return "document"
    }
    var choices: [(String,String)] {
        if mode == 2 { return [("AirDrop","airdrop"),("Float","pin.fill"),("Copy","doc.on.doc"),("Move","folder"),("Copy path","doc.text"),("Terminal","terminal")] }
        if mode == 1 {
            switch kind {
            case "image": return [("Compress","arrow.down.right.and.arrow.up.left"),("Metadata","tag"),("Edit","slider.horizontal.3"),("Annotate","pencil.tip.crop.circle"),("Add BG","photo"),("Crop","crop"),("Resize","arrow.up.left.and.arrow.down.right"),("Redact","eye.slash")]
            case "pdf": return [("Compress","arrow.down.right.and.arrow.up.left"),("Metadata","tag"),("Split","rectangle.split.2x1"),("Organize","square.grid.2x2"),("PDF/A","checkmark.seal"),("Read QR","qrcode.viewfinder")]
            case "archive","spreadsheet":return [("ZIP","archivebox"),("Reveal","folder"),("Copy path","link"),("Copy files","doc.on.doc")]
            case "subtitle":return [("Save text","square.and.arrow.down"),("Reveal","folder"),("Copy path","link"),("Copy files","doc.on.doc")]
            case "audio": return [("Trim","scissors"),("M4A","waveform"),("ZIP","archivebox"),("Reveal","folder"),("Copy path","link"),("Copy files","doc.on.doc")]
            case "video": return [("Trim","scissors"),("M4A","waveform"),("MP4","film"),("MOV","film.stack"),("Reveal","folder"),("Copy path","link")]
            default: return [("TXT","text.alignleft"),("RTF","doc.text"),("HTML","chevron.left.forwardslash.chevron.right"),("Save text","square.and.arrow.down"),("ZIP","archivebox"),("Reveal","folder")]
            }
        }
        if let first,let options=Compatibility.wheel[Compatibility.format(first)] {return options}
        switch kind {
        case "pdf": return [("DOCX","doc"),("PAGES","doc"),("PPTX","doc"),("XLSX","doc"),("JPEG","photo"),("PNG","photo"),("EPUB","book"),("TXT","text.alignleft"),("MD","text.alignleft")]
        case "audio": return [("M4A","waveform"),("Trim","scissors"),("ZIP","archivebox"),("Reveal","folder")]
        case "video": return [("MP4","film"),("MOV","film.stack"),("M4A","waveform"),("Trim","scissors")]
        case "document": return [("TXT","text.alignleft"),("RTF","doc.text"),("HTML","chevron.left.forwardslash.chevron.right"),("DOCX","doc"),("ZIP","archivebox"),("Save text","square.and.arrow.down")]
        default:
            var formats=[("JPEG","photo"),("PNG","photo"),("WEBP","photo"),("HEIC","photo"),("TIFF","photo"),("BMP","photo"),("PDF","doc.richtext")]
            if let ext=first?.pathExtension.lowercased() { let current=["jpg":"JPEG","jpeg":"JPEG","png":"PNG","heic":"HEIC","heif":"HEIC","tif":"TIFF","tiff":"TIFF","bmp":"BMP","webp":"WEBP"][ext]; formats.removeAll { $0.0 == current } }
            return formats
        }
    }
    func available(_ action:String)->Bool {
        if ["PDF/A","Read QR"].contains(action) {return false}
        if action == "Save text",let first { return ["txt","md","csv","json","html","srt","vtt"].contains(first.pathExtension.lowercased()) }
        return true
    }
    func add(_ urls: [URL],replace:Bool=false) {
        var selection=replace ? [] : files
        var seen=Set(selection)
        for u in urls where u.isFileURL && seen.insert(u).inserted {selection.append(u)}
        guard selection != files else {return}
        files=selection
        if ["document","subtitle","spreadsheet"].contains(kind),let u=first,["txt","md","csv","json","html","srt","vtt"].contains(u.pathExtension.lowercased()),let size=try? u.resourceValues(forKeys:[.fileSizeKey]).fileSize,size < 2_000_000,let s=try? String(contentsOf:u,encoding:.utf8) { text=s }
    }
    func choose() { let p = NSOpenPanel(); p.allowsMultipleSelection = true; if p.runModal() == .OK { add(p.urls) } }
    func destination() { let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; if p.runModal() == .OK { output = p.url } }
    let airDropPresenter = AirDropPresenter()
    func performFileAction(_ action:String, at point:NSPoint?) {
        actionStarted?()
        if action == "Float" { ready=files; conversionFinished?(ready); return }
        if action == "AirDrop" {
            let selection = files
            let position = point ?? NSEvent.mouseLocation
            DispatchQueue.main.async { self.airDropPresenter.present(selection, at:position) }
            return
        }
        if action == "Terminal" {
            guard let u=first,let terminal=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.Terminal") else { return }
            let dir=u.hasDirectoryPath ? u : u.deletingLastPathComponent()
            NSWorkspace.shared.open([dir],withApplicationAt:terminal,configuration:NSWorkspace.OpenConfiguration()); return
        }
        if action == "Move" {
            NSApp.activate(ignoringOtherApps:true)
            let picker=NSOpenPanel(); picker.canChooseFiles=false; picker.canChooseDirectories=true; picker.prompt="Move here"
            guard picker.runModal() == .OK,let dir=picker.url else { return }
            do {
                let destinations=files.map { dir.appendingPathComponent($0.lastPathComponent) }
                guard Set(destinations).count == destinations.count, destinations.allSatisfy({ !FileManager.default.fileExists(atPath:$0.path) }) else { throw Failure.message("Destination contains a file with the same name. Nothing was moved.") }
                for (from,to) in zip(files,destinations) { try FileManager.default.moveItem(at:from,to:to) }
                files=destinations; status="Moved to \(dir.lastPathComponent)"
            } catch { status=error.localizedDescription }
            return
        }
        if action == "Metadata",let u=first {
            var description="File: \(u.lastPathComponent)\nSize: \(selectionSize([u]))\n"
            if kind == "pdf",let doc=PDFDocument(url:u) { description += "Pages: \(doc.pageCount)\n" + String(describing:doc.documentAttributes ?? [:]) }
            else if let src=CGImageSourceCreateWithURL(u as CFURL,nil), let props=CGImageSourceCopyPropertiesAtIndex(src,0,nil) { description += String(describing:props) }
            let alert=NSAlert(); alert.messageText="Metadata"; alert.informativeText=String(description.prefix(5000)); alert.addButton(withTitle:"Done")
            if kind == "image" { alert.addButton(withTitle:"Remove metadata from copy") }
            NSApp.activate(ignoringOtherApps:true)
            if alert.runModal() == .alertSecondButtonReturn { run("Strip metadata") }
        }
    }
    func run(_ requested: String, at point:NSPoint? = nil) {
        guard !busy else { return }
        guard available(requested) else { status="\(requested) is not available in this build"; return }
        let action = ["Crop":"Square crop","Split":"Split pages","Copy":"Copy files"][requested] ?? requested
        if action == "Clear" { files = []; return }
        if action == "Choose folder" { destination(); return }
        guard !files.isEmpty else { choose(); return }
        let directMedia=kind=="video" && ["MP4","MOV"].contains(requested) && !["mp4","mov","m4v"].contains(first?.pathExtension.lowercased() ?? "")
        if let editorRequested, !directMedia, usesEditor(requested,kind:kind) {
            let shelf=shouldStageOutput(floating:useDragShelf,explicitFolder:output)
            let selected=files,category=kind,destination=output
            actionStarted?()
            DispatchQueue.main.async { editorRequested(requested,selected,category,shelf,destination) }
            return
        }
        if ["AirDrop","Float","Move","Terminal","Metadata"].contains(action) { performFileAction(action, at:point); return }
        if action == "Reveal" { NSWorkspace.shared.activateFileViewerSelecting(files); return }
        if action == "Copy path" { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(files.map(\.path).joined(separator: "\n"), forType: .string); status = "Paths copied"; return }
        if action == "Copy files" { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(files as [NSURL]); status = "Files copied"; return }
        if action == "Save text" && files.count != 1 { status = "Select one text file to edit and save"; return }
        let shelf = shouldStageOutput(floating:useDragShelf, explicitFolder:output)
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("Clementine-Drag/" + UUID().uuidString, isDirectory: true)
        let selection = files, target = shelf ? staging : output, w = Int(width) ?? 1600, q = quality, s = Double(start) ?? 0, e = Double(end) ?? 10, content = text
        actionStarted?()
        busy = true; status = "Processing \(selection.count) file(s)…"
        Task {
            let results = await Task.detached(priority: .userInitiated) { () -> [Job] in
                var jobs: [Job] = []
                do {
                    if action == "Merge PDF" || action == "Make PDF" {
                        let doc = PDFDocument()
                        for u in selection {
                            if let source = PDFDocument(url: u) { for i in 0..<source.pageCount { if let p = source.page(at: i) { doc.insert(p, at: doc.pageCount) } } }
                            else if let im = NSImage(contentsOf: u), let p = PDFPage(image: im) { doc.insert(p, at: doc.pageCount) }
                            else { throw Failure.message("Cannot add \(u.lastPathComponent) to PDF") }
                        }
                        let out = try outputURL(selection[0], target, "pdf", "merged")
                        guard doc.pageCount > 0, doc.write(to: out) else { throw Failure.message("Could not write PDF") }
                        return [Job(name: "Merged PDF", result: "\(doc.pageCount) pages", url: out)]
                    }
                    for u in selection {
                        do {
                            let out = try await process(u, action, target, w, q, s, e, content)
                            jobs.append(Job(name: u.lastPathComponent, result: "Saved \(out.lastPathComponent)", url: out))
                        } catch { jobs.append(Job(name: u.lastPathComponent, result: error.localizedDescription, url: nil)) }
                    }
                } catch { jobs.append(Job(name: action, result: error.localizedDescription, url: nil)) }
                return jobs
            }.value
            history.insert(contentsOf: results, at: 0); busy = false
            ready = results.compactMap(\.url)
            if shelf { conversionFinished?(ready) }
            let errors = results.filter { $0.url == nil }.count
            status = errors == 0 ? (shelf ? "Ready · drag the converted copy to your destination" : "Saved · originals preserved") : "Finished with \(errors) error(s) · see activity"
        }
    }
}
enum Failure: LocalizedError { case message(String); var errorDescription: String? { if case .message(let s) = self { return s }; return nil } }
func inputType(_ url: URL) -> UTType? {
    switch url.pathExtension.lowercased() {
    case "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp", "avif": return .image
    case "mp4", "mov", "m4v", "mkv", "avi", "webm": return .movie
    case "m4a", "mp3", "wav", "aiff", "aif", "flac", "aac", "ogg": return .audio
    default: return UTType(filenameExtension:url.pathExtension)
    }
}
func outputURL(_ input: URL, _ folder: URL?, _ ext: String, _ suffix: String = "converted") throws -> URL {
    let dir = folder ?? input.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let base = input.deletingPathExtension().lastPathComponent + "-" + suffix
    var out = dir.appendingPathComponent(base).appendingPathExtension(ext); var n = 2
    while FileManager.default.fileExists(atPath: out.path) { out = dir.appendingPathComponent("\(base)-\(n)").appendingPathExtension(ext); n += 1 }
    return out
}
func process(_ u: URL, _ action: String, _ folder: URL?, _ width: Int, _ quality: Double, _ start: Double, _ end: Double, _ text: String) async throws -> URL {
    if let converted=try Compatibility.convert(u,action,folder,quality) { return converted }
    let type = inputType(u)
    if action == "ZIP" {
        let out = try outputURL(u, folder, "zip")
        try command("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", u.path, out.path]); return out
    }
    if u.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: u) {
        if action == "TXT" || action == "MD" || action == "Extract text" {
            let out = try outputURL(u, folder, action == "MD" ? "md" : "txt"); try (doc.string ?? "").write(to: out, atomically: true, encoding: .utf8); return out
        }
        if action == "Rotate PDF" { for i in 0..<doc.pageCount { if let p = doc.page(at:i) { p.rotation = (p.rotation + 90) % 360 } }; let out = try outputURL(u, folder, "pdf", "rotated"); guard doc.write(to:out) else { throw Failure.message("PDF write failed") }; return out }
        guard ["PNG","JPEG","Pages to PNG","Split pages"].contains(action) else { throw Failure.message("Unsupported PDF operation") }
        let directory = try outputURL(u, folder, "", "pages"); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            if action == "Split pages" { let one = PDFDocument(); one.insert(page, at: 0); guard one.write(to: directory.appendingPathComponent("Page-\(i+1).pdf")) else { throw Failure.message("Page export failed") } }
            else { let bounds = page.bounds(for: .mediaBox); let scale = min(300.0 / 72.0, 6000.0 / max(bounds.width,bounds.height)); let image = page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox); guard let cg = image.cgImage(forProposedRect: nil, context:nil,hints:nil) else { throw Failure.message("Page render failed") }; try writeImage(cg, directory.appendingPathComponent("Page-\(i+1).\(action == "JPEG" ? "jpg" : "png")"), action == "JPEG" ? UTType.jpeg : UTType.png, quality) }
        }; return directory
    }
    if type?.conforms(to: .image) == true {
        guard let source = CGImageSourceCreateWithURL(u as CFURL,nil), var cg = CGImageSourceCreateImageAtIndex(source,0,nil) else { throw Failure.message("This image cannot be decoded") }
        if action == "Resize" { guard width > 0 && width <= 16000 else { throw Failure.message("Width must be 1–16000 pixels") }; let h = max(1, Int(Double(cg.height)*Double(width)/Double(cg.width))); guard h <= 32000 else { throw Failure.message("Result is too tall") }; cg = try render(cg,width,h,false) }
        if action == "Rotate" { cg = try render(cg,cg.height,cg.width,true) }
        if action == "Square crop" { let size = min(cg.width,cg.height); guard let crop = cg.cropping(to: CGRect(x:(cg.width-size)/2,y:(cg.height-size)/2,width:size,height:size)) else { throw Failure.message("Crop failed") }; cg = crop }
        if action == "PDF" { let doc = PDFDocument(); guard let p = PDFPage(image:NSImage(cgImage:cg,size:.zero)) else { throw Failure.message("PDF creation failed") }; doc.insert(p,at:0); let out = try outputURL(u,folder,"pdf"); guard doc.write(to:out) else { throw Failure.message("PDF write failed") }; return out }
        let formats: [String:UTType] = ["PNG":.png,"JPEG":.jpeg,"HEIC":.heic,"TIFF":.tiff,"BMP":.bmp]
        let format = formats[action] ?? (action == "Compress" ? .jpeg : .png)
        let out = try outputURL(u,folder,format.preferredFilenameExtension ?? "png",action.lowercased().replacingOccurrences(of:" ",with:"-"))
        try writeImage(cg,out,format,quality); return out
    }
    if type?.conforms(to: .movie) == true || type?.conforms(to: .audio) == true {
        let audio = action == "M4A" || type?.conforms(to: .audio) == true
        let ext = audio ? "m4a" : action == "MOV" ? "mov" : "mp4"
        let asset = AVURLAsset(url:u)
        guard let session = AVAssetExportSession(asset:asset,presetName:audio ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality) else { throw Failure.message("Media format is not supported by macOS") }
        let fileType: AVFileType = audio ? .m4a : ext == "mov" ? .mov : .mp4
        guard session.supportedFileTypes.contains(fileType) else { throw Failure.message("This file cannot be exported to \(ext.uppercased()) by macOS") }
        let out = try outputURL(u,folder,ext,action.lowercased()); session.outputURL = out; session.outputFileType = fileType
        if action == "Trim" { let duration = try await asset.load(.duration).seconds; guard start >= 0 && end > start && end <= duration else { throw Failure.message("Trim must lie within 0–\(Int(duration)) seconds") }; session.timeRange = CMTimeRange(start:CMTime(seconds:start,preferredTimescale:600),end:CMTime(seconds:end,preferredTimescale:600)) }
        await session.export(); guard session.status == .completed else { throw session.error ?? Failure.message("Export failed") }; return out
    }
    if action == "Save text" { guard ["txt","md","csv","json","html","srt","vtt"].contains(u.pathExtension.lowercased()) else { throw Failure.message("Text editing is available for plain-text files only") }; let out = try outputURL(u,folder,u.pathExtension,"edited"); try text.write(to:out,atomically:true,encoding:.utf8); return out }
    guard ["TXT","RTF","HTML","DOCX"].contains(action) else { throw Failure.message("Unsupported file type") }
    let out = try outputURL(u,folder,action.lowercased()); try command("/usr/bin/textutil",["-convert",action.lowercased(),"-output",out.path,u.path]); return out
}
func command(_ path: String, _ args: [String]) throws { let p = Process(); p.executableURL = URL(fileURLWithPath:path); p.arguments = args; let pipe = Pipe(); p.standardError = pipe; try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); if p.terminationStatus != 0 { throw Failure.message(String(data:data,encoding:.utf8) ?? "Operation failed") } }
func render(_ image: CGImage, _ w: Int, _ h: Int, _ rotate: Bool) throws -> CGImage { guard let c = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.message("Image is too large") }; c.interpolationQuality = .high; if rotate { c.translateBy(x:CGFloat(w),y:0); c.rotate(by:.pi/2); c.draw(image,in:CGRect(x:0,y:0,width:h,height:w)) } else { c.draw(image,in:CGRect(x:0,y:0,width:w,height:h)) }; guard let out = c.makeImage() else { throw Failure.message("Image render failed") }; return out }
func writeImage(_ image: CGImage, _ url: URL, _ type: UTType, _ quality: Double) throws { guard let d = CGImageDestinationCreateWithURL(url as CFURL,type.identifier as CFString,1,nil) else { throw Failure.message("Encoder unavailable for \(type.identifier)") }; CGImageDestinationAddImage(d,image,[kCGImageDestinationLossyCompressionQuality:quality] as CFDictionary); guard CGImageDestinationFinalize(d) else { throw Failure.message("Image export failed") } }
func shouldStageOutput(floating: Bool, explicitFolder: URL?) -> Bool { floating || explicitFolder == nil }
func shouldShowWheel(dragging: Bool, hasKey: Bool) -> Bool { dragging && hasKey }
struct Glass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .hudWindow
        view.blendingMode = .behindWindow; view.state = .active; view.appearance = NSAppearance(named:.darkAqua); return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
func selectionSize(_ urls:[URL]) -> String {
    guard !urls.isEmpty else { return "—" }
    var total:Int64=0
    for url in urls {
        guard let values=try? url.resourceValues(forKeys:[.fileSizeKey,.isDirectoryKey]), values.isDirectory != true, let bytes=values.fileSize else { return "—" }
        total += Int64(bytes)
    }
    return ByteCountFormatter.string(fromByteCount:total,countStyle:.file)
}
// The same rounded paths drive rendering, hover, click and drop selection.
struct WheelGeometry {
    static let size: CGFloat = 300
    static let badge = CGRect(x:110,y:134,width:80,height:32)
    static let badgeRadius = badge.height / 2
    static let cachedPaths: [Int:[CGPath]] = Dictionary(uniqueKeysWithValues:(1...12).map { count in
        (count,(0..<count).map { makePath(index:$0,count:count) })
    })
    static func path(index:Int,count:Int)->CGPath { cachedPaths[count]?[index] ?? makePath(index:index,count:count) }
    static func makePath(index: Int, count: Int) -> CGPath {
        let center = CGPoint(x:150,y:150), outer:CGFloat=138, inner:CGFloat=51
        let step=2 * Double.pi / Double(count), gap=0.045
        let start=Double(index)*step - Double.pi/2 - step/2 + gap
        let end=start+step-2*gap
        func point(_ r:CGFloat,_ a:Double)->CGPoint { CGPoint(x:center.x+r*cos(a),y:center.y+r*sin(a)) }
        let p=CGMutablePath(), oc:CGFloat=18, ic:CGFloat=12
        p.move(to:point(outer,start+Double(oc/outer)))
        p.addArc(center:center,radius:outer,startAngle:start+Double(oc/outer),endAngle:end-Double(oc/outer),clockwise:false)
        p.addQuadCurve(to:point(outer-oc,end),control:point(outer,end))
        p.addLine(to:point(inner+ic,end))
        p.addQuadCurve(to:point(inner,end-Double(ic/inner)),control:point(inner,end))
        p.addArc(center:center,radius:inner,startAngle:end-Double(ic/inner),endAngle:start+Double(ic/inner),clockwise:true)
        p.addQuadCurve(to:point(inner+ic,start),control:point(inner,start))
        p.addLine(to:point(outer-oc,start))
        p.addQuadCurve(to:point(outer,start+Double(oc/outer)),control:point(outer,start))
        p.closeSubpath(); return p
    }
    // maskImage clips the behind-window blur itself. The canvas and hit targets
    // use top-left coordinates, so render the same paths into a flipped image.
    static func glassMask(count: Int) -> NSImage {
        let paths = (0..<count).map { path(index: $0, count: count) }
        return NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.white.cgColor)
            paths.forEach { context.addPath($0) }
            context.addPath(CGPath(roundedRect: badge, cornerWidth: badgeRadius,
                                   cornerHeight: badgeRadius, transform: nil))
            context.fillPath()
            return true
        }
    }
    static func selection(at point:CGPoint,count:Int)->Int? {
        guard count > 0 else { return nil }
        return (0..<count).first { path(index:$0,count:count).contains(point) }
    }
    static func labelPoint(index:Int,count:Int)->CGPoint {
        let a=Double(index)*2*Double.pi/Double(count)-Double.pi/2
        return CGPoint(x:150+96*cos(a),y:150+96*sin(a))
    }
}
struct Wheel: NSViewRepresentable {
    @ObservedObject var model:Model
    var floating=false
    func makeNSView(context:Context)->NativeWheel {
        let v=NativeWheel(frame:NSRect(x:0,y:0,width:300,height:300)); v.model=model; v.floating=floating; return v
    }
    func updateNSView(_ v:NativeWheel,context:Context) { v.model=model; v.floating=floating; v.refresh() }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:NativeWheel,context:Context)->CGSize? { CGSize(width:300,height:300) }
}
@MainActor final class NativeWheel: NSView {
    let glass = WheelGlass()
    let canvas = WheelCanvas()
    weak var model:Model?
    var floating=false
    var transition=OptionTransition()
    var dragSequence:Int = -1
    var active:Int? { didSet {
        if active != oldValue {
            canvas.needsDisplay=true
            if let model,transition.enter(active,enabled:active.map { enabled[$0] } ?? false) {
                OptionFeedback.play(haptics:model.hapticsEnabled,sound:model.soundEnabled)
            }
        }
    } }
    var tracking:NSTrackingArea?
    var renderedChoices:[(String,String)] = []
    var paths:[CGPath] = []
    var labels:[NSAttributedString] = []
    var icons:[NSImage?] = []
    var selectedLabels:[NSAttributedString] = []
    var selectedIcons:[NSImage?] = []
    let selectionGradient=NSGradient(starting:NSColor(srgbRed:1,green:0.29,blue:0,alpha:1),ending:NSColor(srgbRed:0.82,green:0.20,blue:0,alpha:1))!
    var enabled:[Bool] = []
    var labelPoints:[CGPoint] = []
    var renderMode = -1
    private var glassSegmentCount = 0
    var signature=""
    var fileSignature=""
    var sizeLabel="—"
    override var isFlipped:Bool { true }
    override var intrinsicContentSize:NSSize { NSSize(width:300,height:300) }
    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer=true
        glass.material = .hudWindow; glass.blendingMode = .behindWindow; glass.state = .active
        glass.appearance=NSAppearance(named:.darkAqua); glass.wantsLayer=true
        glass.frame=bounds; glass.autoresizingMask=[.width,.height]; addSubview(glass)
        canvas.owner=self; canvas.frame=bounds; canvas.autoresizingMask=[.width,.height]; addSubview(canvas)
        registerForDraggedTypes([.fileURL]); setAccessibilityElement(true); setAccessibilityRole(.group)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refresh() {
        guard let model else { return }
        let choices=model.choices
        let next="\(model.mode):" + choices.map { $0.0 + (model.available($0.0) ? "+" : "-") }.joined(separator:"|")
        var changed=false
        if signature != next {
            signature=next; transition.reset(); active=nil; renderMode=model.mode; renderedChoices=choices
            paths=choices.indices.map { WheelGeometry.path(index:$0,count:choices.count) }
            labelPoints=choices.indices.map { WheelGeometry.labelPoint(index:$0,count:choices.count) }
            enabled=choices.map { model.available($0.0) }
            let paragraph=NSMutableParagraphStyle(); paragraph.alignment = .center
            labels=choices.enumerated().map { i,item in
                let title=item.0 == "JPEG" ? "JPG" : item.0 == "Copy path" ? "COPY\nPATH" : item.0.uppercased()
                return NSAttributedString(string:title,attributes:[.font:NSFont.systemFont(ofSize:model.mode == 0 ? 12 : 9,weight:.bold),.foregroundColor:NSColor.white.withAlphaComponent(enabled[i] ? 1 : 0.36),.paragraphStyle:paragraph])
            }
            icons=choices.enumerated().map { i,item in
                guard model.mode != 0,let base=wheelSymbol(item.1) else { return nil }
                return base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors:[NSColor.white.withAlphaComponent(enabled[i] ? 1 : 0.36)])) ?? base
            }
            selectedLabels=labels.map { label in
                let selected=NSMutableAttributedString(attributedString:label)
                selected.addAttribute(.foregroundColor,value:NSColor.white,range:NSRange(location:0,length:selected.length)); return selected
            }
            selectedIcons=choices.map { item in
                guard model.mode != 0,let base=wheelSymbol(item.1) else { return nil }
                return base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors:[.white])) ?? base
            }
            if glassSegmentCount != paths.count {
                glass.maskImage = WheelGeometry.glassMask(count: paths.count)
                glassSegmentCount = paths.count
            }
            changed=true
        }
        let fileKey=model.files.map(\.path).joined(separator:"\n")
        if fileSignature != fileKey {
            fileSignature=fileKey; sizeLabel=selectionSize(model.files)
            setAccessibilityLabel("Conversion wheel, selected size " + sizeLabel); changed=true
        }
        if changed { canvas.needsDisplay=true }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking=NSTrackingArea(rect:.zero,options:[.mouseMoved,.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(tracking!)
    }
    func selection(at point:NSPoint)->Int? { paths.indices.first { paths[$0].contains(point) } }
    override func mouseMoved(with event:NSEvent) { active=selection(at:convert(event.locationInWindow,from:nil)); toolTip=active.map { enabled[$0] ? renderedChoices[$0].0 : renderedChoices[$0].0 + " — not available in this build" } }
    override func mouseEntered(with event:NSEvent) { mouseMoved(with:event) }
    override func mouseExited(with event:NSEvent) { active=nil }
    override func mouseUp(with event:NSEvent) {
        guard let i=selection(at:convert(event.locationInWindow,from:nil)) else { return }; apply(i,urls:nil,at:window?.convertPoint(toScreen:event.locationInWindow))
    }
    func apply(_ index:Int,urls:[URL]?,at point:NSPoint? = nil) {
        guard let model,!model.busy,renderedChoices.indices.contains(index),enabled[index] else { return }
        let action=renderedChoices[index].0
        if let urls,urls != model.files { model.add(urls,replace:true) }
        model.useDragShelf=floating; model.run(action,at:point); model.useDragShelf=false; active=nil
    }
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation { if dragSequence != sender.draggingSequenceNumber { transition.reset(); dragSequence=sender.draggingSequenceNumber }; return draggingUpdated(sender) }
    override func draggingUpdated(_ sender:NSDraggingInfo)->NSDragOperation {
        active=selection(at:convert(sender.draggingLocation,from:nil))
        return active.map { enabled[$0] } == true && model?.busy == false ? .copy : []
    }
    override func draggingExited(_ sender:NSDraggingInfo?) { active=nil }
    override func prepareForDragOperation(_ sender:NSDraggingInfo)->Bool { selection(at:convert(sender.draggingLocation,from:nil)).map { enabled[$0] } == true && model?.busy == false }
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        guard let i=selection(at:convert(sender.draggingLocation,from:nil)), enabled[i],
              let urls=sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL], !urls.isEmpty else { active=nil; return false }
        apply(i,urls:urls,at:sender.draggingDestinationWindow?.convertPoint(toScreen:sender.draggingLocation)); return true
    }
    override func concludeDragOperation(_ sender:NSDraggingInfo?) { active=nil; transition.reset() }
    func paint() {
        guard let c=NSGraphicsContext.current?.cgContext else { return }
        let badge=NSBezierPath(roundedRect:WheelGeometry.badge,xRadius:WheelGeometry.badgeRadius,yRadius:WheelGeometry.badgeRadius)
        NSColor.white.withAlphaComponent(0.07).setFill(); badge.fill()
        NSColor.white.withAlphaComponent(0.13).setStroke(); badge.lineWidth=0.5; badge.stroke()
        let centerStyle=NSMutableParagraphStyle(); centerStyle.alignment = .center
        (sizeLabel as NSString).draw(in:NSRect(x:112,y:142,width:76,height:17),withAttributes:[.font:NSFont.systemFont(ofSize:11,weight:.semibold),.foregroundColor:NSColor.white,.paragraphStyle:centerStyle])
        for i in renderedChoices.indices {
            let path=paths[i]
            let selected=active == i && enabled[i]
            if selected {
                c.saveGState(); c.addPath(path); c.clip()
                selectionGradient.draw(in:path.boundingBoxOfPath,angle:0); c.restoreGState()
            } else {
                c.addPath(path); c.setFillColor(NSColor.black.withAlphaComponent(0.16).cgColor); c.fillPath()
            }
            let label=labelPoints[i]
            if let icon=(selected ? selectedIcons[i] : icons[i]) { icon.draw(in:NSRect(x:label.x-8,y:label.y-20,width:16,height:16),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
            (selected ? selectedLabels[i] : labels[i]).draw(in:NSRect(x:label.x-43,y:label.y+(renderMode != 0 ? 0 : -8),width:86,height:30))
        }
    }
}
@MainActor func resetWheelFeedback(_ view:NSView) {
    if let wheel=view as? NativeWheel { wheel.transition.reset(); wheel.active=nil }
    for child in view.subviews { resetWheelFeedback(child) }
}
final class WheelGlass: NSVisualEffectView {
    override func hitTest(_ point:NSPoint)->NSView? { nil }
}
@MainActor final class WheelCanvas: NSView {
    weak var owner:NativeWheel?
    override var isFlipped:Bool { true }
    override func hitTest(_ point:NSPoint)->NSView? { nil }
    override func draw(_ dirtyRect:NSRect) { owner?.paint() }
}
struct DragResult: NSViewRepresentable {
    let urls: [URL]
    var ended: (() -> Void)? = nil
    func makeNSView(context: Context) -> ResultDragView { let v = ResultDragView(); v.urls=urls; v.ended=ended; return v }
    func updateNSView(_ view: ResultDragView, context: Context) { view.urls=urls; view.ended=ended; view.setAccessibilityElement(true); view.setAccessibilityLabel("Drag converted files to a folder or another app"); view.setAccessibilityRole(.button); view.needsDisplay=true }
}
final class ResultDragView: NSView, NSDraggingSource {
    var urls: [URL] = []; var ended: (() -> Void)?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.12).setFill(); NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:12,yRadius:12).fill()
        guard let first=urls.first else { return }
        NSWorkspace.shared.icon(forFile:first.path).draw(in:NSRect(x:12,y:12,width:32,height:32))
        let title = urls.count == 1 ? first.lastPathComponent : "\(urls.count) converted files"
        (title as NSString).draw(in:NSRect(x:55,y:10,width:bounds.width-66,height:19),withAttributes:[.font:NSFont.systemFont(ofSize:12,weight:.semibold),.foregroundColor:NSColor.white])
        ("Drag to a folder or another app" as NSString).draw(at:NSPoint(x:55,y:31),withAttributes:[.font:NSFont.systemFont(ofSize:10),.foregroundColor:NSColor.lightGray])
    }
    override func mouseDown(with event: NSEvent) {
        guard !urls.isEmpty else { return }
        let items = urls.enumerated().map { i,url -> NSDraggingItem in
            let item=NSDraggingItem(pasteboardWriter:url as NSURL); item.setDraggingFrame(NSRect(x:12+i*5,y:10+i*5,width:40,height:40),contents:NSWorkspace.shared.icon(forFile:url.path)); return item
        }
        beginDraggingSession(with:items,event:event,source:self)
    }
    func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation { .copy }
    func ignoreModifierKeys(for session:NSDraggingSession)->Bool { true }
    func draggingSession(_ session:NSDraggingSession,endedAt screenPoint:NSPoint,operation:NSDragOperation) { if operation != [] { ended?() } }
}
func receive(_ providers: [NSItemProvider], _ model: Model, replace: Bool = false, _ completion: (() -> Void)? = nil) {
    let group = DispatchGroup(); let lock = NSLock(); var urls:[URL] = []
    for p in providers { group.enter(); p.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) { item,_ in defer { group.leave() }; var url:URL?; if let data = item as? Data { url = URL(dataRepresentation:data,relativeTo:nil) } else if let u = item as? URL { url = u }; if let u = url { lock.lock(); urls.append(u); lock.unlock() } } }
    group.notify(queue:.main) { Task { @MainActor in if replace { model.files = [] }; model.add(urls); completion?() } }
}
struct Workspace: View {
    @ObservedObject var model: Model
    @State var targeted = false
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:12) {
                Image(systemName:"circle.hexagongrid.fill").foregroundStyle(orange).font(.title2)
                VStack(alignment:.leading,spacing:3) { Text("Clementine").font(.system(size:17,weight:.semibold)); Text("A little less friction.").font(.system(size:11)).foregroundStyle(.secondary) }
                Spacer()
                Text("LOCAL BY DESIGN").font(.system(size:9,weight:.semibold)).tracking(1.5).foregroundStyle(.secondary)
                Button { model.choose() } label: { Label("Add files",systemImage:"plus") }.buttonStyle(.borderedProminent).tint(orange).foregroundStyle(.black)
            }.padding(24)
            Divider().opacity(0.4)
            HStack(spacing:0) {
                VStack(spacing:12) {
                    HStack(spacing:4) { ForEach(0..<3) { i in Button { model.mode = i } label: { Text(["⇧  Convert","⌘  Tools","⌃  Actions"][i]).font(.system(size:12,weight:.medium)).padding(.horizontal,16).padding(.vertical,9).background(RoundedRectangle(cornerRadius:9).fill(model.mode == i ? Color.white.opacity(0.13) : .clear)) }.buttonStyle(.plain) } }.padding(5).background(RoundedRectangle(cornerRadius:14).fill(Color.black.opacity(0.2)))
                    Wheel(model:model).frame(width:300,height:300)
                    Text(model.files.isEmpty ? "Drop something. Make it something else." : model.first?.lastPathComponent ?? "").font(.system(size:14,weight:.medium)).lineLimit(1)
                    Text("Drop onto a format to convert instantly").font(.system(size:11)).foregroundStyle(.secondary)
                    Menu("More tools") {
                        ForEach(model.kind == "image" ? ["Rotate","Make PDF","Strip metadata","ZIP","Reveal"] : model.kind == "pdf" ? ["Merge PDF","Extract text","Pages to PNG","Rotate PDF","ZIP","Reveal"] : ["ZIP","Reveal"],id:\.self) { action in Button(action) { model.run(action) } }
                    }.frame(width:140)
                    Button("Browse files…") { model.choose() }.buttonStyle(.plain).foregroundStyle(orange).padding(.top,4)
                    Spacer(minLength:10)
                }.padding(24).frame(width:445)
                Rectangle().fill(Color.white.opacity(0.07)).frame(width:1)
                VStack(alignment:.leading,spacing:16) {
                    HStack { Text("YOUR FILES").font(.system(size:10,weight:.bold)).tracking(1.6); Spacer(); Text("\(model.files.count)").foregroundStyle(.secondary); if !model.files.isEmpty { Button("Clear") { model.files=[] }.buttonStyle(.plain).foregroundStyle(.secondary) } }
                    if model.files.isEmpty {
                        VStack(spacing:14) { Image(systemName:"square.stack.3d.up").font(.system(size:35,weight:.ultraLight)).foregroundStyle(orange.opacity(0.8)); Text("Ready when you are").font(.system(size:15,weight:.medium)); Text("Images, PDFs, video, audio\nand text documents.").multilineTextAlignment(.center).font(.system(size:12)).foregroundStyle(.secondary) }.frame(maxWidth:.infinity).frame(height:180).background(RoundedRectangle(cornerRadius:16).strokeBorder(style:StrokeStyle(lineWidth:1,dash:[5])).foregroundStyle(Color.white.opacity(0.15)))
                    } else {
                        ScrollView { VStack(spacing:8) { ForEach(model.files,id:\.self) { u in HStack(spacing:10) { Image(nsImage:NSWorkspace.shared.icon(forFile:u.path)).resizable().frame(width:30,height:30); VStack(alignment:.leading,spacing:3) { Text(u.lastPathComponent).font(.system(size:12,weight:.medium)).lineLimit(1); Text(u.pathExtension.uppercased()).font(.system(size:9)).foregroundStyle(.secondary) }; Spacer(); Button { model.files.removeAll { $0 == u } } label: { Image(systemName:"xmark").font(.system(size:9)) }.buttonStyle(.plain) }.padding(10).background(RoundedRectangle(cornerRadius:10).fill(Color.white.opacity(0.04))) } } }.frame(maxHeight:150)
                        if model.kind == "image",let u=model.first { WorkspaceThumbnail(url:u) }
                        if model.kind == "document" { TextEditor(text:$model.text).font(.system(size:11,design:.monospaced)).frame(height:110).clipShape(RoundedRectangle(cornerRadius:8)); Text("Save text applies to plain-text files.").font(.caption2).foregroundStyle(.secondary) }
                    }
                    if model.kind == "image" {
                        HStack { Text("Resize width"); Spacer(); TextField("1600",text:$model.width).frame(width:65); Text("px").foregroundStyle(.secondary) }.font(.system(size:12))
                        HStack { Text("Quality"); Spacer(); Text("\(Int(model.quality*100))%").foregroundStyle(.secondary) }.font(.system(size:12))
                        Slider(value:$model.quality,in:0.1...1).tint(orange)
                    }
                    if model.kind == "video" || model.kind == "audio" { HStack { Text("Trim (seconds)"); TextField("Start",text:$model.start); Text("–"); TextField("End",text:$model.end) }.font(.caption) }
                    Divider()
                    HStack { VStack(alignment:.leading,spacing:4) { Text("DESTINATION").font(.system(size:9,weight:.bold)).tracking(1); Text(model.output?.lastPathComponent ?? "Drag the result wherever you want").font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); Button { model.destination() } label: { Image(systemName:"folder") }.buttonStyle(.plain) }
                    if model.output != nil { Button("Choose by dragging instead") { model.output=nil }.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(orange) }
                    Text("Drop onto a format, then drag the result beside the original or into any folder. Originals stay untouched.").font(.system(size:10)).foregroundStyle(.secondary)
                    Spacer(minLength:0)
                }.padding(24).frame(width:320)
            }.padding(.top,20)
            Divider().opacity(0.4)
            HStack(spacing:8) { if model.busy { ProgressView().controlSize(.small) } else { Circle().fill(orange).frame(width:5,height:5) }; Text(model.status).font(.system(size:11)).foregroundStyle(.secondary); Spacer(); Text("⇧ while dragging opens the wheel").font(.system(size:10)).foregroundStyle(.tertiary) }.padding(16)
            if !model.ready.isEmpty { DragResult(urls:model.ready).frame(height:58).padding(.horizontal,16) }
            if !model.history.isEmpty { ScrollView { VStack(alignment:.leading,spacing:10) { ForEach(model.history) { job in HStack { Image(systemName:job.url == nil ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle(job.url == nil ? .red : .green); VStack(alignment:.leading) { Text(job.name).font(.caption.bold()); Text(job.result).font(.caption).foregroundStyle(.secondary) }; Spacer(); if let url = job.url { Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([url]) } } } } }.padding(16) }.frame(height:110) }
        }.frame(width:790).background(Glass().overlay(Color.black.opacity(0.18))).preferredColorScheme(.dark)
        .overlay(RoundedRectangle(cornerRadius:18).stroke(targeted ? orange : .clear,lineWidth:2))
        .onDrop(of:[UTType.fileURL],isTargeted:$targeted) { receive($0,model); return true }
    }
}
struct ResultShelf: View {
    @ObservedObject var model: Model
    let close: () -> Void
    var body: some View {
        HStack(spacing:8) { DragResult(urls:model.ready,ended:close).frame(height:58); Button(action:close) { Image(systemName:"xmark") }.buttonStyle(.plain) }
            .padding(12).frame(width:330).background(Glass().clipShape(RoundedRectangle(cornerRadius:18))).preferredColorScheme(.dark)
    }
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var editorWindow:NSWindow?
    var settingsWindow:NSWindow?
    var readiness:NSMenuItem!
    let model = Model(); var window:NSWindow!; var panel:NSPanel!; var statusItem:NSStatusItem!; var timer:Timer?; var lastDrag = -1; var wasDragging=false; var autoWheel = false; var suppressedDrag = -1; var resultPanel: NSPanel!; var idleDragCount = NSPasteboard(name:.drag).changeCount
    func applicationDidFinishLaunching(_ notification:Notification) {
        model.editorRequested = { [weak self] action,files,kind,shelf,folder in self?.presentEditor(action,files,kind,shelf,folder) }
        OptionFeedback.prepare()
        _ = WheelGeometry.cachedPaths
        panel = NSPanel(contentRect:NSRect(x:0,y:0,width:400,height:425),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.acceptsMouseMovedEvents=true; panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.hasShadow = false
        panel.setContentSize(NSSize(width:300,height:300))
        panel.contentView = NSHostingView(rootView:Wheel(model:model,floating:true).preferredColorScheme(.dark))
        resultPanel = NSPanel(contentRect:NSRect(x:0,y:0,width:330,height:82),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        resultPanel.isOpaque=false; resultPanel.backgroundColor = .clear; resultPanel.level = .floating
        resultPanel.contentView = NSHostingView(rootView:ResultShelf(model:model,close:{ self.resultPanel.orderOut(nil) }))
        model.actionStarted = { [weak self] in guard let self else { return }; self.suppressedDrag = self.lastDrag; self.autoWheel=false; self.panel.orderOut(nil) }
        model.conversionFinished = { [weak self] urls in guard let self, !urls.isEmpty else { return }; let point=NSEvent.mouseLocation; let screen=NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame ?? NSScreen.main!.visibleFrame
            self.resultPanel.setFrameOrigin(NSPoint(x:max(screen.minX,min(point.x-165,screen.maxX-330)),y:max(screen.minY,min(point.y-90,screen.maxY-82)))); self.resultPanel.orderFrontRegardless() }
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength); statusItem.button?.image = NSImage(systemSymbolName:"circle.hexagongrid",accessibilityDescription:"Clementine")
        let menu=NSMenu(); menu.autoenablesItems=false; menu.delegate=self
        func entry(_ title:String,_ action:Selector?,_ key:String="",_ symbol:String?=nil)->NSMenuItem {
            let item=NSMenuItem(title:title,action:action,keyEquivalent:key); item.target=self; item.isEnabled=action != nil
            if let symbol { item.image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil) }; menu.addItem(item); return item
        }
        readiness=entry("Clementine is ready",nil,"","checkmark.circle")
        _=entry("⇧: Convert · ⌘: Tools · ⌃: Actions",nil)
        _=entry("Local processing · No usage limit",nil)
        menu.addItem(.separator())
        _=entry("Settings…",#selector(settings),",","gearshape")
        _=entry("Open Workspace…",#selector(show),"","macwindow")
        _=entry("Getting Started…",#selector(gettingStarted),"","sparkles")
        _=entry("About Clementine",#selector(about))
        menu.addItem(.separator())
        _=entry("Quit Clementine",#selector(quit),"q")
        statusItem.menu=menu
        timer = Timer.scheduledTimer(withTimeInterval:0.04,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
        timer?.tolerance=0.008
        RunLoop.main.add(timer!, forMode:.common)
        if CommandLine.arguments.contains("--preview-wheel") { showWheel() }
        let appMenu=NSMenu(); let root=NSMenuItem(); appMenu.addItem(root); let sub=NSMenu(); sub.addItem(withTitle:"Quit Clementine",action:#selector(quit),keyEquivalent:"q").target=self; root.submenu=sub; NSApp.mainMenu=appMenu
        if CommandLine.arguments.contains("--verify-startup") {
            precondition(NSApp.activationPolicy() == .accessory)
            precondition(window == nil && statusItem.isVisible)
            precondition(OptionFeedback.soundID != 0, "Tap sound failed to preload")
            print("PASS accessory startup: no Dock activation, workspace hidden, menu item present")
            fflush(stdout)
        }
        if CommandLine.arguments.contains("--preview-workspace") { show() }
        if CommandLine.arguments.contains("--preview-menu") { DispatchQueue.main.async { self.statusItem.menu?.popUp(positioning:nil,at:NSPoint(x:0,y:0),in:self.statusItem.button) } }
    }
    func menuWillOpen(_ menu:NSMenu) { readiness.title = model.busy ? "Clementine is processing…" : model.wheelEnabled ? "Clementine is ready" : "Clementine is paused" }
    @objc func settings() {
        if settingsWindow == nil {
            let w=NSWindow(contentRect:NSRect(x:0,y:0,width:432,height:528),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            w.title="Clementine Settings"; w.appearance=NSAppearance(named:.darkAqua); w.isReleasedWhenClosed=false
            w.contentView=NSHostingView(rootView:SettingsView(model:model)); w.center(); settingsWindow=w
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc func gettingStarted() {
        let a=NSAlert(); a.messageText="Getting Started"
        a.informativeText="Drag a file and hold Shift for conversions, Command for tools, or Control for actions. Release the key to hide the wheel. Drop onto an option, then drag the result to its destination.\n\nDimmed options are not available yet. Crop opens an adjustable preview. Metadata shows properties and can remove image metadata.\n\nClementine stays in the menu bar. Open Workspace for more tools and conversion settings."
        NSApp.activate(ignoringOtherApps:true); a.runModal()
    }
    @objc func about() {
        let a=NSAlert(); a.messageText="Clementine 0.5"; a.informativeText="Local file conversion and editing.\nAn independent macOS utility.\n\nNo account, uploads or usage limit. Some reference options are shown dimmed until implemented."
        NSApp.activate(ignoringOtherApps:true); a.runModal()
    }
    @objc func show() {
        if window == nil {
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:790,height:650),styleMask:[.titled,.closable,.miniaturizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.acceptsMouseMovedEvents=true; window.title = "Clementine"; window.titlebarAppearsTransparent = true; window.isOpaque = false; window.backgroundColor = .clear; window.contentView = NSHostingView(rootView:ScrollView { Workspace(model:model) }.frame(width:790,height:min(700,(NSScreen.main?.visibleFrame.height ?? 800)-80))); window.center(); window.isReleasedWhenClosed = false
        }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc func showWheel() {
        let p = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(p) }?.visibleFrame ?? NSScreen.main!.visibleFrame
        panel.setFrameOrigin(NSPoint(x:max(screen.minX,min(p.x-150,screen.maxX-300)),y:max(screen.minY,min(p.y-150,screen.maxY-300))))
        if let host=panel.contentView { resetWheelFeedback(host) }
        panel.orderFrontRegardless()
    }
    func poll() {
        guard editorWindow?.isVisible != true, model.wheelEnabled else { if autoWheel { panel.orderOut(nil); autoWheel=false }; return }
        let flags = NSEvent.modifierFlags.intersection([.shift,.command,.control])
        let dragging = NSEvent.pressedMouseButtons & 1 != 0
        defer { wasDragging=dragging }
        if !shouldShowWheel(dragging:dragging, hasKey:!flags.isEmpty) {
            if autoWheel { panel.orderOut(nil); autoWheel=false }
            if !dragging && wasDragging { suppressedDrag = -1; model.useDragShelf = false; idleDragCount = NSPasteboard(name:.drag).changeCount }
            return
        }
        let pasteboard = NSPasteboard(name:.drag)
        let count=pasteboard.changeCount
        guard count != suppressedDrag,count != idleDragCount else { return }
        if lastDrag != count {
            guard let urls=pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],!urls.isEmpty else { return }
            model.add(urls,replace:true); lastDrag=count
        }
        model.useDragShelf = true
        let mode=flags.contains(.control) ? 2 : flags.contains(.command) ? 1 : 0
        if model.mode != mode { model.mode=mode }
        if !autoWheel { autoWheel=true; showWheel() }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func application(_ sender:NSApplication,openFiles filenames:[String]) { model.add(filenames.map { URL(fileURLWithPath:$0) }); show() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
}
if CommandLine.arguments.contains("--benchmark-wheel") {
    _ = WheelGeometry.cachedPaths
    for cached in [false,true] {
        let start=CFAbsoluteTimeGetCurrent(); var hits=0
        for n in 0..<20000 {
            let i=n % 9; let point=WheelGeometry.labelPoint(index:i,count:9)
            let path=cached ? WheelGeometry.path(index:i,count:9) : WheelGeometry.makePath(index:i,count:9)
            if path.contains(point) { hits += 1 }
        }
        precondition(hits == 20000)
        print("\(cached ? "Cached" : "Rebuilt") geometry: \(CFAbsoluteTimeGetCurrent()-start)s, \(hits) hits")
    }
} else if CommandLine.arguments.contains("--self-test") {
    let root = URL(fileURLWithPath:CommandLine.arguments.last!); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let context = CGContext(data:nil,width:100,height:60,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.orange.cgColor); context.fill(CGRect(x:0,y:0,width:100,height:60)); let source = root.appendingPathComponent("sample.png"); try writeImage(context.makeImage()!,source,.png,1)
    Task { do {
        var feedback=OptionTransition()
        precondition(feedback.enter(0,enabled:true))
        precondition(!feedback.enter(nil,enabled:true))
        precondition(!feedback.enter(0,enabled:true))
        precondition(feedback.enter(1,enabled:true))
        precondition(!feedback.enter(1,enabled:true))
        precondition(!feedback.enter(2,enabled:false))
        precondition(!feedback.enter(nil,enabled:true))
        precondition(feedback.enter(3,enabled:true))
        feedback.reset(); precondition(feedback.enter(0,enabled:true))
        print("PASS option feedback: first entry and changes, silent exit/same/disabled")
        await MainActor.run {
            let model=Model()
            for ext in ["heic","png","pdf"] {
                model.files=[URL(fileURLWithPath:"/tmp/example." + ext)]
                for mode in 0...2 {
                    model.mode=mode
                    for item in model.choices { precondition(wheelSymbol(item.1) != nil, "Missing symbol: " + item.1) }
                }
            }
            model.files=[URL(fileURLWithPath:"/tmp/example.pdf")]; model.mode=0
            precondition(["PAGES","DOCX","PNG"].allSatisfy { model.choices.map(\.0).contains($0) && model.available($0) })
            model.mode=2; precondition(model.choices.map { $0.0 } == ["AirDrop","Float","Copy","Move","Copy path","Terminal"])
            print("PASS reference menu labels, symbols, unavailable states")
        }
        for count in [4,6,8,9] {
            for i in 0..<count {
                let p=WheelGeometry.labelPoint(index:i,count:count)
                precondition(WheelGeometry.selection(at:p,count:count) == i)
                for delta in [-8.0,0,8.0] { precondition(WheelGeometry.selection(at:CGPoint(x:p.x+delta,y:p.y),count:count) == i) }
            }
            precondition(WheelGeometry.selection(at:CGPoint(x:150,y:150),count:count) == nil)
            precondition(WheelGeometry.selection(at:CGPoint(x:0,y:0),count:count) == nil)
            let a = -Double.pi/2 + Double.pi/Double(count)
            precondition(WheelGeometry.selection(at:CGPoint(x:150+96*cos(a),y:150+96*sin(a)),count:count) == nil)
        }
        print("PASS every wedge hit target, centers and gaps (4/6/9 wedges)")
        for (drag,key,expected) in [(true,true,true),(true,false,false),(true,true,true),(false,true,false),(false,false,false),(true,true,true)] {
            precondition(shouldShowWheel(dragging:drag,hasKey:key) == expected)
        }; print("PASS wheel show/release/reopen/end")
        precondition(shouldStageOutput(floating:false,explicitFolder:nil))
        precondition(shouldStageOutput(floating:true,explicitFolder:root))
        precondition(!shouldStageOutput(floating:false,explicitFolder:root))
        print("PASS drag destination default and explicit-folder override")
        let neighbor = try outputURL(source,nil,"jpg")
        precondition(neighbor.deletingLastPathComponent() == source.deletingLastPathComponent()); print("PASS beside-original destination")
        for action in ["JPEG","HEIC","TIFF","BMP","Resize","Rotate","Square crop","PDF","ZIP"] { let out = try await process(source,action,root,40,0.8,0,1,""); guard FileManager.default.fileExists(atPath:out.path) else { fatalError("Missing output") }; if action == "Resize" || action == "Rotate" || action == "Square crop" { let s = CGImageSourceCreateWithURL(out as CFURL,nil)!; let im = CGImageSourceCreateImageAtIndex(s,0,nil)!; let expected = action == "Resize" ? (40,24) : action == "Rotate" ? (60,100) : (60,60); guard im.width == expected.0 && im.height == expected.1 else { fatalError("Wrong dimensions") } }; print("PASS \(action)") }
        let pdf = root.appendingPathComponent("sample-converted.pdf")
        for action in ["PNG","TXT","Split pages","Rotate PDF"] { _ = try await process(pdf,action,root,40,0.8,0,1,""); print("PASS PDF \(action)") }
        let txt = root.appendingPathComponent("hello.txt"); try "Hello Clementine".write(to:txt,atomically:true,encoding:.utf8)
        _ = try await process(txt,"RTF",root,40,0.8,0,1,""); print("PASS text conversion"); exit(0)
    } catch { print("FAIL \(error)"); exit(1) } }; RunLoop.main.run()
} else { MainActor.assumeIsolated { let app = NSApplication.shared; let delegate = Delegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run() } }

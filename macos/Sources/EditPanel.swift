import AVKit
import Cocoa
import ImageIO
import PDFKit
import SwiftUI

@MainActor final class EditSession: ObservableObject {
  let action: String
  let files: [URL]
  let kind: String
  @Published var o = EditOptions()
  var initial = EditOptions()
  var size = CGSize(width: 1, height: 1)
  var thumbnail: CGImage?
  @Published var preview: CGImage?
  @Published var error = ""
  @Published var tool = "Arrow"
  @Published var annotationText = "Text"
  @Published var ink = NSColor.systemRed
  var overlayImage: CGImage?
  @Published var undoMarks: [[Mark]] = []
  @Published var original = false
  @Published var zoom = 1.0
  var pageCount = 0
  var player: AVPlayer?
  var duration = 0.0
  var previewTask: Task<Void, Never>?
  var batch: Bool { files.count > 1 }
  init(_ action: String, _ files: [URL], kind: String) throws {
    self.action = action
    self.files = files
    self.kind = kind
    guard let first = files.first else { throw Failure.message("Select a file first") }
    if files.dropFirst().contains(where: { url in
      let type = inputType(url)
      switch kind {
      case "image": return type?.conforms(to: .image) != true
      case "pdf": return url.pathExtension.lowercased() != "pdf"
      case "audio": return type?.conforms(to: .audio) != true
      case "video": return type?.conforms(to: .movie) != true
      default: return false
      }
    }) {
      throw Failure.message("Choose files of the same type for this editor.")
    }
    if kind == "image" {
      let image = try EditEngine.image(first, maxSize: 820)
      thumbnail = image
      preview = image
      guard let source = CGImageSourceCreateWithURL(first as CFURL, nil) else {
        throw Failure.message("Cannot read image dimensions")
      }
      let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
      let svgSize=first.pathExtension.lowercased()=="svg" ? NSImage(contentsOf:first)?.size : nil
      let width = p[kCGImagePropertyPixelWidth as String] as? Int ?? svgSize.map {Int($0.width)} ?? image.width
      let height = p[kCGImagePropertyPixelHeight as String] as? Int ?? svgSize.map {Int($0.height)} ?? image.height
      let rotated = (p[kCGImagePropertyOrientation as String] as? Int ?? 1) > 4
      size = CGSize(width: rotated ? height : width, height: rotated ? width : height)
      o.width = Int(size.width)
      o.height = Int(size.height)
      o.scaleMode = action == "Resize"
      if action == "Rotate" { o.rotation = 90 }
      if action == "Compress" {
        o.format = "JPEG"
        o.quality = 0.75
      }
    } else if kind == "pdf" {
      guard let doc = PDFDocument(url: first), !doc.isLocked, doc.pageCount > 0 else {
        throw Failure.message("Cannot open this PDF")
      }
      pageCount = doc.pageCount
      o.rotation = action == "Rotate PDF" ? 90 : 0
      let attrs = doc.documentAttributes ?? [:]
      o.title = attrs[PDFDocumentAttribute.titleAttribute] as? String ?? ""
      o.author = attrs[PDFDocumentAttribute.authorAttribute] as? String ?? ""
      o.subject = attrs[PDFDocumentAttribute.subjectAttribute] as? String ?? ""
      preview = doc.page(at: 0)?.thumbnail(of: NSSize(width: 380, height: 240), for: .mediaBox)
        .cgImage(forProposedRect: nil, context: nil, hints: nil)
    } else if ["video", "audio"].contains(kind) {
      let asset = AVURLAsset(url: first)
      duration = asset.duration.seconds
      guard duration.isFinite, duration > 0 else {
        throw Failure.message("Cannot read the media duration")
      }
      o.end = duration
      player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
    } else if action == "Save text" {
      guard files.count == 1 else { throw Failure.message("Select one text file to edit") }
      o.text = try String(contentsOf: first, encoding: .utf8)
    }
    initial = o
  }
  var normalRatio: Double? {
    let parts = o.ratio.split(separator: ":").compactMap { Double($0) }
    return parts.count == 2 ? parts[0] / parts[1] * size.height / size.width : nil
  }
  func cropRatio(_ new: String) {
    o.ratio = new
    guard let ratio = normalRatio else { return }
    let w = min(1, ratio)
    let h = w / ratio
    o.crop = CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
  }
  func setCropPixels(_ value: Int, width: Bool) {
    var r = o.crop
    if width {
      r.size.width = min(1, max(1, Double(value)) / size.width)
      if let ratio = normalRatio { r.size.height = r.width / ratio }
    } else {
      r.size.height = min(1, max(1, Double(value)) / size.height)
      if let ratio = normalRatio { r.size.width = r.height * ratio }
    }
    let k = min(1, 1 / r.width, 1 / r.height)
    r.size.width *= k
    r.size.height *= k
    r.origin.x = min(r.minX, 1 - r.width)
    r.origin.y = min(r.minY, 1 - r.height)
    o.crop = r
  }
  func rememberMarks() {
    undoMarks.append(o.marks)
    if undoMarks.count > 40 { undoMarks.removeFirst() }
  }
  func reset() {
    previewTask?.cancel()
    o = initial
    preview = thumbnail ?? preview
    original = false
    zoom = 1
    undoMarks = []
    error = ""
    if ["Rotate", "Compress", "JPEG", "HEIC", "Add BG"].contains(action) { updatePreview() }
  }
  func updatePreview() {
    previewTask?.cancel()
    guard let image = thumbnail else { return }
    let options = o
    let action = action
    let scale = Double(image.width) / size.width
    previewTask = Task {
      try? await Task.sleep(nanoseconds: 25_000_000)
      guard !Task.isCancelled else { return }
      let result = await Task.detached(priority: .userInitiated) { () -> CGImage? in
        if action == "Rotate" {
          var current = image
          for _ in 0..<(options.rotation / 90) {
            guard let next = try? render(current, current.height, current.width, true) else {
              return nil
            }
            current = next
          }
          return current
        }
        if ["Compress", "JPEG", "HEIC"].contains(action) {
          let type: UTType =
            (action == "HEIC" || (action == "Compress" && options.format == "HEIC")) ? .heic : .jpeg
          let data = NSMutableData()
          guard
            let dst = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)
          else { return nil }
          CGImageDestinationAddImage(
            dst, image,
            [kCGImageDestinationLossyCompressionQuality: options.quality] as CFDictionary)
          guard CGImageDestinationFinalize(dst), let src = CGImageSourceCreateWithData(data, nil)
          else { return nil }
          return CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        if action == "Add BG" {
          var small = options
          small.padding *= scale
          return try? EditEngine.composite(image, small, background: true)
        }
        return try? EditEngine.adjusted(image, options)
      }.value
      if !Task.isCancelled, let result { preview = result }
    }
  }
}

struct EditPanel: View {
  @ObservedObject var s: EditSession
  let apply: () -> Void
  let cancel: () -> Void
  var title: String {
    [
      "Resize": "Resize Images", "Crop": "Crop Image", "Edit": "Edit Photo",
      "Annotate": "Annotate Photo", "Add BG": "Add Background", "Redact": "Redact Image",
      "Save text": "Edit Text",
    ][s.action] ?? s.action
  }
  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        Text(title).font(.system(size: 16, weight: .semibold))
        HStack {
          Button(action: cancel) {
            Image(systemName: "xmark").frame(width: 22, height: 22).background(
              Circle().fill(.white.opacity(0.09)))
          }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
          Spacer()
        }
      }.padding(.horizontal, 14).frame(height: 46)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if s.batch {
            Text("\(s.files.count) files · preview of \(s.files[0].lastPathComponent)").font(
              .caption
            ).foregroundStyle(.secondary)
          }
          if s.kind == "image" {
            imageControls
          } else if s.kind == "pdf" {
            pdfControls
          } else if let player = s.player {
            mediaControls(player)
          } else {
            TextEditor(text: $s.o.text).font(.system(.body, design: .monospaced)).frame(
              minHeight: 280)
          }
          if !s.error.isEmpty { Text(s.error).foregroundStyle(.orange).textSelection(.enabled) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
      }
      Divider()
      HStack {
        Button("Reset") { s.reset() }
        Spacer()
        Button(s.action == "Resize" ? "Resize" : "Apply", action: apply).keyboardShortcut(
          .defaultAction
        ).buttonStyle(.borderedProminent).tint(.orange)
          .disabled(
            (["Annotate", "Redact"].contains(s.action) && s.o.marks.isEmpty)
              || (s.action == "Resize" && !s.batch && resultDimensions == s.size))
      }.padding(16)
    }.background(Glass()).ignoresSafeArea(.container, edges: .top).preferredColorScheme(.dark).tint(
      Color(red: 0.99, green: 0.32, blue: 0.04))
  }
  var resultDimensions: CGSize {
    let factor = s.o.scaleMode ? s.o.scale / 100 : Double(s.o.width) / s.size.width
    let width = s.o.scaleMode ? s.size.width * factor : Double(s.o.width)
    let height = s.o.scaleMode || s.o.locked ? s.size.height * factor : Double(s.o.height)
    return CGSize(width: width.rounded(), height: height.rounded())
  }
  func preview(_ height: CGFloat) -> some View {
    ZStack {
      Color.black.opacity(0.7)
      if let image = (s.original ? s.thumbnail : s.preview) {
        Image(decorative: image, scale: 1).resizable().scaledToFit().scaleEffect(s.zoom)
      }
    }.frame(maxWidth: .infinity).frame(height: height).clipShape(RoundedRectangle(cornerRadius: 10))
  }
  @ViewBuilder var imageControls: some View {
    switch s.action {
    case "Resize":
      Picker("Resize by", selection: $s.o.scaleMode) {
        Text("Pixels").tag(false)
        Text("Scale").tag(true)
      }.pickerStyle(.segmented).labelsHidden()
      if s.o.scaleMode {
        HStack {
          Slider(value: $s.o.scale, in: 1...400, step: 1)
          Stepper("\(Int(s.o.scale))%", value: $s.o.scale, in: 1...400, step: 1).fixedSize()
        }
      } else {
        HStack {
          Text("W")
          TextField(
            "Width",
            value: Binding(
              get: { s.o.width },
              set: {
                s.o.width = max(1, min(32000, $0))
                if s.o.locked { s.o.height = Int(resultDimensions.height) }
              }), format: .number.grouping(.never))
          Text("H")
          TextField(
            "Height",
            value: Binding(
              get: { Int(resultDimensions.height) },
              set: {
                s.o.height = max(1, min(32000, $0))
                if s.o.locked {
                  s.o.width = max(
                    1, Int((Double(s.o.height) * s.size.width / s.size.height).rounded()))
                }
              }), format: .number.grouping(.never))
          Text("px")
          Button {
            s.o.locked.toggle()
          } label: {
            Image(systemName: s.o.locked ? "lock.fill" : "lock.open")
          }.help("Lock aspect ratio")
        }
      }
      if let image = s.thumbnail {
        Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxWidth: .infinity)
          .frame(height: 112)
      }
      HStack {
        Spacer()
        Text("\(Int(s.size.width)) × \(Int(s.size.height))  →")
        Text("\(Int(resultDimensions.width)) × \(Int(resultDimensions.height))").foregroundStyle(
          .orange)
        Spacer()
      }.font(.caption)
    case "Crop":
      InteractivePreview(session: s).frame(height: canvasHeight)
      Picker("Aspect ratio", selection: Binding(get: { s.o.ratio }, set: s.cropRatio)) {
        ForEach(["Free", "1:1", "16:9", "9:16", "4:3", "3:4"], id: \.self) { Text($0) }
      }.pickerStyle(.segmented)
      HStack {
        Text("W")
        TextField(
          "Crop width",
          value: Binding(
            get: { Int((s.o.crop.width * s.size.width).rounded()) },
            set: { s.setCropPixels($0, width: true) }), format: .number.grouping(.never)
        ).frame(width: 75)
        Text("H")
        TextField(
          "Crop height",
          value: Binding(
            get: { Int((s.o.crop.height * s.size.height).rounded()) },
            set: { s.setCropPixels($0, width: false) }), format: .number.grouping(.never)
        ).frame(width: 75)
        Text("px")
      }
    case "Edit":
      ZStack(alignment: .top) {
        preview(230)
        HStack {
          Button {
            s.zoom = max(1, s.zoom - 0.25)
          } label: {
            Image(systemName: "minus.magnifyingglass")
          }
          Text("\(Int(s.zoom*100))%")
          Button {
            s.zoom = min(4, s.zoom + 0.25)
          } label: {
            Image(systemName: "plus.magnifyingglass")
          }
          Spacer()
          Button("Reset") { s.reset() }
          Button(s.original ? "Edited" : "Original") { s.original.toggle() }
        }.controlSize(.small).padding(8)
      }
      ForEach(["Light", "Color", "Detail"], id: \.self) { section in
        Text(section).font(.headline)
        ForEach(PhotoAdjustment.all.filter { $0.section == section }) { a in adjustment(a) }
      }
    case "Annotate", "Redact":
      InteractivePreview(session: s).frame(height: canvasHeight).background(
        Color.black.opacity(0.7)
      ).clipShape(RoundedRectangle(cornerRadius: 10))
      if s.action == "Annotate" {
        annotationToolbar
      } else {
        Text("Drag a rectangle over each area to cover it in the exported copy.").font(.caption)
      }
      HStack {
        if ["Draw", "Highlight"].contains(s.tool) {
          Button("Clear Drawing") {
            s.rememberMarks()
            s.o.marks.removeAll { ["Draw", "Highlight"].contains($0.tool) }
          }
        }
        Spacer()
        Button {
          if let previous = s.undoMarks.popLast() { s.o.marks = previous }
        } label: {
          Image(systemName: "arrow.uturn.backward")
        }.disabled(s.undoMarks.isEmpty).help("Undo")
        Button {
          s.rememberMarks()
          _ = s.o.marks.popLast()
        } label: {
          Image(systemName: "trash")
        }.disabled(s.o.marks.isEmpty).help("Remove last annotation")
      }
    case "Rotate":
      preview(205).onChange(of: s.o.rotation) { _ in s.updatePreview() }
      Picker("Rotate", selection: $s.o.rotation) {
        ForEach([90, 180, 270], id: \.self) { Text("\($0)°") }
      }.pickerStyle(.segmented)
    case "Add BG":
      preview(235)
      ColorPicker(
        "Background",
        selection: Binding(
          get: { Color(nsColor: s.o.background) },
          set: {
            s.o.background = NSColor($0)
            s.updatePreview()
          }), supportsOpacity: false)
      HStack {
        Text("Padding")
        Slider(
          value: Binding(
            get: { s.o.padding },
            set: {
              s.o.padding = $0
              s.updatePreview()
            }), in: 0...400, step: 1)
        Text("\(Int(s.o.padding)) px")
      }
    default:
      preview(180).onChange(of: s.o.quality) { _ in s.updatePreview() }.onChange(of: s.o.format) {
        _ in s.updatePreview()
      }
      if s.action == "Compress" {
        Picker("Format", selection: $s.o.format) {
          Text("JPEG").tag("JPEG")
          Text("HEIC").tag("HEIC")
        }
      }
      quality
    }
  }
  var canvasHeight: CGFloat {
    min(400, max(175, (NSScreen.main?.visibleFrame.height ?? 800) - 340))
  }
  func adjustment(_ a: PhotoAdjustment) -> some View {
    let binding = Binding<Double>(
      get: { s.o.values[a.name] ?? 0 },
      set: {
        s.o.values[a.name] = $0
        s.original = false
        s.updatePreview()
      })
    return HStack {
      Text(a.name).frame(width: 91, alignment: .leading)
      Slider(value: binding, in: a.range)
      Text(
        a.name == "Exposure"
          ? String(format: "%+.2f EV", binding.wrappedValue)
          : String(format: "%+.0f", binding.wrappedValue * (a.name == "Hue" ? 1 : 100))
      ).monospacedDigit().frame(width: 61, alignment: .trailing)
      Button {
        binding.wrappedValue = 0
      } label: {
        Image(systemName: "arrow.counterclockwise")
      }.buttonStyle(.plain).disabled(binding.wrappedValue == 0)
    }.font(.caption)
  }
  let tools = [
    ("Arrow", "arrow.up.left"), ("Draw", "scribble"), ("Text", "textformat"),
    ("Rectangle", "rectangle"), ("Circle", "circle"), ("Highlight", "highlighter"),
    ("Number", "1.circle"), ("Magnify", "plus.magnifyingglass"), ("Image", "photo.badge.plus"),
  ]
  var annotationToolbar: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 4) {
        ForEach(tools, id: \.0) { item in
          Button {
            if item.0 == "Image" {
              let p = NSOpenPanel()
              p.allowedContentTypes = [.image]
              guard p.runModal() == .OK, let url = p.url, let image = try? EditEngine.image(url)
              else { return }
              s.overlayImage = image
            }
            s.tool = item.0
          } label: {
            Image(systemName: item.1).frame(maxWidth: .infinity).frame(height: 27).background(
              RoundedRectangle(cornerRadius: 5).fill(
                s.tool == item.0 ? Color.orange : .white.opacity(0.08)))
          }
          .buttonStyle(.plain).help(item.0).accessibilityLabel(item.0)
        }
      }
      HStack {
        ColorPicker(
          "Stroke",
          selection: Binding(get: { Color(nsColor: s.ink) }, set: { s.ink = NSColor($0) }),
          supportsOpacity: false
        ).labelsHidden()
        if s.tool == "Text" { TextField("Annotation text", text: $s.annotationText) }
        Text(
          [
            "Arrow": "Drag from the tail toward the arrowhead.", "Draw": "Drag to draw.",
            "Text": "Click to place your text.", "Number": "Click to place a numbered marker.",
          ][s.tool] ?? "Drag on the photo to place the annotation."
        ).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  var quality: some View {
    HStack {
      Text("Quality")
      Slider(value: $s.o.quality, in: 0.05...1, step: 0.01)
      Text("\(Int((s.o.quality*100).rounded()))%").monospacedDigit()
    }
  }
  @ViewBuilder var pdfControls: some View {
    preview(145)
    Text("\(s.pageCount) pages").foregroundStyle(.secondary)
    if s.action == "Metadata" {
      TextField("Title", text: $s.o.title)
      TextField("Author", text: $s.o.author)
      TextField("Subject", text: $s.o.subject)
      Toggle("Remove document information", isOn: $s.o.stripMetadata)
    } else {
      HStack {
        Text("Pages")
        TextField("All pages, or 1, 3-5", text: $s.o.pages)
      }
      if ["Organize", "Rotate PDF"].contains(s.action) {
        Text("Enter pages in the desired order. Omit pages to remove them from the copy.").font(
          .caption)
        Picker("Rotate", selection: $s.o.rotation) {
          ForEach([0, 90, 180, 270], id: \.self) { Text("\($0)°") }
        }
      }
      if s.action == "Split" {
        Stepper(
          "Pages per file  \(s.o.splitEvery)", value: $s.o.splitEvery, in: 1...max(1, s.pageCount))
      }
      if ["Compress", "PNG", "JPEG", "Pages to PNG"].contains(s.action) {
        Picker("Resolution", selection: $s.o.dpi) {
          ForEach([72.0, 150, 300], id: \.self) { Text("\(Int($0)) dpi") }
        }
      }
      if ["JPEG", "Compress"].contains(s.action) { quality }
      if s.action == "Compress" {
        Text("Saves each page as an image. Selectable text and links are flattened.").font(.caption)
      }
    }
  }
  @ViewBuilder func mediaControls(_ player: AVPlayer) -> some View {
    VideoPlayer(player: player).frame(height: s.kind == "audio" ? 95 : 190)
    if s.action == "Trim" {
      HStack {
        Text("Start")
        TextField("Start", value: $s.o.start, format: .number)
        Text("End")
        TextField("End", value: $s.o.end, format: .number)
        Text("seconds")
      }
      Text("Duration  \(s.duration,specifier:"%.2f") s").font(.caption)
    }
    if s.kind == "video", s.action != "M4A" {
      Picker("Resolution", selection: $s.o.mediaPreset) {
        ForEach(["Original", "1080p", "720p", "480p"], id: \.self) { Text($0) }
      }
    }
  }
}

func usesEditor(_ action: String, kind: String) -> Bool {
  switch kind {
  case "image":
    return [
      "Edit", "Annotate", "Redact", "Add BG", "Crop", "Resize", "Compress", "HEIC", "JPEG",
      "Rotate",
    ].contains(action)
  case "pdf":
    return [
      "Organize", "Split", "Metadata", "Compress", "Rotate PDF", "PNG", "JPEG", "Pages to PNG",
      "TXT", "MD", "Extract text",
    ].contains(action)
  case "video", "audio":
    return action == "Trim" || (kind == "video" && ["MP4", "MOV"].contains(action))
  default: return action == "Save text"
  }
}

@MainActor extension Delegate {
  func presentEditor(
    _ action: String, _ files: [URL], _ kind: String, _ shelf: Bool, _ folder: URL?
  ) {
    if let window = editorWindow, window.isVisible {
      window.makeKeyAndOrderFront(nil)
      return
    }
    do {
      if files.count > 1, ["Redact", "Annotate", "Crop", "Metadata", "Organize"].contains(action) {
        throw Failure.message("Select one file at a time for this editor.")
      }
      let session = try EditSession(action, files, kind: kind)
      if action == "Save text", files == model.files, let first = files.first,
        let bytes = try? first.resourceValues(forKeys: [.fileSizeKey]).fileSize, bytes < 2_000_000
      {
        session.o.text = model.text
        session.initial.text = model.text
      }
      let width: CGFloat = action == "Resize" ? 380 : action == "Edit" ? 570 : 510
      let tall = ["Crop", "Edit", "Redact", "Annotate"].contains(action)
      let height: CGFloat = tall ? 665 : action == "Resize" ? 372 : 465
      let window = NSWindow(
        contentRect: NSRect(
          x: 0, y: 0, width: width,
          height: min(height, (NSScreen.main?.visibleFrame.height ?? 800) - 40)),
        styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered,
        defer: false)
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.title = action
      window.isMovableByWindowBackground = true
      window.isReleasedWhenClosed = false
      window.isOpaque = false
      window.backgroundColor = .clear
      for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
        window.standardWindowButton(button)?.isHidden = true
      }
      window.contentMinSize = NSSize(width: min(width, 400), height: 300)
      let dismiss = { [weak window, weak self] in
        session.player?.pause()
        session.previewTask?.cancel()
        window?.close()
        self?.editorWindow = nil
      }
      window.contentView = NSHostingView(
        rootView: EditPanel(
          s: session,
          apply: { [weak self] in
            guard let self, !self.model.busy else { return }
            do {
              if kind == "pdf" {
                _ = try EditEngine.pageIndices(session.o.pages, count: session.pageCount)
              }
              if action == "Resize", session.o.width <= 0 || session.o.height <= 0 {
                throw Failure.message("Enter positive dimensions")
              }
              if action == "Trim"
                && !(session.o.start >= 0 && session.o.end > session.o.start
                  && session.o.end <= session.duration)
              {
                throw Failure.message("Choose a start before the end, within the media duration")
              }
            } catch {
              session.error = error.localizedDescription
              return
            }
            let options = session.o
            dismiss()
            self.exportEdited(files, action: action, options: options, shelf: shelf, folder: folder)
          }, cancel: dismiss))
      editorWindow = window
      window.center()
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      if ["Add BG", "Rotate", "Compress", "JPEG", "HEIC"].contains(action) {
        session.updatePreview()
      }
    } catch { showEditorError(error.localizedDescription) }
  }
  private func showEditorError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "Clementine"
    alert.informativeText = message
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }
  private func exportEdited(
    _ files: [URL], action: String, options: EditOptions, shelf: Bool, folder: URL?
  ) {
    model.busy = true
    model.status = "Processing…"
    let target =
      shelf
      ? FileManager.default.temporaryDirectory.appendingPathComponent(
        "Clementine-Drag/" + UUID().uuidString) : folder
    Task {
      let results = await Task.detached(priority: .userInitiated) {
        var jobs: [Job] = []
        for file in files {
          do {
            let out = try await EditEngine.export(
              file, action: action, folder: target, options: options)
            jobs.append(
              Job(name: file.lastPathComponent, result: "Saved " + out.lastPathComponent, url: out))
          } catch {
            jobs.append(
              Job(name: file.lastPathComponent, result: error.localizedDescription, url: nil))
          }
        }
        return jobs
      }.value
      model.busy = false
      model.history.insert(contentsOf: results, at: 0)
      model.ready = results.compactMap(\.url)
      model.status = model.ready.isEmpty ? "Export failed" : "Edited copies ready"
      if shelf { model.conversionFinished?(model.ready) }
      if let failed = results.first(where: { $0.url == nil }) {
        showEditorError(failed.name + "\n" + failed.result)
      }
    }
  }
}

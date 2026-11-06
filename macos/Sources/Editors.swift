import AVFoundation
import AVKit
import Cocoa
import CoreImage
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct PhotoAdjustment: Identifiable {
  let name: String
  let section: String
  let range: ClosedRange<Double>
  var id: String { name }
  static let all: [PhotoAdjustment] = [
    .init(name: "Exposure", section: "Light", range: -3...3),
    .init(name: "Brightness", section: "Light", range: -1...1),
    .init(name: "Contrast", section: "Light", range: -1...1),
    .init(name: "Highlights", section: "Light", range: -1...1),
    .init(name: "Shadows", section: "Light", range: -1...1),
    .init(name: "Whites", section: "Light", range: -1...1),
    .init(name: "Blacks", section: "Light", range: -1...1),
    .init(name: "Gamma", section: "Light", range: -1...1),
    .init(name: "Temperature", section: "Color", range: -1...1),
    .init(name: "Tint", section: "Color", range: -1...1),
    .init(name: "Saturation", section: "Color", range: -1...1),
    .init(name: "Vibrance", section: "Color", range: -1...1),
    .init(name: "Hue", section: "Color", range: -180...180),
    .init(name: "Sharpness", section: "Detail", range: 0...2),
  ]
}
struct Mark: Identifiable {
  let id = UUID()
  var tool: String
  var points: [CGPoint]
  var color: NSColor
  var width: Double
  var text: String
  var image: CGImage? = nil
}
struct EditOptions {
  var values: [String: Double] = [:]
  var width = 1600
  var height = 1200
  var scale = 100.0
  var scaleMode = false
  var locked = true
  var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
  var ratio = "Free"
  var quality = 0.85
  var format = "PNG"
  var dpi = 150.0
  var background = NSColor.white
  var padding = 0.0
  var marks: [Mark] = []
  var pages = ""
  var rotation = 0
  var splitEvery = 1
  var title = ""
  var author = ""
  var subject = ""
  var stripMetadata = false
  var start = 0.0
  var end = 10.0
  var mediaPreset = "Original"
  var text = ""
}
enum EditEngine {
  static let context = CIContext(options: [.cacheIntermediates: false])
  static func image(_ url: URL, maxSize: Int? = nil) throws -> CGImage {
    if url.pathExtension.lowercased()=="svg", let vector=NSImage(contentsOf:url) {
      var box=CGRect(origin:.zero,size:vector.size)
      guard box.width>0,box.height>0,box.width*box.height<=100_000_000 else {throw Failure.message("Invalid SVG dimensions")}
      if let maxSize {
        let factor=min(1,CGFloat(maxSize)/max(box.width,box.height))
        box.size=CGSize(width:box.width*factor,height:box.height*factor)
      }
      let pixels=box.size
      guard let result=vector.cgImage(forProposedRect:&box,context:nil,hints:nil) else {throw Failure.message("Cannot render SVG")}
      return try render(result,max(1,Int(pixels.width.rounded())),max(1,Int(pixels.height.rounded())),false)
    }
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw Failure.message("Cannot read this image")
    }
    let properties = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] ?? [:]
    let size = max(
      properties[kCGImagePropertyPixelWidth as String] as? Int ?? 1,
      properties[kCGImagePropertyPixelHeight as String] as? Int ?? 1)
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxSize ?? size,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
      throw Failure.message("Cannot decode this image")
    }
    return cg
  }
  static func adjusted(_ cg: CGImage, _ options: EditOptions) throws -> CGImage {
    var im = CIImage(cgImage: cg)
    func v(_ name: String) -> Double { options.values[name] ?? 0 }
    func filter(_ name: String, _ parameters: [String: Any]) {
      im = im.applyingFilter(name, parameters: parameters)
    }
    if v("Exposure") != 0 { filter("CIExposureAdjust", [kCIInputEVKey: v("Exposure")]) }
    if v("Brightness") != 0 || v("Contrast") != 0 || v("Saturation") != 0 {
      filter(
        "CIColorControls",
        [
          kCIInputBrightnessKey: v("Brightness"), kCIInputContrastKey: 1 + v("Contrast"),
          kCIInputSaturationKey: 1 + v("Saturation"),
        ])
    }
    if v("Highlights") != 0 || v("Shadows") != 0 {
      filter(
        "CIHighlightShadowAdjust",
        ["inputHighlightAmount": 1 - v("Highlights"), "inputShadowAmount": v("Shadows")])
    }
    if v("Whites") != 0 || v("Blacks") != 0 {
      let b = v("Blacks") * 0.2
      let w = v("Whites") * 0.2
      filter(
        "CIToneCurve",
        [
          "inputPoint0": CIVector(x: 0, y: b), "inputPoint1": CIVector(x: 0.25, y: 0.25 + b * 0.5),
          "inputPoint2": CIVector(x: 0.5, y: 0.5),
          "inputPoint3": CIVector(x: 0.75, y: 0.75 + w * 0.5),
          "inputPoint4": CIVector(x: 1, y: 1 + w),
        ])
    }
    if v("Gamma") != 0 { filter("CIGammaAdjust", ["inputPower": pow(2, -v("Gamma"))]) }
    if v("Temperature") != 0 || v("Tint") != 0 {
      filter(
        "CITemperatureAndTint",
        [
          "inputNeutral": CIVector(x: 6500, y: 0),
          "inputTargetNeutral": CIVector(x: 6500 + v("Temperature") * 4000, y: v("Tint") * 150),
        ])
    }
    if v("Vibrance") != 0 { filter("CIVibrance", ["inputAmount": v("Vibrance")]) }
    if v("Hue") != 0 { filter("CIHueAdjust", [kCIInputAngleKey: v("Hue") * .pi / 180]) }
    if v("Sharpness") != 0 { filter("CISharpenLuminance", [kCIInputSharpnessKey: v("Sharpness")]) }
    guard let out = context.createCGImage(im, from: im.extent) else {
      throw Failure.message("Cannot render adjustments")
    }
    return out
  }
  static func dimensions(_ cg: CGImage, _ o: EditOptions) throws -> (Int, Int) {
    let w = o.scaleMode ? Int((Double(cg.width) * o.scale / 100).rounded()) : o.width
    let h =
      o.scaleMode
      ? Int((Double(cg.height) * o.scale / 100).rounded())
      : o.locked ? Int((Double(cg.height) * Double(w) / Double(cg.width)).rounded()) : o.height
    guard w > 0, h > 0, w <= 32000, h <= 32000, w * h <= 100_000_000 else {
      throw Failure.message("Choose dimensions below 32,000 px and 100 megapixels")
    }
    return (w, h)
  }
  static func cropped(_ cg: CGImage, _ rect: CGRect) throws -> CGImage {
    let r = CGRect(
      x: rect.minX * Double(cg.width), y: rect.minY * Double(cg.height),
      width: rect.width * Double(cg.width), height: rect.height * Double(cg.height)
    ).integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    guard r.width >= 1, r.height >= 1, let result = cg.cropping(to: r) else {
      throw Failure.message("Choose a crop inside the image")
    }
    return result
  }
  static func composite(_ cg: CGImage, _ o: EditOptions, background: Bool = false) throws -> CGImage
  {
    let pad = background ? Int(o.padding) : 0
    let w = cg.width + pad * 2
    let h = cg.height + pad * 2
    guard w > 0, h > 0, w * h <= 100_000_000,
      let c = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw Failure.message("Image is too large") }
    if background {
      c.setFillColor(o.background.cgColor)
      c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }
    c.draw(cg, in: CGRect(x: pad, y: pad, width: cg.width, height: cg.height))
    c.translateBy(x: 0, y: CGFloat(h))
    c.scaleBy(x: 1, y: -1)
    drawMarks(o.marks, in: c, size: CGSize(width: w, height: h), source: cg)
    guard let result = c.makeImage() else { throw Failure.message("Cannot render image") }
    return result
  }
  static func pageIndices(_ text: String, count: Int) throws -> [Int] {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return Array(0..<count) }
    var result: [Int] = []
    for part in text.split(separator: ",", omittingEmptySubsequences: false) {
      let numbers = part.trimmingCharacters(in: .whitespaces).split(
        separator: "-", omittingEmptySubsequences: false)
      guard numbers.count <= 2, let first = numbers.first,
        let a = Int(first.trimmingCharacters(in: .whitespaces)),
        a >= 1, a <= count
      else { throw Failure.message("Enter page numbers from 1 to \(count), for example 1,3-5") }
      if numbers.count == 2 {
        guard let b = Int(numbers[1].trimmingCharacters(in: .whitespaces)), b >= a, b <= count
        else { throw Failure.message("Invalid page range") }
        result.append(contentsOf: (a...b).map { $0 - 1 })
      } else {
        result.append(a - 1)
      }
    }
    return result
  }
  static func export(_ u: URL, action: String, folder: URL?, options o: EditOptions) async throws
    -> URL
  {
    if inputType(u)?.conforms(to: .image) == true {
      var cg = try image(u)
      switch action {
      case "Resize":
        let (w, h) = try dimensions(cg, o)
        cg = try render(cg, w, h, false)
      case "Rotate":
        for _ in 0..<(o.rotation / 90) { cg = try render(cg, cg.height, cg.width, true) }
      case "Crop": cg = try cropped(cg, o.crop)
      case "Edit": cg = try adjusted(cg, o)
      case "Annotate", "Redact": cg = try composite(cg, o)
      case "Add BG": cg = try composite(cg, o, background: true)
      default: break
      }
      if action == "PDF" {
        let doc = PDFDocument()
        guard let page = PDFPage(image: NSImage(cgImage: cg, size: .zero)) else {
          throw Failure.message("Cannot create PDF")
        }
        doc.insert(page, at: 0)
        let out = try outputURL(u, folder, "pdf")
        guard doc.write(to: out) else { throw Failure.message("Cannot save PDF") }
        return out
      }
      let formats: [String: UTType] = [
        "PNG": .png, "JPEG": .jpeg, "HEIC": .heic, "TIFF": .tiff, "BMP": .bmp,
      ]
      let format = formats[action] ?? formats[o.format] ?? .png
      let out = try outputURL(
        u, folder, format.preferredFilenameExtension ?? "png",
        action.lowercased().replacingOccurrences(of: " ", with: "-"))
      try writeImage(cg, out, format, o.quality)
      return out
    }
    if u.pathExtension.lowercased() == "pdf" {
      guard let doc = PDFDocument(url: u), !doc.isLocked else {
        throw Failure.message("Cannot open PDF; unlock it first")
      }
      let pages = try pageIndices(o.pages, count: doc.pageCount)
      if ["TXT", "MD", "Extract text"].contains(action) {
        let content = pages.compactMap { doc.page(at: $0)?.string }.joined(separator: "\n\n")
        let out = try outputURL(u, folder, action == "MD" ? "md" : "txt")
        try content.write(to: out, atomically: true, encoding: .utf8)
        return out
      }
      if action == "Metadata" {
        var attrs = o.stripMetadata ? [:] : doc.documentAttributes ?? [:]
        if !o.stripMetadata {
          attrs[PDFDocumentAttribute.titleAttribute] = o.title
          attrs[PDFDocumentAttribute.authorAttribute] = o.author
          attrs[PDFDocumentAttribute.subjectAttribute] = o.subject
        }
        doc.documentAttributes = attrs
      } else if action == "Organize" || action == "Rotate PDF" {
        let copy = PDFDocument()
        for i in pages {
          guard let page = doc.page(at: i)?.copy() as? PDFPage else { continue }
          page.rotation = (page.rotation + o.rotation) % 360
          copy.insert(page, at: copy.pageCount)
        }
        let out = try outputURL(u, folder, "pdf", "organized")
        guard copy.write(to: out) else { throw Failure.message("Cannot save PDF") }
        return out
      } else if action == "Split" || ["PNG", "JPEG", "Pages to PNG"].contains(action) {
        let directory = try outputURL(u, folder, "", "pages")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if action == "Split" {
          guard o.splitEvery > 0 else { throw Failure.message("Pages per file must be at least 1") }
          for offset in stride(from: 0, to: pages.count, by: o.splitEvery) {
            let part = PDFDocument()
            for i in pages[offset..<min(offset + o.splitEvery, pages.count)] {
              if let p = doc.page(at: i)?.copy() as? PDFPage { part.insert(p, at: part.pageCount) }
            }
            guard part.write(to: directory.appendingPathComponent("Pages-\(offset+1).pdf")) else {
              throw Failure.message("Cannot save PDF")
            }
          }
        } else {
          for i in pages {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = min(o.dpi / 72, 6000 / max(bounds.width, bounds.height))
            let im = page.thumbnail(
              of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox
            )
            guard let cg = im.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
              throw Failure.message("Cannot render page")
            }
            try writeImage(
              cg,
              directory.appendingPathComponent("Page-\(i+1).\(action == "JPEG" ? "jpg" : "png")"),
              action == "JPEG" ? .jpeg : .png, o.quality)
          }
        }
        return directory
      } else if action == "Compress" {
        let result = PDFDocument()
        for i in pages {
          guard let page = doc.page(at: i) else { continue }
          let b = page.bounds(for: .mediaBox)
          let scale = min(o.dpi / 72, 4000 / max(b.width, b.height))
          let image = page.thumbnail(
            of: NSSize(width: b.width * scale, height: b.height * scale), for: .mediaBox)
          guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            continue
          }
          let data = NSMutableData()
          guard
            let d = CGImageDestinationCreateWithData(
              data, UTType.jpeg.identifier as CFString, 1, nil)
          else { continue }
          CGImageDestinationAddImage(
            d, cg, [kCGImageDestinationLossyCompressionQuality: o.quality] as CFDictionary)
          guard CGImageDestinationFinalize(d), let im = NSImage(data: data as Data) else {
            continue
          }
          im.size = b.size
          guard let p = PDFPage(image: im) else { continue }
          result.insert(p, at: result.pageCount)
        }
        guard result.pageCount == pages.count else {
          throw Failure.message("Could not compress every page")
        }
        let out = try outputURL(u, folder, "pdf", "compressed")
        guard result.write(to: out) else { throw Failure.message("Cannot save PDF") }
        return out
      } else {
        return try await process(u, action, folder, o.width, o.quality, o.start, o.end, o.text)
      }
      let out = try outputURL(u, folder, "pdf", "metadata")
      guard doc.write(to: out) else { throw Failure.message("Cannot save PDF") }
      return out
    }
    if inputType(u)?.conforms(to: .movie) == true || inputType(u)?.conforms(to: .audio) == true {
      let asset = AVURLAsset(url: u)
      let audio = action == "M4A" || inputType(u)?.conforms(to: .audio) == true
      let presets = [
        "Original": AVAssetExportPresetHighestQuality, "1080p": AVAssetExportPreset1920x1080,
        "720p": AVAssetExportPreset1280x720, "480p": AVAssetExportPreset640x480,
      ]
      guard
        let session = AVAssetExportSession(
          asset: asset,
          presetName: audio
            ? AVAssetExportPresetAppleM4A
            : presets[o.mediaPreset] ?? AVAssetExportPresetHighestQuality)
      else { throw Failure.message("Unsupported media") }
      let type: AVFileType = audio ? .m4a : action == "MOV" ? .mov : .mp4
      guard session.supportedFileTypes.contains(type) else {
        throw Failure.message("This export format is unavailable for this file")
      }
      if action == "Trim" {
        let duration = try await asset.load(.duration).seconds
        guard o.start.isFinite, o.end.isFinite, o.start >= 0, o.end > o.start, o.end <= duration
        else {
          throw Failure.message(
            "Enter a valid start and end within \(String(format:"%.2f",duration)) seconds")
        }
        session.timeRange = CMTimeRange(
          start: CMTime(seconds: o.start, preferredTimescale: 600),
          end: CMTime(seconds: o.end, preferredTimescale: 600))
      }
      let out = try outputURL(
        u, folder, audio ? "m4a" : type == .mov ? "mov" : "mp4", action.lowercased())
      session.outputURL = out
      session.outputFileType = type
      await session.export()
      guard session.status == .completed else {
        throw session.error ?? Failure.message("Export failed")
      }
      return out
    }
    return try await process(u, action, folder, o.width, o.quality, o.start, o.end, o.text)
  }
}

import Cocoa
import SwiftUI
import UniformTypeIdentifiers

struct FormatGroup {
  let title: String
  let inputs: [String]
  let outputs: [String]
  let icon: String
  let exceptions: [String: [String]]

  init(
    _ title: String, _ inputs: String, _ outputs: String, _ icon: String,
    _ exceptions: [String: String] = [:]
  ) {
    self.title = title
    self.inputs = inputs.components(separatedBy: " ")
    self.outputs = outputs.components(separatedBy: " ")
    self.icon = icon
    self.exceptions = exceptions.mapValues { $0.components(separatedBy: " ") }
  }
  func targets(_ input: String) -> [String] {
    (exceptions[input] ?? outputs).filter { $0 != input && $0 != "AVIF" }
  }
}

enum Compatibility {
  static let documentTargets = "PDF DOCX PAGES TXT MD HTML EPUB JPEG PNG"
  static let groups = [
    FormatGroup(
      "Images", "JPEG PNG WEBP HEIC TIFF SVG AVIF BMP", "JPEG PNG WEBP HEIC TIFF AVIF BMP PDF",
      "photo"),
    FormatGroup(
      "Documents", "PDF DOCX PAGES PPT PPTX TXT MD RTF RTFD TEXTCLIPPING EPUB HTML",
      "PDF DOCX PAGES PPTX TXT MD HTML EPUB JPEG PNG XLSX", "doc",
      [
        "PDF": "DOCX PAGES PPTX XLSX JPEG PNG EPUB TXT MD", "PPT": "PDF JPEG PNG",
        "PPTX": "PDF JPEG PNG", "EPUB": "PDF DOCX PAGES TXT MD HTML",
      ].merging(
        Dictionary(
          uniqueKeysWithValues: [
            "DOCX", "PAGES", "TXT", "MD", "RTF", "RTFD", "TEXTCLIPPING", "HTML",
          ].map { ($0, documentTargets) })
      ) { a, _ in a }),
    FormatGroup("Spreadsheets", "XLSX XLS ODS CSV TSV", "XLSX ODS CSV TSV PDF", "tablecells"),
    FormatGroup(
      "Audio", "MP3 M4A WAV FLAC OGG OPUS AIFF WMA", "MP3 M4A WAV FLAC OGG OPUS AIFF WMA",
      "waveform"),
    FormatGroup(
      "Video", "MP4 MOV MKV WEBM AVI WMV GIF", "MP4 MOV MKV WEBM AVI WMV GIF MP3", "film",
      ["GIF": "MP4 MOV MKV WEBM AVI WMV"]),
    FormatGroup("Archives", "ZIP TAR GZIP RAR", "ZIP TAR GZIP", "archivebox"),
    FormatGroup("Subtitles", "SRT VTT", "SRT VTT TXT", "captions.bubble"),
  ]
  static let byInput: [String: FormatGroup] = Dictionary(
    uniqueKeysWithValues: groups.flatMap { g in g.inputs.map { ($0, g) } })
  static let wheel: [String: [(String, String)]] = Dictionary(
    uniqueKeysWithValues: byInput.map { input, group in
      (input, group.targets(input).map { ($0, group.icon) })
    })
  static let aliases = [
    "JPG": "JPEG", "HEIF": "HEIC", "TIF": "TIFF", "AIF": "AIFF", "GZ": "GZIP", "TGZ": "GZIP",
    "M4V": "MP4", "AAC": "M4A",
  ]
  static func format(_ url: URL) -> String {
    let ext = url.pathExtension.uppercased()
    return aliases[ext] ?? ext
  }
  static let resources = Bundle.main.resourceURL!
  private static let tools = NSDictionary(contentsOf: resources.appendingPathComponent("Tools.plist"))
  private static func executable(_ name: String) -> URL {
    URL(fileURLWithPath: tools?[name] as? String ?? "/usr/local/bin/" + name)
  }
  static let python = executable("python3")
  static let node = executable("node")
  static let office = executable("soffice")
  static let ffmpeg = executable("ffmpeg")
  static func media(_ u: URL, _ action: String, _ out: URL, extra: [String] = []) throws {
    let audio: [String: String] = [
      "MP3": "libmp3lame", "M4A": "aac", "WAV": "pcm_s16le", "FLAC": "flac", "OGG": "libvorbis",
      "OPUS": "libopus", "AIFF": "pcm_s16be", "WMA": "wmav2",
    ]
    var args =
      [
        "-hide_banner", "-loglevel", "error", "-nostdin", "-protocol_whitelist", "file,pipe", "-i",
        u.path,
      ] + extra
    if let codec = audio[action] {
      args += ["-map", "0:a:0", "-vn", "-c:a", codec]
      if ["WMA", "MP3"].contains(action) { args += ["-ac", "2", "-ar", "44100", "-b:a", "192k"] }
    } else if action == "GIF" {
      args += [
        "-map", "0:v:0", "-an", "-vf", "fps=15,split[a][b];[a]palettegen[p];[b][p]paletteuse",
        "-loop", "0",
      ]
    } else {
      args += [
        "-map", "0:v:0", "-map", "0:a:0?", "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-pix_fmt",
        "yuv420p",
      ]
      switch action {
      case "WEBM":
        args += [
          "-c:v", "libvpx-vp9", "-deadline", "realtime", "-cpu-used", "6", "-row-mt", "1", "-c:a",
          "libopus",
        ]
      case "AVI": args += ["-c:v", "mpeg4", "-q:v", "4", "-c:a", "libmp3lame"]
      case "WMV":
        args += ["-c:v", "wmv2", "-q:v", "4", "-c:a", "wmav2", "-ac", "2", "-ar", "44100"]
      default: args += ["-c:v", "libx264", "-preset", "veryfast", "-crf", "21", "-c:a", "aac"]
      }
    }
    try command(ffmpeg.path, args + ["-y", out.path])
  }
  static func convert(_ u: URL, _ action: String, _ folder: URL?, _ quality: Double) throws -> URL?
  {
    let input = format(u)
    guard let group = byInput[input], group.targets(input).contains(action) else { return nil }
    if group.title == "Images" && action != "WEBP" && input != "SVG" { return nil }
    if input == "PDF" && ["TXT", "MD", "PNG", "JPEG"].contains(action) { return nil }
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let ext = action == "GZIP" ? "tar.gz" : action == "JPEG" ? "jpg" : action.lowercased()
    let result = temp.appendingPathComponent("result." + ext)
    switch group.title {
    case "Audio", "Video": try media(u, action, result)
    case "Images":
      let cg = try EditEngine.image(u)
      if action == "WEBP" {
        let png = temp.appendingPathComponent("frame.png")
        try writeImage(cg, png, .png, 1)
        try command(
          ffmpeg.path,
          [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-i", png.path, "-frames:v", "1",
            "-c:v", "libwebp", "-quality", String(Int(quality * 100)), result.path,
          ])
      } else if action == "PDF" {
        var bounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        guard let c = CGContext(result as CFURL, mediaBox: &bounds, nil) else {
          throw Failure.message("Cannot create PDF")
        }
        c.beginPDFPage(nil)
        c.draw(cg, in: bounds)
        c.endPDFPage()
        c.closePDF()
      } else {
        let formats: [String: UTType] = [
          "JPEG": .jpeg, "TIFF": .tiff, "BMP": .bmp, "PNG": .png, "HEIC": .heic,
        ]
        try writeImage(cg, result, formats[action]!, quality)
      }
    case "Archives":
      let flags =
        action == "ZIP"
        ? ["--format", "zip"] : (action == "GZIP" ? ["-z"] : []) + ["--format", "pax"]
      do { try command("/usr/bin/tar", ["-cf", result.path] + flags + ["@" + u.path]) } catch {
        guard input == "GZIP" else { throw error }
        try command(
          python.path,
          [
            "-I", resources.appendingPathComponent("office_convert.py").path, u.path, result.path,
            temp.path, office.path, node.path,
          ])
      }
    case "Subtitles":
      let srt = action == "TXT" ? temp.appendingPathComponent("cues.srt") : result
      try command(
        ffmpeg.path, ["-hide_banner", "-loglevel", "error", "-nostdin", "-i", u.path, srt.path])
      if action == "TXT" {
        let blocks = try String(contentsOf: srt, encoding: .utf8).replacingOccurrences(
          of: "\r\n", with: "\n"
        ).components(separatedBy: "\n\n")
        let text = blocks.compactMap { block -> String? in
          let lines = block.components(separatedBy: "\n")
          guard lines.count > 2 else { return nil }
          return lines.dropFirst(2).joined(separator: "\n").replacingOccurrences(
            of: "</?[^>]+>", with: "", options: .regularExpression)
        }.joined(separator: "\n")
        try text.write(to: result, atomically: true, encoding: .utf8)
      }
    default:
      try command(
        python.path,
        [
          "-I", resources.appendingPathComponent("office_convert.py").path, u.path, result.path,
          temp.path, office.path, node.path,
        ])
    }
    guard FileManager.default.fileExists(atPath: result.path) else {
      throw Failure.message("The converter produced no output")
    }
    let imagePages = (group.title == "Documents" && ["JPEG", "PNG"].contains(action))
    let out = try outputURL(u, folder, imagePages ? "" : ext, imagePages ? "pages" : "converted")
    try FileManager.default.moveItem(at: result, to: out)
    return out
  }
}

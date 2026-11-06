import AppKit
import CoreText
import SwiftUI

func drawMarks(_ marks: [Mark], in context: CGContext, size: CGSize, source: CGImage) {
  func pixel(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
  for mark in marks {
    guard let start = mark.points.first.map(pixel), let end = mark.points.last.map(pixel) else {
      continue
    }
    let rect = CGRect(
      x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x),
      height: abs(end.y - start.y))
    let unit = min(size.width, size.height)
    let stroke = max(0.5, mark.width * unit)
    context.saveGState()
    defer { context.restoreGState() }
    context.setLineWidth(stroke)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(mark.color.cgColor)
    context.setFillColor(mark.color.cgColor)
    func drawImage(_ image: CGImage, _ r: CGRect) {
      context.saveGState()
      context.translateBy(x: r.minX, y: r.maxY)
      context.scaleBy(x: 1, y: -1)
      context.draw(image, in: CGRect(origin: .zero, size: r.size))
      context.restoreGState()
    }
    switch mark.tool {
    case "Redact":
      context.setFillColor(NSColor.black.cgColor)
      context.fill(rect)
    case "Rectangle": context.stroke(rect)
    case "Circle": context.strokeEllipse(in: rect)
    case "Image": if let image = mark.image { drawImage(image, rect) }
    case "Magnify":
      guard rect.width > 0, rect.height > 0 else { continue }
      let sourceRect = CGRect(
        x: (rect.midX - rect.width / 4) / size.width * CGFloat(source.width),
        y: (rect.midY - rect.height / 4) / size.height * CGFloat(source.height),
        width: rect.width / size.width * CGFloat(source.width) / 2,
        height: rect.height / size.height * CGFloat(source.height) / 2)
      if let patch = source.cropping(to: sourceRect) {
        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()
        drawImage(patch, rect)
        context.restoreGState()
        context.strokeEllipse(in: rect)
      }
    case "Text", "Number":
      let radius = unit * 0.034
      let number = mark.tool == "Number"
      if number {
        context.fillEllipse(
          in: CGRect(
            x: start.x - radius, y: start.y - radius, width: 2 * radius, height: 2 * radius))
      }
      let string = NSAttributedString(
        string: mark.text,
        attributes: [
          .font: NSFont.boldSystemFont(ofSize: unit * (number ? 0.045 : 0.052)),
          .foregroundColor: number ? NSColor.white : mark.color,
        ])
      let line = CTLineCreateWithAttributedString(string)
      let width = CTLineGetTypographicBounds(line, nil, nil, nil)
      context.translateBy(
        x: start.x - (number ? width / 2 : 0), y: start.y + (number ? radius * 0.48 : 0))
      context.scaleBy(x: 1, y: -1)
      context.textMatrix = .identity
      context.textPosition = .zero
      CTLineDraw(line, context)
    default:
      context.move(to: start)
      for p in mark.points.dropFirst() { context.addLine(to: pixel(p)) }
      if mark.tool == "Arrow" {
        let angle = atan2(end.y - start.y, end.x - start.x)
        for delta in [-0.48, 0.48] {
          context.move(to: end)
          context.addLine(
            to: CGPoint(
              x: end.x - stroke * 5 * cos(angle + delta), y: end.y - stroke * 5 * sin(angle + delta)
            ))
        }
      }
      context.strokePath()
    }
  }
}

struct InteractivePreview: NSViewRepresentable {
  @ObservedObject var session: EditSession
  func makeNSView(context: Context) -> ImageSurface { ImageSurface() }
  func updateNSView(_ view: ImageSurface, context: Context) {
    view.session = session
    view.needsDisplay = true
  }
}

@MainActor final class ImageSurface: NSView {
  override var mouseDownCanMoveWindow: Bool { false }
  weak var session: EditSession?
  override var isFlipped: Bool { true }
  var anchor = CGPoint.zero
  var startingCrop = CGRect.zero
  var handle = (0, 0)
  var moving: Int?
  var originalPoints: [CGPoint] = []
  var drawing = false
  var imageBox: CGRect {
    guard let s = session else { return .zero }
    let room = bounds.insetBy(dx: 8, dy: 8)
    let factor = min(room.width / s.size.width, room.height / s.size.height)
    let size = CGSize(width: s.size.width * factor, height: s.size.height * factor)
    return CGRect(
      x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width,
      height: size.height)
  }
  func mapped(_ r: CGRect) -> CGRect {
    let b = imageBox
    return CGRect(
      x: b.minX + r.minX * b.width, y: b.minY + r.minY * b.height, width: r.width * b.width,
      height: r.height * b.height)
  }
  override func draw(_ dirtyRect: NSRect) {
    guard let s = session, let image = s.thumbnail, let c = NSGraphicsContext.current?.cgContext
    else { return }
    let b = imageBox
    NSImage(cgImage: image, size: .zero).draw(
      in: b, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    if s.action == "Crop" {
      let r = mapped(s.o.crop)
      c.saveGState()
      c.addRect(b)
      c.addRect(r)
      c.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
      c.fillPath(using: .evenOdd)
      c.restoreGState()
      c.setLineWidth(2)
      c.setStrokeColor(NSColor.systemOrange.cgColor)
      c.stroke(r)
      c.setFillColor(NSColor.systemOrange.cgColor)
      for x in [r.minX, r.midX, r.maxX] {
        for y in [r.minY, r.midY, r.maxY] where x != r.midX || y != r.midY {
          let width: CGFloat = x == r.midX ? 20 : 8
          let height: CGFloat = y == r.midY ? 20 : 8
          c.fill(CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height))
        }
      }
    } else {
      c.saveGState()
      c.clip(to: b)
      c.translateBy(x: b.minX, y: b.minY)
      drawMarks(s.o.marks, in: c, size: b.size, source: image)
      c.restoreGState()
    }
  }
  func point(_ event: NSEvent) -> CGPoint {
    let p = convert(event.locationInWindow, from: nil)
    let b = imageBox
    return CGPoint(
      x: max(0, min(1, (p.x - b.minX) / b.width)), y: max(0, min(1, (p.y - b.minY) / b.height)))
  }
  override func mouseDown(with event: NSEvent) {
    guard let s = session,
      imageBox.insetBy(dx: -6, dy: -6).contains(convert(event.locationInWindow, from: nil))
    else { return }
    drawing = true
    anchor = point(event)
    moving = nil
    if s.action == "Crop" {
      startingCrop = s.o.crop
      let r = startingCrop
      handle = (
        abs(anchor.x - r.minX) * imageBox.width < 10
          ? -1 : abs(anchor.x - r.maxX) * imageBox.width < 10 ? 1 : 0,
        abs(anchor.y - r.minY) * imageBox.height < 10
          ? -1 : abs(anchor.y - r.maxY) * imageBox.height < 10 ? 1 : 0
      )
      if handle == (0, 0) && !r.contains(anchor) {
        startingCrop = CGRect(origin: anchor, size: .zero)
        handle = (1, 1)
      }
      return
    }
    let tool = s.action == "Redact" ? "Redact" : s.tool
    if tool == "Image" && s.overlayImage == nil {
      drawing = false
      return
    }
    s.rememberMarks()
    if let index = s.o.marks.indices.reversed().first(where: { i in
      let m = s.o.marks[i]
      guard let p = m.points.first else { return false }
      let xs = m.points.map(\.x)
      let ys = m.points.map(\.y)
      let r = CGRect(
        x: xs.min() ?? p.x, y: ys.min() ?? p.y, width: (xs.max() ?? p.x) - (xs.min() ?? p.x),
        height: (ys.max() ?? p.y) - (ys.min() ?? p.y))
      return r.insetBy(dx: -0.012, dy: -0.012).contains(anchor)
        && !["Draw", "Highlight", "Redact"].contains(tool)
    }) {
      moving = index
      originalPoints = s.o.marks[index].points
      return
    }
    let text =
      tool == "Number"
      ? String(1 + s.o.marks.filter { $0.tool == "Number" }.count) : s.annotationText
    let color = tool == "Highlight" ? s.ink.withAlphaComponent(0.45) : s.ink
    s.o.marks.append(
      Mark(
        tool: tool, points: [anchor, anchor], color: color,
        width: tool == "Highlight" ? 0.037 : 0.005, text: text,
        image: tool == "Image" ? s.overlayImage : nil))
  }
  override func mouseDragged(with event: NSEvent) {
    guard drawing, let s = session else { return }
    let p = point(event)
    let dx = p.x - anchor.x
    let dy = p.y - anchor.y
    if s.action == "Crop" {
      let r = startingCrop
      if handle == (0, 0) {
        s.o.crop.origin = CGPoint(
          x: max(0, min(1 - r.width, r.minX + dx)), y: max(0, min(1 - r.height, r.minY + dy)))
        return
      }
      let x = handle.0 == -1 ? min(r.maxX - 1 / s.size.width, max(0, r.minX + dx)) : r.minX
      let y = handle.1 == -1 ? min(r.maxY - 1 / s.size.height, max(0, r.minY + dy)) : r.minY
      var w = handle.0 == 1 ? max(1 / s.size.width, min(1 - x, r.width + dx)) : r.maxX - x
      var h = handle.1 == 1 ? max(1 / s.size.height, min(1 - y, r.height + dy)) : r.maxY - y
      if let ratio = s.normalRatio {
        if handle.0 == 0 { w = h * ratio } else { h = w / ratio }
        let k = min(1, (handle.0 == -1 ? r.maxX : 1 - x) / w, (handle.1 == -1 ? r.maxY : 1 - y) / h)
        w *= k
        h *= k
      }
      s.o.crop = CGRect(
        x: handle.0 == -1 ? r.maxX - w : x, y: handle.1 == -1 ? r.maxY - h : y, width: w, height: h)
    } else if let i = moving {
      s.o.marks[i].points = originalPoints.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    } else if !s.o.marks.isEmpty {
      let i = s.o.marks.count - 1
      if ["Draw", "Highlight"].contains(s.o.marks[i].tool) {
        s.o.marks[i].points.append(p)
      } else {
        s.o.marks[i].points[1] = p
      }
    }
  }
  override func mouseUp(with event: NSEvent) {
    drawing = false
    moving = nil
  }
}

import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: Model
  @State private var tab = "Compatibility"
  private let tabs = ["General", "Formats", "Compatibility", "Folders", "About"]
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("Settings", selection: $tab) { ForEach(tabs, id: \.self) { Text($0) } }.labelsHidden()
        .pickerStyle(.segmented)
      switch tab {
      case "General":
        Toggle("Enable drag shortcuts", isOn: $model.wheelEnabled)
        Toggle("Haptic taps when changing options", isOn: $model.hapticsEnabled)
        Toggle("Tap sound when changing options", isOn: $model.soundEnabled)
        Text("Hold ⇧ to convert · ⌘ for tools · ⌃ for actions").foregroundStyle(.secondary)
      case "Folders":
        Button("Choose output folder…") { model.destination() }
        Button("Choose destination by dragging") { model.output = nil }
        Text(model.output?.path ?? "Drag converted copies to their destination").foregroundStyle(
          .secondary)
      case "About":
        Text("Clementine 0.5").font(.headline)
        Text("Local file conversion and editing.")
      default:
        Label(
          tab == "Formats" ? "Recognized file formats" : "Format Compatibility",
          systemImage: "tablecells")
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(Compatibility.groups, id: \.title) { group in
              VStack(alignment: .leading, spacing: 8) {
                Label(group.title, systemImage: group.icon).font(.headline)
                if tab == "Formats" {
                  Text(group.inputs.map(name).joined(separator: " · ")).font(.callout)
                } else {
                  matrix(group)
                }
              }.padding(8).background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.04)))
            }
          }
        }
      }
      Spacer(minLength: 0)
    }.padding(12).frame(width: 432, height: 528).background(Color(white:0.18)).preferredColorScheme(.dark)
  }
  func name(_ s: String) -> String { s == "JPEG" ? "JPG" : s == "TEXTCLIPPING" ? "Text clip" : s }
  func matrix(_ group: FormatGroup) -> some View {
    Grid(horizontalSpacing: 1, verticalSpacing: 1) {
      GridRow {
        cell("↱", header: true)
        ForEach(group.outputs, id: \.self) { cell(name($0), header: true) }
      }
      ForEach(group.inputs, id: \.self) { input in
        GridRow {
          cell(name(input), header: true)
          ForEach(group.outputs, id: \.self) { out in
            cell(group.targets(input).contains(out) ? "✓" : "–", header: false)
          }
        }
      }
    }.background(.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 4))
  }
  func cell(_ text: String, header: Bool) -> some View {
    Text(text).font(.system(size: header ? 8.5 : 11, weight: header ? .semibold : .regular))
      .lineLimit(1).minimumScaleFactor(0.65).frame(maxWidth: .infinity, minHeight: 19)
      .foregroundStyle(.white.opacity(text == "–" ? 0.22 : 0.82)).background(Color(white: 0.17))
  }
}

struct WorkspaceThumbnail: View {
  let url: URL
  @State private var preview: CGImage?
  var body: some View {
    Group { if let preview { Image(decorative: preview, scale: 1).resizable().scaledToFit() } }
      .frame(maxWidth: .infinity, maxHeight: 115).clipShape(RoundedRectangle(cornerRadius: 10))
      .task(id: url) {
        preview = nil
        let image = await Task.detached(priority: .utility) {
          try? EditEngine.image(url, maxSize: 460)
        }.value
        if !Task.isCancelled { preview = image }
      }
  }
}

import AppKit

@MainActor final class AirDropPresenter: NSObject, NSSharingServiceDelegate, NSSharingServicePickerDelegate {
    private var service: NSSharingService?
    private var picker: NSSharingServicePicker?
    private var anchor: NSPanel?
    private weak var recipientWindow: NSWindow?
    private var existingWindows = Set<ObjectIdentifier>()
    private var point = NSPoint.zero
    private var items: [NSURL] = []

    func present(_ urls: [URL], at dropPoint: NSPoint) {
        guard !urls.isEmpty else { return }
        if let recipientWindow, recipientWindow.isVisible {
            recipientWindow.makeKeyAndOrderFront(nil)
            return
        }
        finish()
        point = dropPoint
        items = urls.map { (($0 as NSURL).filePathURL ?? $0).standardizedFileURL as NSURL }
        NSApp.activate(ignoringOtherApps: true)

        // AppKit needs a source window, even for a menu-bar app. Only the recipient
        // picker should draw anything or accept input at the end of a Finder drag.
        let panel = NSPanel(contentRect: NSRect(origin: point, size: NSSize(width: 1, height: 1)),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        anchor = panel
        panel.orderFrontRegardless()

        guard items.allSatisfy({ FileManager.default.isReadableFile(atPath: $0.path ?? "") }) else {
            showError("One or more selected files couldn’t be read. Select the files again in Finder and retry.")
            return
        }
        guard let share = NSSharingService(named: .sendViaAirDrop) else { showShareMenu(); return }
        existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        service = share
        share.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(windowAppeared(_:)),
                                               name: NSWindow.didBecomeKeyNotification, object: nil)
        share.perform(withItems: items)
        // Some AppKit versions create the sharing window synchronously.
        NSApp.windows.filter(\.isVisible).forEach { placeRecipient($0) }
    }

    private func place(_ window: NSWindow) {
        let size = window.frame.size
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        window.setFrameOrigin(NSPoint(
            x: max(frame.minX, min(point.x - size.width / 2, frame.maxX - size.width)),
            y: max(frame.minY, min(point.y - size.height / 2, frame.maxY - size.height))))
    }

    @objc private func windowAppeared(_ note: Notification) {
        if let window = note.object as? NSWindow { placeRecipient(window) }
    }
    private func placeRecipient(_ window: NSWindow) {
        guard recipientWindow == nil, let service, window !== anchor,
              !existingWindows.contains(ObjectIdentifier(window)),
              window.title == service.title || window.title == "AirDrop" else { return }
        recipientWindow = window
        place(window)
        NotificationCenter.default.addObserver(self, selector: #selector(recipientClosed(_:)),
                                               name: NSWindow.willCloseNotification, object: window)
    }
    @objc private func recipientClosed(_ note: Notification) {
        // AppKit may still be reporting a failure or completing the share.
        let current = service
        DispatchQueue.main.async { if self.service === current { self.finish() } }
    }
    private func showShareMenu() {
        guard let view = anchor?.contentView else { finish(); return }
        let menu = NSSharingServicePicker(items: items)
        menu.delegate = self
        picker = menu
        menu.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if service == nil { finish() }
        else { self.service = service; service?.delegate = self }
    }
    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        sharingContentScope.pointee = .item
        return anchor
    }
    func sharingService(_ sharingService: NSSharingService, sourceFrameOnScreenForShareItem item: Any) -> NSRect {
        NSRect(origin: point, size: NSSize(width: 1, height: 1))
    }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish() }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        if (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSUserCancelledError { finish() }
        else { showError(error.localizedDescription) }
    }
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t open AirDrop"
        alert.informativeText = message
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Sharing options…")
        alert.layout()
        place(alert.window)
        if alert.runModal() == .alertSecondButtonReturn { showShareMenu() } else { finish() }
    }
    private func finish() {
        NotificationCenter.default.removeObserver(self)
        service?.delegate = nil
        service = nil
        picker = nil
        recipientWindow = nil
        anchor?.orderOut(nil)
        anchor?.close()
        anchor = nil
        existingWindows.removeAll()
        items = []
    }
}

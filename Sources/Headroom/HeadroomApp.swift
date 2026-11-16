import AppKit
import Observation
import SwiftUI

/// Plain AppKit entry point: a menu bar app with no windows of its own until
/// the panel opens, so no SwiftUI scene can pop up an empty window.
@main
enum HeadroomMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusController?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, even when run outside the app bundle.
        NSApp.setActivationPolicy(.accessory)
        let store = UsageStore()
        status = StatusController(store: store)
        store.start()
    }
}

/// Owns the menu bar item and the drop-down panel.
///
/// A plain NSStatusItem with a fixed autosave name keeps a stable identity, so
/// macOS and menu bar managers (Thaw, Ice, Bartender) remember where it sits.
@MainActor
final class StatusController: NSObject {
    private let store: UsageStore
    private let item: NSStatusItem
    private var panel: PanelWindow?
    private var clickMonitor: Any?
    /// True from open() until close(), including the fade-out, so a click
    /// during an animation never reads a half-closed panel as open.
    private var isOpen = false
    /// When the panel last closed. The click that closes it from outside can
    /// also reach toggle(); within a moment of closing, that click is ignored.
    private var closedAt = Date.distantPast

    init(store: UsageStore) {
        self.store = store
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.autosaveName = "Headroom.StatusItem"
        item.behavior = []
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityTitle("Headroom")
            button.imagePosition = .imageOnly
        }
        render()
        NotificationCenter.default.addObserver(
            self, selector: #selector(layoutChanged), name: .headroomLayoutChanged, object: nil)
        if ProcessInfo.processInfo.environment["HEADROOM_AUTOMATION"] == "1" {
            // Test hook: drive the panel from a script without the mouse or
            // keyboard, e.g. for screenshots and recordings.
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(automation(_:)),
                name: NSNotification.Name("dev.stevmolina.headroom.automation"), object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
    }

    @objc private func appearanceChanged() { drawPill() }

    /// A new layout has a new size: reopen in place so it lands under the pill.
    @objc private func layoutChanged() {
        guard isOpen, let panel else { return }
        let passive = !panel.isKeyWindow
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        isOpen = false
        open(passive: passive)
    }

    /// Redraws the pill whenever the store values it reads change. Only this
    /// function re-arms the observation, so there is exactly one chain.
    private func render() {
        withObservationTracking {
            drawPill()
        } onChange: {
            Task { @MainActor [weak self] in self?.render() }
        }
    }

    private func drawPill() {
        let tight = store.tightest
        let remaining = tight?.row.remaining
        let level = remaining.map(Level.init(remaining:)) ?? .normal
        item.button?.image = PillRenderer.image(remaining: remaining, level: level,
                                                scale: item.button?.window?.screen?.backingScaleFactor ?? 2)
        item.button?.toolTip = tight.map {
            "\(Fmt.percent($0.row.remaining)) left · \($0.group.title) \($0.row.metric)"
        } ?? "Headroom"
        item.button?.setAccessibilityValue(item.button?.toolTip)
    }

    // MARK: Panel

    @objc private func toggle() {
        if isOpen {
            close()
        } else if Date().timeIntervalSince(closedAt) > 0.35 {
            open()
        }
    }

    @objc private func automation(_ note: Notification) {
        guard let command = note.object as? String else { return }
        switch command {
        case "open": if !isOpen { open(passive: true) }
        case "close": close()
        case let c where c.hasPrefix("layout:"):
            if let l = PanelLayout(rawValue: String(c.dropFirst(7))) { store.layout = l }
        default: NotificationCenter.default.post(name: .headroomCommand, object: command)
        }
    }

    /// Opens the panel under the pill. `passive` shows it without taking
    /// keyboard focus from the app in front (used by the automation hook).
    private func open(passive: Bool = false) {
        guard let button = item.button, let buttonWindow = button.window else { return }
        isOpen = true
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let screen = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        // Never taller than the screen can show below the menu bar.
        let wanted = store.layout.size
        let height = min(wanted.height, max(320, screen.height - 16))
        panel.setContentSize(NSSize(width: wanted.width, height: height))
        let size = panel.frame.size
        var buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        // When a menu bar manager or macOS overflow hides the pill, its frame is
        // off screen; drop the panel at the top right, under the clock.
        let inMenuBar = buttonRect.minY >= screen.maxY - 2
            && buttonRect.maxX > screen.minX && buttonRect.minX < screen.maxX
        if !inMenuBar {
            buttonRect = NSRect(x: screen.maxX - size.width / 2 - 8, y: screen.maxY, width: 0, height: 0)
        }
        var x = buttonRect.midX - size.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        let y = max(screen.minY + 4, min(buttonRect.minY, screen.maxY) - size.height - 6)
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        store.panelOpened()
        panel.alphaValue = 0
        if passive {
            panel.orderFrontRegardless()
        } else {
            // A non-activating panel takes keys without pulling focus from
            // the app you were in, so nothing is left stuck when it closes.
            panel.makeKeyAndOrderFront(nil)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }
        item.button?.highlight(true)

        // On macOS 27 the menu bar lives in another process, so a click on the
        // pill also arrives here as an outside click. Leave that one to toggle().
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.mouseIsOverPill else { return }
                self.close()
            }
        }
        NotificationCenter.default.post(name: .headroomPanelOpened, object: nil)
    }

    private func close() {
        guard let panel, isOpen else { return }
        isOpen = false
        closedAt = Date()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        item.button?.highlight(false)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                // A reopen during the fade wins: leave the panel on screen.
                guard !self.isOpen else { return }
                panel.orderOut(nil)
                NotificationCenter.default.post(name: .headroomPanelClosed, object: nil)
            }
        })
    }

    private var mouseIsOverPill: Bool {
        guard let button = item.button, let window = button.window else { return false }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        return rect.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func makePanel() -> PanelWindow {
        let root = PanelView()
            .environment(store)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 620)

        let effect = NSVisualEffectView(frame: hosting.frame)
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.cgColor
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        let panel = PanelWindow(contentRect: hosting.frame)
        panel.contentView = effect
        panel.onEscape = { [weak self] in self?.close() }
        panel.onResignKey = { [weak self] in
            // A click on the pill itself is handled by toggle(); closing here
            // too would let that click reopen the panel straight away.
            guard let self, !self.mouseIsOverPill else { return }
            self.close()
        }
        return panel
    }
}

extension Notification.Name {
    static let headroomPanelOpened = Notification.Name("headroomPanelOpened")
    static let headroomPanelClosed = Notification.Name("headroomPanelClosed")
    /// Automation commands for the panel view: "scroll:sessions", "scroll:top",
    /// "session:<index>", "back".
    static let headroomCommand = Notification.Name("headroomCommand")
    static let headroomLayoutChanged = Notification.Name("headroomLayoutChanged")
}

/// Borderless floating panel with rounded corners and a soft shadow.
final class PanelWindow: NSPanel {
    var onEscape: (() -> Void)?
    var onResignKey: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

@MainActor
enum PillRenderer {
    private static var cache: [String: NSImage] = [:]

    /// Draws ring and number as one image. Template (system-tinted) when the
    /// limit is healthy; amber or red when it is running low.
    static func image(remaining: Double?, level: Level, scale: CGFloat) -> NSImage {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let text = remaining.map { Fmt.percent($0) } ?? "–"
        let key = "\(text)|\(level)|\(Int((remaining ?? 0) * 10))|\(dark)|\(scale)"
        if let hit = cache[key] { return hit }

        let color: Color = switch level {
        case .normal: .black
        case .low: Theme.amber
        case .critical: Theme.red
        }
        let view = HStack(spacing: 4) {
            RingView(fraction: (remaining ?? 0) / 100, color: color, lineWidth: 2)
                .frame(width: 12, height: 12)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(.horizontal, 1)
        .frame(height: 18)
        .environment(\.colorScheme, dark ? .dark : .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = level == .normal
        if cache.count > 64 { cache.removeAll() }
        cache[key] = image
        return image
    }
}


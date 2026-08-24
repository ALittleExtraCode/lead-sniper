import Cocoa

/// A tab that has one obvious thing to do, so Return can do it.
protocol PrimaryAction { func performPrimaryAction() }

/// The window: a tab bar, and one pane under it.
///
/// Deliberately not a split view. SunoGet has a browser on one side and tools on
/// the other, so it needs one. Here there is a single list of leads and the
/// thing you are writing, and putting those side by side at 400pt each makes
/// both too narrow to read a post in.
final class MainController: NSViewController {

    struct Pane {
        let title: String
        let view: NSView
        let onShow: (NSView) -> Void
    }

    private let find = FindTab(frame: .zero)
    private let radar = RadarTab(frame: .zero)
    private let setup = SetupTab(frame: .zero)

    /// Find first, because it is what somebody does first and because the radar
    /// has nothing to show until it has been done once.
    private lazy var panes: [Pane] = [
        Pane(title: L.t(.tabFind), view: find, onShow: { ($0 as? FindTab)?.refresh() }),
        Pane(title: L.t(.tabRadar), view: radar, onShow: { ($0 as? RadarTab)?.refresh() }),
        Pane(title: L.t(.tabSetup), view: setup, onShow: { ($0 as? SetupTab)?.refresh() }),
    ]

    private let tabs = SegmentBar()
    private let container = NSView()
    private var shown: NSView?

    override func loadView() {
        // Find hands over to Radar the moment there is something to sweep.
        find.onReady = { [weak self] in
            self?.show(1)
            self?.radar.beginSweep()
        }

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1080, height: 720))
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.bg.cgColor

        tabs.items = panes.enumerated().map { .init(title: $0.element.title, tag: $0.offset) }
        tabs.target = self
        tabs.action = #selector(tabChanged)
        tabs.translatesAutoresizingMaskIntoConstraints = false

        container.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tabs)
        root.addSubview(container)
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            tabs.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16),
            container.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 12),
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
        show(0)
    }

    @objc private func tabChanged() { show(tabs.selectedTag) }

    private func show(_ index: Int) {
        guard let pane = panes[safe: index] else { return }
        shown?.removeFromSuperview()
        let next = pane.view
        next.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(next)
        NSLayoutConstraint.activate([
            next.topAnchor.constraint(equalTo: container.topAnchor),
            next.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            next.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            next.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        shown = next
        tabs.selectedTag = index
        pane.onShow(next)
    }

    /// For macapp/engine_tests.swift and the render harness.
    var radarForTest: RadarTab { radar }
    var findForTest: FindTab { find }
    func showRadarForTest() { show(1) }

    /// Opens the setup tab, for when the radar has nothing to work with.
    func showSetup() { show(2) }
    func showFind() { show(0) }
    func showRadar() { show(1) }
    func showPane(_ index: Int) { show(index) }

    @objc func performPrimary(_ sender: Any?) {
        (shown as? PrimaryAction)?.performPrimaryAction()
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Application

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let main = MainController()

    func applicationDidFinishLaunching(_ note: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = Build.name
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.bg
        window.appearance = NSAppearance(named: .aqua)
        window.contentViewController = main
        window.contentMinSize = NSSize(width: 880, height: 560)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Menu.install(target: self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    @objc func sweepNow(_ sender: Any?) {
        main.showRadar()
        main.radarForTest.beginSweep()
    }
    @objc func findPlaces(_ sender: Any?) { main.showFind() }
    @objc func showTab(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        main.showPane(item.tag)
    }
    @objc func notRelevant(_ sender: Any?) {
        main.showRadar()
        main.radarForTest.dismissSelected()
    }
    @objc func copyAndOpen(_ sender: Any?) {
        main.showRadar()
        main.radarForTest.copyAndOpenSelected()
    }
    @objc func exportLeads(_ sender: Any?) {
        main.showRadar()
        main.radarForTest.exportSelected()
    }
    @objc func openSetup(_ sender: Any?) { main.showSetup() }
    /// Checks, then says what it found. No modal, no progress bar, no
    /// downloading anything: SunoGet's in-app installer was the single most
    /// troublesome part of that app, and opening the page works.
    @objc func checkForUpdates(_ sender: Any?) {
        Task { @MainActor in
            let answer = await Updates.check()
            let alert = NSAlert()
            alert.alertStyle = .informational
            switch answer {
            case .newer(let version, let url):
                alert.messageText = String(format: L.t(.updateNewer), version)
                alert.runModal()
                NSWorkspace.shared.open(url.deletingLastPathComponent())
                return
            case .upToDate:      alert.messageText = L.t(.updateCurrent)
            case .couldNotReach: alert.messageText = L.t(.updateUnreachable)
            }
            alert.runModal()
        }
    }

    @objc func openSite(_ sender: Any?) {
        NSWorkspace.shared.open(Build.site)
    }
}

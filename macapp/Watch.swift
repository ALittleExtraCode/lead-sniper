import Foundation
import UserNotifications

/// Keeps sweeping while the app is open, and says when something turns up.
///
/// This is the difference between the product working and not working, and the
/// scoring says why: a post is worth 20 points inside the first hour and 3 after
/// a day. A button you press when you remember to look finds leads that are
/// already cold, and somebody else has answered them. So the radar watches, and
/// the customer gets told.
///
/// It is deliberately conservative about telling them. A notification for every
/// warm lead trains people to dismiss notifications, and then the one that
/// mattered gets dismissed too.
@MainActor
final class Watch {

    /// How often a full sweep starts. Not how often a request is made -- one
    /// sweep is several requests, paced by `Radar` against the measured limit.
    enum Interval: Int, CaseIterable {
        case off = 0, tenMinutes = 600, halfHour = 1800, hour = 3600, threeHours = 10_800

        var title: String {
            switch self {
            case .off:        return L.t(.watchOff)
            case .tenMinutes: return L.t(.watchTen)
            case .halfHour:   return L.t(.watchHalf)
            case .hour:       return L.t(.watchHour)
            case .threeHours: return L.t(.watchThree)
            }
        }
    }

    /// Only these get a notification. A lead is not news unless it is both
    /// strong and unseen, and `.hot` starts at 65 -- which needs a title match
    /// or a feature plus real intent, not just a fresh post.
    static let notifyFrom: Score.Verdict.Band = .hot

    private let radar: Radar
    private let workspaces: Workspaces
    private var task: Task<Void, Never>?
    private var offset = 0

    /// Called on the main actor whenever a sweep finishes, so the list updates
    /// itself without the customer pressing anything.
    var onSweep: ((Radar.Sweep) -> Void)?

    private(set) var interval: Interval {
        didSet { UserDefaults.standard.set(interval.rawValue, forKey: Self.key) }
    }
    private static let key = "watchInterval"

    init(radar: Radar, workspaces: Workspaces) {
        self.radar = radar
        self.workspaces = workspaces
        // Half an hour by default rather than off: a radar that is not watching
        // is a button, and the whole point is not having to remember to press it.
        //
        // Checked for presence rather than read straight, because `integer(forKey:)`
        // returns 0 for a missing key and 0 is a real case here -- `.off`. So
        // `Interval(rawValue: saved) ?? .halfHour` could never fall back, and
        // every new install came up not watching, which is the exact failure
        // this whole class exists to prevent.
        if UserDefaults.standard.object(forKey: Self.key) == nil {
            interval = .halfHour
        } else {
            interval = Interval(rawValue: UserDefaults.standard.integer(forKey: Self.key)) ?? .halfHour
        }
    }

    var isRunning: Bool { task != nil }

    func set(_ next: Interval) {
        interval = next
        stop()
        if next != .off { start() }
    }

    func start() {
        guard interval != .off, task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Waits first. Starting with a sweep would fire one every time
                // the app launched or a setting changed, which is both rude to
                // Reddit and a good way to get rate limited on startup.
                try? await Task.sleep(nanoseconds: UInt64(self.interval.rawValue) * 1_000_000_000)
                if Task.isCancelled { return }
                await self.sweepOnce()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// One background sweep.
    func sweepOnce() async {
        guard let workspace = workspaces.active, workspace.isUsable else { return }
        let result = await radar.sweep(workspace, offset: offset)
        offset += Radar.groupSize
        onSweep?(result)
        notify(about: result, workspace: workspace)

        // And into the channel the team is already in. Only the ones worth
        // interrupting for, and only ones not seen before -- a webhook that
        // repeats itself every half hour gets muted, and then it is worth
        // nothing at all.
        let worthSending = result.leads.filter { $0.isNew && $0.verdict.band == Self.notifyFrom }
        if !worthSending.isEmpty, !workspace.webhook.isEmpty {
            _ = await Webhook.send(worthSending, workspace: workspace, to: workspace.webhook)
        }
    }

    // MARK: - Telling somebody

    /// Asks once, and never blocks anything on the answer.
    ///
    /// A refused permission has to leave the radar working exactly as before --
    /// the sweep still runs and the list still fills, the customer just has to
    /// look at the window. Tying the feature to the permission is how an app
    /// ends up nagging.
    static func requestPermission() {
        guard canNotify else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Whether notifications can be touched at all.
    ///
    /// `UNUserNotificationCenter.current()` does not fail politely outside a
    /// bundle -- it raises NSInternalInconsistencyException and takes the
    /// process with it ("bundleProxyForCurrentProcess is nil"). That is every
    /// run of the render harness and every run of a bare executable, and it
    /// happened from inside a view's initialiser, so the whole app died before
    /// drawing anything. The radar does not need notifications to work, so this
    /// is checked rather than assumed.
    static var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    private func notify(about result: Radar.Sweep, workspace: Workspace) {
        guard Self.canNotify else { return }
        let worth = result.leads.filter { $0.isNew && $0.verdict.band == Self.notifyFrom }
        guard !worth.isEmpty else { return }

        let content = UNMutableNotificationContent()
        if worth.count == 1, let one = worth[0] as Radar.Lead? {
            content.title = String(format: L.t(.notifyOne), "r/\(one.post.source)")
            content.body = one.post.title
        } else {
            content.title = String(format: L.t(.notifyMany), "\(worth.count)")
            // The best one by name, because "3 new leads" tells you nothing
            // about whether to stop what you are doing.
            content.body = worth[0].post.title
        }
        content.sound = .default

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "sweep-\(worth[0].post.id)",
                                  content: content, trigger: nil))
    }
}

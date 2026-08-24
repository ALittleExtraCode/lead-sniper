import Foundation

/// What the app has actually been doing.
///
/// The radar sweeps every half hour whether anyone is watching or not, and
/// until now the only evidence was a list that quietly changed. That is a bad
/// bargain: the customer is asked to trust a background process with their rate
/// limit and their reputation, and given nothing to check it against.
///
/// Ported from the Python `Logs` and `Analytics` tabs and merged, because they
/// answer the same question at two zoom levels — what happened just now, and
/// what has happened overall.
///
/// The counts are real. That version's analytics reported "ESTIMATED MONTHLY
/// ORGANIC REACH: ~121,060 impressions/month", which is a number nobody
/// measured, and "Total Hot Leads Captured: 1724" against a leads list showing
/// zero. A number you cannot check is worse than no number.
final class Journal {
    static let shared = Journal()

    enum Kind: String, Codable {
        case swept, found, answered, dismissed, searched, failed, watchChanged
    }

    struct Entry: Codable, Equatable {
        var at: Date
        var kind: Kind
        var text: String
        /// The number that matters for this kind: posts read, leads found.
        var count: Int = 0
    }

    private(set) var entries: [Entry] = []
    private let store: UserDefaults
    private static let key = "journal"
    private static let limit = 500

    /// Called on the main actor when anything is written, so a view showing the
    /// log updates itself rather than needing to be reopened.
    var onWrite: (() -> Void)?

    init(store: UserDefaults = .standard) {
        self.store = store
        if let data = store.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func write(_ kind: Kind, _ text: String, count: Int = 0, at: Date = Date()) {
        entries.insert(Entry(at: at, kind: kind, text: text, count: count), at: 0)
        if entries.count > Self.limit { entries = Array(entries.prefix(Self.limit)) }
        if let data = try? JSONEncoder().encode(entries) { store.set(data, forKey: Self.key) }
        onWrite?()
    }

    func clear() {
        entries.removeAll()
        store.removeObject(forKey: Self.key)
        onWrite?()
    }

    // MARK: - What it adds up to

    /// Counts derived from the log itself, so they cannot disagree with it.
    ///
    /// Nothing here is estimated, projected or extrapolated. Every number is a
    /// count of things that are written down directly above it, and can be
    /// checked by scrolling.
    struct Tally {
        var sweeps = 0
        var postsRead = 0
        var leadsFound = 0
        var answered = 0
        var dismissed = 0
        var searches = 0
        var problems = 0
        var since: Date?

        /// Of the leads found, how many were replied to. The only ratio worth
        /// showing, and only once there is enough to divide.
        var replyRate: Int? {
            guard leadsFound >= 10 else { return nil }
            return Int((Double(answered) / Double(leadsFound) * 100).rounded())
        }
    }

    func tally(since: Date? = nil) -> Tally {
        var out = Tally()
        let wanted = entries.filter { since == nil || $0.at >= since! }
        for entry in wanted {
            switch entry.kind {
            case .swept:    out.sweeps += 1; out.postsRead += entry.count
            case .found:    out.leadsFound += entry.count
            case .answered: out.answered += 1
            case .dismissed: out.dismissed += 1
            case .searched: out.searches += 1
            case .failed:   out.problems += 1
            case .watchChanged: break
            }
        }
        out.since = wanted.last?.at
        return out
    }
}

import Foundation

/// One product being watched for.
///
/// The Python version called these "presets" and shipped three, one of which was
/// SunoGet and two of which were placeholders with `https://yourapp.com` in
/// them. That is a demo, not a product: the thing a customer does first is
/// describe their own product, so that has to be the easy path and everything
/// downstream has to work without knowing anything about what they sell.
///
/// Nothing in here is specific to any product. `Score` and `Draft` read these
/// fields and nothing else.
struct Workspace: Codable, Equatable {
    var id: String
    var name: String
    var url: String
    var summary: String              // one line, in the customer's own words

    /// Communities to watch, without the "r/".
    var communities: [String]

    /// Words that suggest a post is about what this product does.
    var terms: [String]

    /// Words that mean "not this, whatever else matched".
    var negativeTerms: [String]

    /// What the product does, in parts. The matched one is what a draft can
    /// speak to specifically, which is the whole difference between a useful
    /// reply and a generic one.
    var features: [Feature]

    /// Older than this and a thread has been answered without you.
    var maximumAgeInDays: Int

    /// Also search Hacker News for the same terms.
    ///
    /// Off by default and offered rather than assumed: HN is a trickle next to
    /// Reddit -- a niche phrase has a couple of dozen mentions across the site's
    /// whole history -- so for many products it will find nothing and look
    /// broken. For the ones it suits, it finds the people who pay.
    var watchesHackerNews: Bool = false

    /// A Slack or Discord webhook to push hot leads to, or empty.
    ///
    /// Per workspace rather than per app: somebody running two products sends
    /// each one's leads to a different channel, and one shared address would
    /// mean the wrong team getting the wrong leads.
    var webhook: String = ""

    struct Feature: Codable, Equatable {
        var name: String
        var triggers: [String]
        /// What this feature lets someone do, phrased to finish the sentence
        /// "it can ___". The original generated this from a hardcoded list of
        /// SunoGet's own features, so every customer's drafts described audio
        /// mastering. It is a field now, because only the customer knows.
        var doesWhat: String
    }

    // MARK: - Defaults

    /// A new workspace, with nothing invented in it.
    ///
    /// Deliberately empty rather than pre-filled with plausible-looking sample
    /// data. A half-filled form that looks finished is how someone ends up
    /// posting a reply that mentions a feature they do not have.
    static func empty(id: String = UUID().uuidString) -> Workspace {
        Workspace(id: id, name: "", url: "", summary: "",
                  communities: [], terms: [], negativeTerms: defaultNegativeTerms,
                  features: [], maximumAgeInDays: 7, watchesHackerNews: false,
                  webhook: "")
    }

    /// Terms that are a bad idea to answer under any product.
    ///
    /// These are not about relevance. A thread about a scam, a refund dispute or
    /// somebody's medical problem is one where a product mention makes the
    /// person mentioning it look like a ghoul, so the radar declines to surface
    /// them at all rather than leaving it to the customer's judgement at speed.
    static let defaultNegativeTerms = [
        "scam", "scammed", "fraud", "chargeback", "refund", "lawsuit", "sue",
        "stolen", "hacked", "died", "death", "passed away", "cancer", "hospital",
        "suicide", "depressed", "divorce", "laid off", "redundant", "evicted",
    ]

    /// Usable with communities, or with Hacker News, or both -- but always with
    /// terms, since nothing can be judged without them.
    var isUsable: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !terms.isEmpty
            && (!communities.isEmpty || watchesHackerNews)
    }

    /// What is missing, in the order it should be fixed.
    var missing: [String] {
        var gaps: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { gaps.append("a name") }
        if communities.isEmpty && !watchesHackerNews {
            gaps.append("somewhere to watch — communities, or Hacker News")
        }
        if terms.isEmpty { gaps.append("some words to watch for") }
        if url.trimmingCharacters(in: .whitespaces).isEmpty { gaps.append("a link to the product") }
        return gaps
    }
}

/// Every workspace the customer has, and which one is in front of them.
///
/// Shared, not one per tab. Each tab used to build its own, and each loaded
/// UserDefaults once at startup and then held a stale copy: describing a product
/// in Find and switching to Setup showed "Untitled" with every field empty,
/// because Setup's copy had been read before Find wrote anything.
final class Workspaces {
    /// The one the interface uses. Tests pass their own store instead.
    static let shared = Workspaces()

    private(set) var all: [Workspace] = []
    private(set) var activeID: String?

    private let store: UserDefaults
    private static let listKey = "workspaces"
    private static let activeKey = "activeWorkspace"

    init(store: UserDefaults = .standard) {
        self.store = store
        load()
    }

    var active: Workspace? {
        guard let activeID else { return all.first }
        return all.first { $0.id == activeID } ?? all.first
    }

    func activate(_ id: String) {
        guard all.contains(where: { $0.id == id }) else { return }
        activeID = id
        store.set(id, forKey: Self.activeKey)
    }

    @discardableResult
    func save(_ workspace: Workspace) -> Workspace {
        if let index = all.firstIndex(where: { $0.id == workspace.id }) {
            all[index] = workspace
        } else {
            all.append(workspace)
            activeID = workspace.id
            store.set(workspace.id, forKey: Self.activeKey)
        }
        persist()
        return workspace
    }

    func delete(_ id: String) {
        all.removeAll { $0.id == id }
        if activeID == id {
            activeID = all.first?.id
            store.set(activeID, forKey: Self.activeKey)
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(all) else { return }
        store.set(data, forKey: Self.listKey)
    }

    private func load() {
        activeID = store.string(forKey: Self.activeKey)
        guard let data = store.data(forKey: Self.listKey),
              let saved = try? JSONDecoder().decode([Workspace].self, from: data)
        else { return }
        all = saved
    }
}

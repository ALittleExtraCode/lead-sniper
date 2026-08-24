import Foundation

/// Sweeps a workspace's communities, inside the budget the server allows.
///
/// Two measured facts shape all of this:
///
///  1. The budget is about one request per twenty seconds, and it counts
///     requests rather than communities. So communities are combined.
///  2. A combined request returns the newest N posts *overall*. Watching
///     r/SaaS alongside a quiet niche community, 41 of 50 results came back
///     from r/SaaS and three from r/startups. Put everything in one request and
///     the busiest community silently becomes the only one being watched.
///
/// Those pull in opposite directions, so the sweep splits the workspace into
/// small groups and takes one group per request. A twelve-community workspace
/// is three requests, about a minute, and every community actually gets looked
/// at. The alternative -- one request per community -- is twelve requests and
/// four minutes, and spends the whole budget on the same answer.
final class Radar {

    /// Communities per request. Small enough that a busy one cannot crowd out
    /// its group-mates within a 50-post response, large enough that a big
    /// workspace still sweeps in a sensible time.
    static let groupSize = 4

    /// What a sweep found, and what went wrong while finding it.
    struct Sweep {
        var leads: [Lead] = []
        var scanned = 0
        var problems: [String] = []
        var rateLimited = false
        /// Phrases that came up repeatedly and are not being watched for.
        /// Free: these are the posts the sweep already read.
        var overheard: [Scout.Finding] = []
    }

    struct Lead: Equatable, Codable {
        var post: Feed.Post
        var verdict: Score.Verdict
        /// True the first time this post is seen, so the interface can mark it.
        var isNew: Bool
        /// A reply has already been copied for this one.
        var isAnswered: Bool = false
    }

    /// True while a sweep is in flight.
    ///
    /// The guard lives here rather than in the caller because there are two
    /// callers and only one of them had it. Pressing "Sweep now" while the
    /// half-hourly watch fired ran both: they interleaved on `seen`, both
    /// called `remember` so the second overwrote the first, both pushed a list
    /// into the interface so it flickered, and both spent the same rate-limit
    /// budget to fetch the same posts.
    private(set) var isSweeping = false

    private var seen: Set<String> = []

    /// Posts a reply has already been copied for.
    ///
    /// Kept apart from `seen`, because they answer different questions and the
    /// interface needs both. Replying twice to the same person is the mistake
    /// that makes somebody look like exactly the bot this product exists not to
    /// be, and it is easy to make: the same thread comes back in every sweep
    /// for as long as it is on the front page.
    private var answered: Set<String> = []

    private let store: UserDefaults
    private static let seenKey = "seenPosts"
    private static let answeredKey = "answeredPosts"

    init(store: UserDefaults = .standard) {
        self.store = store
        seen = Set(store.stringArray(forKey: Self.seenKey) ?? [])
        answered = Set(store.stringArray(forKey: Self.answeredKey) ?? [])
    }

    /// The last sweep, kept.
    ///
    /// Everything found used to be lost the moment the app closed -- open it
    /// again and the list was empty until the next sweep, which is up to half an
    /// hour away and costs somebody else's rate limit. The leads are the work;
    /// throwing them away on quit is throwing the work away.
    private static let keptKey = "keptLeads"
    private static let keptLimit = 400

    func remember(_ leads: [Lead]) {
        let trimmed = Array(leads.prefix(Self.keptLimit))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        store.set(data, forKey: Self.keptKey)
    }

    /// What was on screen last time, with the answered marks brought up to date
    /// -- those live in their own set and may have moved on since.
    func recall() -> [Lead] {
        guard let data = store.data(forKey: Self.keptKey),
              let saved = try? JSONDecoder().decode([Lead].self, from: data)
        else { return [] }
        return saved.map { lead in
            var updated = lead
            updated.isAnswered = answered.contains(lead.post.id)
            updated.isNew = false        // seen once already, by definition
            return updated
        }
    }

    func forgetKept() { store.removeObject(forKey: Self.keptKey) }

    func markAnswered(_ id: String) {
        answered.insert(id)
        store.set(Array(answered), forKey: Self.answeredKey)
    }

    func hasAnswered(_ id: String) -> Bool { answered.contains(id) }

    /// Splits communities into request-sized groups.
    ///
    /// Rotated by `offset` so that when a sweep is cut short -- rate limited,
    /// cancelled, the app quit -- the next one does not begin with the same
    /// group and leave the tail never scanned.
    static func groups(_ communities: [String], offset: Int = 0) -> [[String]] {
        guard !communities.isEmpty else { return [] }
        let rotation = communities.count
        let start = rotation > 0 ? ((offset % rotation) + rotation) % rotation : 0
        let ordered = Array(communities[start...] + communities[..<start])
        return stride(from: 0, to: ordered.count, by: groupSize).map {
            Array(ordered[$0..<min($0 + groupSize, ordered.count)])
        }
    }

    /// Runs one full sweep.
    ///
    /// `wait` is injected so the suite can run a paced sweep without actually
    /// waiting twenty seconds a group.
    func sweep(_ workspace: Workspace,
               now: Date = Date(),
               offset: Int = 0,
               fetch: ([String]) async -> Feed.Outcome = { await Feed.fetch($0) },
               newsSweep: (Workspace, Date) async -> (posts: [Feed.Post], problems: [String])
                   = { await HackerNews.sweep($0, now: $1) },
               wait: (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
               progress: (Int, Int) -> Void = { _, _ in }
    ) async -> Sweep {
        guard !isSweeping else {
            var busy = Sweep()
            busy.problems.append("a sweep is already running")
            return busy
        }
        isSweeping = true
        defer { isSweeping = false }

        var result = Sweep()
        let batches = Self.groups(workspace.communities, offset: offset)
        guard !batches.isEmpty || workspace.watchesHackerNews else {
            result.problems.append("nowhere to watch")
            return result
        }

        var everything: [Feed.Post] = []

        func consider(_ posts: [Feed.Post]) {
            result.scanned += posts.count
            everything.append(contentsOf: posts)
            for post in posts {
                let verdict = Score.judge(post, against: workspace, now: now)
                guard verdict.isLead else { continue }
                result.leads.append(Lead(post: post, verdict: verdict,
                                         isNew: !seen.contains(post.id),
                                         isAnswered: answered.contains(post.id)))
            }
        }

        // Hacker News first, and without pacing: measured at five rapid
        // requests all answering 200, it has no rate limit worth respecting.
        // Reddit's twenty-second budget is the thing that makes a sweep slow,
        // so anything not subject to it should not wait behind it.
        // Hacker News counts as one step, so the bar does not sit still through
        // it and then leap.
        let steps = batches.count + (workspace.watchesHackerNews ? 1 : 0)
        var doneSteps = 0
        progress(0, steps)

        if workspace.watchesHackerNews {
            let news = await newsSweep(workspace, now)
            doneSteps += 1
            progress(doneSteps, steps)
            consider(news.posts)
            result.problems.append(contentsOf: news.problems)
        }

        for (index, group) in batches.enumerated() {
            if index > 0 { await wait(21) }        // the measured reset, plus a margin

            switch await fetch(group) {
            case .posts(let posts):
                consider(posts)
            case .rateLimited(let after):
                // Floored for the same reason as in Discover: a live 429 said
                // to wait zero seconds, and obeying that is not waiting.
                let pause = max(5, after)
                result.rateLimited = true
                result.problems.append("paused for \(Int(pause))s by Reddit")
                await wait(pause)
            case .notFound:
                result.problems.append("r/\(group.joined(separator: ", r/")) — not found or private")
            case .blocked:
                result.problems.append("Reddit refused the request")
            case .failed(let why):
                result.problems.append(why)
            }
            doneSteps += 1
            progress(doneSteps, steps)
        }

        // Remembered only after the whole sweep, so a run that dies halfway
        // does not mark posts as seen that were never shown to anybody.
        for lead in result.leads { seen.insert(lead.post.id) }
        trimAndPersist()
        result.overheard = Scout.suggestions(Scout.read(everything, against: workspace))

        // Answered ones sink, then unseen ones rise, then by score. Something
        // already replied to is not a lead any more, but it is not deleted
        // either -- seeing it there is how you remember you handled it.
        result.leads.sort { left, right in
            if left.isAnswered != right.isAnswered { return !left.isAnswered }
            if left.isNew != right.isNew { return left.isNew }
            return left.verdict.total > right.verdict.total
        }
        // Saved after the sort, not before. Saving first stored an arbitrary
        // order, so what came back on the next launch was not the list that had
        // been on screen.
        remember(result.leads)
        return result
    }

    /// How long a full sweep of this workspace takes, for the interface to say
    /// so before starting one rather than appearing to hang.
    static func expectedSeconds(for workspace: Workspace) -> Int {
        max(1, groups(workspace.communities).count - 1) * 21
    }

    func forget() {
        seen.removeAll()
        store.removeObject(forKey: Self.seenKey)
    }

    /// Answered posts are kept when everything else is forgotten. Forgetting
    /// what you replied to is the one thing with a real cost attached.
    func forgetAnswered() {
        answered.removeAll()
        store.removeObject(forKey: Self.answeredKey)
    }

    /// Kept bounded. An unbounded set of every post id ever seen grows for as
    /// long as the app is installed, and nothing older than a few sweeps
    /// matters -- the feed only reaches back so far anyway.
    private func trimAndPersist() {
        let limit = 5_000
        if seen.count > limit { seen = Set(seen.suffix(limit)) }
        store.set(Array(seen), forKey: Self.seenKey)
    }
}

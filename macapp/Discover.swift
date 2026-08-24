import Foundation

/// Works out where to watch, from what the product does.
///
/// This is the first half of the job and the half that decides whether the
/// second half works at all. Asking somebody to type in the communities their
/// customers use assumes they already know, and the ones they can name off the
/// top of their head are the big obvious ones where their post will sink.
///
/// The Python original solved this by shipping `subreddit_matrix.py`: 100+
/// subreddits, hand-picked, for one product. That is a good list and it is
/// worth nothing to anybody selling something else.
///
/// This derives it instead. Search Reddit for a phrase the customer's people
/// would use, look at which communities the results actually live in, and count.
/// Measured on the live endpoint, `"batch export"` sorted by relevance returned
/// 97 posts across 68 communities, led by r/premiere, r/blender, r/davinciresolve,
/// r/cubase and r/CapCut -- which is exactly where batch exporting gets
/// discussed, and none of it was known in advance.
enum Discover {

    /// A community the search kept landing in.
    struct Place: Equatable {
        var name: String
        /// How many results came from here. The ranking, and shown as-is so the
        /// customer can judge a weak suggestion for themselves.
        var hits: Int
        /// Which of their words found it, so a surprising suggestion can be
        /// traced back rather than taken on faith.
        var found: [String]
        /// One post title from it, as evidence.
        var example: String
    }

    /// Searches one phrase and reports which communities the results live in.
    ///
    /// `sort=relevance` rather than `new`, and this matters more than it looks:
    /// sorted by new, "batch export music" returned 50 posts spread across
    /// r/textiles, r/vedicastrology and r/FitGirlRepack -- the newest posts that
    /// happened to contain the words. Relevance returns the posts that are
    /// *about* it, and their communities are the answer.
    static func search(_ phrase: String,
                       within: String = "year",
                       session: URLSession = .shared) async -> Feed.Outcome {
        let term = phrase.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return .posts([]) }

        var parts = URLComponents(string: "https://www.reddit.com/search.rss")!
        parts.queryItems = [
            // Quoted, so the words have to appear together. Unquoted, Reddit
            // matches them anywhere and the communities stop meaning anything.
            .init(name: "q", value: "\"\(term)\""),
            .init(name: "sort", value: "relevance"),
            .init(name: "t", value: within),
            .init(name: "limit", value: "100"),
        ]
        guard let url = parts.url else { return .failed("could not build the search") }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(Feed.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/atom+xml, application/xml;q=0.9", forHTTPHeaderField: "Accept")

        await RedditGate.shared.take()

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed("no response") }
            switch http.statusCode {
            case 200: return .posts(Feed.parse(data, source: ""))
            case 429:
                let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(Double.init)
                let pause = max(5, reset ?? 30)
                await RedditGate.shared.slowDown(by: pause)
                return .rateLimited(retryAfter: pause)
            case 403: return .blocked
            default:  return .failed("HTTP \(http.statusCode)")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// How many phrases one run will search.
    ///
    /// Each is a request, and search is subject to the same one-every-twenty-
    /// seconds budget as everything else on Reddit, so six phrases is about two
    /// minutes. That is a long time to sit and watch, which is why `run` reports
    /// as it goes rather than at the end.
    static let maximumPhrases = 6

    /// Searches each phrase, and ranks the communities they land in.
    static func run(phrases: [String],
                    now: Date = Date(),
                    search: (String) async -> Feed.Outcome = { await search($0) },
                    wait: (TimeInterval) async -> Void = {
                        try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
                    progress: (String, [Place]) -> Void = { _, _ in }
    ) async -> (places: [Place], problems: [String]) {
        var counts: [String: Int] = [:]
        var credit: [String: Set<String>] = [:]
        var examples: [String: String] = [:]
        var problems: [String] = []

        let wanted = phrases
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(maximumPhrases)

        for (index, phrase) in wanted.enumerated() {
            // 26 rather than 21. Search is charged more heavily than a feed
            // read: at 21s the second phrase of a live run was refused, found
            // nothing, and was then dropped -- so a third of the search
            // contributed nothing and nobody was told why.
            if index > 0 { await wait(26) }

            var attempts = 0
            while attempts < 2 {
                attempts += 1
                switch await search(phrase) {
                case .posts(let posts):
                    for post in posts where !post.source.isEmpty {
                        counts[post.source, default: 0] += 1
                        credit[post.source, default: []].insert(phrase)
                        if examples[post.source] == nil { examples[post.source] = post.title }
                    }
                case .rateLimited(let after):
                    // Waited out and tried again, once. A refused phrase used to
                    // be abandoned, which quietly halved the search.
                    //
                    // Floored here as well as where the response is parsed. A
                    // live 429 carried "0" in its header, and a zero-length wait
                    // is not a wait -- the retry is refused too and the floor
                    // has to hold wherever the number arrives from.
                    if attempts < 2 {
                        await wait(max(5, after))
                        continue
                    }
                    problems.append("Reddit would not answer for \"\(phrase)\"")
                case .blocked:
                    problems.append("Reddit refused the search")
                case .notFound:
                    break
                case .failed(let why):
                    problems.append(why)
                }
                break
            }
            progress(phrase, ranked(counts, credit, examples))
        }
        return (ranked(counts, credit, examples), problems)
    }

    /// Ordered by how many of the customer's phrases found it first, then by
    /// how often.
    ///
    /// A community found by three different phrases is a better bet than one
    /// found nine times by a single phrase, which is usually a big general
    /// community that contains everything.
    static func ranked(_ counts: [String: Int],
                       _ credit: [String: Set<String>],
                       _ examples: [String: String]) -> [Place] {
        counts.map { name, hits in
            Place(name: name, hits: hits,
                  found: (credit[name] ?? []).sorted(),
                  example: examples[name] ?? "")
        }
        .sorted {
            if $0.found.count != $1.found.count { return $0.found.count > $1.found.count }
            if $0.hits != $1.hits { return $0.hits > $1.hits }
            return $0.name.lowercased() < $1.name.lowercased()
        }
    }

    /// Turns a plain description into phrases worth searching.
    ///
    /// The customer types what their product does in their own words. Searching
    /// that whole sentence finds nothing -- an exact-phrase search for "batch
    /// export my whole music library in one go" has no hits anywhere. Searching
    /// single words finds everything and means nothing: "export" alone returned
    /// trade tariffs.
    ///
    /// Pairs of adjacent words are the useful size. They are specific enough to
    /// land in the right communities and common enough to actually occur.
    static func phrases(from description: String, extra: [String] = []) -> [String] {
        let stop: Set<String> = [
            "a", "an", "the", "and", "or", "for", "to", "of", "in", "on", "with",
            "your", "you", "my", "our", "it", "its", "is", "are", "that", "this",
            // "app", "tool" and "software" are NOT here, deliberately. They are
            // half of how people name what they want -- "budgeting app", "note
            // taking app", "recipe app" are all in the sector corpus. Dropping
            // them turned "communication app for iphone" into the single word
            // "communication", which is too vague to search and threw away the
            // only usable phrase in the sentence.
            "platform", "solution", "helps", "lets",
            "easy", "easily", "simple", "best", "free", "all", "any", "one",
            // Quantifiers and filler. "whole" produced "whole music" from
            // "my whole music library", which found r/Epicthemusical.
            "whole", "entire", "every", "each", "own", "thing", "things", "stuff",
            "lots", "many", "much", "some", "just", "really", "very", "then",
            "go", "get", "make", "made", "using", "use", "used", "into", "from",
            "so", "but", "not", "can", "will", "want", "need", "like", "up", "out",
        ]

        // Split into runs of consecutive kept words, and pair only WITHIN a run.
        //
        // This is the whole fix. Pairing across a dropped word invents phrases
        // nobody wrote: "batch export my whole music library in one go" gave
        // "export whole" and "whole music", because dropping "my" made "export"
        // and "whole" adjacent when they never were. Those two phrases then went
        // on to choose the communities AND become the words the sweep judged
        // against, so one bad bigram poisoned everything downstream -- 50 posts
        // read, 0 leads, from a description that was perfectly clear.
        var runs: [[String]] = [[]]
        for word in description.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted) {
            if word.count > 2 && !stop.contains(word) {
                runs[runs.count - 1].append(word)
            } else if !runs[runs.count - 1].isEmpty {
                runs.append([])
            }
        }

        var pairs: [String] = []
        for run in runs where run.count > 1 {
            for i in 0..<(run.count - 1) {
                pairs.append("\(run[i]) \(run[i + 1])")
            }
        }
        // A single surviving word is still worth searching if it is all there is
        // -- better than nothing from "password manager" typed as one word.
        if pairs.isEmpty, let lone = runs.first(where: { $0.count == 1 })?.first {
            pairs.append(lone)
        }

        // The customer's own phrases first: they thought about these, and a
        // guessed bigram never beats a term somebody chose deliberately.
        var seen = Set<String>()
        return (extra + pairs)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Whether a description is too vague to search for.
    ///
    /// "An app for people to connect" reduces to the single word "people".
    /// Searching Reddit for that returns everything and means nothing, and two
    /// minutes later the customer has a list of communities with no bearing on
    /// their product and no idea why. Better to say so before spending the time.
    ///
    /// The test is whether anything survived as a pair: a pair is a thing people
    /// write, a lone common word is a category.
    static func tooVague(_ phrases: [String]) -> Bool {
        let pairs = phrases.filter { $0.split(separator: " ").count >= 2 }
        return pairs.isEmpty
    }

    /// Roughly how long a run takes, so the interface can say so up front.
    static func expectedSeconds(for phrases: [String]) -> Int {
        max(0, min(phrases.count, maximumPhrases) - 1) * 26
    }

    // MARK: - Elsewhere

    /// Why this is Reddit and Hacker News and not everywhere.
    ///
    /// Worth writing down rather than quietly omitting, because "find me
    /// customers on Twitter and Facebook" is the obvious next question and the
    /// answer is not a technical one:
    ///
    ///   · X/Twitter removed free API access. Search starts at a paid tier, per
    ///     month, per seat, and the terms forbid the kind of monitoring this
    ///     does at the cheaper levels.
    ///   · Facebook and Instagram have no public content search at all. The
    ///     Graph API reaches pages you own and nothing else.
    ///   · LinkedIn has no content search API for third parties.
    ///
    /// So the honest set is the one where the content is genuinely public and
    /// the terms allow reading it. Any product claiming to sweep all four is
    /// either paying thousands a month or scraping in a way that gets the
    /// customer's account closed.
    static let unavailable = ["X/Twitter", "Facebook", "Instagram", "LinkedIn"]
}

import Foundation

/// Hacker News, through the public Algolia index.
///
/// A second source, and a very different one. Measured against the live index:
///
///   five rapid requests ........................ 200, 200, 200, 200, 200
///   one request ................................ 0.50s
///   "batch export" in comments, all time ....... 28 hits
///   the same phrase in the last 48 hours ....... 0 hits
///
/// Two things follow from that. There is no meaningful rate limit, so this can
/// be searched freely where Reddit allows one request every twenty seconds. And
/// the volume is tiny -- a niche phrase has a couple of dozen mentions in the
/// site's entire history -- so searching the last hour finds nothing, ever.
///
/// It is a trickle rather than a firehose, and worth having anyway: the people
/// asking are frequently the ones who will pay.
enum HackerNews {

    /// How far back to look.
    ///
    /// Much wider than the Reddit sweep, for the volume reason above, and
    /// because an HN thread stays worth answering for longer -- comments are
    /// read for days rather than minutes.
    static let window: TimeInterval = 14 * 86_400

    /// Terms searched per sweep.
    ///
    /// One request each, which is fine here, but a workspace can carry thirty
    /// keywords and thirty requests to be polite about is thirty too many. The
    /// first few are the ones the customer thought of first, which are usually
    /// their best.
    static let maximumTerms = 8

    /// Searches one term, as an exact phrase.
    ///
    /// Quoted, because Algolia ANDs loose words and that quietly changes the
    /// question: `batch export` returned 628 hits about anything containing
    /// both words anywhere, while `"batch export"` returned 7 that were about
    /// batch exporting.
    static func search(_ term: String,
                       since: Date,
                       session: URLSession = .shared) async -> Feed.Outcome {
        let phrase = term.trimmingCharacters(in: .whitespaces)
        guard !phrase.isEmpty else { return .posts([]) }

        var parts = URLComponents(string: "https://hn.algolia.com/api/v1/search_by_date")!
        parts.queryItems = [
            .init(name: "query", value: "\"\(phrase)\""),
            .init(name: "tags", value: "(story,comment)"),
            .init(name: "numericFilters", value: "created_at_i>\(Int(since.timeIntervalSince1970))"),
            .init(name: "hitsPerPage", value: "40"),
        ]
        guard let url = parts.url else { return .failed("could not build the query") }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(Feed.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed("no response") }
            switch http.statusCode {
            case 200:  return .posts(parse(data))
            case 429:  return .rateLimited(retryAfter: 60)
            default:   return .failed("HTTP \(http.statusCode)")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Every term the workspace watches, deduplicated.
    static func sweep(_ workspace: Workspace,
                      now: Date = Date(),
                      search: (String, Date) async -> Feed.Outcome = { await search($0, since: $1) }
    ) async -> (posts: [Feed.Post], problems: [String]) {
        let since = now.addingTimeInterval(-window)
        var found: [Feed.Post] = []
        var seen = Set<String>()
        var problems: [String] = []

        for term in workspace.terms.prefix(maximumTerms) {
            switch await search(term, since) {
            case .posts(let posts):
                for post in posts where seen.insert(post.id).inserted {
                    found.append(post)
                }
            case .rateLimited:
                problems.append("Hacker News asked us to slow down")
                return (found, problems)
            case .failed(let why):
                problems.append("Hacker News: \(why)")
            case .notFound, .blocked:
                problems.append("Hacker News refused the request")
            }
        }
        found.sort { $0.posted > $1.posted }
        return (found, problems)
    }

    // MARK: - Parsing

    static func parse(_ data: Data) -> [Feed.Post] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = root["hits"] as? [[String: Any]]
        else { return [] }

        return hits.compactMap { hit in
            guard let id = hit["objectID"] as? String else { return nil }

            // A hit is either a story or a comment on one, and they carry the
            // text under different keys. A comment's own title is its story's,
            // which is the context somebody answering it needs.
            let title = (hit["title"] as? String)
                ?? (hit["story_title"] as? String)
                ?? ""
            let body = plain((hit["comment_text"] as? String)
                ?? (hit["story_text"] as? String) ?? "")
            guard !title.isEmpty || !body.isEmpty else { return nil }

            let seconds = (hit["created_at_i"] as? Double)
                ?? Double(hit["created_at_i"] as? Int ?? 0)

            return Feed.Post(
                id: "hn-\(id)",
                source: "news.ycombinator.com",
                title: title.isEmpty ? String(body.prefix(80)) : title,
                body: body,
                author: hit["author"] as? String ?? "someone",
                // The item, not the linked article: the conversation is the
                // thing being answered.
                link: URL(string: "https://news.ycombinator.com/item?id=\(id)"),
                posted: Date(timeIntervalSince1970: seconds),
                // Site-wide search, no community chosen: one ambiguous word is
                // not evidence here.
                scoped: false)
        }
    }

    /// HN text is HTML with escaped entities, and it uses `&#x27;` rather than
    /// `&apos;`, which a naive decoder leaves sitting in the middle of words.
    static func plain(_ html: String) -> String {
        var s = html
        for tag in ["<p>", "</p>", "<br>", "<br/>", "<i>", "</i>", "<pre>", "</pre>", "<code>", "</code>"] {
            s = s.replacingOccurrences(of: tag, with: " ")
        }
        // Anything else that looks like a tag, removed without a regex so a
        // stray "<" in prose survives -- this is a site about code.
        var out = "", depth = 0
        for ch in s {
            if ch == "<" { depth += 1 }
            else if ch == ">" { if depth > 0 { depth -= 1 } }
            else if depth == 0 { out.append(ch) }
        }
        for (entity, char) in [("&#x27;", "'"), ("&#x2F;", "/"), ("&quot;", "\""),
                               ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                               ("&#38;", "&"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                  .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

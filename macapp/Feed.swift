import Foundation

/// Reads public community feeds, politely.
///
/// The Python original rotated a fake Chrome User-Agent on every request and
/// sold that as "bypasses rate limits & 403 API paywalls". Measured against the
/// live endpoint, that is both wrong and unnecessary:
///
///   no User-Agent at all ......................... HTTP 403
///   an honest identifying User-Agent ............. HTTP 200, 25 entries, 0.48s
///
/// Reddit asks for a User-Agent that says what the client is and who runs it,
/// and it serves the feed happily to one. Pretending to be Chrome buys nothing
/// and puts the customer on the wrong side of a platform they depend on. So the
/// app identifies itself, honestly, every time.
enum Feed {

    /// The form Reddit's own guidance asks for: platform, identifier, version.
    static let userAgent = "macos:com.leadsniper.app:\(Build.version) (by /u/leadsniper)"

    /// One post, as read off a feed. Nothing is scored or judged here -- this is
    /// the raw material, and keeping it separate is what lets the scorer be
    /// tested against fixed input rather than against the internet.
    struct Post: Equatable, Codable {
        var id: String
        var source: String          // "musicproduction", not "r/musicproduction"
        var title: String
        var body: String
        var author: String
        var link: URL?
        var posted: Date

        /// Whether the customer chose where this came from.
        ///
        /// True for a subreddit they picked: inside r/musicproduction, "export"
        /// can only mean one thing, and the choice of community is itself
        /// evidence. False for a site-wide search, where it has to compete with
        /// trade tariffs and everything else the word means. The scorer asks for
        /// more corroboration when this is false.
        var scoped: Bool = true

        /// Title and body together, lower-cased, for matching against.
        var haystack: String { (title + " " + body).lowercased() }
    }

    /// What a fetch produced, including the reasons it produced nothing.
    ///
    /// The original printed a warning and returned an empty list, so a customer
    /// whose feed was rate-limited saw "0 leads" and concluded the product did
    /// not work. Silence and emptiness are different answers and the interface
    /// has to be able to tell them apart.
    enum Outcome: Equatable {
        case posts([Post])
        case rateLimited(retryAfter: TimeInterval)
        case notFound            // the community does not exist, or is private
        case blocked             // 403: usually a missing or refused User-Agent
        case failed(String)

        var posts: [Post] {
            if case .posts(let p) = self { return p }
            return []
        }
    }

    // MARK: - Fetching

    /// Reads the newest posts from one or more communities in a single request.
    ///
    /// Several communities per request is the right call, and it is worth being
    /// precise about why, because the obvious reading of a 429 is wrong.
    /// Measured against the live endpoint:
    ///
    ///   r/a+b+c/new.rss?limit=50, first request .... 200, 50 entries, 108KB
    ///     x-ratelimit-used: 1  remaining: 0.0  reset: 19
    ///   three single-community requests, 3s apart .. 200, then 429, then 429
    ///
    /// The budget is roughly one request per twenty seconds, and it counts
    /// requests, not communities. So combining is not a trick that happens to
    /// work -- it is the only way to cover a whole workspace inside the budget.
    /// The Python original had this right and then undid it: when the combined
    /// request came back empty it fell back to one request per community at 0.5s
    /// intervals, which is a guaranteed 429 and reads to the customer as "the
    /// product does not work".
    static func fetch(_ communities: [String],
                      limit: Int = 50,
                      session: URLSession = .shared) async -> Outcome {
        let names = communities
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "r/ ")) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return .failed("no communities") }
        let joined = names.joined(separator: "+")
        guard let url = URL(string: "https://www.reddit.com/r/\(joined)/new.rss?limit=\(limit)")
        else { return .failed("not a community name") }
        let name = names.count == 1 ? names[0] : ""

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/atom+xml, application/xml;q=0.9", forHTTPHeaderField: "Accept")

        // The budget belongs to the machine, not to this caller.
        await RedditGate.shared.take()

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("no response")
            }
            switch http.statusCode {
            case 200:
                return .posts(parse(data, source: name))
            case 429:
                // Honour the server's own numbers. Guessing is how a client
                // turns a twenty-second pause into a long block. Retry-After
                // first, then the rate-limit reset, then a conservative default.
                let stated = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(Double.init)
                // Floored. The header came back "0" on a live 429, and taking
                // it at its word meant waiting no time at all and being refused
                // again immediately -- which reads to the customer as the
                // product simply not working.
                let pause = max(5, stated ?? reset ?? 30)
                // Everyone waits, not just whoever was refused.
                await RedditGate.shared.slowDown(by: pause)
                return .rateLimited(retryAfter: pause)
            case 403:
                return .blocked
            case 404:
                return .notFound
            default:
                return .failed("HTTP \(http.statusCode)")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Parsing

    /// Atom, parsed with XMLParser rather than a regex.
    ///
    /// The original stripped tags with `re.sub(r'<[^>]+>', ' ', ...)`, which
    /// mangles any post containing a `<` in prose -- and this is a feed of
    /// people writing about code and settings, so that is not a rare case.
    static func parse(_ data: Data, source: String) -> [Post] {
        let reader = AtomReader(source: source)
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.posts
    }

    private final class AtomReader: NSObject, XMLParserDelegate {
        private let source: String
        private(set) var posts: [Post] = []

        private var inEntry = false
        private var path: [String] = []
        private var text = ""
        private var id = "", title = "", body = "", author = "", link: URL?
        private var updated = "", community = ""

        init(source: String) { self.source = source }

        func parser(_ parser: XMLParser, didStartElement name: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String]) {
            path.append(name)
            text = ""
            if name == "entry" {
                inEntry = true
                id = ""; title = ""; body = ""; author = ""; link = nil
                updated = ""; community = ""
            }
            // The permalink is an attribute, not element text.
            if inEntry, name == "link", let href = attributes["href"] {
                link = URL(string: href)
            }
            // When several communities are combined into one request, this is
            // the only thing that says which one an entry came from:
            //   <category term="SaaS" label="r/SaaS"/>
            if inEntry, name == "category", let term = attributes["term"] {
                community = term
            }
        }

        func parser(_ parser: XMLParser, foundCharacters found: String) { text += found }

        // Reddit wraps post bodies in CDATA, which arrives here and not in
        // foundCharacters. Dropping it cost the scorer the whole body of every
        // post, leaving it to judge on titles alone.
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            text += String(data: CDATABlock, encoding: .utf8) ?? ""
        }

        func parser(_ parser: XMLParser, didEndElement name: String,
                    namespaceURI: String?, qualifiedName: String?) {
            defer { path.removeLast(); text = "" }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard inEntry else { return }
            switch name {
            case "id":      id = value.components(separatedBy: "_").last ?? value
            case "title":   title = decoded(value)
            case "updated": updated = value
            case "content": body = plainText(value)
            case "name":
                // Only the author's name; an entry has other <name> elements.
                if path.contains("author") {
                    author = value.replacingOccurrences(of: "/u/", with: "")
                                  .replacingOccurrences(of: "u/", with: "")
                }
            case "entry":
                inEntry = false
                guard !id.isEmpty, !title.isEmpty else { return }
                posts.append(Post(id: id, source: community.isEmpty ? source : community,
                                  title: title, body: body,
                                  author: author.isEmpty ? "someone" : author,
                                  link: link, posted: Self.date(from: updated)))
            default: break
            }
        }

        /// Feed content is HTML inside XML, so it is escaped twice, and the two
        /// layers must be peeled in order.
        ///
        /// Verified against the live endpoint: the raw XML carries
        /// `&lt;div class=&quot;md&quot;&gt;`, so by the time XMLParser hands it
        /// over the *tags* are literal `<div>` while a `<` the person actually
        /// typed is still `&lt;`. Decoding first collapses that distinction and
        /// the tag-stripper then eats from their `<` to the next `>` -- which is
        /// usually the rest of the sentence. Strip the real tags first, decode
        /// after, and "if x < 10 then bail" survives.
        private func plainText(_ html: String) -> String {
            var s = html
            // Block-level tags become spaces so words either side do not fuse.
            for tag in ["</p>", "<br>", "<br/>", "<br />", "</div>", "</li>"] {
                s = s.replacingOccurrences(of: tag, with: " ")
            }
            s = stripTags(s)          // real tags, still literal
            s = decoded(s)            // now the person's own "&lt;" becomes "<"
            return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// Removes tags without a regex, so a bare `<` in prose survives.
        private func stripTags(_ s: String) -> String {
            var out = "", depth = 0
            for ch in s {
                if ch == "<" { depth += 1 }
                else if ch == ">" { if depth > 0 { depth -= 1 } }
                else if depth == 0 { out.append(ch) }
            }
            return out
        }

        private func decoded(_ s: String) -> String {
            guard s.contains("&") else { return s }
            var out = s
            for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                   ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
                                   ("&nbsp;", " "), ("&#32;", " ")] {
                out = out.replacingOccurrences(of: entity, with: char)
            }
            return out
        }

        private static let formatter: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()

        static func date(from iso: String) -> Date {
            formatter.date(from: iso) ?? Date()
        }
    }
}

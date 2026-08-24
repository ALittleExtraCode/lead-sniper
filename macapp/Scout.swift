import Foundation

/// What your communities are actually saying, right now.
///
/// Ported from the Python `keyword_scout.py` and turned round. That version
/// carried a fixed list of twenty terms SunoGet cared about and counted how
/// often each appeared -- which can only ever confirm what you already thought.
/// This reads the words that are there and reports the ones you are *not*
/// watching for, which is the useful direction: the phrase your customers use
/// that never occurred to you is worth more than a tally of the ones that did.
///
/// It costs nothing extra. The sweep has already fetched these posts.
enum Scout {

    struct Finding: Equatable {
        var phrase: String
        var posts: Int
        /// Whether the workspace already watches for this.
        var known: Bool
        /// One title it appeared in, so a suggestion can be judged rather than
        /// taken on trust.
        var example: String
    }

    /// Words too common to mean anything. Not a general stop list -- these are
    /// the ones that survive being paired up and still say nothing.
    static let ignored: Set<String> = [
        "the", "and", "for", "you", "your", "with", "that", "this", "have", "has",
        "was", "are", "not", "but", "all", "any", "can", "get", "got", "how", "why",
        "what", "when", "who", "from", "out", "its", "it's", "into", "just", "like",
        "does", "did", "doing", "been", "being", "will", "would", "could", "should",
        "some", "more", "most", "much", "very", "really", "want", "need", "know",
        "think", "make", "made", "use", "using", "used", "one", "two", "new", "now",
        "then", "than", "there", "their", "they", "them", "about", "after", "before",
        "over", "under", "again", "still", "even", "also", "only", "other", "same",
        "way", "time", "day", "days", "week", "year", "help", "please", "thanks",
        "anyone", "everyone", "something", "anything", "nothing", "someone",
        "http", "https", "www", "com", "org", "net", "reddit", "post", "posts",
        "edit", "update", "sorry", "hey", "hi", "guys", "here", "look", "looking",
    ]

    /// Counts adjacent word pairs across a batch of posts.
    ///
    /// Pairs rather than single words, for the same reason the search uses them:
    /// "export" on its own tells you nothing, "batch export" tells you what
    /// people want. Titles only -- a post body wanders, a title is the thing
    /// somebody chose to say.
    static func read(_ posts: [Feed.Post], against workspace: Workspace,
                     minimum: Int = 2) -> [Finding] {
        var counts: [String: Int] = [:]
        var examples: [String: String] = [:]

        for post in posts {
            let words = post.title
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !ignored.contains($0) }
            guard words.count > 1 else { continue }
            // Deduplicated within a post: a title repeating itself is one post
            // saying a thing, not two.
            var seenHere = Set<String>()
            for i in 0..<(words.count - 1) {
                let pair = "\(words[i]) \(words[i + 1])"
                guard seenHere.insert(pair).inserted else { continue }
                counts[pair, default: 0] += 1
                if examples[pair] == nil { examples[pair] = post.title }
            }
        }

        let watched = Set(workspace.terms.map { $0.lowercased() })
        return counts
            .filter { $0.value >= minimum }
            .map { pair, n in
                Finding(phrase: pair, posts: n,
                        known: watched.contains(pair),
                        example: examples[pair] ?? "")
            }
            // Unknown first, because a phrase you already watch is not news, and
            // the whole point is to surface the ones you missed.
            .sorted {
                if $0.known != $1.known { return !$0.known }
                if $0.posts != $1.posts { return $0.posts > $1.posts }
                return $0.phrase < $1.phrase
            }
    }

    /// The ones worth offering to add.
    static func suggestions(_ findings: [Finding], limit: Int = 12) -> [Finding] {
        Array(findings.filter { !$0.known }.prefix(limit))
    }
}

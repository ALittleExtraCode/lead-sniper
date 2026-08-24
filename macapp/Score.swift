import Foundation

/// Decides whether a post is worth a person's attention, and says why.
///
/// The score is built out of named parts rather than one number, because the
/// number on its own is not useful to anyone. A customer looking at a list of
/// leads needs to know *why* something is at the top before they will trust the
/// order, and when the radar is wrong they need to be able to see which part
/// was wrong and change it. So every point is attributable to a reason, and the
/// reasons are what the interface shows.
///
/// The Python original scored `keywords × 15 + question × 35 + title × 25` and
/// then hardcoded the explanations to one product -- `_generate_action_phrase`
/// returned "batch-export and back up all master audio" for any customer whose
/// feature happened to contain the word "download". Nothing here knows what the
/// product is; it only knows what the workspace told it.
enum Score {

    /// One reason a post scored what it did.
    struct Reason: Equatable, Codable {
        var points: Int
        var label: Label
        var detail: String        // the actual matched text, for the interface

        enum Label: String, Equatable, Codable {
            case asking           // phrased as a question or a request
            case wantsAlternative // already shopping, the strongest signal there is
            case titleMatch       // matched in the title, not buried in the body
            case bodyMatch
            case feature          // matched something the product actually does
            case fresh            // posted recently enough to still be answerable
            case painPoint        // describing a problem rather than a preference
        }
    }

    /// What the radar concluded about one post.
    struct Verdict: Equatable, Codable {
        var total: Int
        var reasons: [Reason]
        var disqualified: DisqualifiedBecause?
        var feature: String?      // the workspace's own feature name, or nil

        var isLead: Bool { disqualified == nil && total >= 25 }

        /// Three bands, because a list sorted by a percentage invites people to
        /// argue with the percentage. Bands invite them to work down the list.
        var band: Band {
            if disqualified != nil { return .skip }
            if total >= 65 { return .hot }
            if total >= 40 { return .warm }
            return .cool
        }

        enum Band: String, Codable { case hot, warm, cool, skip }
    }

    /// Why a post was thrown out. Named, because "0 results" with no explanation
    /// is the thing that makes people distrust a filter and turn it off.
    enum DisqualifiedBecause: Equatable, Codable {
        case negativeTerm(String)
        case ownPromotion         // somebody else advertising: not a lead
        case tooOld(days: Int)
        case nothingMatched
    }

    // MARK: - Signals

    /// Someone asking for something, rather than announcing something.
    ///
    /// Ordered longest-first so "is there a tool that" is not credited twice for
    /// also containing "is there a".
    static let askingPhrases = [
        "does anyone know", "has anyone found", "is there a tool", "is there anything",
        "is there a way", "what do you all use", "what does everyone use", "what do you use",
        "any recommendations", "recommendations for", "looking for a", "looking for an",
        "trying to find", "how do i", "how do you", "how can i", "how to", "any way to",
        "is there a", "is there any", "anyone got", "any suggestions", "need help",
        "help me find", "what should i use", "which one should", "best way to",
        "any tools", "any apps", "any software", "suggestions for", "advice on",
    ]

    /// Actively shopping. Someone comparing options is closer to choosing one
    /// than someone merely describing a problem, so this is weighted hardest.
    static let alternativePhrases = [
        // Every phrase here has to be one that a person only writes when they
        // are choosing between products. "instead of" was in this list and is
        // not: it appears in ordinary prose in roughly every other post.
        "alternative to", "alternatives to", "any alternatives",
        "better than", "cheaper than", "replacement for", "replace",
        "switching from", "switch from", "migrating from", "moving away from",
        "fed up with", "sick of paying", "too expensive", "not worth the price",
        "cancel my subscription", "cancelling my", "worth paying for",
        "free version of", "free alternative", "open source alternative",
        "what do people use instead", "anything better",
    ]

    /// A problem being described. Weaker than asking, but real.
    static let painPhrases = [
        "struggling with", "frustrated", "wasting time", "takes forever",
        "manually", "by hand", "tedious", "painful", "nightmare", "hate having to",
        "keeps breaking", "does not work", "doesn't work", "gave up on", "no idea how",
        "stuck on", "can't figure out", "cannot figure out", "is there really no",
    ]

    /// Somebody else's advertisement. The radar exists to find people who need
    /// something, not other founders posting their launch.
    static let promotionPhrases = [
        "i built", "i made", "i created", "i launched", "just launched", "we launched",
        "check out my", "my new app", "my saas", "introducing", "feedback on my",
        "roast my", "show hn", "just shipped", "we built", "our product",
        "sign up here", "free trial", "discount code", "promo code", "affiliate",
    ]

    // MARK: - Scoring

    /// Scores one post against one workspace.
    ///
    /// `now` is passed in rather than read, so the recency test is testable
    /// against fixed input instead of against whenever the suite happens to run.
    static func judge(_ post: Feed.Post, against workspace: Workspace,
                      now: Date = Date()) -> Verdict {
        let haystack = post.haystack
        let title = post.title.lowercased()

        // 1. Anything the customer has said they never want to see.
        for term in workspace.negativeTerms where !term.isEmpty {
            if contains(haystack, term.lowercased()) {
                return Verdict(total: 0, reasons: [], disqualified: .negativeTerm(term), feature: nil)
            }
        }

        // 2. Somebody else's advert. Checked against the title only: plenty of
        //    genuine questions say "I built a thing and now I need to..." in the
        //    body, and throwing those away loses real leads.
        if let promo = promotionPhrases.first(where: { contains(title, $0) }) {
            return Verdict(total: 0, reasons: [], disqualified: .ownPromotion, feature: nil)
        }

        // 3. Age. A three-day-old thread has been answered by somebody else.
        let age = now.timeIntervalSince(post.posted)
        let days = Int(age / 86_400)
        if days > workspace.maximumAgeInDays {
            return Verdict(total: 0, reasons: [], disqualified: .tooOld(days: days), feature: nil)
        }

        var reasons: [Reason] = []

        // 4. Freshness. Steep, because this is a radar and not an archive: the
        //    value of a lead falls away much faster than linearly.
        let hours = age / 3600
        switch hours {
        case ..<1:  reasons.append(Reason(points: 20, label: .fresh, detail: "within the hour"))
        case ..<6:  reasons.append(Reason(points: 14, label: .fresh, detail: "in the last few hours"))
        case ..<24: reasons.append(Reason(points: 8, label: .fresh, detail: "today"))
        case ..<72: reasons.append(Reason(points: 3, label: .fresh, detail: "this week"))
        default:    break
        }

        // 5. Shopping for something. The single strongest signal.
        if let phrase = alternativePhrases.first(where: { contains(haystack, $0) }) {
            reasons.append(Reason(points: 30, label: .wantsAlternative, detail: phrase))
        }

        // 6. Asking rather than telling.
        if let phrase = askingPhrases.first(where: { contains(haystack, $0) }) {
            let inTitle = contains(title, phrase)
            reasons.append(Reason(points: inTitle ? 25 : 15, label: .asking, detail: phrase))
        }

        // 7. Describing a problem.
        if let phrase = painPhrases.first(where: { contains(haystack, $0) }) {
            reasons.append(Reason(points: 10, label: .painPoint, detail: phrase))
        }

        // 8. The customer's own terms. The title is worth more than the body,
        //    and the count is capped: a post that says "video" nine times is not
        //    nine times the lead, it is one lead about video.
        var titleHits: [String] = [], bodyHits: [String] = []
        for term in workspace.terms where !term.isEmpty {
            let lower = term.lowercased()
            if contains(title, lower) { titleHits.append(term) }
            else if contains(haystack, lower) { bodyHits.append(term) }
        }
        if !titleHits.isEmpty {
            reasons.append(Reason(points: min(30, titleHits.count * 15), label: .titleMatch,
                                  detail: titleHits.prefix(3).joined(separator: ", ")))
        }
        if !bodyHits.isEmpty {
            reasons.append(Reason(points: min(12, bodyHits.count * 4), label: .bodyMatch,
                                  detail: bodyHits.prefix(3).joined(separator: ", ")))
        }

        // 9. Which of the customer's features this is actually about. This is
        //    what the draft needs in order to say something specific.
        var feature: String?
        for candidate in workspace.features {
            if let hit = candidate.triggers.first(where: { contains(haystack, $0.lowercased()) }) {
                feature = candidate.name
                reasons.append(Reason(points: 12, label: .feature, detail: hit))
                break
            }
        }

        // 10. Relevance is a gate, not a contribution.
        //
        // This was scored alongside everything else at first, and measured
        // against 50 real posts it put "How I got 115 signups with $0 ad spend"
        // top of the list for a pricing tool, on 30 points for `wantsAlternative`
        // -- because the body contained the words "instead of". Four of twelve
        // results were real.
        //
        // Asking, shopping and complaining are things people do in every post
        // ever written. They say how ready someone is, not what they are ready
        // about. So a post has to match the customer's own words or one of their
        // features before any of that counts for anything.
        // A title hit or a feature hit is evidence. One stray word in a long
        // body is not -- "trial" appearing once put a post about ad spend into
        // the results for a pricing tool -- so the body has to say it twice.
        //
        // An unscoped source asks for more. Searching Hacker News site-wide for
        // "export" surfaced "Canada will match US tariffs dollar for dollar",
        // which contains the word and means something else entirely. A feature
        // match does not rescue it either: the trigger words are the same
        // ambiguous words. Without a community to narrow the meaning, the match
        // has to be in the title or said more than once.
        let relevant = post.scoped
            ? (!titleHits.isEmpty || feature != nil || bodyHits.count >= 2)
            : (!titleHits.isEmpty || bodyHits.count >= 2)
        guard relevant else {
            return Verdict(total: 0, reasons: reasons, disqualified: .nothingMatched, feature: nil)
        }

        let total = min(100, reasons.reduce(0) { $0 + $1.points })
        return Verdict(total: total, reasons: reasons.sorted { $0.points > $1.points },
                       disqualified: nil, feature: feature)
    }

    /// Whole-word containment.
    ///
    /// Plain substring matching made "ai" match "again", "chain" and "email",
    /// which is most of the words in a technical community. Multi-word phrases
    /// are checked as-is, since their own spaces already bound them.
    static func contains(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        if needle.contains(" ") { return haystack.contains(needle) }

        var search = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: search) {
            let beforeOK = found.lowerBound == haystack.startIndex
                || !isWordCharacter(haystack[haystack.index(before: found.lowerBound)])
            let afterOK = found.upperBound == haystack.endIndex
                || !isWordCharacter(haystack[found.upperBound])
            if beforeOK && afterOK { return true }
            guard found.upperBound < haystack.endIndex else { return false }
            search = found.upperBound..<haystack.endIndex
        }
        return false
    }

    private static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }
}

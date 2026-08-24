import Foundation

/// A starting point for a reply. Never a finished one.
///
/// The Python original filled a template -- "Awesome post u/{author}! If you
/// need to {action_phrase} for \"{title}\", X is completely free at {url}" --
/// and offered one-click copy. Three personas, every matched post, structurally
/// identical every time. That is recognisable on sight, searchable in bulk, and
/// it gets the customer's account banned and their domain blocked sitewide. It
/// also does not work: people can tell.
///
/// What this does instead:
///
///   · writes something specific to the post, or writes nothing
///   · says plainly that the product is the writer's own, because Reddit's
///     self-promotion rules turn on disclosure and because not disclosing is
///     the thing that makes a helpful comment into an advert
///   · refuses to be copied until a human has changed it, which is enforced in
///     `hasBeenEdited` rather than merely suggested in the interface
///
/// It is deliberately a little unfinished. A draft that reads as ready to post
/// will get posted as-is, and then it is a template again.
enum Draft {

    struct Result: Equatable {
        var text: String
        /// What the writer still has to supply. Shown above the editor, because
        /// a draft with a gap in it is a draft somebody reads before sending.
        var gaps: [String]
        /// The exact text handed over, kept so an edit can be detected.
        var original: String

        /// Whether a person has actually written any of this.
        ///
        /// This is the only thing standing between the product and a template
        /// cannon, so it is worth being exact about what it asks.
        ///
        /// It used to count characters that differed, index by index, and that
        /// failed two ways when attacked:
        ///
        ///   · inserting one character at the START shifted every index, so a
        ///     single keystroke registered as a complete rewrite
        ///   · DELETING the bracketed prompt changed 47 characters, cleared the
        ///     bar, and left the untouched template ready to post
        ///
        /// The second one matters most: the gate was passed by removing the very
        /// line telling you to write something. So the question is not "how much
        /// changed" but "how much of this is yours" -- words that were not in
        /// the draft handed over. Deleting cannot satisfy that, and neither can
        /// a keystroke.
        func hasBeenEdited(_ current: String) -> Bool {
            let mine = Result.words(current)
            guard mine.count >= 14 else { return false }   // shorter than a reply
            let given = Set(Result.words(original))
            let ownWords = mine.filter { !given.contains($0) }
            return ownWords.count >= 5
        }

        /// Words, lower-cased, with the bracketed prompt removed.
        ///
        /// The prompt is stripped from both sides so that deleting it neither
        /// helps nor hurts -- it is instruction, not content.
        static func words(_ text: String) -> [String] {
            var stripped = text
            while let open = stripped.firstIndex(of: "["),
                  let close = stripped[open...].firstIndex(of: "]") {
                stripped.removeSubrange(open...close)
            }
            return stripped
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 1 }
        }
    }

    // MARK: - Writing

    /// Openings that acknowledge what was actually asked, without gushing.
    ///
    /// "Awesome post!" is the tell. These are the shapes people use when they
    /// genuinely answer a question, and none of them is a compliment.
    static let openings = [
        "Depends what you are set up with already, but",
        "Not sure this is what you want, but",
        "Might be more than you need, but",
        "For what it is worth,",
        "If you are still looking,",
        "One option, and I should say up front it is mine —",
        "Worth saying I am biased here, but",
    ]

    /// How the writer discloses. Reddit's rules turn on this, and so does
    /// whether the comment reads as help or as an advert.
    static let disclosures = [
        "I built %@, which does exactly this",
        "I make %@, so take this with the appropriate pinch of salt",
        "this is my own thing, %@",
        "%@ is mine, so I would say this",
        "I wrote %@ for this specific problem",
    ]

    /// The gaps the writer has to close themselves. These are not decoration —
    /// they are the parts a template cannot know and a person can.
    static let prompts = [
        "say what they actually asked, in your words",
        "add the one detail that shows you read the post",
        "cut anything that sounds like marketing",
    ]

    /// Writes a draft for one post.
    ///
    /// Returns nil when there is nothing honest to say: no matched feature means
    /// no specific claim can be made, and a reply with no specific claim is an
    /// advert. The interface shows the lead anyway and leaves the writing to the
    /// person, which is the correct outcome.
    static func write(for post: Feed.Post, verdict: Score.Verdict,
                      workspace: Workspace,
                      pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> Result? {
        guard verdict.disqualified == nil else { return nil }
        guard let featureName = verdict.feature,
              let feature = workspace.features.first(where: { $0.name == featureName }),
              !feature.doesWhat.isEmpty
        else { return nil }

        let product = workspace.name.isEmpty ? "it" : workspace.name
        let opening = openings[pick(openings.count)]
        let disclosure = String(format: disclosures[pick(disclosures.count)], product)

        var lines: [String] = []
        lines.append("\(opening) \(disclosure) — it can \(feature.doesWhat).")

        // The link goes on its own line, unwrapped. Not because a bare URL is
        // more persuasive, but because a link buried mid-sentence in a pitch is
        // what people are trained to distrust.
        if !workspace.url.isEmpty {
            lines.append(workspace.url)
        }

        lines.append("")
        lines.append("[\(prompts[pick(prompts.count)])]")

        let text = lines.joined(separator: "\n")
        return Result(text: text,
                      gaps: ["it still reads like a template — say it your way",
                             "delete the bracketed line before posting"],
                      original: text)
    }

    /// Whether a draft is safe to hand over.
    ///
    /// Checked on the way out rather than trusted on the way in: the bracketed
    /// prompt is there to be replaced, and a reply posted with it still in is
    /// worse than no reply at all.
    static func isReadyToPost(_ text: String) -> [String] {
        var problems: [String] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { problems.append("nothing written yet") }
        if trimmed.contains("[") && trimmed.contains("]") {
            problems.append("the bracketed note is still in it")
        }
        if trimmed.count < 40 { problems.append("too short to be worth posting") }
        if trimmed.lowercased().contains("awesome post") {
            problems.append("\"awesome post\" reads as a bot")
        }
        return problems
    }
}

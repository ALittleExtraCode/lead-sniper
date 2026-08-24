import Foundation

var failures = 0
func check(_ passed: Bool, _ what: String) {
    print(passed ? "      ✅ \(what)" : "      ❌ \(what)")
    if !passed { failures += 1 }
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n[1] the feed is read, not guessed at")

let posts = Feed.parse(Fixtures.atomData, source: "")
check(posts.count == 5, "all five entries parsed (\(posts.count))")

// When several communities are combined into one request -- which is the only
// way to stay inside a budget of one request per twenty seconds -- the entry's
// <category term> is the only thing that says where it came from.
let sources = Set(posts.map(\.source))
check(sources == ["musicproduction", "webdev", "SaaS"],
      "each entry knows its own community (\(sources.sorted()))")

check(posts.allSatisfy { !$0.body.isEmpty }, "every post has a body")
check(posts.allSatisfy { $0.link != nil }, "and a link")
check(posts.allSatisfy { $0.author != "someone" }, "and a named author")
check(posts.allSatisfy { !$0.author.contains("/u/") }, "with the /u/ stripped")
check(posts[0].id == "aaa111", "the id is the part after the underscore (\(posts[0].id))")

// The original stripped tags with re.sub(r'<[^>]+>', ' '), which eats from a
// stray "<" to the next ">" -- usually the rest of the sentence. This is a feed
// of people writing about code.
let codePost = posts.first { $0.source == "webdev" }!
check(codePost.body.contains("x < 10"),
      "a \"<\" in prose survives: \"\(codePost.body.prefix(46))\"")
check(codePost.body.contains("choking"), "and so does everything after it")
check(codePost.title.contains("x < 10"), "including in the title (\(codePost.title))")

// Entities are escaped twice in this feed, so one pass leaves "&amp;" visible.
let ampersandPost = posts.first { $0.source == "musicproduction" && $0.title.hasPrefix("Alt") }!
check(ampersandPost.title.contains("export & backup"),
      "double-escaped entities decode fully (\(ampersandPost.title))")
check(!posts.contains { $0.body.contains("<") && $0.source != "webdev" },
      "no markup is left in any body")
check(!posts.contains { $0.body.contains("SC_OFF") }, "and no HTML comments")

// ─────────────────────────────────────────────────────────────────────────────
print("\n[2] a failed fetch says which failure it was")

// The original printed a warning and returned []. A rate-limited customer saw
// "0 leads" and concluded the product was broken.
check(Feed.Outcome.rateLimited(retryAfter: 19).posts.isEmpty, "rate limited carries no posts")
check(Feed.Outcome.posts(posts).posts.count == 5, "and a good fetch carries them")
check(Feed.Outcome.blocked != Feed.Outcome.notFound, "blocked and missing are different answers")

// ─────────────────────────────────────────────────────────────────────────────
print("\n[3] relevance is a gate, not a scoring component")

let workspace = Fixtures.workspace
let verdicts = posts.map { ($0, Score.judge($0, against: workspace, now: Fixtures.now)) }

let asking = verdicts.first { $0.0.id == "aaa111" }!
check(asking.1.isLead, "someone asking for a bulk export is a lead (\(asking.1.total))")
check(asking.1.feature == "Batch export", "matched against the right feature")
check(asking.1.reasons.contains { $0.label == .asking }, "and knows they were asking")

// Measured against 50 real posts, generic intent signals put "How I got 115
// signups with $0 ad spend" top of the list for a pricing tool, on the strength
// of the words "instead of" in its body. Asking, shopping and complaining
// describe readiness, not subject.
let unrelated = verdicts.first { $0.0.id == "bbb222" }!
check(!unrelated.1.isLead, "a parser question is not a lead for an exporter")
check(unrelated.1.disqualified == .nothingMatched, "and says exactly why")

let advert = verdicts.first { $0.0.id == "ccc333" }!
check(advert.1.disqualified == .ownPromotion,
      "somebody else's launch post is not a lead (\(advert.0.title))")

let scam = verdicts.first { $0.0.id == "ddd444" }!
if case .negativeTerm = scam.1.disqualified {} else {
    check(false, "a chargeback thread is refused before it is scored")
}
check(scam.1.disqualified != nil, "a chargeback thread is refused before it is scored")

let shopping = verdicts.first { $0.0.id == "eee555" }!
check(shopping.1.isLead, "somebody shopping for an alternative is a lead")
check(shopping.1.reasons.contains { $0.label == .wantsAlternative },
      "and that is what it says (\(shopping.1.total))")
check(shopping.1.total > asking.1.total || shopping.1.reasons.first?.points ?? 0 >= 25,
      "shopping outranks or matches merely asking")

// ─────────────────────────────────────────────────────────────────────────────
print("\n[4] the score explains itself")

for (post, verdict) in verdicts where verdict.isLead {
    check(!verdict.reasons.isEmpty, "\"\(post.title.prefix(32))\" gives its reasons")
    check(verdict.reasons.allSatisfy { !$0.detail.isEmpty },
          "  each naming the text that matched")
    check(verdict.total == min(100, verdict.reasons.reduce(0) { $0 + $1.points }),
          "  and the total is the sum of them, not a separate number")
    check(verdict.reasons.first!.points >= verdict.reasons.last!.points,
          "  strongest reason first")
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n[5] matching is by word, not by substring")

// Plain containment made "ai" match "again", "chain" and "email" -- most of the
// words in a technical community.
check(!Score.contains("i tried again and again", "ai"), "\"ai\" does not match \"again\"")
check(!Score.contains("send me an email", "ai"), "nor \"email\"")
check(Score.contains("this ai tool is good", "ai"), "but does match \"ai\"")
check(Score.contains("ai, mostly", "ai"), "including before a comma")
check(Score.contains("about ai", "ai"), "and at the end")
check(Score.contains("ai", "ai"), "and on its own")
check(!Score.contains("export", "port"), "\"port\" does not match \"export\"")
check(Score.contains("looking for a tool", "looking for a"), "phrases match as written")

// ─────────────────────────────────────────────────────────────────────────────
print("\n[6] freshness decays, because a cold lead is answered already")

func aged(_ hours: Double) -> Feed.Post {
    Feed.Post(id: "x", source: "musicproduction",
              title: "Any way to bulk download a library?",
              body: "trying to export everything", author: "someone",
              link: nil, posted: Fixtures.now.addingTimeInterval(-hours * 3600))
}
let freshest = Score.judge(aged(0.5), against: workspace, now: Fixtures.now)
let today = Score.judge(aged(12), against: workspace, now: Fixtures.now)
let lastWeek = Score.judge(aged(24 * 6), against: workspace, now: Fixtures.now)
check(freshest.total > today.total, "an hour old beats twelve hours (\(freshest.total) vs \(today.total))")
check(today.total > lastWeek.total, "twelve hours beats six days (\(today.total) vs \(lastWeek.total))")
check(freshest.band == .hot || freshest.band == .warm, "and the freshest one is worth looking at")

let ancient = Score.judge(aged(24 * 30), against: workspace, now: Fixtures.now)
check(ancient.disqualified == .tooOld(days: 30), "a month-old thread is dropped, not ranked")

// ─────────────────────────────────────────────────────────────────────────────
print("\n[7] a workspace knows nothing about any particular product")

var blank = Workspace.empty()
check(!blank.isUsable, "an empty workspace is not usable")
check(blank.missing.contains("a name"), "and says what it needs: \(blank.missing)")
blank.name = "Thing"; blank.communities = ["webdev"]; blank.terms = ["thing"]
check(blank.isUsable, "and becomes usable once told")

// The defaults ship no invented sample data -- a half-filled form that looks
// finished is how somebody posts about a feature they do not have.
check(Workspace.empty().terms.isEmpty, "a new workspace invents no keywords")
check(Workspace.empty().features.isEmpty, "and no features")
check(!Workspace.empty().negativeTerms.isEmpty, "but does refuse the obvious harm")
for term in ["scam", "chargeback", "suicide", "died"] {
    check(Workspace.defaultNegativeTerms.contains(term),
          "  \"\(term)\" is refused by default")
}

let store = UserDefaults(suiteName: "leadsniper.tests")!
store.removePersistentDomain(forName: "leadsniper.tests")
let spaces = Workspaces(store: store)
spaces.save(Fixtures.workspace)
check(Workspaces(store: store).all.count == 1, "a workspace survives a restart")
check(Workspaces(store: store).active?.name == "Batch Exporter", "and is still the active one")
store.removePersistentDomain(forName: "leadsniper.tests")


// ─────────────────────────────────────────────────────────────────────────────
print("\n[8] a draft is a starting point, and will not pretend otherwise")

let leadPost = posts.first { $0.id == "aaa111" }!
let leadVerdict = Score.judge(leadPost, against: workspace, now: Fixtures.now)
let draft = Draft.write(for: leadPost, verdict: leadVerdict, workspace: workspace, pick: { _ in 0 })!

check(draft.text.contains(workspace.url), "the draft carries the link")
check(draft.text.contains("export a whole library in one go"),
      "and says what the matched feature actually does")
check(draft.text.lowercased().contains("mine") || draft.text.lowercased().contains("i built")
      || draft.text.lowercased().contains("i make") || draft.text.lowercased().contains("i wrote"),
      "and discloses that the product is the writer's own")
check(!draft.text.lowercased().contains("awesome post"), "and does not open by gushing")
check(draft.text.contains("[") && draft.text.contains("]"),
      "and leaves a bracketed gap the writer has to close")

// The gate. The original offered one-click copy of a finished template; this
// refuses to be copied until somebody has actually written something.
// Attacked rather than assumed. The first version counted characters that
// differed, index by index, and fell to both of these:
let noBracket = draft.original.components(separatedBy: "\n").dropLast(2).joined(separator: "\n")
check(!draft.hasBeenEdited(draft.original), "an untouched draft is not edited")
check(!draft.hasBeenEdited(draft.original + " "), "nor one with a space added")
check(!draft.hasBeenEdited(draft.original + "!"), "nor one character at the end")
check(!draft.hasBeenEdited("x" + draft.original),
      "nor one character at the START, which shifted every index and read as a rewrite")
check(!draft.hasBeenEdited(noBracket),
      "nor DELETING the prompt line, which used to clear the bar and leave the template postable")
check(!draft.hasBeenEdited("x" + noBracket), "nor both together")
check(!draft.hasBeenEdited(noBracket + " thanks and good luck"),
      "nor four words of padding")
check(!draft.hasBeenEdited("ok"), "nor something too short to be a reply")
let realEdit = "Had this exact problem last year with about 300 tracks. "
             + "I built Batch Exporter for it — it can export a whole library in one go. "
             + workspace.url
check(draft.hasBeenEdited(realEdit), "but a rewritten reply is")

// And it is checked again on the way out.
check(Draft.isReadyToPost(draft.original).contains { $0.contains("bracketed") },
      "posting with the bracket still in is refused")
check(Draft.isReadyToPost(realEdit).isEmpty, "and a real reply passes")
check(!Draft.isReadyToPost("Awesome post! check out my thing at example.com").isEmpty,
      "\"awesome post\" is refused")

// No matched feature means no specific claim can honestly be made, and a reply
// with no specific claim is an advert.
var vague = workspace
vague.features = []
let vagueVerdict = Score.judge(leadPost, against: vague, now: Fixtures.now)
check(Draft.write(for: leadPost, verdict: vagueVerdict, workspace: vague, pick: { _ in 0 }) == nil,
      "with nothing specific to say, it writes nothing")

// Two drafts for the same post must not be the same text.
var texts = Set<String>()
for i in 0..<7 {
    if let d = Draft.write(for: leadPost, verdict: leadVerdict, workspace: workspace, pick: { i % $0 }) {
        texts.insert(d.text)
    }
}
check(texts.count >= 4, "drafts vary between posts (\(texts.count) of 7 distinct)")

// ─────────────────────────────────────────────────────────────────────────────
print("\n[9] the sweep covers every community, not just the loudest")

// A combined request returns the newest N overall: measured on the live feed,
// 41 of 50 came from r/SaaS and 3 from r/startups. Putting everything in one
// request quietly makes the busiest community the only one watched.
let twelve = (1...12).map { "community\($0)" }
let batched = Radar.groups(twelve)
check(batched.count == 3, "twelve communities become three requests (\(batched.count))")
check(batched.flatMap { $0 }.sorted() == twelve.sorted(), "and every one is included")
check(batched.allSatisfy { $0.count <= Radar.groupSize }, "none over the group size")

// A sweep that is cut short must not restart on the same group forever.
let firstRun = Radar.groups(twelve, offset: 0).first!
let secondRun = Radar.groups(twelve, offset: 4).first!
check(firstRun != secondRun, "a later sweep starts somewhere else (\(secondRun))")
check(Radar.groups([], offset: 3).isEmpty, "and no communities is not a crash")
check(Radar.groups(["one"], offset: 99).count == 1, "nor is an offset past the end")

let store2 = UserDefaults(suiteName: "leadsniper.tests.radar")!
store2.removePersistentDomain(forName: "leadsniper.tests.radar")
let radar = Radar(store: store2)

var requested: [[String]] = []
var waited: [TimeInterval] = []
let swept = await radar.sweep(Fixtures.workspace, now: Fixtures.now,
    fetch: { group in
        requested.append(group)
        return .posts(Feed.parse(Fixtures.atomData, source: ""))
    },
    wait: { waited.append($0) })

check(requested.count == 1, "three communities are one request (\(requested.count))")
check(waited.isEmpty, "and a single request waits for nothing")
check(swept.leads.allSatisfy { $0.isNew }, "everything is new the first time")
check(!swept.leads.isEmpty, "and the sweep found leads (\(swept.leads.count))")

// Seen posts persist, so the second sweep can mark what is genuinely new.
let radar2 = Radar(store: store2)
let again = await radar2.sweep(Fixtures.workspace, now: Fixtures.now,
    fetch: { _ in .posts(Feed.parse(Fixtures.atomData, source: "")) },
    wait: { _ in })
check(again.leads.allSatisfy { !$0.isNew }, "and nothing is new the second time")

// A rate limit is reported, not swallowed. The original printed a warning and
// returned [], so a throttled customer saw "0 leads" and blamed the product.
let limited = await radar2.sweep(Fixtures.workspace, now: Fixtures.now,
    fetch: { _ in .rateLimited(retryAfter: 19) }, wait: { _ in })
check(limited.rateLimited, "a rate limit is reported as a rate limit")
check(limited.problems.contains { $0.contains("19") }, "with the server's own number: \(limited.problems)")
check(limited.leads.isEmpty, "and no leads are invented")

let broken = await radar2.sweep(Fixtures.workspace, now: Fixtures.now,
    fetch: { _ in .notFound }, wait: { _ in })
check(broken.problems.contains { $0.contains("not found") }, "a missing community says so")
store2.removePersistentDomain(forName: "leadsniper.tests.radar")


// ─────────────────────────────────────────────────────────────────────────────
print("\n[10] replying twice is the mistake worth preventing")

let store3 = UserDefaults(suiteName: "leadsniper.tests.answered")!
store3.removePersistentDomain(forName: "leadsniper.tests.answered")
let tracked = Radar(store: store3)

let firstPass = await tracked.sweep(Fixtures.workspace, now: Fixtures.now,
    fetch: { _ in .posts(Feed.parse(Fixtures.atomData, source: "")) }, wait: { _ in })
check(firstPass.leads.allSatisfy { !$0.isAnswered }, "nothing is answered to begin with")

let answeredID = firstPass.leads[0].post.id
tracked.markAnswered(answeredID)
check(tracked.hasAnswered(answeredID), "copying a reply records it")

// The same thread comes back in every sweep while it is on the front page.
let secondPass = await tracked.sweep(Fixtures.workspace, now: Fixtures.now,
    fetch: { _ in .posts(Feed.parse(Fixtures.atomData, source: "")) }, wait: { _ in })
let sameLead = secondPass.leads.first { $0.post.id == answeredID }
check(sameLead?.isAnswered == true, "and it comes back marked, not clean")
check(secondPass.leads.last?.post.id == answeredID,
      "answered ones sink to the bottom rather than vanishing")

// It survives a restart. Forgetting what you replied to has a real cost, so it
// is kept even when the seen list is cleared.
let restarted = Radar(store: store3)
check(restarted.hasAnswered(answeredID), "and survives a restart")
restarted.forget()
check(restarted.hasAnswered(answeredID), "and survives forgetting what was seen")
restarted.forgetAnswered()
check(!restarted.hasAnswered(answeredID), "but can be cleared deliberately")
store3.removePersistentDomain(forName: "leadsniper.tests.answered")

// ─────────────────────────────────────────────────────────────────────────────
print("\n[11] the updater only ever points at our own site")

check(Updates.trusted(URL(string: "https://leadsniper.com/dist/LeadSniper.dmg")!),
      "our own https link is followed")
check(Updates.trusted(URL(string: "https://www.leadsniper.com/dist/x.dmg")!),
      "and a subdomain of it")
check(!Updates.trusted(URL(string: "http://leadsniper.com/dist/x.dmg")!),
      "plain http is refused")
check(!Updates.trusted(URL(string: "https://leadsniper.com.evil.test/x.dmg")!),
      "and a lookalike domain is refused")
check(!Updates.trusted(URL(string: "https://example.com/x.dmg")!), "and anywhere else")
check(!Updates.trusted(URL(string: "file:///tmp/x.dmg")!), "and a local file")

// The version comes off the network and ends up on screen.
check(Updates.plausible("1.4"), "\"1.4\" is a version")
check(Updates.plausible("0.1"), "so is \"0.1\"")
check(!Updates.plausible(""), "an empty string is not")
check(!Updates.plausible("1.4-beta"), "nor one with words in it")
check(!Updates.plausible(String(repeating: "9.", count: 40)), "nor an absurdly long one")
check(!Updates.plausible(".5"), "nor one starting with a dot")

// String comparison puts 1.10 before 1.9, which is backwards.
check(Updates.isNewer("1.10", than: "1.9"), "1.10 is newer than 1.9")
check(Updates.isNewer("2.0", than: "1.99"), "2.0 is newer than 1.99")
check(Updates.isNewer("0.2", than: "0.1"), "0.2 is newer than 0.1")
check(!Updates.isNewer("1.4", than: "1.4"), "the same version is not newer")
check(!Updates.isNewer("1.3", than: "1.4"), "and an older one is not")
check(!Updates.isNewer("1.4", than: "1.4.1"), "nor a shorter prefix of a newer one")

// ─────────────────────────────────────────────────────────────────────────────
print("\n[12] the watch only interrupts for something worth interrupting for")

check(Watch.notifyFrom == .hot,
      "only hot leads raise a notification, so the alerts stay worth reading")
check(Watch.Interval.allCases.contains(.off), "and it can be turned off entirely")

// A fresh install must come up watching. `integer(forKey:)` returns 0 for a
// missing key and 0 is a real case here (.off), so the intended default could
// never fall back and every new install came up not watching.
let fresh = UserDefaults(suiteName: "leadsniper.tests.watch")!
fresh.removePersistentDomain(forName: "leadsniper.tests.watch")
check(fresh.object(forKey: "watchInterval") == nil, "nothing saved on a fresh install")
check(Watch.Interval(rawValue: fresh.integer(forKey: "watchInterval")) == .off,
      "and reading it straight gives .off, which is the trap")
fresh.set(Watch.Interval.off.rawValue, forKey: "watchInterval")
check(fresh.object(forKey: "watchInterval") != nil,
      "while a deliberate .off is distinguishable from nothing at all")
fresh.removePersistentDomain(forName: "leadsniper.tests.watch")
check(Watch.Interval(rawValue: 0) == .off, "off is off")
check(Watch.Interval.tenMinutes.rawValue == 600, "ten minutes is ten minutes")
check(Watch.Interval.allCases.allSatisfy { !$0.title.isEmpty }, "every interval has a name")

// UNUserNotificationCenter.current() raises NSInternalInconsistencyException
// outside a bundle rather than failing politely, and it was being called from a
// view's initialiser -- so the process died before drawing anything. This suite
// runs outside a bundle, so reaching here at all is the check.
check(!Watch.canNotify, "notifications are known to be unavailable outside a bundle")
Watch.requestPermission()
check(true, "and asking for permission anyway does not take the process down")

// A sweep takes longer than you would think, and the interface says so before
// starting one rather than appearing to hang.
var big = Fixtures.workspace
big.communities = (1...12).map { "c\($0)" }
check(Radar.expectedSeconds(for: big) == 42,
      "twelve communities take about \(Radar.expectedSeconds(for: big))s")
check(Radar.expectedSeconds(for: Fixtures.workspace) < 22,
      "and three take one request")
// Every interval has to be longer than the sweep it starts, or sweeps overlap.
for option in Watch.Interval.allCases where option != .off {
    check(option.rawValue > Radar.expectedSeconds(for: big),
          "\(option.title) leaves room for a full sweep")
}


// ─────────────────────────────────────────────────────────────────────────────
print("\n[13] finding where to watch, from what the product does")

// A whole sentence has no exact-phrase hits anywhere; single words find
// everything and mean nothing ("export" alone returned trade tariffs). Pairs of
// adjacent words are the size that works.
let derived = Discover.phrases(from: "batch export my whole music library in one go")
check(derived.contains("batch export"), "\"batch export\" comes out of a plain description")
check(derived.contains("music library"), "and so does \"music library\"")
check(!derived.contains { $0.split(separator: " ").count > 2 }, "nothing longer than a pair")
check(!derived.contains { $0.contains(" the ") || $0.hasPrefix("the ") },
      "and the filler words are dropped")
check(Discover.phrases(from: "").isEmpty, "an empty description gives nothing")
check(Discover.phrases(from: "the and or for").isEmpty, "and so does one that is all filler")

// The customer's own words go first: they thought about those.
let withOwn = Discover.phrases(from: "password manager", extra: ["self-hosted vault"])
check(withOwn.first == "self-hosted vault", "a phrase they chose outranks a guessed one")

// Ranking: found by three phrases beats found nine times by one, which is
// usually a big general community that contains everything.
let ranked = Discover.ranked(
    ["broad": 9, "narrow": 3],
    ["broad": ["one"], "narrow": ["one", "two", "three"]],
    ["broad": "x", "narrow": "y"])
check(ranked.first?.name == "narrow",
      "three phrases finding it beats one phrase finding it nine times")

// A live run's second phrase was refused, returned nothing and was dropped, so
// a third of the search silently contributed nothing.
var asked: [String] = []
var waits: [TimeInterval] = []
var refuseOnce = true
let run = await Discover.run(
    phrases: ["batch export", "music library", "bulk download"],
    search: { phrase in
        asked.append(phrase)
        if phrase == "music library", refuseOnce {
            refuseOnce = false
            return .rateLimited(retryAfter: 0)      // exactly what the live 429 said
        }
        return .posts([Feed.Post(id: "p-\(phrase)", source: "somewhere",
                                 title: "about \(phrase)", body: "", author: "a",
                                 link: nil, posted: Fixtures.now)])
    },
    wait: { waits.append($0) })
check(asked.filter { $0 == "music library" }.count == 2, "a refused phrase is tried again")
check(run.places.contains { $0.found.contains("music library") },
      "so its results are not lost")
check(run.problems.isEmpty, "and nothing is reported as a problem")
check(waits.allSatisfy { $0 > 0 }, "no zero-length wait: the 429 header said 0 and meant it")
check(waits.contains { $0 >= 26 }, "phrases are spaced further apart than a feed read")


// ─────────────────────────────────────────────────────────────────────────────
print("\n[14] the sector phrases are the size that was measured to work")

check(Sectors.all.count >= 30, "enough sectors to cover a small product (\(Sectors.all.count))")
check(Sectors.all.allSatisfy { $0.phrases.count >= 5 }, "each with a usable list")

var tooShort: [String] = [], tooLong: [String] = [], shouty: [String] = []
var everyPhrase: [String] = []
for sector in Sectors.all {
    for phrase in sector.phrases {
        everyPhrase.append(phrase)
        let words = phrase.split(separator: " ").count
        // "export" found 20,907 posts and matched trade tariffs. "batch export
        // my whole music library in one go" found nothing anywhere. Two or three
        // is the size that returns posts about the thing.
        if words < 2 { tooShort.append("\(sector.name)/\(phrase)") }
        if words > 3 { tooLong.append("\(sector.name)/\(phrase)") }
        if phrase != phrase.lowercased() { shouty.append(phrase) }
    }
}
check(tooShort.isEmpty, "nothing is one word (\(tooShort.prefix(3)))")
check(tooLong.isEmpty, "nothing is four or more (\(tooLong.prefix(3)))")
check(shouty.isEmpty, "all lower case, as a search wants (\(shouty.prefix(3)))")
check(everyPhrase.allSatisfy { !$0.contains("\"") && !$0.contains(",") },
      "and none carries punctuation that would break the quoted search")

// Marketing language finds nothing, because nobody writes it in a post.
let marketing = ["streamline", "leverage", "seamless", "boost", "robust", "solution",
                 "cutting edge", "best in class", "end to end"]
let salesy = everyPhrase.filter { p in marketing.contains { p.contains($0) } }
check(salesy.isEmpty, "no marketing language (\(salesy.prefix(3)))")

// Half of a good list is what goes wrong, because that is what a lead sounds
// like. "print keeps failing" is a person; "3D printing software" is a category.
// This list started out tech-only -- crash, error, failed -- and six sectors
// failed the check while being perfectly good: "getting sued", "volunteer
// burnout", "toddler tantrums", "leads falling through", "keep procrastinating".
// A problem does not have to be a stack trace.
let troubleWords = ["keeps", "keep ", "crash", "broke", "failed", "failing", "lost",
                    "stopped", "wrong", "slow", "error", "issues", "not ", "cannot",
                    "too ", "chasing", "missed", "forever", "surprise", "corrupted",
                    "drains", "hit a", "got ", "no ", "low ", "angry", "dropped",
                    "clogged", "burnout", "tantrum", "sued", "sue", "afford",
                    "stuck", "bad ", "duplicate", "manual", "falling through",
                    "picky", "wakings", "are down", "backlog", "suspended",
                    "plateau", "ghosted", "turnover", "shifting", "dispute",
                    "eviction", "unpaid", "late payments", "screen time",
                    "procrastinating", "forgetting", "is it normal", "how to"]
let withTrouble = Sectors.all.filter { sector in
    sector.phrases.contains { p in troubleWords.contains { p.contains($0) } }
}
check(withTrouble.count >= Sectors.all.count - 1,
      "\(withTrouble.count)/\(Sectors.all.count) sectors include what goes wrong, not just what it is")

// Duplicates across sectors are fine and expected -- "self hosted" belongs to
// several -- but a sector repeating itself is a shorter list than it looks.
for sector in Sectors.all {
    check(Set(sector.phrases).count == sector.phrases.count,
          "\(sector.name) has no repeats")
}

// And they have to survive the same route a typed description takes.
for sector in Sectors.all.prefix(6) {
    let asTyped = Discover.phrases(from: "", extra: sector.phrases)
    check(asTyped.count == sector.phrases.count,
          "\(sector.name) phrases pass through unchanged")
}


// ─────────────────────────────────────────────────────────────────────────────
print("\n[15] one workspace store, not one per tab")

// Each tab built its own, and each read UserDefaults once at startup and then
// held a stale copy: describing a product in Find and switching to Setup showed
// "Untitled" with every field empty.
let sharedStore = UserDefaults(suiteName: "leadsniper.tests.shared")!
sharedStore.removePersistentDomain(forName: "leadsniper.tests.shared")
let one = Workspaces(store: sharedStore)
let two = Workspaces(store: sharedStore)
one.save(Fixtures.workspace)
check(one.all.count == 1, "a save lands in the store it was made on")
check(two.all.isEmpty, "and a separate instance cannot see it — which was the bug")
check(Workspaces.shared === Workspaces.shared, "so the interface shares exactly one")
sharedStore.removePersistentDomain(forName: "leadsniper.tests.shared")

// ─────────────────────────────────────────────────────────────────────────────
print("\n[16] the leads survive a quit")

let keepStore = UserDefaults(suiteName: "leadsniper.tests.keep")!
keepStore.removePersistentDomain(forName: "leadsniper.tests.keep")
let keeper = Radar(store: keepStore)
let found = await keeper.sweep(Fixtures.workspace, now: Fixtures.now,
    fetch: { _ in .posts(Feed.parse(Fixtures.atomData, source: "")) }, wait: { _ in })
check(!found.leads.isEmpty, "a sweep found something (\(found.leads.count))")

// Everything found used to be lost on close: reopening showed an empty list
// until the next sweep, up to half an hour and somebody else's rate limit away.
let reopened = Radar(store: keepStore)
let restored = reopened.recall()
check(restored.count == found.leads.count, "and it is all still there after a restart")
check(restored.allSatisfy { !$0.isNew }, "marked as already seen, because it was")
check(restored.first?.post.title == found.leads.first?.post.title, "in the same order")
check(restored.first?.verdict.reasons.isEmpty == false, "with the reasons intact")

// The answered marks live in their own set and may have moved on since.
reopened.markAnswered(restored[0].post.id)
let afterAnswering = Radar(store: keepStore).recall()
check(afterAnswering.first?.isAnswered == true, "an answer made since is reflected")
keepStore.removePersistentDomain(forName: "leadsniper.tests.keep")

// ─────────────────────────────────────────────────────────────────────────────
print("\n[17] the scout reports what you are NOT watching for")

// keyword_scout.py counted how often each of twenty hardcoded terms appeared,
// which can only confirm what you already thought. Turned round: the phrase
// your customers use that never occurred to you is the valuable one.
let heard = Feed.parse(Fixtures.atomData, source: "")
    + (1...4).map { i in
        Feed.Post(id: "extra-\(i)", source: "musicproduction",
                  title: "Stem separation keeps failing on long tracks",
                  body: "", author: "a", link: nil, posted: Fixtures.now)
    }
let findings = Scout.read(heard, against: Fixtures.workspace)
check(!findings.isEmpty, "it hears something (\(findings.count) phrases)")
check(findings.allSatisfy { $0.posts >= 2 }, "and only what was said more than once")
check(findings.allSatisfy { $0.phrase.split(separator: " ").count == 2 },
      "as pairs, the size that is searchable")
check(findings.first?.known == false, "unknown phrases come first, because those are the news")
check(findings.contains { $0.phrase == "stem separation" },
      "a repeated phrase is picked up: \(findings.prefix(3).map(\.phrase))")
check(findings.allSatisfy { !Scout.ignored.contains($0.phrase.split(separator: " ").map(String.init)[0]) },
      "and filler words are not offered as insights")
check(findings.allSatisfy { !$0.example.isEmpty }, "each with a real title as evidence")

// A phrase already being watched is not a suggestion.
var watching = Fixtures.workspace
watching.terms = ["stem separation"]
let already = Scout.read(heard, against: watching)
check(already.first { $0.phrase == "stem separation" }?.known == true,
      "a watched phrase is marked as known")
check(!Scout.suggestions(already).contains { $0.phrase == "stem separation" },
      "and is not offered again")
check(Scout.read([], against: Fixtures.workspace).isEmpty, "no posts, no findings")


// ─────────────────────────────────────────────────────────────────────────────
print("\n[18] one Reddit budget, shared by everything that uses it")

// The sweep paced itself and the search paced itself, and neither knew the
// other existed. Two callers each spacing their own requests twenty seconds
// apart still put two requests into the same twenty-second window.
await RedditGate.shared.reset()
let firstSlot = Date()
await RedditGate.shared.take()
check(Date().timeIntervalSince(firstSlot) < 1, "the first caller goes straight through")

let queued = await RedditGate.shared.queued()
check(queued > 15, "and the next one is made to wait (\(Int(queued))s)")

// A refusal has to teach everybody, not just whoever was refused.
await RedditGate.shared.reset()
await RedditGate.shared.slowDown(by: 45)
let afterBackoff = await RedditGate.shared.queued()
check(afterBackoff > 40, "a 429 pushes the whole queue back (\(Int(afterBackoff))s)")

// A server saying "wait zero seconds" is not a reason to wait zero seconds.
await RedditGate.shared.reset()
await RedditGate.shared.slowDown(by: 0)
let floored = await RedditGate.shared.queued()
check(floored >= 4, "and a zero-length back-off is floored (\(Int(floored))s)")
await RedditGate.shared.reset()


// ─────────────────────────────────────────────────────────────────────────────
print("\n[19] the phrases do not invent things nobody wrote")

// Pairing across a dropped stop word invented phrases: "batch export my whole
// music library in one go" gave "export whole" and "whole music", because
// dropping "my" made two words adjacent that never were. Those phrases then
// chose the communities AND became the terms the sweep judged against, so one
// bad bigram poisoned everything downstream — 50 posts read, 0 leads.
let clean = Discover.phrases(from: "batch export my whole music library in one go")
check(clean.contains("batch export"), "the real phrase survives")
check(clean.contains("music library"), "and so does the other one")
check(!clean.contains("export whole"), "\"export whole\" is not invented across the dropped \"my\"")
check(!clean.contains("whole music"), "nor \"whole music\", which found r/Epicthemusical")
check(clean.count == 2, "only what was actually written (\(clean))")

let hosted = Discover.phrases(from: "a self hosted password manager for small teams")
check(hosted.contains("password manager"), "\"password manager\" survives")
check(hosted.contains("small teams"), "and \"small teams\"")
check(!hosted.contains("manager small"), "but not across the dropped \"for\"")

// A description too vague to search is refused before two minutes are spent.
// "app", "tool" and "software" are half of how people name what they want, and
// dropping them as filler threw away the only usable phrase in the sentence:
// "communication app for iphone" became the lone word "communication".
check(Discover.phrases(from: "communication app for iphone") == ["communication app"],
      "\"communication app\" survives (\(Discover.phrases(from: "communication app for iphone")))")
check(Discover.phrases(from: "budgeting app") == ["budgeting app"], "and \"budgeting app\"")
check(!Discover.tooVague(Discover.phrases(from: "communication app for iphone")),
      "so it is searchable rather than refused")

check(Discover.tooVague(Discover.phrases(from: "an app for people to connect")),
      "\"an app for people to connect\" is too vague — it reduces to one word")
check(Discover.tooVague(["people"]), "a lone word is too vague")
check(!Discover.tooVague(["batch export"]), "a pair is not")
check(!Discover.tooVague(["people", "video editor"]), "nor a mix containing one")

// A one-word description still yields something rather than nothing.
check(!Discover.phrases(from: "spreadsheets").isEmpty, "a single word is not discarded")


// ─────────────────────────────────────────────────────────────────────────────
print("\n[20] a workspace can be handed to somebody else")

let exported = try! Share.export(Fixtures.workspace)
let reimported = try! Share.importPreset(exported)
check(reimported.name == Fixtures.workspace.name, "a round trip keeps the name")
check(reimported.communities == Fixtures.workspace.communities, "and the communities")
check(reimported.terms == Fixtures.workspace.terms, "and the words watched for")
check(reimported.features.count == Fixtures.workspace.features.count, "and the features")
check(reimported.id != Fixtures.workspace.id,
      "but takes a new id, so importing a colleague's file does not overwrite yours")

// A file that imports into an unusable state is worse than one that fails: the
// customer ends up on the Radar wondering why nothing happens.
var incomplete = Fixtures.workspace
incomplete.communities = []; incomplete.watchesHackerNews = false
let brokenData = try! Share.export(incomplete)
do {
    _ = try Share.importPreset(brokenData)
    check(false, "an unusable workspace is refused")
} catch Share.ImportProblem.unusable(let missing) {
    check(!missing.isEmpty, "an unusable workspace is refused, saying what is missing: \(missing)")
} catch { check(false, "refused for the wrong reason") }

do {
    _ = try Share.importPreset(Data("{\"hello\":1}".utf8))
    check(false, "a foreign JSON file is refused")
} catch Share.ImportProblem.notLeadSniper {
    check(true, "a foreign JSON file is refused")
} catch { check(false, "refused for the wrong reason") }
do {
    _ = try Share.importPreset(Data("not json at all".utf8))
    check(false, "and so is something that is not JSON")
} catch { check(true, "and so is something that is not JSON") }

// ─────────────────────────────────────────────────────────────────────────────
print("\n[21] the CSV survives real Reddit titles")

// Titles contain commas, quotation marks and newlines as a matter of course,
// and a naive join shifts the columns for exactly the rows somebody cares about.
let nasty = Radar.Lead(
    post: Feed.Post(id: "n1", source: "musicproduction",
                    title: "Help, my \"batch export\" is broken\nand slow",
                    body: "", author: "someone", link: URL(string: "https://x.test/a"),
                    posted: Fixtures.now),
    verdict: Score.judge(Feed.Post(id: "n1", source: "musicproduction",
                                   title: "Any way to bulk download a library?",
                                   body: "export batch", author: "a", link: nil,
                                   posted: Fixtures.now),
                         against: Fixtures.workspace, now: Fixtures.now),
    isNew: true)
let sheet = Share.csv([nasty])
let rows = sheet.split(separator: "\n")
check(rows.count == 2, "one header and one row, despite the newline in the title (\(rows.count))")
check(sheet.contains("\"\"batch export\"\""), "quotation marks are doubled, as CSV requires")
check(!sheet.contains("broken\nand"), "and the newline inside the title is flattened")
check(rows[0].hasPrefix("band,score,community"), "the header names the columns")
check(sheet.contains("https://x.test/a"), "the link is there to click")

check(Share.field("plain") == "plain", "a plain value is not quoted needlessly")
check(Share.field("a,b") == "\"a,b\"", "a comma forces quoting")
check(Share.field("say \"this\"") == "\"say \"\"this\"\"\"", "and quotes are escaped")

check(Share.filename(for: Fixtures.workspace, extension: "csv", on: Fixtures.now)
        == "batch-exporter-2026-08-23.csv",
      "the filename is safe and dated (\(Share.filename(for: Fixtures.workspace, extension: "csv", on: Fixtures.now)))")

// ─────────────────────────────────────────────────────────────────────────────
print("\n[22] the webhook only ever posts where it was told to")

// A webhook URL grants write access to somebody's channel and is typed in by
// hand from a clipboard. A mistyped one must fail here, not post the team's
// leads to whatever host was in the paste buffer.
check(Webhook.trusted(URL(string: "https://hooks.slack.com/services/T/B/x")!), "Slack is allowed")
check(Webhook.trusted(URL(string: "https://discord.com/api/webhooks/1/x")!), "Discord is allowed")
check(!Webhook.trusted(URL(string: "http://hooks.slack.com/services/T/B/x")!), "but not over plain http")
check(!Webhook.trusted(URL(string: "https://hooks.slack.com.evil.test/x")!), "nor a lookalike host")
check(!Webhook.trusted(URL(string: "https://example.com/hook")!), "nor anywhere else")

let hot = Radar.Lead(
    post: Feed.Post(id: "h", source: "musicproduction", title: "Bulk export tool?",
                    body: "", author: "someone", link: URL(string: "https://r.test/1"),
                    posted: Fixtures.now),
    verdict: Score.judge(posts[0], against: Fixtures.workspace, now: Fixtures.now),
    isNew: true)
let note = Webhook.message(for: [hot], workspace: Fixtures.workspace)
check(note.contains("Bulk export tool?"), "the message names the post")
check(note.contains("https://r.test/1"), "and carries the link on its own line")
check(note.contains("r/musicproduction"), "and says where it came from")
check(note.contains("Batch Exporter"), "and which product it is for")
check(Webhook.message(for: [], workspace: Fixtures.workspace).isEmpty, "nothing to say, nothing sent")

let many = Array(repeating: hot, count: 9)
let long = Webhook.message(for: many, workspace: Fixtures.workspace)
check(long.contains("and 4 more in the app"),
      "a long list is cut short rather than filling the channel")

let unset = await Webhook.send([hot], workspace: Fixtures.workspace, to: "")
check(unset == .notConfigured, "an empty address sends nothing")
let wrong = await Webhook.send([hot], workspace: Fixtures.workspace, to: "https://example.com/x")
if case .failed = wrong { check(true, "a foreign address is refused before any request") }
else { check(false, "a foreign address is refused before any request") }


// ─────────────────────────────────────────────────────────────────────────────
print("\n[23] the one real secret is not stored as a preference")

// A Slack webhook URL grants write access to a channel. It was being written
// into UserDefaults -- a plain plist any process running as this user can read
// -- and into the export file people send each other.
let hookID = "test-workspace-\(Int(Fixtures.now.timeIntervalSince1970))"
Secret.remove(for: hookID)
check(Secret.read(for: hookID).isEmpty, "nothing stored to begin with")
Secret.save("https://hooks.slack.com/services/T/B/secret", for: hookID)
check(Secret.read(for: hookID) == "https://hooks.slack.com/services/T/B/secret",
      "it goes in and comes back")
Secret.save("https://hooks.slack.com/services/T/B/changed", for: hookID)
check(Secret.read(for: hookID).hasSuffix("changed"), "and can be replaced, not duplicated")
Secret.save("", for: hookID)
check(Secret.read(for: hookID).isEmpty, "clearing it removes it")
Secret.remove(for: hookID)

// The exported file must not carry it, because that file gets emailed.
var withHook = Fixtures.workspace
withHook.id = hookID
withHook.webhook = "https://hooks.slack.com/services/T/B/private"
let shared = String(data: try! Share.export(withHook), encoding: .utf8)!
check(!shared.contains("hooks.slack.com"), "an exported workspace carries no webhook address")
check(!shared.contains("private"), "nor any part of it")
check(shared.contains("hasWebhook"), "only the fact that one is set")
Secret.remove(for: hookID)

// ─────────────────────────────────────────────────────────────────────────────
print("\n[24] two sweeps cannot run at once")

// The manual sweep had a guard and the half-hourly watch did not, so pressing
// "Sweep now" as the timer fired ran both: they interleaved on the seen set,
// both saved so the second overwrote the first, both pushed a list into the
// interface, and both spent the same rate-limit budget on the same posts.
let busyStore = UserDefaults(suiteName: "leadsniper.tests.busy")!
busyStore.removePersistentDomain(forName: "leadsniper.tests.busy")
let busyRadar = Radar(store: busyStore)
check(!busyRadar.isSweeping, "idle to begin with")

var sawBusy = false
async let firstSweep = busyRadar.sweep(Fixtures.workspace, now: Fixtures.now,
    fetch: { _ in
        // While this one is mid-flight, a second caller tries to start.
        sawBusy = busyRadar.isSweeping
        return .posts(Feed.parse(Fixtures.atomData, source: ""))
    }, wait: { _ in })
let firstResult = await firstSweep
check(sawBusy, "a sweep reports itself as running while it runs")
check(!busyRadar.isSweeping, "and idle again afterwards")
check(!firstResult.leads.isEmpty, "the one that got in did its work")

// A second, started while the first holds the flag, is turned away rather than
// interleaving.
busyRadar.forgetKept()
let held = Radar(store: busyStore)
async let a = held.sweep(Fixtures.workspace, now: Fixtures.now,
    fetch: { _ in
        try? await Task.sleep(nanoseconds: 40_000_000)
        return .posts(Feed.parse(Fixtures.atomData, source: ""))
    }, wait: { _ in })
try? await Task.sleep(nanoseconds: 5_000_000)
let b = await held.sweep(Fixtures.workspace, now: Fixtures.now,
    fetch: { _ in .posts(Feed.parse(Fixtures.atomData, source: "")) }, wait: { _ in })
let aResult = await a
check(!aResult.leads.isEmpty, "the first sweep completes")
check(b.leads.isEmpty && b.problems.contains { $0.contains("already running") },
      "and the second is turned away, saying so: \(b.problems)")
busyStore.removePersistentDomain(forName: "leadsniper.tests.busy")


// ─────────────────────────────────────────────────────────────────────────────
print("\n[25] hostile and malformed input is survived, not trusted")

// A feed is somebody else's data. None of this can crash, and none of it can
// put a megabyte into a table row.
let huge = String(repeating: "export ", count: 1500)
let hostile = """
<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom">
<entry><id>t3_a</id><title>\(huge)</title><category term="x"/>
<updated>2026-08-23T21:00:00+00:00</updated>
<content type="html">\(huge)\(huge)</content></entry>
</feed>
"""
let capped = Feed.parse(Data(hostile.utf8), source: "x")
check(capped.count == 1, "a 10,000-character post still parses")
check(capped[0].title.count <= 400, "the title is capped (\(capped[0].title.count))")
check(capped[0].body.count <= 4_000, "and so is the body (\(capped[0].body.count))")

for (name, data) in [("empty", Data()), ("not xml", Data("hello".utf8)),
                     ("truncated", Data("<feed><entry><title>x".utf8))] {
    check(Feed.parse(data, source: "s").isEmpty, "\(name) input yields nothing rather than crashing")
}
for (name, data) in [("empty", Data()), ("html", Data("<html>".utf8)),
                     ("wrong shape", Data("{\"hits\":\"nope\"}".utf8))] {
    check(HackerNews.parse(data).isEmpty, "malformed HN JSON (\(name)) yields nothing")
}

// Terms are matched by string range, not regex, so a metacharacter in somebody's
// keyword is a keyword rather than a syntax error or a runaway pattern.
var meta = Workspace.empty(id: "meta")
meta.name = "T"; meta.communities = ["x"]
meta.terms = ["c++", "a.b", "(paren)", "[bracket]", "$dollar", "back\\slash"]
for term in meta.terms {
    let post = Feed.Post(id: "m", source: "x", title: "I use \(term) daily",
                         body: "", author: "a", link: nil, posted: Fixtures.now)
    let verdict = Score.judge(post, against: meta, now: Fixtures.now)
    check(verdict.reasons.contains { $0.label == .titleMatch },
          "\"\(term)\" is matched as text, not as a pattern")
}

// Empty and whitespace-only posts are judged, not crashed on.
for (name, title, body) in [("empty", "", ""), ("whitespace", "   ", "\n\t"),
                            ("emoji", "🎧🎛️", "🎵")] {
    let post = Feed.Post(id: "e", source: "x", title: title, body: body,
                         author: "a", link: nil, posted: Fixtures.now)
    let verdict = Score.judge(post, against: Fixtures.workspace, now: Fixtures.now)
    check(!verdict.isLead, "\(name) content is not a lead")
    check(Draft.write(for: post, verdict: verdict, workspace: Fixtures.workspace) == nil,
          "  and nothing is drafted for it")
}


// ─────────────────────────────────────────────────────────────────────────────
print("\n[26] the list takes no for an answer")

// Without this a thread you read and rejected comes back in the next sweep, and
// the one after, for as long as it is on the front page — so working down a
// list of twenty means rejecting the same six every half hour.
let noStore = UserDefaults(suiteName: "leadsniper.tests.no")!
noStore.removePersistentDomain(forName: "leadsniper.tests.no")
let judge = Radar(store: noStore)

let sweptOnce = await judge.sweep(Fixtures.workspace, now: Fixtures.now,
    fetch: { _ in .posts(Feed.parse(Fixtures.atomData, source: "")) }, wait: { _ in })
check(sweptOnce.leads.allSatisfy { !$0.isDismissed }, "nothing is dismissed to begin with")

let rejected = sweptOnce.leads[0].post.id
judge.dismiss(rejected)
check(judge.hasDismissed(rejected), "saying no is recorded")

let sweptAgain = await judge.sweep(Fixtures.workspace, now: Fixtures.now,
    fetch: { _ in .posts(Feed.parse(Fixtures.atomData, source: "")) }, wait: { _ in })
let cameBack = sweptAgain.leads.first { $0.post.id == rejected }
check(cameBack?.isDismissed == true, "and it comes back marked rather than clean")
check(sweptAgain.leads.last?.post.id == rejected,
      "sinking to the bottom rather than vanishing, so a mistake is still visible")

// Reversible: a keystroke that cannot be undone is one people are careful with,
// and careful is slow.
judge.restore(rejected)
check(!judge.hasDismissed(rejected), "and it can be put back")

// It survives a restart, and is separate from having answered.
judge.dismiss(rejected)
let reopened2 = Radar(store: noStore)
check(reopened2.hasDismissed(rejected), "the decision survives a restart")
check(!reopened2.hasAnswered(rejected), "and is not confused with having replied")
check(reopened2.recall().first { $0.post.id == rejected }?.isDismissed == true,
      "a restored list remembers it too")

// Dismissed sinks below answered, which sinks below live leads.
var mixed = sweptAgain.leads
if mixed.count >= 2 {
    judge.markAnswered(mixed[1].post.id)
    let ordered = await judge.sweep(Fixtures.workspace, now: Fixtures.now,
        fetch: { _ in .posts(Feed.parse(Fixtures.atomData, source: "")) }, wait: { _ in })
    let live = ordered.leads.filter { !$0.isAnswered && !$0.isDismissed }
    let done = ordered.leads.filter { $0.isAnswered && !$0.isDismissed }
    let gone = ordered.leads.filter { $0.isDismissed }
    let order = live.map { _ in 0 } + done.map { _ in 1 } + gone.map { _ in 2 }
    check(order == order.sorted(), "live, then answered, then not-relevant")
}
noStore.removePersistentDomain(forName: "leadsniper.tests.no")

print(failures == 0 ? "\nAll engine tests passed." : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)

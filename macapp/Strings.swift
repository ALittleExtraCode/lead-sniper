import Foundation

/// The interface, in words.
///
/// A flat table rather than a .strings bundle, for the same reason SunoGet uses
/// one: the app is built by `swiftc` from a file list with no resource step, so
/// anything living in .lproj folders would not survive the build. English only
/// for now, and structured so the other languages drop in without touching a
/// call site.
enum L {
    enum Key {
        case tabRadar, tabSetup
        case sweep, sweeping, sweepingLong, watching, readyToSweep
        case needsSetup, needsSetupLong
        case foundLeads, ofWhichNew, nothingFound, nothingFoundLong
        case thePost, whyItMatched, yourReply
        case copyAndOpen, justOpen, mustEdit, readyToPost, noDraftPossible
        case bandHot, bandWarm, bandCool
        case reasonAsking, reasonShopping, reasonTitle, reasonBody
        case reasonFeature, reasonFresh, reasonPain
        case justNow, minutesAgo, hoursAgo, daysAgo
        case product, newProduct, newProductHint, untitled, aboutProduct
        case fieldName, hintName, fieldUrl, hintUrl, fieldSummary, hintSummary
        case whereToWatch, fieldCommunities, hintCommunities
        case fieldTerms, hintTerms, fieldNegative, hintNegative
        case whatItDoes, hintFeatures, addFeature
        case featureName, featureTriggers, featureDoes
        case save, stillNeeds, savedWatching, noFeaturesYet
        case menuFile, menuEdit, menuHelp, menuSweep, menuSetup, menuSite
        case menuUndo, menuRedo, menuCut, menuCopy, menuPaste, menuSelectAll
        case menuAbout, menuHide, menuHideOthers, menuQuit
        case watchOff, watchTen, watchHalf, watchHour, watchThree
        case watching2, watchingLabel, notifyOne, notifyMany
        case answered, alreadyAnswered, markUnanswered
        case menuCheckUpdates, updateNewer, updateCurrent, updateUnreachable
        case alsoHackerNews, hintHackerNews
        case tabFind, whatYouMake, whatDoesItDo, hintWhatDoesItDo
        case whatIsItCalled, hintWhatIsItCalled, findPlaces, describeItFirst
        case searchingFor, findingTakes, searchedSoFar, whereTheyTalk
        case nothingFoundYet, foundNowhere, foundPlaces, foundByHits
        case watchThese, nowWatching, whereItCannotLook, notElsewhere
        case pickSector, orPickSector, theseWillBeSearched, willTake
        case fromLastTime, alsoSaying, tooVague
        case fieldWebhook, hintWebhook
        case exportPreset, importPreset, exported, imported, saveFirst
        case notAPreset, presetTooNew, presetUnusable
        case exportLeads, exportedLeads, nothingToExport
        case nextCheckMinutes, nextCheckSeconds, checkingNow
        case notRelevant, putBack, dismissed, dismissedNote, keyboardHint
        case rejectedPattern
    }

    static func t(_ key: Key) -> String { english[key] ?? "" }

    private static let english: [Key: String] = [
        .tabRadar: "Radar",
        .tabSetup: "Setup",

        .sweep: "Sweep now",
        .sweeping: "Reading the feeds…",
        .sweepingLong: "Reading the feeds — about %@ seconds, because Reddit allows one request every twenty",
        .watching: "Watching %@ communities for %@",
        .readyToSweep: "Nothing read yet.\nSweep to see what people are asking about right now.",

        .needsSetup: "Start in Find",
        .needsSetupLong: "Nothing to watch for yet.\nGo to Find, say what you have made, and let it work out which communities to watch.",

        .foundLeads: "%@ worth answering, out of %@ posts read",
        .ofWhichNew: "%@ you have not seen",
        .nothingFound: "nothing matched, out of %@ posts read",
        .nothingFoundLong: "Read %@ posts and none of them were about your product.\nThat is usually the right answer. If it keeps happening, widen the words you watch for in Setup.",

        .thePost: "THE POST",
        .whyItMatched: "WHY IT MATCHED",
        .yourReply: "YOUR REPLY",

        .copyAndOpen: "Copy and open thread",
        .justOpen: "Open thread",
        .mustEdit: "Write it in your own words before you can copy it. A reply that could have been sent to anybody gets your account banned, and people can tell.",
        .readyToPost: "Ready. It will be copied and the thread opened.",
        .noDraftPossible: "Nothing specific to say about this one — it matched your words but none of your features. Worth answering only if you can help without mentioning the product.",

        .bandHot: "HOT",
        .bandWarm: "WARM",
        .bandCool: "COOL",

        .reasonAsking: "asking",
        .reasonShopping: "shopping",
        .reasonTitle: "in the title",
        .reasonBody: "in the post",
        .reasonFeature: "your feature",
        .reasonFresh: "posted",
        .reasonPain: "frustrated",

        .justNow: "just now",
        .minutesAgo: "%@m ago",
        .hoursAgo: "%@h ago",
        .daysAgo: "%@d ago",

        .product: "PRODUCT",
        .newProduct: "New product",
        .newProductHint: "Describe the new one, then save.",
        .untitled: "Untitled",
        .aboutProduct: "ABOUT IT",

        .fieldName: "Name",
        .hintName: "What you call it. This is what goes in a reply when you disclose that it is yours.",
        .fieldUrl: "Link",
        .hintUrl: "Where it lives. Drafts put this on its own line rather than buried in a sentence.",
        .fieldSummary: "In one line",
        .hintSummary: "What it does, as you would say it to somebody in a pub. Not a tagline.",

        .whereToWatch: "WHERE TO WATCH",
        .fieldCommunities: "Communities",
        .hintCommunities: "Subreddits, comma separated, without the r/. Watch the places your customers already talk, not the biggest ones.",
        .fieldTerms: "Words to watch for",
        .hintTerms: "The words someone would use describing the problem you solve — in their language, not your feature names. These decide everything: a post has to match one of these or a feature before anything else counts.",
        .fieldNegative: "Never show me",
        .hintNegative: "Words that mean skip it whatever else matched. The defaults refuse chargebacks, lawsuits and bereavements, because a product mention in one of those makes you look like a ghoul.",

        .whatItDoes: "WHAT IT DOES",
        .hintFeatures: "One row per thing it does. The trigger words are how a post is matched to it, and \"it can…\" is what a draft will actually say — so write that as a plain claim you could defend.",
        .addFeature: "Add a feature",
        .featureName: "Feature",
        .featureTriggers: "trigger words, comma separated",
        .featureDoes: "it can…",

        .save: "Save",
        .stillNeeds: "Still needs %@",
        .savedWatching: "Saved. Watching %@ communities for %@ words.",
        .noFeaturesYet: "no features yet, so it will find leads but not draft anything",

        .menuFile: "File",
        .menuEdit: "Edit",
        .menuHelp: "Help",
        .menuSweep: "Sweep Now",
        .menuSetup: "Setup",
        .menuSite: "LeadSniper Website",
        .menuUndo: "Undo",
        .menuRedo: "Redo",
        .menuCut: "Cut",
        .menuCopy: "Copy",
        .menuPaste: "Paste",
        .menuSelectAll: "Select All",
        .menuAbout: "About LeadSniper",
        .menuHide: "Hide LeadSniper",
        .menuHideOthers: "Hide Others",
        .menuQuit: "Quit LeadSniper",

        .watchOff: "Only when I ask",
        .watchTen: "Every 10 minutes",
        .watchHalf: "Every half hour",
        .watchHour: "Every hour",
        .watchThree: "Every 3 hours",
        .watchingLabel: "Check for me",
        .watching2: "Watching. A lead is worth most in its first hour, so leaving this on is the point of the thing.",
        .notifyOne: "Someone in %@ is asking",
        .notifyMany: "%@ new leads worth answering",

        .answered: "ANSWERED",
        .alreadyAnswered: "You have already copied a reply for this one. The same thread comes back every sweep while it is on the front page — replying twice is what makes somebody look like a bot.",
        .markUnanswered: "Mark as unanswered",

        .menuCheckUpdates: "Check for Updates",
        .updateNewer: "Version %@ is out. Opening the download page.",
        .updateCurrent: "This is the newest version.",
        .updateUnreachable: "Could not reach leadsniper.com just now.",

        .alsoHackerNews: "Also search Hacker News",
        .tabFind: "Find",
        .whatYouMake: "WHAT YOU MAKE",
        .whatDoesItDo: "What does it do?",
        .hintWhatDoesItDo: "In your own words, the way you would say it to somebody in a pub. Pairs of words out of this are what gets searched — \"batch export\", \"password manager\" — so plain beats polished. A tagline finds nothing.",
        .whatIsItCalled: "What is it called?",
        .hintWhatIsItCalled: "Used when a draft discloses that the product is yours.",
        .findPlaces: "Find where they talk",
        .describeItFirst: "Say what it does first.",
        .searchingFor: "Searching for %@",
        .fieldWebhook: "Send hot leads to Slack or Discord",
        .hintWebhook: "A webhook address, if you want the good ones pushed into a channel. A lead is worth most in its first hour and nobody watches an app window all day. Only HOT leads, only ones not sent before — a webhook that repeats itself gets muted. Leave empty for none.",

        .exportPreset: "Export",
        .importPreset: "Import",
        .exported: "Saved as %@. Send it to anyone with LeadSniper.",
        .imported: "Imported %@ — watching %@ communities.",
        .saveFirst: "Save it first, then it can be exported.",
        .notAPreset: "That is not a LeadSniper workspace file.",
        .presetTooNew: "That file was made by a newer version (%@). Update LeadSniper first.",
        .presetUnusable: "That file is missing %@, so it would import into something that cannot sweep.",

        .rejectedPattern: "The ones you have rejected keep saying %@ — add those to \"Never show me\" in Setup and they will stop appearing.",
        .notRelevant: "Not relevant (D)",
        .putBack: "Put back (U)",
        .dismissed: "NOT RELEVANT",
        .dismissedNote: "Set aside. It will keep appearing in sweeps — the thread is still on the front page — but it stays marked and stays at the bottom. Press U to put it back.",
        .keyboardHint: "↑↓ to move · D not relevant · Return to open the thread",

        .nextCheckMinutes: "next in %@ min",
        .nextCheckSeconds: "next in %@s",
        .checkingNow: "checking…",

        .exportLeads: "Export CSV",
        .exportedLeads: "%@ leads written to %@.",
        .nothingToExport: "Nothing to export yet — sweep first.",

        .tooVague: "That is too vague to search for. Say what it actually does — \"batch export\", \"password manager\", \"track expenses\". Nobody posts asking for an app to connect people, but plenty post asking how to do a specific thing.",
        .alsoSaying: "People are also saying %@ — add them in Setup if they fit.",
        .fromLastTime: "%@ from last time. Sweep for anything new.",
        .pickSector: "Pick a sector",
        .orPickSector: "Or start from a sector",
        .theseWillBeSearched: "These are what gets searched. Tap one to drop it — a phrase that is wrong wastes half a minute of the rate limit.",
        .willTake: "%@ phrases, about %@ seconds",
        .findingTakes: "About %@ seconds — Reddit allows one search every twenty, so this is mostly waiting.",
        .searchedSoFar: "%@ of %@ · just searched \"%@\" · %@ communities so far",
        .whereTheyTalk: "WHERE THEY TALK",
        .nothingFoundYet: "Nothing searched yet. Say what your product does and it will go and find the communities where that gets discussed.",
        .foundNowhere: "Nothing came back. Try plainer words — the ones your customers would use, not your feature names.",
        .foundPlaces: "%@ worth watching, out of %@ communities seen",
        .foundByHits: "%@ of your phrases · %@ posts",
        .watchThese: "Watch these",
        .nowWatching: "Added %@. Now watching %@ communities — go to Radar.",
        .whereItCannotLook: "WHERE IT CANNOT LOOK",
        .notElsewhere: "X/Twitter, Facebook, Instagram and LinkedIn are not here, and will not be. X removed free API access — search now starts at a paid tier per month, and the terms restrict this kind of monitoring. Meta's API only reaches pages you already own; there is no public content search. LinkedIn has none for third parties. Any tool claiming to sweep all of them is either paying thousands a month or scraping in a way that gets your accounts closed. Reddit and Hacker News are the two where the content is genuinely public and reading it is permitted.",

        .hintHackerNews: "Searches the same words on Hacker News, over the last fortnight rather than the last hour — HN is a trickle next to Reddit, and a niche phrase has a couple of dozen mentions across the site's whole history. Worth having if your customers are technical. It has no rate limit, so it costs nothing but the time.",
    ]
}

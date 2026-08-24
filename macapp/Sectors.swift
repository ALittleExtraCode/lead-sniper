import Foundation

/// Starting phrases, by the kind of thing you make.
///
/// Phrases and not community names, deliberately. A hardcoded list of subreddits
/// is wrong within a year -- they get renamed, go private, get banned -- and it
/// is exactly what the live search is for. What people *say* when they have a
/// problem barely changes: somebody has been typing "keeps crashing" for twenty
/// years and will be typing it in twenty more. So a sector supplies the words,
/// the search finds the places, and this corpus can be small and still be right.
///
/// Every phrase is two or three words, because that is the size that was
/// measured to work. "batch export" found 97 posts across 68 communities;
/// "export" found 20,907 and matched trade tariffs; "batch export my whole music
/// library in one go" found nothing at all, anywhere.
///
/// They are also things a person literally types. Half of each list is what the
/// thing IS and half is what goes WRONG with it, because somebody posting "print
/// keeps failing" is a lead and somebody posting "3D printing software" is a
/// category page.
enum Sectors {
    struct Sector: Equatable {
        let name: String
        let phrases: [String]
    }

    static let all: [Sector] = [
        Sector(name: "Developer tools", phrases: [
            "code editor", "git client", "regex tester", "diff tool", "keeps crashing",
            "merge conflict", "eating my ram", "any alternative to",
            "worth paying for",
        ]),
        Sector(name: "APIs and backend", phrases: [
            "api gateway", "handling webhooks", "background jobs", "oauth flow",
            "rate limited", "cors error", "keeps timing out", "worth switching to",
        ]),
        Sector(name: "DevOps and hosting", phrases: [
            "ci pipeline", "reverse proxy", "load balancer", "uptime monitoring",
            "build takes forever", "surprise bill", "keeps going down", "cold starts",
            "cheapest vps", "cheaper alternative",
        ]),
        Sector(name: "Databases", phrases: [
            "connection pool", "read replica", "schema migration", "vector database",
            "slow queries", "lost my data", "too many connections",
            "corrupted database", "restore from backup", "worth migrating to",
        ]),
        Sector(name: "Self-hosting and homelab", phrases: [
            "home server", "media server", "mini pc", "out of space", "drive failed",
            "port forwarding", "remote access", "self hosted alternative",
            "worth self hosting",
        ]),
        Sector(name: "Design tools", phrases: [
            "vector editor", "font manager", "ui kit", "keeps crashing",
            "fonts not loading", "export looks blurry", "any alternative to",
            "worth the subscription", "one time purchase",
        ]),
        Sector(name: "Video and film", phrases: [
            "free video editor", "color grading", "proxy workflow", "media offline",
            "dropped frames", "choppy playback", "render takes forever",
            "export failed", "any alternative to", "worth upgrading",
        ]),
        Sector(name: "Photography", phrases: [
            "free photo editor", "raw converter", "photo organizer",
            "tethered shooting", "culling software", "corrupted sd card",
            "colors look off", "corrupted catalog", "worth paying for",
            "no subscription",
        ]),
        Sector(name: "Music and audio", phrases: [
            "audio interface", "midi controller", "stem separation", "sample library",
            "latency issues", "crackling audio", "cpu spikes",
            "project keeps crashing", "free alternative",
        ]),
        Sector(name: "3D and CAD", phrases: [
            "cad software", "parametric modeling", "render engine", "stl file",
            "non manifold", "laggy viewport", "crashes on render", "failed to import",
            "perpetual license", "worth learning",
        ]),
        Sector(name: "Writing and publishing", phrases: [
            "distraction free writing", "grammar checker", "self publishing",
            "manuscript formatting", "beta readers", "lost my draft", "export to epub",
            "keeps crashing", "any alternative to", "query letter",
        ]),
        Sector(name: "Note-taking and PKM", phrases: [
            "note taking app", "second brain", "markdown editor", "self hosted",
            "daily notes", "lost my notes", "sync issues", "vendor lock in",
            "export my notes", "worth the subscription",
        ]),
        Sector(name: "Education and courses", phrases: [
            "self taught", "lesson plans", "flash cards", "spaced repetition",
            "practice tests", "grading papers", "keep procrastinating", "how to study",
            "any good courses", "free alternative to",
        ]),
        Sector(name: "Translation and language", phrases: [
            "language exchange", "machine translation", "language learning app",
            "translate subtitles", "native speaker", "stuck at intermediate",
            "keep forgetting words", "bad translation", "any good apps",
            "per word rate",
        ]),
        Sector(name: "Marketing and SEO", phrases: [
            "keyword research", "backlink checker", "rank tracker", "seo audit",
            "traffic dropped", "not getting indexed", "high bounce rate",
            "free seo tools", "any alternative to",
        ]),
        Sector(name: "Sales and CRM", phrases: [
            "simple crm", "lead tracking", "sales pipeline", "cold email",
            "duplicate contacts", "manual data entry", "leads falling through",
            "free crm", "recommend a crm",
        ]),
        Sector(name: "Analytics and data", phrases: [
            "data pipeline", "self hosted analytics", "event tracking",
            "build a dashboard", "slow queries", "messy data", "exporting to csv",
            "open source alternative", "raised their prices",
        ]),
        Sector(name: "Accounting and invoicing", phrases: [
            "invoice template", "expense tracking", "scanning receipts",
            "bank reconciliation", "unpaid invoices", "chasing late payments",
            "quarterly taxes", "still using spreadsheets", "cheaper alternative to",
            "free invoicing software",
        ]),
        Sector(name: "E-commerce", phrases: [
            "abandoned cart", "print on demand", "inventory management",
            "shipping costs", "sales dropped", "account suspended",
            "chargeback dispute", "transaction fees", "worth switching to",
        ]),
        Sector(name: "Project management", phrases: [
            "project management tool", "task tracker", "kanban board", "gantt chart",
            "time tracking app", "scope creep", "too many tools", "missing deadlines",
            "any alternative to",
        ]),
        Sector(name: "HR and recruiting", phrases: [
            "applicant tracking system", "employee onboarding", "performance review",
            "resume screening", "background check", "high turnover", "got ghosted",
            "hiring is broken",
        ]),
        Sector(name: "Legal and contracts", phrases: [
            "contract template", "non disclosure agreement", "contract review",
            "cease and desist", "breach of contract", "getting sued",
            "afford a lawyer", "is this enforceable", "can i sue",
        ]),
        Sector(name: "Customer support", phrases: [
            "help desk", "ticketing system", "shared inbox", "knowledge base",
            "canned responses", "ticket backlog", "angry customer",
            "anyone switched from",
        ]),
        Sector(name: "Scheduling and calendars", phrases: [
            "booking link", "shared calendar", "meeting scheduler",
            "appointment reminders", "online booking system", "double booked",
            "no shows", "calendar not syncing", "free scheduling tool",
        ]),
        Sector(name: "Health and fitness", phrases: [
            "workout tracker", "calorie counter", "meal prep", "heart rate monitor",
            "hit a plateau", "not syncing", "lower back pain", "cancel my membership",
            "any alternative to",
        ]),
        Sector(name: "Finance and budgeting", phrases: [
            "budgeting app", "expense tracker", "sinking funds", "emergency fund",
            "paycheck to paycheck", "stopped syncing", "overdraft fees",
            "budget spreadsheet", "free alternative to",
        ]),
        Sector(name: "Travel", phrases: [
            "travel insurance", "carry on only", "points and miles",
            "missed my connection", "flight got cancelled", "lost luggage",
            "long layover", "jet lag",
        ]),
        Sector(name: "Food and cooking", phrases: [
            "recipe app", "meal planner", "sourdough starter", "cast iron",
            "came out dry", "too salty", "keeps burning", "any substitute for",
        ]),
        Sector(name: "Parenting", phrases: [
            "baby monitor", "sleep training", "potty training", "screen time",
            "picky eater", "night wakings", "toddler tantrums", "is it normal",
        ]),
        Sector(name: "AI and machine learning", phrases: [
            "local llm", "fine tuning", "vector database", "keeps hallucinating",
            "out of memory", "inference speed", "api costs", "any alternative to",
            "worth paying for",
        ]),
        Sector(name: "Security and privacy", phrases: [
            "password manager", "two factor", "self hosted", "encrypted backup",
            "data breach", "got hacked", "locked out of", "open source alternative",
            "is it safe",
        ]),
        Sector(name: "Mobile apps", phrases: [
            "offline mode", "habit tracker", "in app purchases", "keeps crashing",
            "drains my battery", "not syncing", "after the update", "rejected my app",
            "free alternative to", "worth the subscription",
        ]),
        Sector(name: "Browser extensions", phrases: [
            "ad blocker", "tab manager", "price tracker", "screenshot tool",
            "extension stopped working", "broke after update", "too many permissions",
            "memory hog", "any extension that", "safe to install",
        ]),
        Sector(name: "No-code and automation", phrases: [
            "no code tool", "drag and drop", "web scraper", "automate my workflow",
            "connect two apps", "without coding", "keeps timing out", "keeps failing",
            "cheaper alternative to", "any tool that",
        ]),
        Sector(name: "Games and game dev", phrases: [
            "free game engine", "sprite sheet", "level editor", "find playtesters",
            "crashes on startup", "low fps", "input lag", "corrupted save file",
            "any alternative to",
        ]),
        Sector(name: "Hardware and 3D printing", phrases: [
            "resin printer", "slicer settings", "bed leveling", "free cad software",
            "clogged nozzle", "layer shifting", "first layer issues",
            "print keeps failing", "best budget printer",
        ]),
        Sector(name: "Real estate and property", phrases: [
            "tenant screening", "rent roll", "lease agreement", "maintenance requests",
            "property management software", "security deposit", "not paying rent",
            "eviction notice", "low appraisal",
        ]),
        Sector(name: "Trades and field work", phrases: [
            "job costing", "work order", "change order", "estimating software",
            "invoicing software", "chasing invoices", "no cell service",
            "double booked", "cheaper alternative to",
        ]),
        Sector(name: "Nonprofits and community", phrases: [
            "donor management", "volunteer signup", "grant writing", "silent auction",
            "membership dues", "volunteer burnout", "donations are down",
            "small nonprofit", "free for nonprofits", "nonprofit discount",
        ]),
    ]

    /// How many phrases the interface offers from a sector.
    ///
    /// A sector carries eight to ten, and a search runs six. Offering all of
    /// them and silently using the first six would be a lie about what is
    /// happening, so the extra ones are shown unlit and can be swapped in.
    static let offered = 10
}

import Foundation

/// A feed with the awkward shapes the real one has.
///
/// Written rather than captured, so the suite does not ship other people's
/// posts, but every quirk in it was observed on the live endpoint first:
///
///   · `<category term="SaaS" label="r/SaaS"/>` is the only thing that says
///     which community an entry came from when several are combined
///   · content arrives as escaped HTML beginning `<!-- SC_OFF --><div class="md">`
///   · ids look like `t3_1vwj8cf` and the useful part is after the underscore
///   · authors are written `/u/name`
///   · entities are escaped twice, so `&amp;amp;` has to survive two passes
///
/// The `<` in prose case is the one that matters most: this is a feed of people
/// writing about code and settings, and the original stripped tags with
/// `re.sub(r'<[^>]+>', ' ', ...)`, which eats everything from a stray `<` to the
/// next `>` -- often the rest of the sentence.
enum Fixtures {

    static let atom = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>newest submissions</title>
      <entry>
        <author><name>/u/someone_asking</name></author>
        <category term="musicproduction" label="r/musicproduction"/>
        <content type="html">&lt;!-- SC_OFF --&gt;&lt;div class="md"&gt;&lt;p&gt;I have about 400 tracks and no way to get them off the site. Is there a tool that can batch export the lot? Doing it by hand is taking forever.&lt;/p&gt;&lt;/div&gt;</content>
        <id>t3_aaa111</id>
        <link href="https://www.reddit.com/r/musicproduction/comments/aaa111/bulk_export/"/>
        <updated>2026-08-23T21:00:00+00:00</updated>
        <title>Any way to bulk download a whole library?</title>
      </entry>
      <entry>
        <author><name>/u/writes_code</name></author>
        <category term="webdev" label="r/webdev"/>
        <content type="html">&lt;!-- SC_OFF --&gt;&lt;div class="md"&gt;&lt;p&gt;My condition is if x &amp;lt; 10 then bail, but the parser keeps choking. Ideas?&lt;/p&gt;&lt;/div&gt;</content>
        <id>t3_bbb222</id>
        <link href="https://www.reddit.com/r/webdev/comments/bbb222/parser/"/>
        <updated>2026-08-23T20:00:00+00:00</updated>
        <title>Parser dies when x &amp;lt; 10</title>
      </entry>
      <entry>
        <author><name>/u/founder_person</name></author>
        <category term="SaaS" label="r/SaaS"/>
        <content type="html">&lt;!-- SC_OFF --&gt;&lt;div class="md"&gt;&lt;p&gt;Spent six months on it. Would love feedback on the export flow.&lt;/p&gt;&lt;/div&gt;</content>
        <id>t3_ccc333</id>
        <link href="https://www.reddit.com/r/SaaS/comments/ccc333/launch/"/>
        <updated>2026-08-23T19:00:00+00:00</updated>
        <title>I built a batch export tool for musicians</title>
      </entry>
      <entry>
        <author><name>/u/unlucky</name></author>
        <category term="SaaS" label="r/SaaS"/>
        <content type="html">&lt;!-- SC_OFF --&gt;&lt;div class="md"&gt;&lt;p&gt;Paid for an export tool and it never arrived. Card company is involved now.&lt;/p&gt;&lt;/div&gt;</content>
        <id>t3_ddd444</id>
        <link href="https://www.reddit.com/r/SaaS/comments/ddd444/scam/"/>
        <updated>2026-08-23T18:00:00+00:00</updated>
        <title>Think I have been scammed, requesting a chargeback</title>
      </entry>
      <entry>
        <author><name>/u/ampersands</name></author>
        <category term="musicproduction" label="r/musicproduction"/>
        <content type="html">&lt;!-- SC_OFF --&gt;&lt;div class="md"&gt;&lt;p&gt;Looking for an alternative to what I use now. Mixing &amp;amp; mastering, mostly.&lt;/p&gt;&lt;/div&gt;</content>
        <id>t3_eee555</id>
        <link href="https://www.reddit.com/r/musicproduction/comments/eee555/alt/"/>
        <updated>2026-08-23T17:00:00+00:00</updated>
        <title>Alternative to my current export &amp;amp; backup setup?</title>
      </entry>
    </feed>
    """

    static var atomData: Data { Data(atom.utf8) }

    /// The workspace the fixture is scored against.
    static var workspace: Workspace {
        var w = Workspace.empty(id: "test")
        w.name = "Batch Exporter"
        w.url = "https://example.com"
        w.summary = "Exports a whole music library in one go."
        w.communities = ["musicproduction", "SaaS", "webdev"]
        w.terms = ["export", "download", "backup", "library", "batch", "bulk"]
        w.features = [
            .init(name: "Batch export", triggers: ["batch", "bulk", "all at once"],
                  doesWhat: "export a whole library in one go"),
            .init(name: "Backup", triggers: ["backup", "archive"],
                  doesWhat: "keep an offline copy of everything"),
        ]
        return w
    }

    /// Fixed, so recency scoring is tested against a known clock rather than
    /// against whenever the suite happens to run.
    static var now: Date {
        ISO8601DateFormatter().date(from: "2026-08-23T21:30:00+00:00")!
    }
}

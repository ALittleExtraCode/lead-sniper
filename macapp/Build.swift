import Foundation

/// One place that knows what version this is. The build script rewrites it.
enum Build {
    static let version = "0.1"
    static let name = "LeadSniper"

    /// The one place the domain is written.
    ///
    /// It was spelled out in five files, and one of them was `Updates.trusted`.
    /// With the wrong spelling there the updater fetched the manifest, saw a
    /// newer version, failed its own domain check and reported "up to date" —
    /// a silent failure that would have hidden every release forever.
    static let host = "lead-sniper.com"
    static var site: URL { URL(string: "https://\(host)")! }
    static var manifest: URL { URL(string: "https://\(host)/dist/latest.json")! }
    static var download: URL { URL(string: "https://\(host)/dist/LeadSniper.dmg")! }
}

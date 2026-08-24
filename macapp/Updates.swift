import Foundation

/// Asks whether there is a newer version, and nothing else.
///
/// Carried over from SunoGet, including the parts that were learned rather than
/// designed:
///
///   · a deadline, because a check that hangs looks identical to an app that
///     has frozen, and SunoGet shipped that twice
///   · the download link is only followed if it is https and on our own domain,
///     so a compromised or mistyped manifest cannot point the updater anywhere
///   · the version string is validated before it is compared, since it comes
///     off the network and ends up on screen
///
/// The download is deliberately not automatic. SunoGet's in-app installer was
/// the single most troublesome part of that app; opening the page and letting
/// somebody drag it across is duller and it works.
enum Updates {

    enum Answer: Equatable {
        case newer(version: String, url: URL)
        case upToDate
        case couldNotReach
    }

    static let manifest = URL(string: "https://leadsniper.com/dist/latest.json")!

    /// Only ever links to our own site, over https.
    static func trusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "leadsniper.com" || host.hasSuffix(".leadsniper.com")
    }

    /// Digits and dots, and short. It comes off the network and is shown to a
    /// person, so it is checked before either of those things happen.
    static func plausible(_ version: String) -> Bool {
        !version.isEmpty && version.count <= 16
            && version.allSatisfy { $0.isNumber || $0 == "." }
            && !version.hasPrefix(".") && !version.hasSuffix(".")
    }

    /// Compares two dotted versions numerically. "1.10" is after "1.9", which
    /// string comparison gets backwards.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func check(current: String = Build.version,
                      session: URLSession = .shared) async -> Answer {
        var request = URLRequest(url: manifest, timeoutInterval: 15)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(Feed.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = json["version"] as? String,
                  plausible(version)
            else { return .couldNotReach }

            guard isNewer(version, than: current) else { return .upToDate }

            // No link, or a link somewhere else, means the manifest is not one
            // we will act on -- say up to date rather than send someone
            // somewhere unexpected.
            guard let link = json["url"] as? String,
                  let url = URL(string: link), trusted(url)
            else { return .upToDate }

            return .newer(version: version, url: url)
        } catch {
            return .couldNotReach
        }
    }
}

import Foundation

/// Pushes hot leads into a Slack or Discord channel.
///
/// Ported from the Python `omnichannel_dispatcher`, minus the part that posted
/// to Reddit. What is left is the useful half: a lead is worth most in its first
/// hour, and nobody watches an app window all day. A message in the channel the
/// team is already in beats a notification on one person's Mac.
///
/// Slack and Discord take different keys for the same thing -- `text` and
/// `content` -- and both ignore the other. Sending both is one request that
/// works for either, rather than asking the customer which they have.
enum Webhook {

    enum Result: Equatable {
        case sent
        case notConfigured
        case rejected(Int)
        case failed(String)
    }

    /// Only https, and only to the two services this knows the shape of.
    ///
    /// A webhook URL is a secret that grants write access to somebody's channel,
    /// and it is typed in by hand from a clipboard. Restricting where it can be
    /// sent means a mistyped or pasted-wrong URL fails here rather than posting
    /// the team's leads to whatever host happened to be in the paste buffer.
    static func trusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "hooks.slack.com"
            || host == "discord.com" || host == "discordapp.com"
            || host.hasSuffix(".discord.com")
    }

    /// What a lead looks like in a channel.
    ///
    /// Plain text with the link on its own line. Neither service is asked to
    /// render anything clever, because a message that renders differently in the
    /// two of them is one somebody has to check twice.
    static func message(for leads: [Radar.Lead], workspace: Workspace) -> String {
        guard !leads.isEmpty else { return "" }
        var lines: [String] = []
        lines.append(leads.count == 1
            ? "1 lead worth answering for \(workspace.name)"
            : "\(leads.count) leads worth answering for \(workspace.name)")
        for lead in leads.prefix(5) {
            lines.append("")
            lines.append("\(lead.verdict.band.rawValue.uppercased()) · r/\(lead.post.source) · \(lead.verdict.total)")
            lines.append(lead.post.title)
            if let link = lead.post.link { lines.append(link.absoluteString) }
            // The strongest reason only. A channel message listing six is a
            // channel message nobody finishes reading.
            if let why = lead.verdict.reasons.first {
                lines.append("why: \(why.label.rawValue) — \(why.detail)")
            }
        }
        if leads.count > 5 {
            lines.append("")
            lines.append("…and \(leads.count - 5) more in the app.")
        }
        return lines.joined(separator: "\n")
    }

    static func send(_ leads: [Radar.Lead], workspace: Workspace,
                     to address: String,
                     session: URLSession = .shared) async -> Result {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .notConfigured }
        guard let url = URL(string: trimmed), trusted(url) else {
            return .failed("that is not a Slack or Discord webhook address")
        }
        let text = message(for: leads, workspace: workspace)
        guard !text.isEmpty else { return .notConfigured }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Feed.userAgent, forHTTPHeaderField: "User-Agent")
        // Both keys, one request: Slack reads `text`, Discord reads `content`,
        // and each ignores the other.
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["text": text, "content": text])

        do {
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200...299).contains(code) ? .sent : .rejected(code)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

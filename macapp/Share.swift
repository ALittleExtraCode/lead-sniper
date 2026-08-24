import Foundation

/// Getting things out of the app, and back in.
///
/// Two separate jobs that both come down to writing a file:
///
///   · a workspace, so somebody can hand their setup to a colleague or keep a
///     copy. The Python version called these presets and shipped them as JSON
///     in a folder, which is a good idea badly placed -- a file you can send
///     someone beats a file they have to know the path of.
///   · the leads, as CSV, because the next thing anybody does with a list of
///     leads is put it somewhere else.
enum Share {

    // MARK: - Workspaces

    /// A workspace as a file somebody can send.
    ///
    /// Versioned from the start. A preset with no version is one you cannot
    /// safely change the shape of later, and this one will change.
    struct Preset: Codable {
        var leadsniper = 1
        var workspace: Workspace
        /// Written for a human opening the file in a text editor, not read back.
        var note = "A LeadSniper workspace. Open LeadSniper and use Setup → Import."
    }

    static func export(_ workspace: Workspace) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Preset(workspace: workspace))
    }

    enum ImportProblem: Error, Equatable {
        case notLeadSniper
        case fromANewerVersion(Int)
        case unusable([String])
    }

    /// A preset in the Python engine's schema.
    ///
    /// Read as well as our own, because the customer already has files in this
    /// shape and telling somebody their own data is the wrong format is a poor
    /// answer. The shapes line up almost exactly -- `subreddits` is
    /// `communities`, `keywords` is `terms` -- with one real gap: their features
    /// carry trigger words but no statement of what the feature lets you DO.
    /// That is the sentence a draft is built from, so it is filled in from the
    /// description rather than left empty, which would mean no drafts at all.
    private struct PythonPreset: Decodable {
        var name: String?
        var product_url: String?
        var description: String?
        var subreddits: [String]?
        var keywords: [String]?
        var negative_keywords: [String]?
        var features: [PythonFeature]?

        struct PythonFeature: Decodable {
            var name: String?
            var trigger_words: [String]?
        }
    }

    private static func adopt(_ preset: PythonPreset) -> Workspace? {
        guard let name = preset.name, !name.isEmpty else { return nil }
        var workspace = Workspace.empty()
        workspace.name = name
        workspace.url = preset.product_url ?? ""
        workspace.summary = preset.description ?? ""
        workspace.communities = preset.subreddits ?? []
        workspace.terms = (preset.keywords ?? []).map { $0.lowercased() }
        if let negatives = preset.negative_keywords, !negatives.isEmpty {
            // Merged, not replaced: their lists cover relevance, ours covers the
            // threads where a product mention makes somebody look like a ghoul.
            var all = Workspace.defaultNegativeTerms
            for term in negatives where !all.contains(term) { all.append(term) }
            workspace.negativeTerms = all
        }
        workspace.features = (preset.features ?? []).compactMap { feature in
            guard let featureName = feature.name, !featureName.isEmpty else { return nil }
            return Workspace.Feature(
                name: featureName,
                triggers: (feature.trigger_words ?? []).map { $0.lowercased() },
                doesWhat: (preset.description ?? featureName).lowercasedStart)
        }
        return workspace
    }

    /// Reads a preset, and refuses one that would not work.
    ///
    /// A file that imports into an unusable state is worse than one that fails:
    /// the customer ends up on the Radar wondering why nothing happens, with no
    /// reason to suspect the file they just opened.
    static func importPreset(_ data: Data) throws -> Workspace {
        var workspace: Workspace

        if let preset = try? JSONDecoder().decode(Preset.self, from: data) {
            guard preset.leadsniper <= 1 else {
                throw ImportProblem.fromANewerVersion(preset.leadsniper)
            }
            workspace = preset.workspace
        } else if let python = try? JSONDecoder().decode(PythonPreset.self, from: data),
                  let adopted = adopt(python) {
            workspace = adopted
        } else {
            throw ImportProblem.notLeadSniper
        }
        // A new identity, so importing a colleague's file does not overwrite the
        // workspace you already have under the same id.
        workspace.id = UUID().uuidString
        guard workspace.isUsable else {
            throw ImportProblem.unusable(workspace.missing)
        }
        return workspace
    }

    // MARK: - Leads

    /// The leads as CSV, in the order they are on screen.
    ///
    /// Includes the reasons, because a lead without them is a link somebody has
    /// to re-read from scratch, and the reasons are the part this app adds.
    static func csv(_ leads: [Radar.Lead], now: Date = Date()) -> String {
        var out = ["band,score,community,author,posted,answered,title,link,why"]
        let stamp = ISO8601DateFormatter()
        for lead in leads {
            let why = lead.verdict.reasons
                .map { "\($0.label.rawValue): \($0.detail)" }
                .joined(separator: "; ")
            out.append([
                lead.verdict.band.rawValue,
                "\(lead.verdict.total)",
                "r/\(lead.post.source)",
                lead.post.author,
                stamp.string(from: lead.post.posted),
                lead.isAnswered ? "yes" : "no",
                lead.post.title,
                lead.post.link?.absoluteString ?? "",
                why,
            ].map(field).joined(separator: ","))
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// One CSV field, quoted properly.
    ///
    /// Reddit titles contain commas, quotation marks and newlines as a matter of
    /// course, and a naive join produces a file that opens in a spreadsheet with
    /// the columns shifted for exactly the rows somebody cares about.
    static func field(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        guard cleaned.contains(",") || cleaned.contains("\"") || cleaned.contains(" ") else {
            return cleaned
        }
        return "\"" + cleaned.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// A filename that will not collide or upset the filesystem.
    static func filename(for workspace: Workspace, extension ext: String,
                         on day: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let safe = workspace.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
        return "\(safe.isEmpty ? "leadsniper" : safe)-\(formatter.string(from: day)).\(ext)"
    }
}


private extension String {
    /// Lower-cases the first letter so it reads inside "it can ___", unless the
    /// word is an acronym.
    ///
    /// The guard used to look at the two characters AFTER the first, which for
    /// "AI video captioning" is "I " -- a space is not upper case, so it decided
    /// this was ordinary prose and produced "aI video captioning". The question
    /// is whether the first TWO characters are both capitals.
    var lowercasedStart: String {
        guard let first, first.isUppercase,
              !prefix(2).allSatisfy({ $0.isUppercase })
        else { return self }
        return first.lowercased() + dropFirst()
    }
}

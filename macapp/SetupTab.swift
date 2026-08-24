import Cocoa
import UniformTypeIdentifiers

/// Describing your own product.
///
/// This is the first screen a new customer really uses, and the whole radar is
/// only as good as what gets typed here. So it asks for things in the customer's
/// own words and never pre-fills anything plausible-looking: the Python original
/// shipped presets containing `https://yourapp.com` and one product's real
/// feature list, and a half-filled form that looks finished is how somebody ends
/// up posting about a feature they do not have.
final class SetupTab: NSView, PrimaryAction {

    private let workspaces = Workspaces.shared

    private let nameField = DarkField()
    private let urlField = DarkField()
    private let summaryField = DarkField()
    private let communitiesField = DarkField()
    private let termsField = DarkField()
    private let negativeField = DarkField()
    private let newsToggle = ToggleChip()
    private let webhookField = DarkField()
    private let languageChip = MenuChip()
    private let featuresStack = NSStackView()
    private let saveButton = AccentButton(title: "", target: nil, action: nil)
    private let statusLabel = NSTextField.themed("", size: 11, color: Theme.textMuted)
    private let picker = NSPopUpButton()

    private var features: [Workspace.Feature] = []
    private var editing: Workspace = .empty()

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        load(workspaces.active ?? .empty())
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() { reloadPicker() }
    func performPrimaryAction() { save() }

    // MARK: - Layout

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = .clear

        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 14
        column.edgeInsets = NSEdgeInsets(top: 4, left: 16, bottom: 20, right: 16)
        column.translatesAutoresizingMaskIntoConstraints = false

        let scroller = NSScrollView()
        scroller.drawsBackground = false
        scroller.hasVerticalScroller = true
        scroller.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(column)
        scroller.documentView = doc
        addSubview(scroller)
        NSLayoutConstraint.activate([
            scroller.topAnchor.constraint(equalTo: topAnchor),
            scroller.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroller.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroller.bottomAnchor.constraint(equalTo: bottomAnchor),
            doc.widthAnchor.constraint(equalTo: scroller.contentView.widthAnchor),
            column.topAnchor.constraint(equalTo: doc.topAnchor),
            column.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])

        func addCard(_ title: String, _ body: NSView) {
            let card = CardView.titled(title, body)
            column.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -32).isActive = true
        }

        func row(_ label: String, _ field: DarkField, _ hint: String) -> NSView {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.heightAnchor.constraint(equalToConstant: 30).isActive = true
            field.widthAnchor.constraint(equalToConstant: 560).isActive = true
            let title = NSTextField.themed(label, size: 11, color: Theme.textPrimary)
            title.font = .systemFont(ofSize: 11, weight: .semibold)
            let note = NSTextField.themed(hint, size: 10, color: Theme.textMuted)
            note.lineBreakMode = .byWordWrapping
            note.maximumNumberOfLines = 0
            note.preferredMaxLayoutWidth = 560
            let stack = NSStackView(views: [title, field, note])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 4
            return stack
        }

        // ---- which product -------------------------------------------------
        picker.target = self
        picker.action = #selector(pickWorkspace)
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.widthAnchor.constraint(equalToConstant: 260).isActive = true
        let newButton = NSButton(title: L.t(.newProduct), target: self, action: #selector(newWorkspace))
        newButton.isBordered = false
        newButton.font = .systemFont(ofSize: 11, weight: .semibold)
        newButton.contentTintColor = Theme.accent
        let exportButton = NSButton(title: L.t(.exportPreset), target: self, action: #selector(exportPreset))
        let importButton = NSButton(title: L.t(.importPreset), target: self, action: #selector(importPreset))
        for b in [exportButton, importButton] {
            b.isBordered = false
            b.font = .systemFont(ofSize: 11, weight: .semibold)
            b.contentTintColor = Theme.accent
        }
        languageChip.items = L.languages.enumerated().map { (title: $0.element.name, tag: $0.offset) }
        languageChip.offTag = -1
        languageChip.selectedTag = L.languages.firstIndex { $0.code == L.code } ?? 0
        languageChip.target = self
        languageChip.action = #selector(languagePicked)

        let pickerRow = NSStackView(views: [picker, newButton, importButton, exportButton,
                                            NSView(), languageChip])
        pickerRow.orientation = .horizontal
        pickerRow.spacing = 12
        addCard(L.t(.product), pickerRow)

        // ---- the product ---------------------------------------------------
        let about = NSStackView(views: [
            row(L.t(.fieldName), nameField, L.t(.hintName)),
            row(L.t(.fieldUrl), urlField, L.t(.hintUrl)),
            row(L.t(.fieldSummary), summaryField, L.t(.hintSummary)),
        ])
        about.orientation = .vertical
        about.alignment = .leading
        about.spacing = 12
        addCard(L.t(.aboutProduct), about)

        // ---- where to watch ------------------------------------------------
        newsToggle.title = L.t(.alsoHackerNews)
        newsToggle.target = self
        newsToggle.action = #selector(toggleNews)
        let newsNote = NSTextField.themed(L.t(.hintHackerNews), size: 10, color: Theme.textMuted)
        newsNote.lineBreakMode = .byWordWrapping
        newsNote.maximumNumberOfLines = 0
        newsNote.preferredMaxLayoutWidth = 560
        let newsBox = NSStackView(views: [newsToggle, newsNote])
        newsBox.orientation = .vertical
        newsBox.alignment = .leading
        newsBox.spacing = 4

        let watching = NSStackView(views: [
            row(L.t(.fieldCommunities), communitiesField, L.t(.hintCommunities)),
            newsBox,
            row(L.t(.fieldTerms), termsField, L.t(.hintTerms)),
            row(L.t(.fieldNegative), negativeField, L.t(.hintNegative)),
            row(L.t(.fieldWebhook), webhookField, L.t(.hintWebhook)),
        ])
        watching.orientation = .vertical
        watching.alignment = .leading
        watching.spacing = 12
        addCard(L.t(.whereToWatch), watching)

        // ---- what it does --------------------------------------------------
        featuresStack.orientation = .vertical
        featuresStack.alignment = .leading
        featuresStack.spacing = 10
        let addFeature = NSButton(title: L.t(.addFeature), target: self, action: #selector(addFeature))
        addFeature.isBordered = false
        addFeature.font = .systemFont(ofSize: 11, weight: .semibold)
        addFeature.contentTintColor = Theme.accent
        let featureNote = NSTextField.themed(L.t(.hintFeatures), size: 10, color: Theme.textMuted)
        featureNote.lineBreakMode = .byWordWrapping
        featureNote.maximumNumberOfLines = 0
        featureNote.preferredMaxLayoutWidth = 560
        let featureBox = NSStackView(views: [featureNote, featuresStack, addFeature])
        featureBox.orientation = .vertical
        featureBox.alignment = .leading
        featureBox.spacing = 10
        addCard(L.t(.whatItDoes), featureBox)

        saveButton.title = L.t(.save)
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        saveButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 0
        statusLabel.preferredMaxLayoutWidth = 380
        let footer = NSStackView(views: [saveButton, statusLabel])
        footer.orientation = .horizontal
        footer.spacing = 12
        footer.alignment = .centerY
        column.addArrangedSubview(footer)

        reloadPicker()
    }

    // MARK: - Features

    private func rebuildFeatureRows() {
        featuresStack.setViews(features.enumerated().map { index, feature in
            let name = DarkField()
            name.stringValue = feature.name
            name.placeholderString = L.t(.featureName)
            name.tag = index
            name.target = self
            name.action = #selector(featureEdited)
            name.translatesAutoresizingMaskIntoConstraints = false
            name.widthAnchor.constraint(equalToConstant: 150).isActive = true
            name.heightAnchor.constraint(equalToConstant: 28).isActive = true

            let triggers = DarkField()
            triggers.stringValue = feature.triggers.joined(separator: ", ")
            triggers.placeholderString = L.t(.featureTriggers)
            triggers.tag = 1000 + index
            triggers.target = self
            triggers.action = #selector(featureEdited)
            triggers.translatesAutoresizingMaskIntoConstraints = false
            triggers.widthAnchor.constraint(equalToConstant: 190).isActive = true
            triggers.heightAnchor.constraint(equalToConstant: 28).isActive = true

            let does = DarkField()
            does.stringValue = feature.doesWhat
            does.placeholderString = L.t(.featureDoes)
            does.tag = 2000 + index
            does.target = self
            does.action = #selector(featureEdited)
            does.translatesAutoresizingMaskIntoConstraints = false
            does.widthAnchor.constraint(equalToConstant: 190).isActive = true
            does.heightAnchor.constraint(equalToConstant: 28).isActive = true

            let remove = NSButton(title: "✕", target: self, action: #selector(removeFeature))
            remove.isBordered = false
            remove.tag = index
            remove.contentTintColor = Theme.textMuted

            let row = NSStackView(views: [name, triggers, does, remove])
            row.orientation = .horizontal
            row.spacing = 8
            return row
        }, in: .leading)
    }

    @objc private func featureEdited(_ sender: NSTextField) {
        let index = sender.tag % 1000
        guard features.indices.contains(index) else { return }
        switch sender.tag / 1000 {
        case 0: features[index].name = sender.stringValue
        case 1: features[index].triggers = Self.split(sender.stringValue)
        default: features[index].doesWhat = sender.stringValue
        }
    }

    @objc private func toggleNews() {
        newsToggle.isLit.toggle()
    }

    @objc private func addFeature() {
        features.append(.init(name: "", triggers: [], doesWhat: ""))
        rebuildFeatureRows()
    }

    @objc private func removeFeature(_ sender: NSButton) {
        guard features.indices.contains(sender.tag) else { return }
        features.remove(at: sender.tag)
        rebuildFeatureRows()
    }

    // MARK: - Loading and saving

    private func reloadPicker() {
        picker.removeAllItems()
        for workspace in workspaces.all {
            picker.addItem(withTitle: workspace.name.isEmpty ? L.t(.untitled) : workspace.name)
        }
        if workspaces.all.isEmpty { picker.addItem(withTitle: L.t(.untitled)) }
        if let active = workspaces.active,
           let index = workspaces.all.firstIndex(where: { $0.id == active.id }) {
            picker.selectItem(at: index)
        }
    }

    @objc private func pickWorkspace() {
        guard let chosen = workspaces.all[safe: picker.indexOfSelectedItem] else { return }
        workspaces.activate(chosen.id)
        load(chosen)
    }

    @objc private func newWorkspace() {
        load(.empty())
        statusLabel.stringValue = L.t(.newProductHint)
    }

    private func load(_ workspace: Workspace) {
        editing = workspace
        nameField.stringValue = workspace.name
        urlField.stringValue = workspace.url
        summaryField.stringValue = workspace.summary
        communitiesField.stringValue = workspace.communities.joined(separator: ", ")
        termsField.stringValue = workspace.terms.joined(separator: ", ")
        negativeField.stringValue = workspace.negativeTerms.joined(separator: ", ")
        newsToggle.isLit = workspace.watchesHackerNews
        webhookField.stringValue = workspace.webhook
        features = workspace.features
        rebuildFeatureRows()
        statusLabel.stringValue = ""
    }

    @objc private func save() {
        var workspace = editing
        workspace.name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        workspace.url = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        workspace.summary = summaryField.stringValue.trimmingCharacters(in: .whitespaces)
        workspace.communities = Self.split(communitiesField.stringValue).map {
            $0.replacingOccurrences(of: "r/", with: "")
        }
        workspace.terms = Self.split(termsField.stringValue)
        workspace.negativeTerms = Self.split(negativeField.stringValue)
        workspace.features = features.filter { !$0.name.isEmpty && !$0.triggers.isEmpty }
        workspace.watchesHackerNews = newsToggle.isLit
        // Set after the id is settled, so the keychain item is filed under the
        // workspace it belongs to rather than under a temporary one.
        workspace.webhook = webhookField.stringValue.trimmingCharacters(in: .whitespaces)

        guard workspace.isUsable else {
            statusLabel.stringValue = String(format: L.t(.stillNeeds),
                                             workspace.missing.joined(separator: ", "))
            return
        }
        workspaces.save(workspace)
        workspaces.activate(workspace.id)
        editing = workspace
        reloadPicker()

        // Saying what will now happen, rather than "Saved." A count of what is
        // being watched is the thing that tells someone whether they got it right.
        var told = String(format: L.t(.savedWatching),
                          "\(workspace.communities.count)", "\(workspace.terms.count)")
        if workspace.features.isEmpty { told += " · " + L.t(.noFeaturesYet) }
        statusLabel.stringValue = told
    }

    /// Changing the language.
    ///
    /// Asks for a relaunch rather than redrawing. Right-to-left mirroring is set
    /// by two defaults AppKit only reads before NSApplication exists, so a
    /// switch to Arabic that redrew in place would come up fully translated and
    /// still laid out left to right. Rebuilding every view for the other
    /// fourteen and not for that one would be a worse kind of inconsistent.
    @objc private func languagePicked() {
        guard let chosen = L.languages[safe: languageChip.selectedTag] else { return }
        guard chosen.code != L.code else { return }
        L.code = chosen.code
        L.applyLayoutDirection()

        let alert = NSAlert()
        alert.messageText = L.t(.languageChanged)
        alert.informativeText = L.t(.languageRelaunch)
        alert.addButton(withTitle: L.t(.relaunchNow))
        alert.addButton(withTitle: L.t(.later))
        if alert.runModal() == .alertFirstButtonReturn {
            let path = Bundle.main.bundlePath
            // Relaunched by a detached shell, because the app cannot start its
            // own replacement while it is still holding the bundle.
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", "sleep 0.4; open \"\(path)\""]
            try? task.run()
            NSApp.terminate(nil)
        }
    }

    // MARK: - Sharing a setup

    @objc private func exportPreset() {
        guard let workspace = workspaces.active, workspace.isUsable else {
            statusLabel.stringValue = L.t(.saveFirst)
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Share.filename(for: workspace, extension: "json")
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Share.export(workspace).write(to: url)
            statusLabel.stringValue = String(format: L.t(.exported), url.lastPathComponent)
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let workspace = try Share.importPreset(Data(contentsOf: url))
            workspaces.save(workspace)
            workspaces.activate(workspace.id)
            load(workspace)
            reloadPicker()
            statusLabel.stringValue = String(format: L.t(.imported), workspace.name,
                                             "\(workspace.communities.count)")
        } catch Share.ImportProblem.notLeadSniper {
            statusLabel.stringValue = L.t(.notAPreset)
        } catch Share.ImportProblem.fromANewerVersion(let v) {
            statusLabel.stringValue = String(format: L.t(.presetTooNew), "\(v)")
        } catch Share.ImportProblem.unusable(let missing) {
            statusLabel.stringValue = String(format: L.t(.presetUnusable),
                                             missing.joined(separator: ", "))
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    /// Splits a comma-or-newline list, trimming and dropping blanks.
    static func split(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

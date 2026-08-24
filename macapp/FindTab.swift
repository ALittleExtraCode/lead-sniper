import Cocoa

/// Step one: work out where your people are.
///
/// The customer types what their product does, in their own words, and this
/// goes and finds the communities where that gets discussed. It is deliberately
/// the first tab, because it is the first thing anybody needs and because the
/// alternative -- an empty "communities" field waiting to be filled in -- asks
/// them to already know the answer.
final class FindTab: NSView, PrimaryAction {

    private let workspaces = Workspaces.shared

    private let describeField = DarkField()
    private let companyField = DarkField()
    private let findButton = AccentButton(title: "", target: nil, action: nil)
    private let statusLabel = NSTextField.themed("", size: 11, color: Theme.textMuted)
    private let meter = Meter()
    private let sectorChip = MenuChip()
    private let phraseStack = FlowStack()
    private let phrasesLabel = NSTextField.themed("", size: 10.5, color: Theme.textMuted)
    private let resultsStack = NSStackView()
    private let watchButton = AccentButton(title: "", target: nil, action: nil)
    private let notElsewhere = NSTextField.themed("", size: 10, color: Theme.textMuted)

    /// The phrases that will actually be searched, shown and editable.
    ///
    /// These were derived invisibly at first, which meant a two-minute search
    /// could run on words the customer would have rejected in a second if they
    /// had been able to see them.
    private var phrases: [String] = []
    private var dropped: Set<String> = []

    /// Called once a workspace is ready to sweep. Set by MainController.
    ///
    /// Without this the flow dead-ended: "Watch these" saved a workspace and
    /// printed a line, and the customer was left on a page that had finished
    /// with them, with no indication that the next thing lived on another tab.
    var onReady: (() -> Void)?

    private var places: [Discover.Place] = []
    private var ticked: Set<String> = []
    private var running = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        load()
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() { load() }
    func performPrimaryAction() { find() }

    private func load() {
        // The workspace is optional; deriving is not. This used to return early
        // when there was no workspace -- which on a fresh install is always --
        // so `derive` never ran, `updateReady` never ran, and the Find button
        // kept the enabled look it was born with on a completely empty form.
        if let workspace = workspaces.active {
            if companyField.stringValue.isEmpty { companyField.stringValue = workspace.name }
            if describeField.stringValue.isEmpty { describeField.stringValue = workspace.summary }
        }
        if phrases.isEmpty { derive() }
    }

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

        func field(_ label: String, _ control: DarkField, _ hint: String, width: CGFloat = 620) -> NSView {
            control.translatesAutoresizingMaskIntoConstraints = false
            control.heightAnchor.constraint(equalToConstant: 32).isActive = true
            control.widthAnchor.constraint(equalToConstant: width).isActive = true
            let name = NSTextField.themed(label, size: 11, color: Theme.textPrimary)
            name.font = .systemFont(ofSize: 11, weight: .semibold)
            let note = NSTextField.themed(hint, size: 10, color: Theme.textMuted)
            note.lineBreakMode = .byWordWrapping
            note.maximumNumberOfLines = 0
            note.preferredMaxLayoutWidth = width
            let stack = NSStackView(views: [name, control, note])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 4
            return stack
        }

        // ---- what you make -------------------------------------------------
        describeField.placeholder = "batch export my whole music library in one go"
        companyField.placeholder = "Batch Exporter"
        describeField.target = self
        describeField.action = #selector(find)
        // Typing shows the phrases as they change; it does not search. A search
        // is two minutes of somebody else's rate limit.
        describeField.delegate = self
        let ask = NSStackView(views: [
            field(L.t(.whatDoesItDo), describeField, L.t(.hintWhatDoesItDo)),
            field(L.t(.whatIsItCalled), companyField, L.t(.hintWhatIsItCalled), width: 320),
        ])
        ask.orientation = .vertical
        ask.alignment = .leading
        ask.spacing = 12

        findButton.title = L.t(.findPlaces)
        findButton.target = self
        findButton.action = #selector(find)
        findButton.translatesAutoresizingMaskIntoConstraints = false
        findButton.heightAnchor.constraint(equalToConstant: 38).isActive = true
        findButton.widthAnchor.constraint(equalToConstant: 190).isActive = true

        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 0
        statusLabel.preferredMaxLayoutWidth = 400
        let go = NSStackView(views: [findButton, statusLabel])
        go.orientation = .horizontal
        go.spacing = 12
        go.alignment = .centerY

        phrasesLabel.lineBreakMode = .byWordWrapping
        phrasesLabel.maximumNumberOfLines = 0
        phrasesLabel.preferredMaxLayoutWidth = 620

        // A sector fills the phrases in one click, for anybody who would rather
        // start from a list than from a blank field.
        sectorChip.items = [(title: L.t(.pickSector), tag: -1)]
            + Sectors.all.enumerated().map { (title: $0.element.name, tag: $0.offset) }
        sectorChip.offTag = -1
        sectorChip.selectedTag = -1
        sectorChip.target = self
        sectorChip.action = #selector(sectorPicked)

        let sectorRow = NSStackView(views: [
            NSTextField.themed(L.t(.orPickSector), size: 10.5, color: Theme.textMuted),
            sectorChip, NSView()])
        sectorRow.orientation = .horizontal
        sectorRow.spacing = 8
        sectorRow.alignment = .centerY

        phraseStack.translatesAutoresizingMaskIntoConstraints = false

        meter.translatesAutoresizingMaskIntoConstraints = false
        meter.heightAnchor.constraint(equalToConstant: 4).isActive = true
        meter.isHidden = true

        let askBox = NSStackView(views: [ask, sectorRow, phrasesLabel, phraseStack, go, meter])
        askBox.orientation = .vertical
        askBox.alignment = .leading
        askBox.spacing = 12
        addCard(L.t(.whatYouMake), askBox)
        phraseStack.widthAnchor.constraint(equalTo: askBox.widthAnchor).isActive = true
        meter.widthAnchor.constraint(equalTo: askBox.widthAnchor).isActive = true

        // ---- what it found -------------------------------------------------
        resultsStack.orientation = .vertical
        resultsStack.alignment = .leading
        resultsStack.spacing = 6

        watchButton.title = L.t(.watchThese)
        watchButton.target = self
        watchButton.action = #selector(watchTicked)
        watchButton.isEnabled = false
        watchButton.translatesAutoresizingMaskIntoConstraints = false
        watchButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        watchButton.widthAnchor.constraint(equalToConstant: 190).isActive = true

        let foundBox = NSStackView(views: [resultsStack, watchButton])
        foundBox.orientation = .vertical
        foundBox.alignment = .leading
        foundBox.spacing = 12
        addCard(L.t(.whereTheyTalk), foundBox)

        // ---- and where it cannot look --------------------------------------
        notElsewhere.stringValue = L.t(.notElsewhere)
        notElsewhere.lineBreakMode = .byWordWrapping
        notElsewhere.maximumNumberOfLines = 0
        notElsewhere.preferredMaxLayoutWidth = 620
        addCard(L.t(.whereItCannotLook), notElsewhere)

        showEmpty()
    }

    private func showEmpty() {
        // The space where results will go is where somebody is already looking
        // and already wondering what to do, so it explains rather than sitting
        // blank. It is replaced by real results the moment there are any.
        let described = !describeField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
        let guide = Guide(steps: [
            .init(title: L.t(.guide1), detail: L.t(.guide1Detail),
                  examples: ["batch export my whole music library"], isNext: !described),
            .init(title: L.t(.guide2), detail: L.t(.guide2Detail),
                  examples: ["batch export", "music library"], isNext: described),
            .init(title: L.t(.guide3), detail: L.t(.guide3Detail),
                  examples: ["r/selfhosted", "r/musichoarder", "r/DataHoarder"]),
            .init(title: L.t(.guide4), detail: L.t(.guide4Detail),
                  examples: ["HOT · in the title · export", "posted · within the hour"]),
        ])
        guide.translatesAutoresizingMaskIntoConstraints = false
        guide.widthAnchor.constraint(equalToConstant: 560).isActive = true
        resultsStack.setViews([guide], in: .leading)
    }

    // MARK: - Finding

    /// Works out the phrases and puts them on screen. Does not search.
    @objc private func derive() {
        let described = describeField.stringValue.trimmingCharacters(in: .whitespaces)
        // Empty is a state to show, not a reason to return. Bailing here meant
        // `show` never ran, so `updateReady` never ran, so the Find button kept
        // the enabled look it was born with -- solid and inviting, with nothing
        // behind it. On an empty field it is now visibly disabled.
        show(phrases: described.isEmpty ? [] : Discover.phrases(from: described))
    }

    private func show(phrases found: [String]) {
        phrases = found
        dropped.removeAll()
        phrasesLabel.stringValue = phrases.isEmpty ? "" : L.t(.theseWillBeSearched)
        phraseStack.setViews(phrases.map { phrase in
            let chip = ToggleChip()
            chip.title = phrase
            chip.isLit = true
            chip.target = self
            chip.action = #selector(togglePhrase)
            chip.identifier = NSUserInterfaceItemIdentifier(phrase)
            return chip
        })
        updateReady()
    }

    @objc private func togglePhrase(_ sender: ToggleChip) {
        guard let phrase = sender.identifier?.rawValue else { return }
        sender.isLit.toggle()
        if sender.isLit { dropped.remove(phrase) } else { dropped.insert(phrase) }
        updateReady()
    }

    private var chosen: [String] {
        Array(phrases.filter { !dropped.contains($0) }.prefix(Discover.maximumPhrases))
    }

    private func updateReady() {
        findButton.isEnabled = !running && !chosen.isEmpty && !Discover.tooVague(chosen)
        if !running, Discover.tooVague(chosen), !chosen.isEmpty {
            statusLabel.stringValue = L.t(.tooVague)
        } else if !running, !chosen.isEmpty {
            statusLabel.stringValue = String(format: L.t(.willTake),
                                             "\(chosen.count)",
                                             "\(Discover.expectedSeconds(for: chosen))")
        }
    }

    /// A sector fills the phrases and starts straight away: picking one is
    /// already a deliberate choice, and making somebody click twice for it adds
    /// nothing.
    @objc private func sectorPicked() {
        guard let sector = Sectors.all[safe: sectorChip.selectedTag] else { return }
        var found = sector.phrases
        // Their own words go first when they have written any -- a sector is a
        // starting point, not a replacement for knowing your own product.
        let own = Discover.phrases(from: describeField.stringValue)
        found = own + found.filter { !own.contains($0) }
        show(phrases: found)
        find()
    }

    @objc private func find() {
        guard !running else { return }
        if phrases.isEmpty { derive() }
        guard !chosen.isEmpty else {
            statusLabel.stringValue = L.t(.describeItFirst)
            return
        }
        // Refuse to spend two minutes on words that cannot work. "An app for
        // people to connect" reduces to "people", and a search for that comes
        // back with communities that have nothing to do with the product.
        guard !Discover.tooVague(chosen) else {
            statusLabel.stringValue = L.t(.tooVague)
            return
        }
        let phrases = chosen
        running = true
        findButton.isEnabled = false
        ticked.removeAll()
        meter.show(0)
        statusLabel.stringValue = String(format: L.t(.findingTakes),
                                         "\(Discover.expectedSeconds(for: phrases))")

        Task { @MainActor in
            var done = 0
            let out = await Discover.run(phrases: phrases, progress: { phrase, sofar in
                Task { @MainActor in
                    done += 1
                    self.meter.progress = Double(done) / Double(phrases.count)
                    // Results appear as they are found, not at the end. Six
                    // phrases is two and a half minutes, and for all of it the
                    // panel said "Nothing searched yet" while the status line
                    // claimed 72 communities -- so the app looked broken at
                    // exactly the moment it was working hardest.
                    self.places = sofar
                    self.render([], settled: false)
                    self.statusLabel.stringValue = String(
                        format: L.t(.searchedSoFar), "\(done)", "\(phrases.count)",
                        phrase, "\(sofar.count)")
                }
            })
            self.running = false
            self.findButton.isEnabled = true
            self.meter.show(nil)
            self.places = out.places
            self.render(out.problems)
        }
    }

    private func render(_ problems: [String], settled: Bool = true) {
        guard !places.isEmpty else {
            guard settled else { return }
            showEmpty()
            statusLabel.stringValue = problems.isEmpty ? L.t(.foundNowhere)
                                                       : problems.joined(separator: " · ")
            return
        }
        // Anything found by more than one phrase, plus the strongest singles.
        // Everything found once by one phrase is a very long tail of noise.
        let worth = places.filter { $0.found.count > 1 || $0.hits >= 2 }.prefix(24)
        // Only chosen for them once, at the end. Re-ticking mid-run would undo
        // whatever they had just unticked while watching it fill in.
        if settled { ticked = Set(worth.prefix(8).map(\.name)) }
        else { ticked.formUnion(worth.prefix(8).map(\.name)) }

        resultsStack.setViews(worth.map { place in
            let tick = ToggleChip()
            tick.title = "r/\(place.name)"
            tick.isLit = ticked.contains(place.name)
            tick.target = self
            tick.action = #selector(togglePlace)
            tick.identifier = NSUserInterfaceItemIdentifier(place.name)

            let why = NSTextField.themed(
                String(format: L.t(.foundByHits), "\(place.found.count)", "\(place.hits)"),
                size: 10, color: Theme.textMuted)
            let sample = NSTextField.themed(place.example, size: 10, color: Theme.textMuted)
            sample.lineBreakMode = .byTruncatingTail
            sample.preferredMaxLayoutWidth = 360

            let row = NSStackView(views: [tick, why, sample])
            row.orientation = .horizontal
            row.spacing = 10
            row.alignment = .centerY
            return row
        }, in: .leading)

        watchButton.isEnabled = settled && !ticked.isEmpty
        guard settled else { return }
        var told = String(format: L.t(.foundPlaces), "\(worth.count)", "\(places.count)")
        if !problems.isEmpty { told += " · " + problems.joined(separator: " · ") }
        statusLabel.stringValue = told
    }

    /// For the render harness: the mid-search state.
    func showPartialForTest(phrases p: [String], found: [Discover.Place],
                            done: Int, total: Int, latest: String) {
        show(phrases: p)
        running = true
        findButton.isEnabled = false
        places = found
        render([], settled: false)
        statusLabel.stringValue = String(format: L.t(.searchedSoFar),
                                         "\(done)", "\(total)", latest, "\(found.count)")
    }

    func showPhrasesForTest(_ p: [String]) { show(phrases: p) }

    /// For the render harness.
    func showForTest(_ found: [Discover.Place]) {
        places = found
        render([])
    }

    @objc private func togglePlace(_ sender: ToggleChip) {
        guard let name = sender.identifier?.rawValue else { return }
        sender.isLit.toggle()
        if sender.isLit { ticked.insert(name) } else { ticked.remove(name) }
        watchButton.isEnabled = !ticked.isEmpty
    }

    /// Writes the ticked communities into the workspace, making one if needed.
    @objc private func watchTicked() {
        guard !ticked.isEmpty else { return }
        var workspace = workspaces.active ?? .empty()
        let named = companyField.stringValue.trimmingCharacters(in: .whitespaces)
        if !named.isEmpty { workspace.name = named }
        if workspace.summary.isEmpty {
            workspace.summary = describeField.stringValue.trimmingCharacters(in: .whitespaces)
        }
        // Added to what is already there rather than replacing it: running this
        // twice with different wording should widen the net, not reset it.
        var communities = workspace.communities
        for name in ticked.sorted() where !communities.contains(name) {
            communities.append(name)
        }
        workspace.communities = communities

        // The phrases that found them become the words to watch for, if nothing
        // has been set. They are, by construction, the words that led to these
        // communities in the first place.
        if workspace.terms.isEmpty {
            workspace.terms = Discover.phrases(from: describeField.stringValue)
                .prefix(Discover.maximumPhrases).map { $0 }
        }
        // Something to say about the product, or no draft can ever be written.
        //
        // This was the flow's dead end and it was invisible: `Draft.write`
        // returns nil without a matched feature, so a customer who came through
        // Find got leads with a permanently empty reply box and nothing
        // explaining why. What they typed into "What does it do?" is exactly the
        // claim a draft needs -- it is already the answer to "it can ___".
        if workspace.features.isEmpty {
            let described = describeField.stringValue.trimmingCharacters(in: .whitespaces)
            if !described.isEmpty {
                workspace.features = [.init(
                    name: workspace.name.isEmpty ? L.t(.whatItDoes) : workspace.name,
                    triggers: workspace.terms,
                    doesWhat: described.asCapability)]
            }
        }

        workspaces.save(workspace)
        workspaces.activate(workspace.id)
        statusLabel.stringValue = String(format: L.t(.nowWatching),
                                         "\(ticked.count)", "\(workspace.communities.count)")
        // Straight on to the sweep. Finding the places is not the point; the
        // point is what is being said in them.
        onReady?()
    }
}


extension FindTab: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) { derive() }
}


private extension String {
    /// Turns what somebody wrote about themselves into what the product can do.
    ///
    /// The description is written in the first person -- "batch export MY whole
    /// music library" -- and a draft says "it can ___", so the possessive comes
    /// out backwards: "it can batch export my whole music library" is the
    /// product claiming to export the reader's collection into its own hands.
    /// Swapped to the second person, which is what the sentence means when the
    /// product is the one doing it.
    var asCapability: String {
        var out = self
        for (mine, yours) in [(" my ", " your "), (" our ", " your "),
                              (" mine", " yours"), (" me ", " you ")] {
            out = out.replacingOccurrences(of: mine, with: yours,
                                           options: .caseInsensitive)
        }
        if out.lowercased().hasPrefix("my ") { out = "your " + out.dropFirst(3) }
        // Lower-cased first character so it reads inside "it can ___", but only
        // when the rest is not an acronym: "MIDI sync" must stay MIDI.
        guard let first = out.first, first.isUppercase,
              !out.prefix(2).allSatisfy({ $0.isUppercase })
        else { return out }
        return first.lowercased() + out.dropFirst()
    }
}

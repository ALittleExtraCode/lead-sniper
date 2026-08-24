import Cocoa
import UniformTypeIdentifiers

/// The leads, and the reply being written to one of them.
///
/// A list on the left and the writing on the right, because those are the two
/// halves of the job and doing one always means looking at the other. The post
/// stays on screen while the reply is written — the alternative is a modal that
/// hides the thing you are replying to, which is how generic replies get
/// written.
final class RadarTab: NSView, NSTableViewDataSource, NSTableViewDelegate, PrimaryAction {

    private let workspaces = Workspaces.shared
    private let radar = Radar()
    private lazy var watch = Watch(radar: radar, workspaces: workspaces)
    private let watchPicker = MenuChip()

    private let table = NSTableView()
    private let statusLabel = NSTextField.themed("", size: 11, color: Theme.textMuted)
    private let sweepButton = AccentButton(title: "", target: nil, action: nil)
    private let emptyLabel = NSTextField.themed("", size: 12, color: Theme.textMuted)
    private let meter = Meter()
    private let countdown = NSTextField.themed("", size: 10.5, color: Theme.textMuted)
    private var ticker: Timer?
    private var nextCheck: Date?
    private var dismissButton: NSButton?

    private let postTitle = NSTextField(wrappingLabelWithString: "")
    private let postMeta = NSTextField.themed("", size: 10.5, color: Theme.textMuted)
    private let postBody = NSTextField(wrappingLabelWithString: "")
    private let whyStack = FlowStack()
    private let editor = NSTextView()
    private let editorScroll = NSScrollView()
    private let gapLabel = NSTextField.themed("", size: 10.5, color: Theme.textMuted)
    private let copyButton = AccentButton(title: "", target: nil, action: nil)
    private let openButton = NSButton()

    private var leads: [Radar.Lead] = []
    private var draft: Draft.Result?
    private var sweeping = false
    private var sweepOffset = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        watch.onSweep = { [weak self] result in
            guard let self else { return }
            self.leads = result.leads
            self.table.reloadData()
            self.report(result)
            if self.table.selectedRow < 0, !result.leads.isEmpty {
                self.table.selectRowIndexes([0], byExtendingSelection: false)
                self.showSelection(result.leads[0])
            }
        }
        Watch.requestPermission()
        watch.start()
        armCountdown()
        // Whatever was on screen last time, back on screen. Waiting up to half
        // an hour for the next sweep before showing anything is a long time to
        // look at an empty list.
        let kept = radar.recall()
        if !kept.isEmpty {
            leads = kept
            table.reloadData()
            table.selectRowIndexes([0], byExtendingSelection: false)
            showSelection(kept[0])
            reportRestored()
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        // A repeating Timer is retained by the run loop, not by this view, so
        // without this it keeps firing for the life of the process against a
        // view nobody can see. The watch's task is cancelled for the same
        // reason: it would go on sweeping, and spending the rate limit, for a
        // tab that is gone.
        ticker?.invalidate()
        Task { @MainActor [watch] in watch.stop() }
    }

    func refresh() {
        updateStatus()
        if leads.isEmpty { showSelection(nil) }
    }

    /// Marks a restored list as restored. "12 worth answering" about a list from
    /// yesterday reads as twelve found just now.
    private func reportRestored() {
        statusLabel.stringValue = String(format: L.t(.fromLastTime), "\(leads.count)")
        emptyLabel.isHidden = true
    }

    func performPrimaryAction() { sweep() }

    // MARK: - Layout

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = .clear

        // ---- left: the list ------------------------------------------------
        table.headerView = nil
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .regular
        table.gridStyleMask = []
        table.style = .plain
        table.rowHeight = 66
        table.dataSource = self
        table.delegate = self
        table.doubleAction = #selector(openThread)
        table.target = self
        table.addTableColumn(NSTableColumn(identifier: .init("lead")))

        let listScroll = NSScrollView()
        listScroll.documentView = table
        listScroll.hasVerticalScroller = true
        listScroll.drawsBackground = false
        listScroll.translatesAutoresizingMaskIntoConstraints = false

        sweepButton.title = L.t(.sweep)
        sweepButton.target = self
        sweepButton.action = #selector(sweep)
        sweepButton.translatesAutoresizingMaskIntoConstraints = false
        sweepButton.heightAnchor.constraint(equalToConstant: 38).isActive = true
        sweepButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 0
        statusLabel.preferredMaxLayoutWidth = 170

        // How often it looks by itself. Beside the manual button rather than
        // buried in a settings window, because it is the setting that decides
        // whether the product works: a lead is worth 20 points in its first hour
        // and 3 after a day.
        watchPicker.items = Watch.Interval.allCases.map { (title: $0.title, tag: $0.rawValue) }
        watchPicker.offTag = Watch.Interval.off.rawValue
        watchPicker.selectedTag = watch.interval.rawValue
        watchPicker.target = self
        watchPicker.action = #selector(watchChanged)

        let controls = NSStackView(views: [sweepButton, statusLabel])
        controls.orientation = .horizontal
        controls.spacing = 12
        controls.alignment = .centerY
        controls.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.lineBreakMode = .byWordWrapping
        emptyLabel.maximumNumberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        // Shortcuts nobody is told about are shortcuts nobody uses.
        let keys = NSTextField.themed(L.t(.keyboardHint), size: 10, color: Theme.textMuted)

        let watchRow = NSStackView(views: [
            NSTextField.themed(L.t(.watchingLabel), size: 10.5, color: Theme.textMuted),
            watchPicker, countdown, NSView()])
        watchRow.orientation = .horizontal
        watchRow.spacing = 8
        watchRow.alignment = .centerY
        watchRow.translatesAutoresizingMaskIntoConstraints = false

        let left = NSView()
        left.translatesAutoresizingMaskIntoConstraints = false
        meter.translatesAutoresizingMaskIntoConstraints = false
        meter.heightAnchor.constraint(equalToConstant: 4).isActive = true
        meter.isHidden = true

        keys.translatesAutoresizingMaskIntoConstraints = false
        left.addSubview(watchRow)
        left.addSubview(keys)
        left.addSubview(meter)
        left.addSubview(controls)
        left.addSubview(listScroll)
        left.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: left.topAnchor),
            controls.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            controls.trailingAnchor.constraint(lessThanOrEqualTo: left.trailingAnchor),
            watchRow.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 10),
            watchRow.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            keys.topAnchor.constraint(equalTo: watchRow.bottomAnchor, constant: 8),
            keys.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            meter.topAnchor.constraint(equalTo: keys.bottomAnchor, constant: 8),
            meter.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            meter.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            listScroll.topAnchor.constraint(equalTo: meter.bottomAnchor, constant: 10),
            listScroll.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            listScroll.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            listScroll.bottomAnchor.constraint(equalTo: left.bottomAnchor),
            emptyLabel.topAnchor.constraint(equalTo: listScroll.topAnchor, constant: 8),
            emptyLabel.leadingAnchor.constraint(equalTo: listScroll.leadingAnchor),
            emptyLabel.widthAnchor.constraint(equalTo: listScroll.widthAnchor, constant: -8),
        ])

        // ---- right: one continuous read, not three boxes -------------------
        //
        // This was three cards stacked with a gap between each. Three boxes down
        // a column is what a preferences pane looks like; a thread you are about
        // to answer is one thing, read top to bottom, so it is set as one.
        let right = NSStackView()
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = Theme.Space.gap
        right.edgeInsets = NSEdgeInsets(top: Theme.Space.section, left: Theme.Space.section,
                                        bottom: Theme.Space.section, right: Theme.Space.section)
        right.translatesAutoresizingMaskIntoConstraints = false

        // The post title is the content, so it is set like content.
        postTitle.font = Theme.Font.display
        postTitle.textColor = Theme.textPrimary
        postTitle.maximumNumberOfLines = 3
        postTitle.preferredMaxLayoutWidth = 640

        postMeta.font = Theme.Font.meta

        postBody.font = Theme.Font.body
        postBody.textColor = Theme.textSecond
        postBody.maximumNumberOfLines = 10
        postBody.cell?.wraps = true
        postBody.cell?.truncatesLastVisibleLine = true
        postBody.preferredMaxLayoutWidth = 640

        for view in [postTitle, postMeta, postBody] {
            right.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: right.widthAnchor,
                                        constant: -Theme.Space.section * 2).isActive = true
        }

        let firstRule = Theme.rule()
        right.addArrangedSubview(firstRule)
        firstRule.widthAnchor.constraint(equalTo: right.widthAnchor,
                                         constant: -Theme.Space.section * 2).isActive = true

        let whyLabel = Theme.sectionLabel(L.t(.whyItMatched))
        right.addArrangedSubview(whyLabel)
        whyStack.translatesAutoresizingMaskIntoConstraints = false
        right.addArrangedSubview(whyStack)
        whyStack.widthAnchor.constraint(equalTo: right.widthAnchor,
                                        constant: -Theme.Space.section * 2).isActive = true

        let secondRule = Theme.rule()
        right.addArrangedSubview(secondRule)
        secondRule.widthAnchor.constraint(equalTo: right.widthAnchor,
                                          constant: -Theme.Space.section * 2).isActive = true

        right.addArrangedSubview(Theme.sectionLabel(L.t(.yourReply)))

        editor.font = Theme.Font.body
        editor.textColor = Theme.textPrimary
        editor.backgroundColor = Theme.sunken
        editor.insertionPointColor = Theme.accent
        editor.isEditable = true
        editor.isRichText = false
        editor.textContainerInset = NSSize(width: 12, height: 12)
        editor.delegate = self
        editorScroll.documentView = editor
        editorScroll.drawsBackground = false
        editorScroll.hasVerticalScroller = true
        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        editorScroll.wantsLayer = true
        editorScroll.layer?.borderWidth = 1
        editorScroll.layer?.borderColor = NSColor(srgbRed: 0xd8/255, green: 0xd4/255,
                                                  blue: 0xc9/255, alpha: 1).cgColor
        editorScroll.layer?.backgroundColor = Theme.sunken.cgColor
        editorScroll.drawsBackground = true
        editorScroll.backgroundColor = Theme.sunken
        editorScroll.layer?.cornerRadius = 10
        editorScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true

        gapLabel.font = Theme.Font.meta
        gapLabel.lineBreakMode = .byWordWrapping
        gapLabel.maximumNumberOfLines = 0
        gapLabel.preferredMaxLayoutWidth = 640

        copyButton.title = L.t(.copyAndOpen)
        copyButton.target = self
        copyButton.action = #selector(copyAndOpen)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        copyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true

        openButton.title = L.t(.justOpen)
        openButton.isBordered = false
        openButton.font = .systemFont(ofSize: 12, weight: .semibold)
        openButton.contentTintColor = Theme.accent
        openButton.target = self
        openButton.action = #selector(openThread)

        let dismissButton = NSButton(title: L.t(.notRelevant), target: self, action: #selector(toggleDismiss))
        dismissButton.isBordered = false
        dismissButton.font = .systemFont(ofSize: 12, weight: .semibold)
        dismissButton.contentTintColor = Theme.textMuted
        self.dismissButton = dismissButton

        let exportButton = NSButton(title: L.t(.exportLeads), target: self, action: #selector(exportLeads))
        exportButton.isBordered = false
        exportButton.font = .systemFont(ofSize: 12, weight: .semibold)
        exportButton.contentTintColor = Theme.textMuted

        let actions = NSStackView(views: [copyButton, openButton, dismissButton, exportButton, NSView()])
        actions.orientation = .horizontal
        actions.spacing = Theme.Space.gap
        actions.alignment = .centerY

        for view in [editorScroll, gapLabel, actions] {
            right.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: right.widthAnchor,
                                        constant: -Theme.Space.section * 2).isActive = true
        }

        let panel = NSView()
        panel.wantsLayer = true
        panel.layer?.backgroundColor = Theme.card.cgColor
        panel.translatesAutoresizingMaskIntoConstraints = false

        let edge = NSView()
        edge.wantsLayer = true
        edge.layer?.backgroundColor = Theme.cardBorder.cgColor
        edge.translatesAutoresizingMaskIntoConstraints = false

        let rightScroll = NSScrollView()
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(right)
        rightScroll.documentView = doc
        rightScroll.drawsBackground = false
        rightScroll.hasVerticalScroller = true
        rightScroll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(left)
        addSubview(panel)
        panel.addSubview(edge)
        panel.addSubview(rightScroll)
        NSLayoutConstraint.activate([
            doc.widthAnchor.constraint(equalTo: rightScroll.contentView.widthAnchor),
            right.topAnchor.constraint(equalTo: doc.topAnchor),
            right.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            right.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            right.bottomAnchor.constraint(equalTo: doc.bottomAnchor),

            left.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Space.margin),
            left.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            // The list is a fixed column and the post gets everything else. The
            // other way round gave 568pt to two one-line rows and squeezed the
            // post being answered into 480.
            left.widthAnchor.constraint(equalToConstant: 360),

            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: Theme.Space.margin),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),

            edge.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            edge.topAnchor.constraint(equalTo: panel.topAnchor),
            edge.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            edge.widthAnchor.constraint(equalToConstant: 1),

            rightScroll.topAnchor.constraint(equalTo: panel.topAnchor),
            rightScroll.leadingAnchor.constraint(equalTo: edge.trailingAnchor),
            rightScroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            rightScroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
        ])

        showSelection(nil)
        updateStatus()
    }

    // MARK: - Sweeping

    /// Reloads the workspace and sweeps. Called when Find hands over.
    func beginSweep() {
        updateStatus()
        sweep()
    }

    @objc private func sweep() {
        guard !sweeping else { return }
        guard let workspace = workspaces.active, workspace.isUsable else {
            statusLabel.stringValue = L.t(.needsSetup)
            return
        }
        sweeping = true
        sweepButton.isEnabled = false
        let seconds = Radar.expectedSeconds(for: workspace)
        statusLabel.stringValue = seconds > 25
            ? String(format: L.t(.sweepingLong), "\(seconds)")
            : L.t(.sweeping)

        let offset = sweepOffset
        sweepOffset += Radar.groupSize
        meter.show(0)
        Task { @MainActor in
            let result = await radar.sweep(workspace, offset: offset,
                progress: { done, total in
                    Task { @MainActor in
                        self.meter.progress = total > 0 ? Double(done) / Double(total) : 0
                    }
                })
            self.leads = result.leads
            self.sweeping = false
            self.sweepButton.isEnabled = true
            self.meter.show(nil)
            self.armCountdown()
            self.table.reloadData()
            self.report(result)
            if !result.leads.isEmpty {
                self.table.selectRowIndexes([0], byExtendingSelection: false)
                self.showSelection(result.leads[0])
            } else {
                self.showSelection(nil)
            }
        }
    }

    /// What the sweep found, said plainly.
    ///
    /// "0 leads" on its own is what makes somebody conclude the product is
    /// broken, when in fact it read 200 posts and none of them were about their
    /// product — which is the correct answer and a different one.
    private func report(_ result: Radar.Sweep) {
        var parts: [String] = []
        if result.leads.isEmpty {
            parts.append(String(format: L.t(.nothingFound), "\(result.scanned)"))
        } else {
            let fresh = result.leads.filter(\.isNew).count
            parts.append(String(format: L.t(.foundLeads), "\(result.leads.count)", "\(result.scanned)"))
            if fresh > 0 { parts.append(String(format: L.t(.ofWhichNew), "\(fresh)")) }
        }
        // What the sweep overheard that is not being watched for. A phrase your
        // customers use that never occurred to you is worth more than another
        // count of one you already had.
        if !result.overheard.isEmpty {
            let top = result.overheard.prefix(3).map { "\"\($0.phrase)\"" }
            parts.append(String(format: L.t(.alsoSaying), top.joined(separator: ", ")))
        }
        parts.append(contentsOf: result.problems)
        statusLabel.stringValue = parts.joined(separator: " · ")
        emptyLabel.stringValue = result.leads.isEmpty ? String(format: L.t(.nothingFoundLong), "\(result.scanned)") : ""
        emptyLabel.isHidden = !result.leads.isEmpty
    }

    private func updateStatus() {
        guard let workspace = workspaces.active, workspace.isUsable else {
            statusLabel.stringValue = L.t(.needsSetup)
            emptyLabel.stringValue = L.t(.needsSetupLong)
            emptyLabel.isHidden = false
            sweepButton.isEnabled = false
            return
        }
        sweepButton.isEnabled = !sweeping
        if leads.isEmpty {
            statusLabel.stringValue = String(format: L.t(.watching),
                                             "\(workspace.communities.count)", workspace.name)
            emptyLabel.stringValue = L.t(.readyToSweep)
            emptyLabel.isHidden = false
        }
    }

    /// A visible countdown to the next automatic check.
    ///
    /// The watch was completely invisible: it swept every half hour and the only
    /// evidence was the list quietly changing. An interval picker that says
    /// "Every half hour" with nothing behind it asks to be trusted; a number
    /// counting down can be checked.
    func armCountdown() {
        ticker?.invalidate()
        guard watch.interval != .off else {
            nextCheck = nil
            countdown.stringValue = ""
            return
        }
        nextCheck = Date().addingTimeInterval(TimeInterval(watch.interval.rawValue))
        tick()
        // Every ten seconds, not every second. A number flickering once a second
        // in the corner of the eye is the kind of motion this app avoids, and
        // "in 24 min" does not need finer resolution than that.
        ticker = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let nextCheck else { countdown.stringValue = ""; return }
        let left = nextCheck.timeIntervalSinceNow
        guard left > 0 else { countdown.stringValue = L.t(.checkingNow); return }
        countdown.stringValue = left < 90
            ? String(format: L.t(.nextCheckSeconds), "\(Int(left))")
            : String(format: L.t(.nextCheckMinutes), "\(Int((left / 60).rounded()))")
    }

    @objc private func watchChanged() {
        let chosen = Watch.Interval(rawValue: watchPicker.selectedTag) ?? .off
        watch.set(chosen)
        armCountdown()
        if chosen != .off { statusLabel.stringValue = L.t(.watching2) }
    }

    // MARK: - Selection

    private func showSelection(_ lead: Radar.Lead?) {
        guard let lead, let workspace = workspaces.active else {
            postTitle.stringValue = ""
            postMeta.stringValue = ""
            postBody.stringValue = ""
            whyStack.setViews([])
            editor.string = ""
            draft = nil
            gapLabel.stringValue = ""
            copyButton.isEnabled = false
            openButton.isHidden = true
            dismissButton?.isHidden = true
            return
        }
        postTitle.stringValue = lead.post.title
        postMeta.stringValue = "r/\(lead.post.source) · u/\(lead.post.author) · \(Self.ago(lead.post.posted))"
        postBody.stringValue = lead.post.body

        // Every point on screen is attributable to something in the post.
        whyStack.setViews(lead.verdict.reasons.map { reason in
            let chip = ToggleChip()
            chip.title = "\(Self.name(reason.label)) · \(reason.detail)"
            chip.isLit = reason.points >= 20
            chip.isEnabled = false
            return chip
        })

        openButton.isHidden = false
        dismissButton?.isHidden = false
        dismissButton?.title = lead.isDismissed ? L.t(.putBack) : L.t(.notRelevant)

        // Looked at and rejected: no draft, and say so. It stays visible rather
        // than vanishing, because a list that silently loses rows is one nobody
        // trusts.
        if lead.isDismissed {
            draft = nil
            editor.string = ""
            gapLabel.stringValue = L.t(.dismissedNote)
            copyButton.isEnabled = false
            return
        }

        // Already replied to: say so, and do not offer a draft. The same thread
        // comes back in every sweep while it is on the front page.
        if lead.isAnswered {
            draft = nil
            editor.string = ""
            gapLabel.stringValue = L.t(.alreadyAnswered)
            copyButton.isEnabled = false
            return
        }

        if let written = Draft.write(for: lead.post, verdict: lead.verdict, workspace: workspace) {
            draft = written
            editor.string = written.text
            gapLabel.stringValue = written.gaps.map { "· \($0)" }.joined(separator: "\n")
        } else {
            draft = nil
            editor.string = ""
            gapLabel.stringValue = L.t(.noDraftPossible)
        }
        updateCopyState()
    }

    /// The copy button is the enforcement point.
    ///
    /// A draft that can be copied unchanged is a template, and a template gets
    /// the customer banned. So this stays disabled until a person has actually
    /// written something, and says which condition is still unmet.
    private func updateCopyState() {
        guard let draft else {
            copyButton.isEnabled = !editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return
        }
        let edited = draft.hasBeenEdited(editor.string)
        let problems = Draft.isReadyToPost(editor.string)
        copyButton.isEnabled = edited && problems.isEmpty
        if !edited {
            gapLabel.stringValue = L.t(.mustEdit)
        } else if !problems.isEmpty {
            gapLabel.stringValue = problems.map { "· \($0)" }.joined(separator: "\n")
        } else {
            gapLabel.stringValue = L.t(.readyToPost)
        }
    }

    @objc func copyAndOpen() {
        guard copyButton.isEnabled else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(editor.string, forType: .string)
        // Recorded at the point of copying, not of posting, because that is the
        // last moment the app can see. Better to mark one you abandoned than to
        // let the same thread come back unmarked every sweep.
        if let lead = leads[safe: table.selectedRow] {
            radar.markAnswered(lead.post.id)
            leads[table.selectedRow].isAnswered = true
            table.reloadData()
            gapLabel.stringValue = L.t(.alreadyAnswered)
            copyButton.isEnabled = false
        }
        openThread()
    }

    /// Says no to a lead, or takes it back.
    ///
    /// Reversible on purpose. A keystroke that cannot be undone is one people
    /// are careful with, and careful is slow -- which defeats the point of a
    /// list you are meant to work down quickly.
    @objc func toggleDismiss() {
        let row = table.selectedRow
        guard let lead = leads[safe: row] else { return }
        if lead.isDismissed {
            radar.restore(lead.post.id)
            leads[row].isDismissed = false
        } else {
            // The whole lead, not just the id: the post is what the radar
            // learns from.
            radar.dismiss(lead)
            leads[row].isDismissed = true
            offerNegatives()
        }
        table.reloadData()
        showSelection(leads[safe: row])

        // Straight on to the next one. The whole reason for a keyboard shortcut
        // is not having to aim at anything between decisions.
        if leads[row].isDismissed, row + 1 < leads.count {
            table.selectRowIndexes([row + 1], byExtendingSelection: false)
            showSelection(leads[safe: row + 1])
        }
    }

    /// Driven from the menu, so the shortcuts work from anywhere.
    func dismissSelected() { toggleDismiss() }
    func copyAndOpenSelected() { copyAndOpen() }
    func exportSelected() { exportLeads() }

    /// What the rejections have in common, offered once there are enough of them.
    ///
    /// Suggested rather than applied. Adding a word to "never show me" silently,
    /// on the app's own initiative, would mean leads disappearing for a reason
    /// nobody was told about -- which is the worst failure this product can
    /// have, because it is invisible.
    private func offerNegatives() {
        guard let workspace = workspaces.active else { return }
        let common = Scout.whyRejected(radar.rejectedPosts(), against: workspace)
        guard !common.isEmpty else { return }
        statusLabel.stringValue = String(format: L.t(.rejectedPattern),
                                         common.prefix(3).map { "\"\($0.phrase)\"" }
                                             .joined(separator: ", "))
    }

    /// D dismisses, U undoes, Return opens the thread.
    ///
    /// The arrow keys already move the selection, so the only thing missing was
    /// a way to decide without reaching for the mouse.
    override func keyDown(with event: NSEvent) {
        // Never while something is being typed: "d" belongs to the editor.
        if let responder = window?.firstResponder,
           responder is NSTextView || responder is NSTextField {
            super.keyDown(with: event)
            return
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "d", "u":
            toggleDismiss()
        case "\r":
            openThread()
        default:
            super.keyDown(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    @objc func exportLeads() {
        guard !leads.isEmpty, let workspace = workspaces.active else {
            statusLabel.stringValue = L.t(.nothingToExport)
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Share.filename(for: workspace, extension: "csv")
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Share.csv(leads).write(to: url, atomically: true, encoding: .utf8)
            statusLabel.stringValue = String(format: L.t(.exportedLeads),
                                             "\(leads.count)", url.lastPathComponent)
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func openThread() {
        guard let row = table.selectedRow as Int?, let lead = leads[safe: row],
              let link = lead.post.link else { return }
        NSWorkspace.shared.open(link)
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { leads.count }

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let lead = leads[safe: row] else { return nil }
        let width = column?.width ?? tableView.bounds.width
        let spent = lead.isAnswered || lead.isDismissed

        let cell = NSView(frame: NSRect(x: 0, y: 0, width: width, height: tableView.rowHeight))
        cell.autoresizingMask = [.width]
        cell.wantsLayer = true

        // A colour bar down the left edge rather than a word in the corner.
        // Band, state and selection are three things the eye needs before it
        // reads anything, and a 3pt rule carries all of them without spending a
        // line of text on it.
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = (spent ? Theme.cardBorder
                                            : Self.bandColour(lead.verdict.band)).cgColor
        bar.layer?.cornerRadius = 1.5
        bar.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(wrappingLabelWithString: lead.post.title)
        title.font = Theme.Font.serif(14.5, weight: spent ? .regular : .semibold)
        title.textColor = spent ? Theme.textMuted : Theme.textPrimary
        title.preferredMaxLayoutWidth = width - 34
        title.cell?.wraps = true
        title.cell?.truncatesLastVisibleLine = true
        title.maximumNumberOfLines = 2
        title.identifier = NSUserInterfaceItemIdentifier("mayTruncate")

        let state = lead.isDismissed ? L.t(.dismissed)
                  : lead.isAnswered ? L.t(.answered)
                  : Self.bandName(lead.verdict.band)
        let meta = NSTextField(labelWithAttributedString: NSAttributedString(
            string: "\(state)   r/\(lead.post.source)   \(Self.ago(lead.post.posted))",
            attributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                         .foregroundColor: spent ? Theme.textMuted
                                                 : Self.bandColour(lead.verdict.band),
                         .kern: 0.5]))
        meta.lineBreakMode = .byTruncatingTail

        let words = NSStackView(views: [title, meta])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 3
        words.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(bar)
        cell.addSubview(words)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            bar.topAnchor.constraint(equalTo: cell.topAnchor, constant: 9),
            bar.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -9),
            bar.widthAnchor.constraint(equalToConstant: 3),
            words.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 12),
            words.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            words.topAnchor.constraint(equalTo: cell.topAnchor, constant: 11),
        ])

        let hairline = NSView()
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = Theme.cardBorder.cgColor
        hairline.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(hairline)
        NSLayoutConstraint.activate([
            hairline.leadingAnchor.constraint(equalTo: words.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            hairline.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
        ])

        return cell
    }

    /// The row draws its own selection.
    ///
    /// This was a tinted view inside the cell, rebuilt on `reloadData` from
    /// inside the selection delegate — which AppKit does not honour. Measured:
    /// every row was built exactly once, with `selectedRow = -1`, so the
    /// highlight was written and never drawn and you could not tell what was
    /// selected. A row view redraws itself when the selection changes, which is
    /// what it is for.
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        LeadRow()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        showSelection(leads[safe: table.selectedRow])
    }

    /// For the render harness: mid-sweep, with the bar part way.
    func showSweepingForTest(_ progress: Double) {
        meter.show(progress)
        sweepButton.isEnabled = false
        statusLabel.stringValue = "Reading the feeds…"
        armCountdown()
    }

    /// For the render harness: puts leads on screen without a sweep.
    func showForTest(_ found: [Radar.Lead], now: Date) {
        leads = found
        table.reloadData()
        statusLabel.stringValue = String(format: L.t(.foundLeads), "\(found.count)", "50")
        emptyLabel.isHidden = true
        if !found.isEmpty {
            table.selectRowIndexes([0], byExtendingSelection: false)
            showSelection(found[0])
        }
    }

    // MARK: - Wording

    static func bandName(_ band: Score.Verdict.Band) -> String {
        switch band {
        case .hot:  return L.t(.bandHot)
        case .warm: return L.t(.bandWarm)
        case .cool: return L.t(.bandCool)
        case .skip: return ""
        }
    }

    static func bandColour(_ band: Score.Verdict.Band) -> NSColor {
        switch band {
        case .hot:  return Theme.hot
        case .warm: return Theme.warm
        default:    return Theme.cool
        }
    }

    static func name(_ label: Score.Reason.Label) -> String {
        switch label {
        case .asking:           return L.t(.reasonAsking)
        case .wantsAlternative: return L.t(.reasonShopping)
        case .titleMatch:       return L.t(.reasonTitle)
        case .bodyMatch:        return L.t(.reasonBody)
        case .feature:          return L.t(.reasonFeature)
        case .fresh:            return L.t(.reasonFresh)
        case .painPoint:        return L.t(.reasonPain)
        }
    }

    /// How long ago, in the roughest useful unit. A lead an hour old and one
    /// ninety minutes old are the same lead.
    static func ago(_ date: Date, from now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<120:      return L.t(.justNow)
        case ..<3600:     return String(format: L.t(.minutesAgo), "\(Int(seconds / 60))")
        case ..<86_400:   return String(format: L.t(.hoursAgo), "\(Int(seconds / 3600))")
        default:          return String(format: L.t(.daysAgo), "\(Int(seconds / 86_400))")
        }
    }
}

extension RadarTab: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) { updateCopyState() }
}

/// Top-left origin, so a stack in a scroll view fills downwards.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}


/// A row that lifts off the page when it is the one being read.
///
/// White on the paper list, with a soft shadow — the same relationship the
/// detail panel has to the page, so selecting a lead and reading it look like
/// one gesture.
final class LeadRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let box = bounds.insetBy(dx: 0, dy: 3)
        let path = NSBezierPath(roundedRect: NSRect(x: box.minX, y: box.minY,
                                                    width: box.width - 6, height: box.height),
                                xRadius: 8, yRadius: 8)
        NSGraphicsContext.current?.saveGraphicsState()
        let lift = NSShadow()
        lift.shadowColor = NSColor(white: 0, alpha: 0.09)
        lift.shadowOffset = NSSize(width: 0, height: -1)
        lift.shadowBlurRadius = 4
        lift.set()
        Theme.card.setFill()
        path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}

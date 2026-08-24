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
        table.selectionHighlightStyle = .none
        table.gridStyleMask = []
        table.style = .plain
        table.rowHeight = 78
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
        sweepButton.widthAnchor.constraint(equalToConstant: 150).isActive = true

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
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

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

        left.addSubview(watchRow)
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
            meter.topAnchor.constraint(equalTo: watchRow.bottomAnchor, constant: 10),
            meter.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            meter.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            listScroll.topAnchor.constraint(equalTo: meter.bottomAnchor, constant: 10),
            listScroll.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            listScroll.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            listScroll.bottomAnchor.constraint(equalTo: left.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: listScroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: listScroll.centerYAnchor),
            emptyLabel.widthAnchor.constraint(equalTo: listScroll.widthAnchor, constant: -60),
        ])

        // ---- right: the post, and the reply --------------------------------
        let right = NSStackView()
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 14
        right.translatesAutoresizingMaskIntoConstraints = false

        postTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        postTitle.textColor = Theme.textPrimary
        postTitle.maximumNumberOfLines = 3
        postTitle.preferredMaxLayoutWidth = 640

        postBody.font = .systemFont(ofSize: 12)
        postBody.textColor = Theme.textSecond
        postBody.maximumNumberOfLines = 8
        postBody.cell?.wraps = true
        postBody.cell?.truncatesLastVisibleLine = true
        postBody.preferredMaxLayoutWidth = 640

        let postBox = NSStackView(views: [postTitle, postMeta, postBody])
        postBox.orientation = .vertical
        postBox.alignment = .leading
        postBox.spacing = 6
        for label in [postTitle, postMeta, postBody] {
            label.widthAnchor.constraint(equalTo: postBox.widthAnchor).isActive = true
        }
        // Cards fill the column. An .leading-aligned stack sizes its children to
        // their intrinsic width, which left an empty "THE POST" card 140pt wide
        // beside a full-width one below it.
        func addCard(_ title: String, _ body: NSView) {
            let card = CardView.titled(title, body)
            right.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
        }

        addCard(L.t(.thePost), postBox)

        whyStack.translatesAutoresizingMaskIntoConstraints = false
        addCard(L.t(.whyItMatched), whyStack)

        // The editor. A real NSTextView, because this is writing rather than a
        // field to fill in, and it should feel like it.
        editor.font = .systemFont(ofSize: 12.5)
        editor.textColor = Theme.textPrimary
        editor.backgroundColor = Theme.card
        editor.insertionPointColor = Theme.accent
        editor.isEditable = true
        editor.isRichText = false
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.delegate = self
        editorScroll.documentView = editor
        editorScroll.drawsBackground = false
        // A visible edge, because a white box on a white card is not a box. On
        // the dark theme the darker fill did this job by itself.
        editorScroll.wantsLayer = true
        editorScroll.layer?.borderWidth = 1
        editorScroll.layer?.borderColor = Theme.cardBorder.cgColor
        editorScroll.layer?.cornerRadius = 8
        editorScroll.hasVerticalScroller = true
        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        editorScroll.heightAnchor.constraint(equalToConstant: 132).isActive = true

        gapLabel.lineBreakMode = .byWordWrapping
        gapLabel.maximumNumberOfLines = 0
        gapLabel.preferredMaxLayoutWidth = 640

        copyButton.title = L.t(.copyAndOpen)
        copyButton.target = self
        copyButton.action = #selector(copyAndOpen)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        copyButton.widthAnchor.constraint(equalToConstant: 190).isActive = true

        openButton.title = L.t(.justOpen)
        openButton.isBordered = false
        openButton.font = .systemFont(ofSize: 11, weight: .semibold)
        openButton.contentTintColor = Theme.accent
        openButton.target = self
        openButton.action = #selector(openThread)

        let exportButton = NSButton(title: L.t(.exportLeads), target: self, action: #selector(exportLeads))
        exportButton.isBordered = false
        exportButton.font = .systemFont(ofSize: 11, weight: .semibold)
        exportButton.contentTintColor = Theme.accent

        let actions = NSStackView(views: [copyButton, openButton, exportButton, NSView()])
        actions.orientation = .horizontal
        actions.spacing = 12
        actions.alignment = .centerY

        let replyBox = NSStackView(views: [editorScroll, gapLabel, actions])
        replyBox.orientation = .vertical
        replyBox.alignment = .leading
        replyBox.spacing = 8
        editorScroll.widthAnchor.constraint(equalTo: replyBox.widthAnchor).isActive = true
        gapLabel.widthAnchor.constraint(equalTo: replyBox.widthAnchor).isActive = true
        actions.widthAnchor.constraint(equalTo: replyBox.widthAnchor).isActive = true
        addCard(L.t(.yourReply), replyBox)

        let rightScroll = NSScrollView()
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(right)
        rightScroll.documentView = doc
        rightScroll.drawsBackground = false
        rightScroll.hasVerticalScroller = true
        rightScroll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(left)
        addSubview(rightScroll)
        NSLayoutConstraint.activate([
            doc.widthAnchor.constraint(equalTo: rightScroll.contentView.widthAnchor),
            right.topAnchor.constraint(equalTo: doc.topAnchor),
            right.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            right.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            right.bottomAnchor.constraint(equalTo: doc.bottomAnchor),

            left.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            left.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            // The list is a fixed column and the post gets everything else. The
            // other way round gave 568pt to two one-line rows and squeezed the
            // post being answered into 480.
            left.widthAnchor.constraint(equalToConstant: 340),

            rightScroll.topAnchor.constraint(equalTo: topAnchor),
            rightScroll.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 16),
            rightScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            rightScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
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
    private func armCountdown() {
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

    @objc private func copyAndOpen() {
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

    @objc private func exportLeads() {
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

        let cell = NSView(frame: NSRect(x: 0, y: 0, width: width, height: tableView.rowHeight))
        cell.autoresizingMask = [.width]

        let band = NSTextField.themed(
            lead.isAnswered ? L.t(.answered) : Self.bandName(lead.verdict.band),
            size: 9.5,
            color: lead.isAnswered ? Theme.cool : Self.bandColour(lead.verdict.band))
        band.font = .systemFont(ofSize: 9.5, weight: .bold)

        let meta = NSTextField.themed("r/\(lead.post.source) · \(Self.ago(lead.post.posted))",
                                      size: 9.5, color: Theme.textMuted)
        let head = NSStackView(views: [band, meta, NSView()])
        head.orientation = .horizontal
        head.spacing = 8

        let title = NSTextField(wrappingLabelWithString: lead.post.title)
        // Answered rows are always regular weight. Muting the colour alone was
        // enough on a dark ground; on paper a semibold line still pulls the eye
        // first, so an already-handled thread outshouted a live one.
        title.font = .systemFont(ofSize: 11.5,
                                 weight: lead.isAnswered ? .regular
                                       : (lead.isNew ? .semibold : .regular))
        title.textColor = lead.isAnswered ? Theme.textMuted : Theme.textPrimary
        title.preferredMaxLayoutWidth = width - 22
        title.cell?.wraps = true
        title.cell?.truncatesLastVisibleLine = true
        title.maximumNumberOfLines = 2

        let stack = NSStackView(views: [head, title])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            stack.topAnchor.constraint(equalTo: cell.topAnchor),
        ])

        if row == tableView.selectedRow {
            stack.wantsLayer = true
            stack.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.14).cgColor
            stack.layer?.borderColor = Theme.accent.withAlphaComponent(0.4).cgColor
            stack.layer?.borderWidth = 1
            stack.layer?.cornerRadius = 8
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        table.reloadData()
        showSelection(leads[safe: table.selectedRow])
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

import Cocoa

/// The site's palette, lifted from :root in index.html rather than approximated,
/// so the app and sunoget.com read as one product.
enum Theme {
    // Ink on cream.
    //
    // The previous palette was warm white, one blue and grey text, which is
    // inoffensive and has no point of view. This one is a page: cream ground,
    // near-black warm ink, rules instead of boxes, and rust where something
    // needs attention. No blue anywhere -- blue is what every admin panel
    // reaches for, and reaching for it is why the last one looked like every
    // admin panel.
    //
    // Held to the same standard as before. Every colour that carries text was
    // measured against BOTH surfaces and the worse kept:
    //
    //   ink 15.18   ink-2 9.10   muted 6.11   rust 6.50   oxblood 9.38
    //   cream on rust 7.39 (button labels)
    //
    // The weakest anywhere is 5.15:1, against the 4.5:1 AA asks for.
    static let bg          = NSColor(srgbRed: 0xf2/255, green: 0xec/255, blue: 0xe1/255, alpha: 1)
    static let card        = NSColor(srgbRed: 0xfd/255, green: 0xfb/255, blue: 0xf6/255, alpha: 1)
    static let cardBorder  = NSColor(srgbRed: 0xe2/255, green: 0xd9/255, blue: 0xc9/255, alpha: 1)

    /// Rust. Used for the live state and for the one button that matters,
    /// and almost nowhere else -- an accent that appears everywhere is not an
    /// accent, it is a background.
    static let accent      = NSColor(srgbRed: 0x8f/255, green: 0x38/255, blue: 0x18/255, alpha: 1)
    static let accentTop   = NSColor(srgbRed: 0xa8/255, green: 0x44/255, blue: 0x2a/255, alpha: 1)
    static let accentEnd   = NSColor(srgbRed: 0x6d/255, green: 0x23/255, blue: 0x18/255, alpha: 1)

    /// The three bands, as three weights of the same warm family rather than a
    /// traffic light. Hot is the only one that shouts.
    static let hot         = NSColor(srgbRed: 0x8f/255, green: 0x38/255, blue: 0x18/255, alpha: 1)
    static let warm        = NSColor(srgbRed: 0x8a/255, green: 0x6d/255, blue: 0x3a/255, alpha: 1)
    static let cool        = NSColor(srgbRed: 0x6b/255, green: 0x61/255, blue: 0x56/255, alpha: 1)

    static let textPrimary = NSColor(srgbRed: 0x1a/255, green: 0x17/255, blue: 0x14/255, alpha: 1)
    static let textSecond  = NSColor(srgbRed: 0x44/255, green: 0x3d/255, blue: 0x34/255, alpha: 1)
    static let textMuted   = NSColor(srgbRed: 0x5f/255, green: 0x56/255, blue: 0x4c/255, alpha: 1)
    static let ok          = NSColor(srgbRed: 0x40/255, green: 0x5c/255, blue: 0x38/255, alpha: 1)
    static let bad         = NSColor(srgbRed: 0x7a/255, green: 0x24/255, blue: 0x18/255, alpha: 1)

    /// A chip that is on. Warm, and barely there -- on a page, a selected thing
    /// is marked by its rule and its weight, not by being highlighted.
    static let chipLit     = NSColor(srgbRed: 0xf4/255, green: 0xe7/255, blue: 0xdd/255, alpha: 1)
    static let chipLitEdge = NSColor(srgbRed: 0xc4/255, green: 0x96/255, blue: 0x80/255, alpha: 1)

    static let sunken      = NSColor(srgbRed: 0xf7/255, green: 0xf2/255, blue: 0xe8/255, alpha: 1)
    static let hover       = NSColor(white: 0, alpha: 0.04)

    static func mono(_ size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .regular) }

    // MARK: - Type

    /// A real scale, rather than everything within two points of everything else.
    ///
    /// The first version set almost every label between 10 and 13pt, which is
    /// why the interface read as a form: with no size contrast, nothing is more
    /// important than anything else and the eye has nowhere to land. These are
    /// spaced far enough apart to be told apart at a glance.
    enum Font {
        /// The thing you are reading. A post title is the content, so it is set
        /// like content.
        /// New York, the system serif. A post title is somebody's sentence, and
        /// setting it in a serif says so -- it is the thing being read, not a
        /// control. Falls back to the system font on anything that lacks it.
        static let display = serif(23, weight: .semibold)
        static let title   = serif(16, weight: .semibold)

        static func serif(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.serif),
                  let font = NSFont(descriptor: descriptor, size: size)
            else { return base }
            return font
        }
        /// Post bodies and drafts. 13.5 with generous leading, because this is
        /// prose somebody actually reads rather than a label they scan.
        static let body    = NSFont.systemFont(ofSize: 13.5)
        static let row     = NSFont.systemFont(ofSize: 13, weight: .medium)
        static let meta    = NSFont.systemFont(ofSize: 11.5)
        /// Section markers. Tracked out, because at this size the letterforms
        /// crowd each other.
        static let label   = NSFont.systemFont(ofSize: 10.5, weight: .bold)
    }

    /// One spacing scale, so gaps are chosen rather than guessed.
    enum Space {
        static let tight: CGFloat = 6
        static let close: CGFloat = 10
        static let gap: CGFloat = 18
        static let section: CGFloat = 30
        static let margin: CGFloat = 24
    }

    /// A tracked-out section marker.
    static func sectionLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithAttributedString: NSAttributedString(
            string: text.uppercased(),
            attributes: [.font: Font.label,
                         .foregroundColor: textMuted,
                         .kern: 0.8]))
        return field
    }

    /// A hairline that reads as a division rather than a border.
    static func rule() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = cardBorder.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }
}

extension CardView {
    /// The app's standard surface: a tracked-out marker, then the content.
    ///
    /// The marker sits closer to its content than the card's own padding, so it
    /// reads as belonging to what follows rather than floating above it.
    static func titled(_ title: String, _ body: NSView) -> CardView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        let label = Theme.sectionLabel(title)
        label.translatesAutoresizingMaskIntoConstraints = false
        body.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)
        card.addSubview(body)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: Theme.Space.gap),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Theme.Space.margin),
            label.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor,
                                            constant: -Theme.Space.margin),
            body.topAnchor.constraint(equalTo: label.bottomAnchor, constant: Theme.Space.close),
            body.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Theme.Space.margin),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Theme.Space.margin),
            body.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Theme.Space.gap),
        ])
        return card
    }
}

/// A flat dark panel with the site's card border. AppKit gives no way to restyle
/// a stock box, so the card look is drawn rather than themed.
/// A surface, lifted rather than outlined.
///
/// The old card was a white rectangle with a 1px border, repeated three times
/// down a column, which is what made the interface read as a form. A soft
/// shadow separates a surface from the page without drawing a box around every
/// idea on screen.
final class CardView: NSView {
    var fill: NSColor = Theme.card
    var radius: CGFloat = 14
    /// Whether this is a surface at all. A section that is just a heading and
    /// some text does not need to be in a box, and boxing it is what made the
    /// interface look like a preferences pane.
    var isRaised = true { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirty: NSRect) {
        guard isRaised else { return }
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSGraphicsContext.current?.saveGraphicsState()
        // Depth from a shadow rather than a hairline. Two shadows, because one
        // soft one reads as fog and one tight one reads as a sticker: the tight
        // pass gives the edge, the soft pass gives the lift.
        let close = NSShadow()
        close.shadowColor = NSColor(white: 0, alpha: 0.10)
        close.shadowOffset = NSSize(width: 0, height: -1)
        close.shadowBlurRadius = 2
        close.set()
        fill.setFill(); path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        NSGraphicsContext.current?.saveGraphicsState()
        let far = NSShadow()
        far.shadowColor = NSColor(white: 0, alpha: 0.06)
        far.shadowOffset = NSSize(width: 0, height: -6)
        far.shadowBlurRadius = 16
        far.set()
        fill.setFill(); path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}

/// The site's primary button: accent gradient, white bold label, no macOS bezel.
final class AccentButton: NSButton {
    var isDanger = false { didSet { needsDisplay = true } }

    /// Redrawn when enablement changes, because the default does not.
    override var isEnabled: Bool { didSet { needsDisplay = true } }

    override var title: String { didSet { invalidateIntrinsicContentSize() } }

    /// Sized to its own words.
    ///
    /// The buttons carried fixed widths, which works in exactly one language.
    /// Measured across fifteen: German needs 204pt for "Copy and open thread"
    /// in a 190pt button, Russian 218, and Indonesian 216 for "Find where they
    /// talk". A fixed width does not wrap or shrink -- it clips, silently, in
    /// the languages nobody building it can read.
    override var intrinsicContentSize: NSSize {
        let font = NSFont.systemFont(ofSize: 13, weight: .bold)
        let width = (title as NSString).size(withAttributes: [.font: font]).width
        return NSSize(width: (width + 34).rounded(), height: NSView.noIntrinsicMetric)
    }

    override func draw(_ dirty: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9)
        // A disabled accent button used to draw exactly like an enabled one:
        // full gradient, white bold label, and nothing happening on click. In
        // LeadSniper this button is the point at which a draft is refused until
        // it has been written, so looking clickable while refusing is the worst
        // possible way for it to behave.
        if !isEnabled {
            Theme.sunken.setFill(); path.fill()
            Theme.cardBorder.setStroke(); path.lineWidth = 1; path.stroke()
        } else if isDanger {
            NSColor(srgbRed: 0xe1/255, green: 0x1d/255, blue: 0x48/255, alpha: 1).setFill()
            path.fill()
        } else {
            let g = NSGradient(starting: Theme.accentTop, ending: Theme.accentEnd)
            g?.draw(in: path, angle: 300)
        }
        if isHighlighted && isEnabled {
            NSColor(white: 0, alpha: 0.18).setFill()
            path.fill()
        }
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: isEnabled ? NSColor.white : Theme.textMuted,
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .paragraphStyle: style,
        ]
        let size = title.size(withAttributes: attrs)
        title.draw(in: NSRect(x: 0, y: (bounds.height - size.height) / 2,
                              width: bounds.width, height: size.height), withAttributes: attrs)
    }
}

/// Dark field with its text vertically centred and padded off the border.
///
/// An NSTextField draws its content at the top of the cell and hard against the
/// left edge. Once the height is pinned for a consistent card layout, the
/// placeholder floats above centre and the caret sits on the border. Only a
/// custom cell can move it, and the drawing, editing and selection rects all
/// have to agree or the text jumps the moment the field takes focus.
final class InsetTextFieldCell: NSTextFieldCell {
    var padding = NSSize(width: 9, height: 0)

    private func centred(_ rect: NSRect) -> NSRect {
        let base = super.drawingRect(forBounds: rect)
        let text = cellSize(forBounds: rect)
        let dy = max(0, (base.height - text.height) / 2)
        return NSRect(x: base.origin.x + padding.width,
                      y: base.origin.y + dy,
                      width: max(0, base.width - padding.width * 2),
                      height: text.height)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect { centred(rect) }
    override func titleRect(forBounds rect: NSRect) -> NSRect { centred(rect) }

    override func edit(withFrame rect: NSRect, in controlView: NSView,
                       editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centred(rect), in: controlView,
                   editor: editor, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView,
                         editor: NSText, delegate: Any?, start: Int, length: Int) {
        super.select(withFrame: centred(rect), in: controlView,
                     editor: editor, delegate: delegate, start: start, length: length)
    }
}

final class DarkField: NSTextField {
    static let height: CGFloat = 30
    private static let idle = NSColor(srgbRed: 0xc8/255, green: 0xc4/255, blue: 0xba/255, alpha: 1)

    /// Styled on construction, not by a factory.
    ///
    /// All of this used to live in `make(placeholder:)`, so a plain
    /// `DarkField()` was an unstyled white NSTextField sitting in a dark
    /// interface -- which is exactly what shipped in the Find tab, because the
    /// factory is easy not to know about. A type that only looks right if you
    /// remember to build it a particular way is a trap.
    override init(frame: NSRect) {
        super.init(frame: frame)
        style()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        style()
    }

    private func style() {
        let cell = InsetTextFieldCell(textCell: "")
        cell.isEditable = true
        cell.isSelectable = true
        cell.isScrollable = true
        cell.wraps = false
        cell.usesSingleLineMode = true
        self.cell = cell
        font = .systemFont(ofSize: 12)
        textColor = Theme.textPrimary
        // The layer paints the background so the rounded corners are not squared
        // off by the cell drawing its own opaque rectangle.
        drawsBackground = false
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.backgroundColor = Theme.card.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = DarkField.idle.cgColor
    }

    var placeholder: String = "" {
        didSet {
            placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
                .foregroundColor: Theme.textMuted, .font: NSFont.systemFont(ofSize: 12)])
        }
    }

    static func make(placeholder: String) -> DarkField {
        let f = DarkField()
        f.placeholder = placeholder
        f.translatesAutoresizingMaskIntoConstraints = false
        f.heightAnchor.constraint(equalToConstant: DarkField.height).isActive = true
        return f
    }

    override func drawFocusRingMask() {}

    /// Focused fields take the accent border, as they do on the site.
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { layer?.borderColor = Theme.accent.withAlphaComponent(0.7).cgColor }
        return ok
    }
    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        layer?.borderColor = DarkField.idle.cgColor
    }
}

extension NSTextField {
    static func themed(_ s: String, size: CGFloat = 11, weight: NSFont.Weight = .regular,
                       color: NSColor = Theme.textSecond) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        return l
    }
    static func sectionLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s.uppercased())
        l.font = .systemFont(ofSize: 9.5, weight: .heavy)
        l.textColor = Theme.textMuted
        return l
    }
}

extension NSButton {
    func themedCheckbox() {
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: Theme.textSecond,
            .font: NSFont.systemFont(ofSize: 11.5, weight: .medium)])
        // A checkbox otherwise paints in the system accent -- blue on most Macs,
        // which is the one obviously foreign colour in an orange UI.
        contentTintColor = Theme.accent
    }
}

/// A row of notches, one of which is lit.
///
/// Where a setting has three to six choices and the choices are short, a pop-up
/// spends a whole row and a click to say what a strip of notches says at a
/// glance. Used for the blend length, the pitch pull and how many prompts to
/// write.
final class SegmentBar: NSControl {
    struct Item { let title: String; let tag: Int }

    var items: [Item] = [] { didSet { needsDisplay = true } }
    var selectedTag: Int = 0 { didSet { needsDisplay = true } }
    private var hovered = -1
    private var tracking: NSTrackingArea?

    convenience init(items: [Item], tag selected: Int) {
        self.init(frame: .zero)
        self.items = items
        self.selectedTag = selected
        wantsLayer = true
    }

    var selectedItem: Item? { items.first { $0.tag == selectedTag } }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 26) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved,
                                                          .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    private func index(at point: NSPoint) -> Int {
        guard !items.isEmpty, bounds.width > 0 else { return -1 }
        let i = Int(point.x / (bounds.width / CGFloat(items.count)))
        return min(max(i, 0), items.count - 1)
    }

    override func mouseMoved(with event: NSEvent) {
        let i = index(at: convert(event.locationInWindow, from: nil))
        if i != hovered { hovered = i; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hovered = -1; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        let i = index(at: convert(event.locationInWindow, from: nil))
        // Not `items[safe:]`: that subscript lives in App.swift, and Theme is
        // compiled into test suites that do not include it.
        guard i >= 0, i < items.count, items[i].tag != selectedTag else { return }
        selectedTag = items[i].tag
        if let action, let target { NSApp.sendAction(action, to: target, from: self) }
    }

    override func draw(_ dirty: NSRect) {
        guard !items.isEmpty else { return }
        let outer = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        Theme.sunken.setFill(); outer.fill()
        Theme.cardBorder.setStroke(); outer.lineWidth = 1; outer.stroke()

        let cell = bounds.width / CGFloat(items.count)
        for (i, item) in items.enumerated() {
            let rect = NSRect(x: cell * CGFloat(i), y: 0, width: cell, height: bounds.height)
            let lit = item.tag == selectedTag
            if lit {
                let inset = rect.insetBy(dx: 2, dy: 2)
                let path = NSBezierPath(roundedRect: inset, xRadius: 5, yRadius: 5)
                NSGradient(starting: Theme.accentTop, ending: Theme.accentEnd)?.draw(in: path, angle: 300)
            } else if i == hovered {
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5)
                Theme.card.setFill(); path.fill()
                Theme.cardBorder.setStroke(); path.lineWidth = 1; path.stroke()
            }
            // A hairline between unlit notches, so the strip reads as a scale
            // rather than as one wide field with a word in it.
            if i > 0 && !lit && items[i - 1].tag != selectedTag {
                Theme.hover.setFill()
                NSRect(x: rect.minX, y: 6, width: 1, height: bounds.height - 12).fill()
            }
            let style = NSMutableParagraphStyle(); style.alignment = .center
            style.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: lit ? NSColor.white : Theme.textSecond,
                .font: NSFont.systemFont(ofSize: 10.5, weight: lit ? .semibold : .medium),
                .paragraphStyle: style,
            ]
            let size = item.title.size(withAttributes: attrs)
            item.title.draw(in: NSRect(x: rect.minX, y: (bounds.height - size.height) / 2,
                                       width: rect.width, height: size.height), withAttributes: attrs)
        }
    }
}

/// A chip that carries a value and opens a menu for it.
///
/// One row of chips reads as one row of chips; a bare pop-up dropped among them
/// reads as something that fell in. This is a chip whose title is its current
/// setting, lit when that setting is anything other than off.
final class MenuChip: ToggleChip {
    var items: [(title: String, tag: Int)] = [] {
        didSet { if selectedTag == 0, let first = items.first { selectedTag = first.tag } }
    }
    var selectedTag = 0 { didSet { refresh() } }
    /// The tag that counts as "off", drawn unlit.
    var offTag = 0

    private func refresh() {
        title = items.first { $0.tag == selectedTag }?.title ?? title
        isLit = selectedTag != offTag
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        // The chevron is 7pt wide and wants the same margin the text has on the
        // other side, or it sits against the edge of the pill and the chip looks
        // cramped on the right and roomy on the left.
        return NSSize(width: base.width + MenuChip.chevronRoom, height: base.height)
    }

    /// 7pt of chevron plus a matching margin either side of it.
    static let chevronRoom: CGFloat = 18

    override func mouseDown(with event: NSEvent) {
        let menu = NSMenu()
        for item in items {
            let entry = menu.addItem(withTitle: item.title, action: #selector(pick(_:)),
                                     keyEquivalent: "")
            entry.target = self
            entry.tag = item.tag
            entry.state = item.tag == selectedTag ? .on : .off
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        selectedTag = sender.tag
        if let action, let target { NSApp.sendAction(action, to: target, from: self) }
    }

    override func draw(_ dirty: NSRect) {
        super.draw(dirty)
        // A small chevron on the trailing edge, so it is visibly a menu and not
        // a switch.
        let colour = isLit ? Theme.accent : Theme.textMuted
        colour.withAlphaComponent(0.85).setStroke()
        // NSButton draws flipped, so the chevron points down with +y.
        let path = NSBezierPath()
        // Ends 10pt from the trailing edge, which is what the title is inset by
        // on the leading one.
        let x = bounds.maxX - 17, y = bounds.midY - 1.5
        path.move(to: NSPoint(x: x, y: y))
        path.line(to: NSPoint(x: x + 3.5, y: y + 3.5))
        path.line(to: NSPoint(x: x + 7, y: y))
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}

/// A word that can be on or off.
///
/// Four checkboxes stacked down a narrow panel are four rows for four words. As
/// chips they are one row, and the state is the fill rather than a tick box the
/// eye has to find. (`ChipButton` in Chrome.swift is the site's partner badge,
/// which is a different thing that happens to be pill-shaped.)
class ToggleChip: NSButton {
    var isLit = false { didSet { needsDisplay = true } }
    /// Drawn hollow with a dotted edge: "this one is left to chance".
    var isOpen = false { didSet { needsDisplay = true } }
    var chipFont: NSFont = .systemFont(ofSize: 10.5, weight: .semibold)

    convenience init(_ title: String, lit: Bool = false, target: AnyObject? = nil,
                     action: Selector? = nil) {
        self.init(frame: .zero)
        self.title = title
        self.isLit = lit
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
    }

    override var intrinsicContentSize: NSSize {
        let width = title.size(withAttributes: [.font: chipFont]).width
        return NSSize(width: ceil(width) + 20, height: 24)
    }

    override func draw(_ dirty: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        if isLit {
            Theme.chipLit.setFill(); path.fill()
            Theme.chipLitEdge.setStroke()
        } else {
            Theme.sunken.setFill(); path.fill()
            Theme.cardBorder.setStroke(); path.lineWidth = 1; path.stroke()
            Theme.cardBorder.setStroke()
        }
        path.lineWidth = 1
        if isOpen { path.setLineDash([3, 2.5], count: 2, phase: 0) }
        path.stroke()
        if isHighlighted {
            Theme.hover.setFill(); path.fill()
        }
        let style = NSMutableParagraphStyle(); style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: isLit ? Theme.accent : Theme.textSecond,
            .font: chipFont,
            .paragraphStyle: style,
        ]
        let size = title.size(withAttributes: attrs)
        title.draw(in: NSRect(x: 4, y: (bounds.height - size.height) / 2,
                              width: bounds.width - 8, height: size.height), withAttributes: attrs)
    }
}


/// A hairline in the card's own border colour.
///
/// NSBox's separator draws in a system grey that vanishes against near-black,
/// which is a divider that is not there.
final class Hairline: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }
    override func draw(_ dirty: NSRect) {
        Theme.cardBorder.setFill()
        bounds.fill()
    }
}

/// A row of things that wraps instead of squeezing.
///
/// `NSStackView` has one row and no idea what to do when the contents are wider
/// than it is: it compresses, and drawn pills truncate their own titles. Four
/// chips that fit across 340pt in English need 350 in French, so the row has to
/// be able to become two rows.
final class FlowStack: NSView {
    var columnSpacing: CGFloat = 6
    var rowSpacing: CGFloat = 6
    /// Views pushed to the trailing edge of the last row.
    var trailing: [NSView] = []
    /// Centres each row within the width. For a panel of controls the left edge
    /// is the right answer; in a column where everything else is centred, a
    /// left-aligned block of chips reads as a mistake.
    var centresRows = false

    private var laidOutHeight: CGFloat = 0

    func setViews(_ views: [NSView], trailing: [NSView] = []) {
        subviews.forEach { $0.removeFromSuperview() }
        self.trailing = trailing
        for view in views + trailing {
            view.translatesAutoresizingMaskIntoConstraints = true
            addSubview(view)
        }
        needsLayout = true
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: max(laidOutHeight, 24))
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        guard width > 1 else { return }
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var rows: [[NSView]] = [[]]
        for view in subviews where !trailing.contains(view) {
            let size = view.intrinsicContentSize
            let w = size.width > 0 ? size.width : view.frame.width
            if x > 0 && x + w > width {
                x = 0
                y += rowHeight + rowSpacing
                rows.append([])
            }
            view.frame = NSRect(x: x, y: y, width: w, height: size.height)
            rows[rows.count - 1].append(view)
            x += w + columnSpacing
            rowHeight = max(rowHeight, size.height)
        }
        if centresRows {
            // Each row nudged right by half of what it left empty. Done after
            // the fact rather than during, because a row's width is not known
            // until the view that overflows it has been found.
            for row in rows where !row.isEmpty {
                let used = row.reduce(0) { $0 + $1.frame.width }
                    + columnSpacing * CGFloat(row.count - 1)
                let inset = ((width - used) / 2).rounded()
                guard inset > 0 else { continue }
                for view in row { view.frame.origin.x += inset }
            }
        }

        // The trailing views sit at the right-hand end, dropping to a row of
        // their own rather than colliding with what is already there.
        var right = width
        var trailingRow = y
        for view in trailing.reversed() {
            let size = view.intrinsicContentSize
            let w = size.width > 0 ? size.width : view.frame.width
            if right - w < x {
                trailingRow = y + rowHeight + rowSpacing
                y = trailingRow
                right = width
                x = 0
                rowHeight = size.height
            }
            view.frame = NSRect(x: right - w, y: trailingRow, width: w, height: size.height)
            right -= w + columnSpacing
            rowHeight = max(rowHeight, size.height)
        }
        let height = y + rowHeight
        if abs(height - laidOutHeight) > 0.5 {
            laidOutHeight = height
            invalidateIntrinsicContentSize()
        }
    }
}


/// A thin determinate bar.
///
/// Determinate, and that is the point. This app makes people wait -- a discovery
/// search is six requests at twenty-six seconds each, because that is what the
/// rate limit allows -- and a spinner says only "something is happening", which
/// after ninety seconds reads as "nothing is happening". A bar that is two
/// thirds along is a promise you can check.
///
/// Nothing bounces or pulses. This is a tool somebody has open all day, and
/// motion in the corner of the eye is a tax on attention, not a feature.
final class Meter: NSView {
    /// 0 to 1. Animated to, rather than jumped to, so a step forward is
    /// noticeable without being watched for.
    var progress: Double = 0 {
        didSet {
            progress = min(max(progress, 0), 1)
            guard abs(progress - oldValue) > 0.001 else { return }
            animate(to: progress)
        }
    }

    private let track = CALayer()
    private let fill = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        track.backgroundColor = Theme.sunken.cgColor
        fill.backgroundColor = Theme.accent.cgColor
        layer?.addSublayer(track)
        layer?.addSublayer(fill)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 4) }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        track.frame = bounds
        // Laid out without animation, or a window resize slides the fill across
        // the screen for no reason.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = NSRect(x: 0, y: 0, width: bounds.width * progress, height: bounds.height)
        fill.cornerRadius = bounds.height / 2
        CATransaction.commit()
    }

    private func animate(to value: Double) {
        guard bounds.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        fill.frame = NSRect(x: 0, y: 0, width: bounds.width * value, height: bounds.height)
        CATransaction.commit()
    }

    /// Hidden when there is nothing to report, rather than sitting at zero: an
    /// empty bar reads as a stalled one.
    func show(_ value: Double?) {
        if let value {
            isHidden = false
            progress = value
        } else {
            isHidden = true
            progress = 0
        }
    }
}


/// The four steps, shown where the app would otherwise be empty.
///
/// Built to fill the space rather than float over it. A modal that explains an
/// app is a modal people dismiss without reading and then never see again; the
/// empty state is where somebody is already looking, already wondering what to
/// do, and it is going to be replaced by real content the moment they do it.
///
/// Each step carries a real example in the app's own chips, because "it finds
/// the communities" means nothing next to seeing r/selfhosted sitting there.
final class Guide: NSView {
    struct Step {
        let title: String
        let detail: String
        /// Shown as chips underneath, in the app's own style.
        let examples: [String]
        /// The one that is the current thing to do, drawn lit.
        var isNext = false
    }

    private let stack = NSStackView()

    init(steps: [Step]) {
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            // Equal, not lessThanOrEqualTo. With the loose constraint nothing
            // pushed the view's height, so it laid out 560 wide and 0 tall and
            // drew nothing at all -- present, sized, invisible.
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        stack.setViews(steps.enumerated().map { build($0.offset + 1, $0.element) }, in: .leading)
        reveal()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build(_ number: Int, _ step: Step) -> NSView {
        let badge = NSTextField.themed("\(number)", size: 11, color: .white)
        badge.font = .systemFont(ofSize: 11, weight: .bold)
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = (step.isNext ? Theme.accent : Theme.cool).cgColor
        badge.layer?.cornerRadius = 11
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.widthAnchor.constraint(equalToConstant: 22).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let title = NSTextField.themed(step.title, size: 13, color: Theme.textPrimary)
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let detail = NSTextField(wrappingLabelWithString: step.detail)
        detail.font = .systemFont(ofSize: 11.5)
        detail.textColor = Theme.textSecond
        detail.preferredMaxLayoutWidth = 400

        let words = NSStackView(views: [title, detail])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 3

        if !step.examples.isEmpty {
            let chips = FlowStack()
            chips.translatesAutoresizingMaskIntoConstraints = false
            chips.setViews(step.examples.map { text in
                let chip = ToggleChip()
                chip.title = text
                chip.isLit = step.isNext
                chip.isEnabled = false
                return chip
            })
            words.addArrangedSubview(chips)
            chips.widthAnchor.constraint(equalToConstant: 400).isActive = true
        }

        let row = NSStackView(views: [badge, words])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        return row
    }

    /// A gentle stagger, once.
    ///
    /// Slides only. It does NOT fade, and that is the whole lesson from getting
    /// this wrong: the first version set every row's alpha to 0 and relied on an
    /// animation to bring it back. Measured, the view laid out correctly at
    /// 560x350 with every row at alpha 0 — present, sized, and completely
    /// invisible, because the animation had not run by the time it was drawn.
    ///
    /// An effect whose failure mode is "the content is gone" is not worth
    /// having. A transform can fail and the worst case is that the steps are
    /// already where they belong.
    private func reveal() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        for (index, view) in stack.arrangedSubviews.enumerated() {
            view.wantsLayer = true
            view.layer?.setAffineTransform(CGAffineTransform(translationX: 0, y: -10))
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.06) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    context.allowsImplicitAnimation = true
                    view.layer?.setAffineTransform(.identity)
                }
            }
        }
    }
}

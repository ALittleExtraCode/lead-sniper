import Foundation

/// One queue for everything that talks to Reddit.
///
/// The sweep paced itself and the search paced itself, and neither knew the
/// other existed. In ordinary use they overlap constantly -- the watch fires
/// every half hour, and the obvious time to be running a discovery search is
/// while you are sitting in front of the app. Two callers each politely spacing
/// their own requests twenty seconds apart still put two requests into the same
/// twenty-second window, and Reddit refuses both.
///
/// Everything goes through here now. The budget belongs to the machine, not to
/// whichever part of the app happened to ask.
actor RedditGate {
    static let shared = RedditGate()

    /// Measured: `x-ratelimit-remaining` reads 0.0 after a single request and
    /// resets in 19 seconds. 21 leaves a margin without wasting the budget.
    private let spacing: TimeInterval = 21

    private var nextFree = Date.distantPast

    /// Waits until it is this caller's turn, then claims the slot.
    ///
    /// Claiming happens before the request rather than after it, so two callers
    /// arriving together do not both see a free slot. The slot is reserved for
    /// the caller's whole request, which is what serialises them.
    func take() async {
        let now = Date()
        let readyAt = max(now, nextFree)
        nextFree = readyAt.addingTimeInterval(spacing)
        let pause = readyAt.timeIntervalSince(now)
        if pause > 0 {
            try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
        }
    }

    /// Told when the server pushes back, so every other caller waits too.
    ///
    /// Without this a 429 taught only the caller that got it, and the next one
    /// along walked straight into the same wall.
    func slowDown(by seconds: TimeInterval) {
        let until = Date().addingTimeInterval(max(5, seconds))
        if until > nextFree { nextFree = until }
    }

    /// How long the next request would have to wait, for an interface that
    /// wants to say so rather than appear to hang.
    func queued() -> TimeInterval {
        max(0, nextFree.timeIntervalSince(Date()))
    }

    /// Only for the suite: puts the budget back.
    func reset() { nextFree = .distantPast }
}

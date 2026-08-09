# Concurrency details

Read this before adding a long-running calculation, wiring up a progress bar, or reaching for `assumeIsolated`.

The basics are in `CLAUDE.md`: the model layer is actor-based, and two AppKit callbacks (`awakeFromNib()`, `Timer` blocks) are
`nonisolated` and so wrap their bodies in `MainActor.assumeIsolated { … }`.

## Progress reporting from a long calculation

Both long calculations report progress the same way, and new ones should follow it. The calculation takes an optional
`AsyncStream<…>.Continuation`; the UI creates the stream with `.bufferingNewest(1)`, drains it in a
`Task { @MainActor in for await … }`, and finishes the continuation when the work returns (**including on the error path** —
otherwise the drain task outlives the calculation). `AsyncStream.Continuation` is `Sendable`, so it crosses into an actor with no
`assumeIsolated` and no `DispatchQueue.main.async`; `.bufferingNewest(1)` means the solver never blocks on a slow UI; and because
each `for await` iteration resumes on the main actor, AppKit actually gets to redraw *between* updates. That last point is the whole
reason the pattern works where ad-hoc main-thread hops historically didn't.

Two things learned the hard way, both worth preserving:

- **An indeterminate `NSProgressIndicator` animates off the main run loop**, so it keeps spinning even when the main thread is wedged. A determinate bar does not. If a converted bar stalls, that is a real main-thread block being *exposed*, not introduced.
- **A bar that never moves usually means the work isn't completing incrementally**, not that the plumbing is broken. Check whether the underlying units of work actually finish at different times before touching the UI code — see the bounded-concurrency note in `PchFiniteElementPackage`'s `CLAUDE.md`.

Throttle the emitting side to roughly what the bar can show. `SimulateRK45` reports only when its fraction advances ≥0.2% (a run is
10⁵+ steps; a 100pt bar has ~100 useful positions) and checks `Task.isCancelled` at the **top of its loop** rather than at the
throttled report site — a long run of rejected steps would otherwise never reach a check. `FrequencyDomainSolver.Sweep` reports
every `points/200` completed solves; unlike the RK45 bar, its progress is genuinely **linear in wall-clock time**, because every
contour point costs the same.

## Bounded parallelism in the frequency sweep

The frequency sweep bounds its own parallelism to one task per core (primed, then topped up as each completes) rather than
launching all ~2000 solves at once. Each in-flight solve holds an nx×nx complex matrix — ~2.5 MB at nx=400 — so an unbounded
`TaskGroup` would need several GB of live matrices. Keep the bound if you touch that loop.

## `assumeIsolated`

It *traps* if the assumption is ever wrong, so only use it where the main thread is guaranteed — otherwise hop with
`Task { @MainActor in … }`. The existing sites were exercised by hand (design-file load → inductance/capacitance → simulation →
coil-results animation → pinch-zoom) when Swift 6 mode was adopted, so a trap firing in one of them signals a genuine regression,
not a pre-existing latent bug.

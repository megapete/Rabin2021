# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS (AppKit/Cocoa) desktop application that simulates the **impulse voltage distribution** through transformer windings — i.e. how a lightning/impulse voltage waveform distributes across the discs of a coil during very fast transients. It builds inductance and capacitance matrices for a winding geometry and integrates the resulting system of ODEs over time.

Note the naming skew: the git repo, source folder, and bundle identifier are all `Rabin2021` (the original working name), but the Xcode project, scheme, and shipped product are named **`ImpulseDistribution`**. They refer to the same app.

## Build & run

```bash
# Build (Debug)
xcodebuild -project ImpulseDistribution.xcodeproj -scheme ImpulseDistribution -configuration Debug build

# Build (Release)
xcodebuild -project ImpulseDistribution.xcodeproj -scheme ImpulseDistribution -configuration Release build
```

- Normal development is done in Xcode (open `ImpulseDistribution.xcodeproj`, ⌘R to run).
- **There is no test target** — do not look for or attempt to run XCTest.
- **Swift 6 language mode** with `SWIFT_STRICT_CONCURRENCY = complete`, macOS deployment target 26.0, **Apple Silicon only** (`arm64`; see commit "Set project to build for Apple Silicon only"). Note that these two settings are on the **app target only** — the project level is still `SWIFT_STRICT_CONCURRENCY = targeted`, which is what the SPM packages inherit. Do not move them up to the project, and do not enable `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; both break `PchMatrixPackage`.
- The preprocessor macros `ACCELERATE_NEW_LAPACK=1` and `ACCELERATE_LAPACK_ILP64=1` are set **project-wide** (`GCC_PREPROCESSOR_DEFINITIONS`, in the Apple Clang – Preprocessing build settings). The LAPACK-using matrix code needs them because of Apple's 2023 LAPACK/BLAS changes. Leave them in place.

### Not everything in `Rabin2021/` is compiled

Eight `.swift` files sit in the source folder but are **not in the target's Compile Sources phase**, so editing them has no effect on the built app. Check target membership before touching a file:

| File(s) | Status |
|---|---|
| `PchMatrix.swift` | Superseded. The `PchMatrix` the code actually uses comes from `PchMatrixPackage`. |
| `PCH_ProgressIndicatorWindow.swift` | Superseded by the class of the same name in `PchProgressIndicatorPackage`. |
| `EslamianVahidiModel.swift` | Dead; its only reference (`PhaseModel.swift:46`) is commented out. |
| `PCH_GraphingView.swift`, `PCH_GraphingWindow.swift` | Dead; the only reference is inside a commented-out block in `AppController.swift`. |
| `oldPchMatrixView*.swift` (3 files) | Legacy. |

The compiled target is exactly these 21: `AppController`, `AppDelegate`, `BasicSection`, `CoilResultsDisplayView`, `CoilResultsDisplayWindow`, `ConductorImpedance`, `Connector`, `Core`, `FrequencyDomainSolver`, `GetNumberDialog`, `GetSimDetailsDialog`, `Node`, `NumericalLaplaceTransform`, `PhaseModel`, `Segment`, `ShowCoilResultsDialog`, `ShowWaveFormsDialog`, `SimulationModel`, `TransformerView`, `WaveFormDisplayView`, `WaveFormDisplayWindow`.

**When adding a `.swift` file, add it to the Compile Sources phase.** Eight files in this folder are already orphaned, and SourceKit reports a misleading `No such module 'PchBasePackage'` on a file that is not in the target — that diagnostic means "not in Compile Sources", not "package missing".

## Dependencies (Swift Package Manager)

Resolved packages live in `ImpulseDistribution.xcodeproj/.../swiftpm/Package.resolved`. Several are private/GitHub packages by the same author (megapete):

- `PchBasePackage` — core utilities (logging via `ALog`, etc.). **Keep the Release `-disable-cmo` flag** on this package; it fixes a CGFloat/Double CMO swiftmodule deserialization crash when archiving.
- `PchFiniteElementPackage` — finite-element support. **This is the path actually used to compute the inductance matrix**, via `PchFePhase.CalculateInductanceMatrix`, which also supplies the inductance progress stream (`PchFePhase.InductanceProgress`) and honours cancellation. Tracked by **branch `main`**, so a fresh resolve always takes the tip; note that `Package.resolved` is **gitignored** in this repo (the `*.xcworkspace` rule in the author's global ignore file), so the exact revision is not pinned in version control.
- `PchMatrixPackage`, `PchExcelDesignFilePackage`, `PchDialogBoxPackage`, `PchProgressIndicatorPackage` — matrix ops, Excel design-file import, dialogs, progress UI.
- `swift-numerics` (`ComplexModule`, `RealModule`) — complex/real math used by the matrix and inductance code.

## Domain model (the important architecture)

The physics model is layered from smallest to largest unit. Understanding this hierarchy is essential:

- **`BasicSection`** (struct, `BasicSection.swift`) — the smallest unit the program recognizes: one coil section at a physical location. `LocStruct` gives its `(radial, axial)` position, where radial 0 is closest to the core leg and axial 0 is closest to the bottom yoke.
- **`Segment`** (`actor`, `Segment.swift`) — a collection of *axially contiguous* `BasicSection`s from the **same winding**. This is the unit that is actually modeled and drawn. Static rings and radial shields are special Segments created via class factory functions. Segments are `Equatable`/hashed **by serial number** — be very careful when assigning serial numbers.
- **`Core`** (struct, `Core.swift`) — core geometry (diameter, window height, leg centers) used by inductance calculations.
- **`Node`** (struct, `Node.swift`) — a connection point between segments. Its `number` is **0-based and doubles as the index into the capacitance matrix**. Shunt capacitances to ground use `toNode = -1`.
- **`Connector`** / **`Segment.Connection`** (`Connector.swift`, `Segment.swift`) — an electrical "jumper". A `Connector` has a `fromLocation`/`toLocation` from the `Connector.Location` enum: eight physical points on a segment (`{inside,center,outside}_{upper,lower}` plus `outside_center`/`inside_center`) and the special *terminations* `floating`, `ground`, `impulse`. A `Segment.Connection` pairs a `Connector` with an optional `segmentID`: non-nil ⇒ a jumper to that segment's location; nil ⇒ a termination on `self`. Coil ends and tapping gaps carry a `floating` lead by default; `AddConnector` **replaces** a floating lead with ground/impulse but **appends** a segment-to-segment jumper (leaving the floating lead in place).
- **`PhaseModel`** (`actor`, `PhaseModel.swift`) — the central model object. Owns the sorted `segmentStore`, the `nodeStore`, and the `core`. All model mutation/queries go through it. Throws `PhaseModelError`.

### Calculation & simulation layers

- **`EslamianVahidiModel.swift`** (`EslamianVahidiSegment`) — an **alternative inductance-matrix implementation that is not compiled into the app** (see the target-membership table above) using the double-Fourier-series method from the Eslamian & Vahidi paper ("New Methods for Computation of the Inductance Matrix of Transformer Windings for Very Fast Transients Studies"), covering both inside- and outside-the-core-window cases. The active code path computes the inductance matrix via the finite-element package (`PchFiniteElementPackage`) instead; this file is kept for reference/comparison only.
- **The transient is solved in the frequency domain**, not by time-marching. This is the live path, and it replaced the RK45 integrator (2026-08-01). Three files:
  - **`ConductorImpedance.swift`** — R(ω) from Dowell's exact 1-D skin (`F_R`) and proximity (`G_R`) functions, each normalized by its own value at 60 Hz so the Excel design file's per-unit eddy data is reproduced exactly at 60 Hz. These *replace* DelVecchio 12.103/12.104 — but note the old expressions are precisely the **high-frequency asymptotes of this same normalized model** (the identity `2·ξ₆₀/G_R(ξ₆₀) = 6/ξ₆₀³` holds exactly), so above ~100 kHz the two agree to 1 part in 10⁴. Only the sub-crossover range changed, where the old form over-predicted eddy loss (6× at 1 kHz, 466× at 60 Hz) and could return R_ac < R_dc or NaN.
  - **`NumericalLaplaceTransform.swift`** — damped-contour NILT (`s = σ + jmΔω`, σT = 5, record twice the displayed span). Knows nothing about transformers, so it is verified standalone against closed-form transforms. **Default window is `.none`**: the dominant error is a missing-tail bias, not Gibbs ringing, so a window makes it 2–10× worse.
  - **`FrequencyDomainSolver.swift`** — assembles `[sC', −Ā; −B, sM+Z(s)]` and sweeps. **It subtracts the s→∞ asymptote before inverting** — `α = C'⁻¹E`, the classical capacitive initial distribution — because inverting `V(s)` directly converges only as 1/f_max (1.7e-2 at 10 MHz; ~2 GHz would be needed for 1e-4). The subtraction takes the spectrum from 1/s² to 1/s⁴ and is 15–40× more accurate at identical cost. Do not remove it.

  Two consequences worth knowing: every frequency sees its **own** R, so there is no "fundamental frequency" estimate and no two-pass scheme; and **bandwidth is a real accuracy control**, exposed in the simulation dialog, not a free parameter.

  Verified end-to-end against an independent RK4 integration of the same ODEs on a synthetic ladder: worst nodal disagreement 2.4e-4 of peak, solve residual 3e-16, impulsed and grounded nodes exact.

- **`SimulationModel.swift`** (`actor SimulationModel`) — built from a `PhaseModel`. Its `init` does the work that both solvers depend on: resolving jumpers into merged node groups, building the `vDropInd`/`iDropInd` incidence arrays, and applying the boundary-condition row surgery to the capacitance matrix. It owns `M` (Cholesky-factorized, for the RK45 path) and **`unfactoredM`** (the matrix itself, which the frequency-domain solver needs — reading `M` there would assemble the Cholesky factor as though it were the inductance). `Snapshot()` extracts a `Sendable` `NetworkSnapshot` so the frequency sweep can run with no actor hops in its inner loop.
  - `SolveFrequencyDomain(waveForm:displaySpan:maximumFrequency:progress:)` is the **live entry point**. Results come back on a **uniform** time grid.
  - `SimulateRK45` / `DifferentialFormula` remain as an **independent cross-check**, reached via *Simulate → Compare Solvers (Debug)*. Both solvers return an **empty array for cancellation as well as failure**, so callers must check `Task.isCancelled` to tell the two apart.

  **Why RK45 is kept.** The frequency-domain solver cannot detect its own assembly errors: a flipped incidence sign or mis-ordered row surgery yields a well-conditioned system that solves to machine precision and returns a smooth, plausible, wrong answer. RK45 reaches the answer by a completely different route while sharing the same matrices, so agreement is real evidence. `CompareSolvers` pins **both** to the same constant resistance via `NetworkSnapshot.resistanceFrequencyOverride` — otherwise they are solving different equations and a disagreement means nothing. Leave that override `nil` for production runs.

  `SimulateRK45`'s repaired step control: error is now checked on **both** V and I (`f6.dIdt` was always computed and discarded, so this was free), the step factor δ is clamped to [0.1, 4], and there is an `hMin` plus a consecutive-rejection cap so a non-converging run fails instead of looping forever. `DifferentialFormula` returns an **Optional** — the old `([], [])` error return was silently destructive, because the `zip`-based vector operators in that file *truncate* rather than trap, so an empty derivative quietly emptied V and I and surfaced several steps later as "Could not get max value!".
- **`PchMatrix`** — the matrix class wrapping Accelerate BLAS/LAPACK for `Double` and `Complex<Double>`, including sparse (coordinate-form) matrices. The live version is in **`PchMatrixPackage`**, not the uncompiled `Rabin2021/PchMatrix.swift` copy — change it in the package. Read the long header comment before touching it — it documents the `OpaquePointer`/`with...Pointer` idioms forced by Apple's LAPACK headers.

## App / UI layer

- **`AppDelegate.swift`** — standard NSApplication delegate (entry point).
- **`AppController.swift`** — the main controller: menu/IBActions, User Defaults, and file loading. Input comes from Excel transformer **design files** (`PchExcelDesignFilePackage`); `.cir` (`PCH_CIR_FILETYPE`) is **export only** — `doCreateCirFile` writes a SPICE netlist for external validation. It emits R+L series branches with the segment series capacitance in parallel, `K` cards for every mutual pair, shunt capacitances, an `EXP()` source that reproduces the full wave exactly, and both `.ac` and `.tran` cards. **Run `.ac` first** — the solver *is* a frequency-domain solve, so an AC sweep compares like with like and localises any mismatch to an assembly error; `.tran` afterwards checks only the inverse transform. **Export a small model (10–20 segments):** coupling is one `K` card per pair, so ~190 at 20 segments but ~20,000 at 200, where SPICE becomes numerically fragile as k → 1. Correctness is size-independent, and the large case is precisely what SPICE cannot do — which is why this program computes the inductance matrix itself. Use ngspice. Iteration constants like `PCH_RABIN2021_IterationCount = 200` live here. It also owns the two long-running calculations' UI:
  - The main window's two progress bars (`indCalcProgInd`, `simCalcProgInd`) are **determinate** and driven by the progress streams described under *Concurrency*. Set up at launch, reset in `didFinishInductanceCalculation()` / `didFinishSimulationRun()`. The bar's `toolTip` carries the detail text (which pass, which section) because `workingLabel` is *shared* by both calculations — don't write per-calculation text into it.
  - Both are cancellable via `runningInductanceTask` / `runningSimulationTask` and the **Cancel Inductance Calculation** (Inductance menu) and **Cancel Simulation** (Simulate menu, ⌘.) items, enabled by `validateMenuItem` only while the matching task is live. The inductance calculation is wrapped in its own `Task` inside `updateModel` purely to get a cancel handle — `updateModel` has four call sites, none of which retains a `Task`. A user cancellation is **not** an error: no alert, but `inductanceIsValid` is forced false (a previous successful run could otherwise leave it stale-true) and the view is still refreshed, since the segment edits that triggered the update have already been applied to the model.
- **`TransformerView.swift`** — the `NSView` that draws the winding cross-section (adapted from the author's earlier *AndersenFE_2020* project). All drawn dimensions are multiplied by the file-scope `dimensionMultiplier` (`1000`) because `NSView` misbehaves with sub-1 (meter-scale) coordinates. It also contains the **connector-routing subsystem**:
  - `@MainActor struct SegmentPath` wraps a `Segment` for drawing; `SegmentPath.SetUpConnectors(...)` builds a `ViewConnector` (path + optional ground/impulse image) for each of a segment's `Connection`s. It classifies each connection (adjacent same-coil, non-adjacent same-coil, coil-to-coil, or termination) and routes accordingly: connectors avoid crossing coils by running in the radial gaps and crossing over/under the winding, choosing over-vs-under by shortest total travel (`ConnectorCrossover`); overlapping runs are spread into parallel **lanes** (`ViewConnector.assignLane` + `ConnectorChannel`); connectors attach to the tip of an existing `floating` lead rather than drawing a new stub.
  - Routing **offsets are derived from the model geometry** by `UpdateConnectorMetrics()` (tightest hilo gap and winding height) so they scale with model size; lead-stub length instead tracks the **view scale** so it stays constant on screen.
  - `RebuildConnectors()` re-runs the whole pass; it is triggered by `segments` changes **and on zoom** (menu/button handlers + a `didEndLiveMagnify` observer) and coalesces concurrent requests. Incremental add/remove-connector paths call `SetUpConnectors` directly on the affected segment(s).
- Dialogs / windows (`*.swift` + matching `*.xib`): `GetNumberDialog`, `GetSimDetailsDialog`, `ShowCoilResultsDialog`, `ShowWaveFormsDialog`, `CoilResultsDisplayView/Window`, `WaveFormDisplayView/Window`. `GetSimDetailsDialog` carries the **bandwidth** field (MHz, default 10, clamped 2–200 by `bandwidthInHz`) — the solver's only accuracy control, since there is no longer a step size or error tolerance to set. The four dialogs subclass `PCH_DialogBox` from `PchDialogBoxPackage`. The progress-indicator window (`rb2021_progressIndicatorWindow` in `AppController`) is `PchProgressIndicatorPackage`'s class; `PCH_GraphingView/Window` and the `old...`-prefixed files are dead — see the target-membership table above.

## Concurrency

The model layer is **actor-based** — `PhaseModel`, `Segment`, and `SimulationModel` are all `actor`s, and most model methods are `async`. Many model types are `Sendable`/`Codable`. When adding or calling model code, expect `await` and respect actor isolation; concurrency correctness here has been an ongoing source of fixes.

Two AppKit patterns recur in the UI layer, both because the callback is `nonisolated` even though it only ever runs on the main thread:

- **`awakeFromNib()`** — `NSObject`'s declaration is `nonisolated`, so an override does *not* inherit its class's `@MainActor`. Every existing override therefore wraps its body in `MainActor.assumeIsolated { … }`.
- **`Timer` blocks** — the `scheduledTimer(withTimeInterval:repeats:block:)` closure is `@Sendable` and nonisolated; the animation timer in `CoilResultsDisplayWindow` uses the same `MainActor.assumeIsolated { … }` wrapper.

### Progress reporting from a long calculation

Both long calculations report progress the same way, and new ones should follow it. The calculation takes an optional `AsyncStream<…>.Continuation`; the UI creates the stream with `.bufferingNewest(1)`, drains it in a `Task { @MainActor in for await … }`, and finishes the continuation when the work returns (**including on the error path** — otherwise the drain task outlives the calculation). `AsyncStream.Continuation` is `Sendable`, so it crosses into an actor with no `assumeIsolated` and no `DispatchQueue.main.async`; `.bufferingNewest(1)` means the solver never blocks on a slow UI; and because each `for await` iteration resumes on the main actor, AppKit actually gets to redraw *between* updates. That last point is the whole reason the pattern works where ad-hoc main-thread hops historically didn't.

Two things learned the hard way, both worth preserving:

- **An indeterminate `NSProgressIndicator` animates off the main run loop**, so it keeps spinning even when the main thread is wedged. A determinate bar does not. If a converted bar stalls, that is a real main-thread block being *exposed*, not introduced.
- **A bar that never moves usually means the work isn't completing incrementally**, not that the plumbing is broken. Check whether the underlying units of work actually finish at different times before touching the UI code — see the bounded-concurrency note in `PchFiniteElementPackage`'s `CLAUDE.md`.

Throttle the emitting side to roughly what the bar can show. `SimulateRK45` reports only when its fraction advances ≥0.2% (a run is 10⁵+ steps; a 100pt bar has ~100 useful positions) and checks `Task.isCancelled` at the **top of its loop** rather than at the throttled report site — a long run of rejected steps would otherwise never reach a check. `FrequencyDomainSolver.Sweep` reports every `points/200` completed solves; unlike the RK45 bar, its progress is genuinely **linear in wall-clock time**, because every contour point costs the same.

The frequency sweep bounds its own parallelism to one task per core (primed, then topped up as each completes) rather than launching all ~2000 solves at once. Each in-flight solve holds an nx×nx complex matrix — ~2.5 MB at nx=400 — so an unbounded `TaskGroup` would need several GB of live matrices. Keep the bound if you touch that loop.

`assumeIsolated` *traps* if the assumption is ever wrong, so only use it where the main thread is guaranteed — otherwise hop with `Task { @MainActor in … }`. The existing sites were exercised by hand (design-file load → inductance/capacitance → simulation → coil-results animation → pinch-zoom) when Swift 6 mode was adopted, so a trap firing in one of them signals a genuine regression, not a pre-existing latent bug.

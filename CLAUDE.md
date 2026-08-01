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

The compiled target is exactly these 18: `AppController`, `AppDelegate`, `BasicSection`, `CoilResultsDisplayView`, `CoilResultsDisplayWindow`, `Connector`, `Core`, `GetNumberDialog`, `GetSimDetailsDialog`, `Node`, `PhaseModel`, `Segment`, `ShowCoilResultsDialog`, `ShowWaveFormsDialog`, `SimulationModel`, `TransformerView`, `WaveFormDisplayView`, `WaveFormDisplayWindow`.

## Dependencies (Swift Package Manager)

Resolved packages live in `ImpulseDistribution.xcodeproj/.../swiftpm/Package.resolved`. Several are private/GitHub packages by the same author (megapete):

- `PchBasePackage` — core utilities (logging via `ALog`, etc.). **Keep the Release `-disable-cmo` flag** on this package; it fixes a CGFloat/Double CMO swiftmodule deserialization crash when archiving.
- `PchFiniteElementPackage` — finite-element support. **This is the path actually used to compute the inductance matrix.**
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
- **`SimulationModel.swift`** (`actor SimulationModel`) — the transient solver. Built from a `PhaseModel`, it integrates the coupled dV/dt, dI/dt system with an adaptive **RK45** method (`SimulateRK45` → `DifferentialFormula`), driven by an input impulse `WaveForm`, and produces `[SimulationStepResult]`.
- **`PchMatrix`** — the matrix class wrapping Accelerate BLAS/LAPACK for `Double` and `Complex<Double>`, including sparse (coordinate-form) matrices. The live version is in **`PchMatrixPackage`**, not the uncompiled `Rabin2021/PchMatrix.swift` copy — change it in the package. Read the long header comment before touching it — it documents the `OpaquePointer`/`with...Pointer` idioms forced by Apple's LAPACK headers.

## App / UI layer

- **`AppDelegate.swift`** — standard NSApplication delegate (entry point).
- **`AppController.swift`** — the main controller: menu/IBActions, User Defaults, and file loading. Input comes from Excel transformer **design files** (`PchExcelDesignFilePackage`) and `.cir` files (`PCH_CIR_FILETYPE`). Iteration constants like `PCH_RABIN2021_IterationCount = 200` live here.
- **`TransformerView.swift`** — the `NSView` that draws the winding cross-section (adapted from the author's earlier *AndersenFE_2020* project). All drawn dimensions are multiplied by the file-scope `dimensionMultiplier` (`1000`) because `NSView` misbehaves with sub-1 (meter-scale) coordinates. It also contains the **connector-routing subsystem**:
  - `@MainActor struct SegmentPath` wraps a `Segment` for drawing; `SegmentPath.SetUpConnectors(...)` builds a `ViewConnector` (path + optional ground/impulse image) for each of a segment's `Connection`s. It classifies each connection (adjacent same-coil, non-adjacent same-coil, coil-to-coil, or termination) and routes accordingly: connectors avoid crossing coils by running in the radial gaps and crossing over/under the winding, choosing over-vs-under by shortest total travel (`ConnectorCrossover`); overlapping runs are spread into parallel **lanes** (`ViewConnector.assignLane` + `ConnectorChannel`); connectors attach to the tip of an existing `floating` lead rather than drawing a new stub.
  - Routing **offsets are derived from the model geometry** by `UpdateConnectorMetrics()` (tightest hilo gap and winding height) so they scale with model size; lead-stub length instead tracks the **view scale** so it stays constant on screen.
  - `RebuildConnectors()` re-runs the whole pass; it is triggered by `segments` changes **and on zoom** (menu/button handlers + a `didEndLiveMagnify` observer) and coalesces concurrent requests. Incremental add/remove-connector paths call `SetUpConnectors` directly on the affected segment(s).
- Dialogs / windows (`*.swift` + matching `*.xib`): `GetNumberDialog`, `GetSimDetailsDialog`, `ShowCoilResultsDialog`, `ShowWaveFormsDialog`, `CoilResultsDisplayView/Window`, `WaveFormDisplayView/Window`. The four dialogs subclass `PCH_DialogBox` from `PchDialogBoxPackage`. The progress-indicator window (`rb2021_progressIndicatorWindow` in `AppController`) is `PchProgressIndicatorPackage`'s class; `PCH_GraphingView/Window` and the `old...`-prefixed files are dead — see the target-membership table above.

## Concurrency

The model layer is **actor-based** — `PhaseModel`, `Segment`, and `SimulationModel` are all `actor`s, and most model methods are `async`. Many model types are `Sendable`/`Codable`. When adding or calling model code, expect `await` and respect actor isolation; concurrency correctness here has been an ongoing source of fixes.

Two AppKit patterns recur in the UI layer, both because the callback is `nonisolated` even though it only ever runs on the main thread:

- **`awakeFromNib()`** — `NSObject`'s declaration is `nonisolated`, so an override does *not* inherit its class's `@MainActor`. Every existing override therefore wraps its body in `MainActor.assumeIsolated { … }`.
- **`Timer` blocks** — the `scheduledTimer(withTimeInterval:repeats:block:)` closure is `@Sendable` and nonisolated; the animation timer in `CoilResultsDisplayWindow` uses the same `MainActor.assumeIsolated { … }` wrapper.

`assumeIsolated` *traps* if the assumption is ever wrong, so only use it where the main thread is guaranteed — otherwise hop with `Task { @MainActor in … }`. The existing sites were exercised by hand (design-file load → inductance/capacitance → simulation → coil-results animation → pinch-zoom) when Swift 6 mode was adopted, so a trap firing in one of them signals a genuine regression, not a pre-existing latent bug.

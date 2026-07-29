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
- Swift 5.0, macOS deployment target 26.0, **Apple Silicon only** (`arm64`; see commit "Set project to build for Apple Silicon only").
- `PchMatrix.swift` requires the preprocessor macros `ACCELERATE_NEW_LAPACK=1` and `ACCELERATE_LAPACK_ILP64=1` (set in the project's Apple Clang – Preprocessing build settings). These are needed because of Apple's 2023 LAPACK/BLAS changes.

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
- **`Connector`** (`Connector.swift`) — electrical connections between segments/nodes.
- **`PhaseModel`** (`actor`, `PhaseModel.swift`) — the central model object. Owns the sorted `segmentStore`, the `nodeStore`, and the `core`. All model mutation/queries go through it. Throws `PhaseModelError`.

### Calculation & simulation layers

- **`EslamianVahidiModel.swift`** (`EslamianVahidiSegment`) — an **alternative, currently unused** inductance-matrix implementation using the double-Fourier-series method from the Eslamian & Vahidi paper ("New Methods for Computation of the Inductance Matrix of Transformer Windings for Very Fast Transients Studies"), covering both inside- and outside-the-core-window cases. The active code path computes the inductance matrix via the finite-element package (`PchFiniteElementPackage`) instead; this class is kept for reference/comparison.
- **`SimulationModel.swift`** (`actor SimulationModel`) — the transient solver. Built from a `PhaseModel`, it integrates the coupled dV/dt, dI/dt system with an adaptive **RK45** method (`SimulateRK45` → `DifferentialFormula`), driven by an input impulse `WaveForm`, and produces `[SimulationStepResult]`.
- **`PchMatrix.swift`** — the project's own matrix class wrapping Accelerate BLAS/LAPACK for `Double` and `Complex<Double>`, including sparse (coordinate-form) matrices. Read the long header comment before touching it — it documents the `OpaquePointer`/`with...Pointer` idioms forced by Apple's LAPACK headers.

## App / UI layer

- **`AppDelegate.swift`** — standard NSApplication delegate (entry point).
- **`AppController.swift`** — the main controller: menu/IBActions, User Defaults, and file loading. Input comes from Excel transformer **design files** (`PchExcelDesignFilePackage`) and `.cir` files (`PCH_CIR_FILETYPE`). Iteration constants like `PCH_RABIN2021_IterationCount = 200` live here.
- **`TransformerView.swift`** — the `NSView` that draws the winding cross-section (adapted from the author's earlier *AndersenFE_2020* project). All drawn dimensions are multiplied by `1000` because `NSView` misbehaves with sub-1 (meter-scale) coordinates.
- Dialogs / windows (`*.swift` + matching `*.xib`): `GetNumberDialog`, `GetSimDetailsDialog`, `ShowCoilResultsDialog`, `ShowWaveFormsDialog`, `CoilResultsDisplayView/Window`, `WaveFormDisplayView/Window`, `PCH_GraphingView/Window`, `PCH_ProgressIndicatorWindow`. Files prefixed `old...` (e.g. `oldPchMatrixView*`) are legacy and generally not on the active path.

## Concurrency

The model layer is **actor-based** — `PhaseModel`, `Segment`, and `SimulationModel` are all `actor`s, and most model methods are `async`. Many model types are `Sendable`/`Codable`. When adding or calling model code, expect `await` and respect actor isolation; concurrency correctness here has been an ongoing source of fixes.

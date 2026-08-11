# App / UI layer

Read this before touching `AppController`, `TransformerView` (including connector routing), the graph views, `AxisScale`,
`InitialDistributionWindow`, or the dialogs.

## `AppDelegate.swift`

Standard NSApplication delegate (entry point).

## `AppController.swift`

The main controller: menu/IBActions, User Defaults, and file loading. Input comes from Excel transformer **design files**
(`PchExcelDesignFilePackage`); `.cir` is **export only** (see `docs/solver.md`). Iteration constants like
`PCH_RABIN2021_IterationCount = 200` live here. It also owns the two long-running calculations' UI:

- **`recalculateModel(reinitialize:includeInductance:)` is the recalculation pipeline**, split out of `updateModel`'s tail: radial build-up → FE phase → eddy losses → inductance → capacitance → `updateViews()`. Anything that changes the model *without* swapping Segments calls it directly, because `updateModel` cannot be reached with empty segment arrays (`PhaseModel.UpdateConnectors` throws on those). It always calls `ApplyRadialBuildUp()` first — cheap, idempotent, and it means no caller has to reason about when geometry went stale. `includeInductance: false` recomputes only the capacitance, which is what a geometry search wants: the inductance dominates the cost and barely moves when a coil widens by millimetres.
- The main window's two progress bars (`indCalcProgInd`, `simCalcProgInd`) are **determinate** and driven by the progress streams described in `docs/concurrency.md`. Set up at launch, reset in `didFinishInductanceCalculation()` / `didFinishSimulationRun()`. The bar's `toolTip` carries the detail text (which pass, which section) because `workingLabel` is *shared* by both calculations — don't write per-calculation text into it.
- **`PCH_ErrorAlert(message:info:)` is the only way the app tells the user a command refused to act**, and there are ~50 call sites: nearly every guard in a menu handler ends there. It used to be a `PchBasePackage` global that put a real alert up; when the package dropped it, a local stub that only called `DLog` replaced it — and `DLog` is `#if DEBUG`, so in Release every refusal became *completely* silent. The visible symptom was a menu command that could be picked and then did nothing (reported against **Interleave Section** on a double-stacked tap winding, where the tapping-gap guard was firing into a log nobody was reading). It now puts an `NSAlert` up, *except* when `SelfTest.isRunningHeadless` — a modal alert in a scripted run hangs it forever, which is the same reason the harness never calls `recalculateModel` (see `docs/self-test.md`). A guard that cannot say why it refused is worth no more than no guard at all; keep new ones reporting through this function.
- Both are cancellable via `runningInductanceTask` / `runningSimulationTask` and the **Cancel Inductance Calculation** (Inductance menu) and **Cancel Simulation** (Simulate menu, ⌘.) items, enabled by `validateMenuItem` only while the matching task is live. The inductance calculation is wrapped in its own `Task` inside `recalculateModel` purely to get a cancel handle — none of its callers retains a `Task`. A user cancellation is **not** an error: no alert, but `inductanceIsValid` is forced false (a previous successful run could otherwise leave it stale-true) and the view is still refreshed, since the segment edits that triggered the update have already been applied to the model.

## `TransformerView.swift`

The `NSView` that draws the winding cross-section (adapted from the author's earlier *AndersenFE_2020* project). All drawn
dimensions are multiplied by the file-scope `dimensionMultiplier` (`1000`) because `NSView` misbehaves with sub-1 (meter-scale)
coordinates. It also contains the **connector-routing subsystem**:

- `@MainActor struct SegmentPath` wraps a `Segment` for drawing; `SegmentPath.SetUpConnectors(...)` builds a `ViewConnector` (path + optional ground/impulse image) for each of a segment's `Connection`s. It classifies each connection (adjacent same-coil, non-adjacent same-coil, coil-to-coil, or termination) and routes accordingly: connectors avoid crossing coils by running in the radial gaps and crossing over/under the winding, choosing over-vs-under by shortest total travel (`ConnectorCrossover`); overlapping runs are spread into parallel **lanes** (`ViewConnector.assignLane` + `ConnectorChannel`); connectors attach to the tip of an existing `floating` lead rather than drawing a new stub.
- Routing **offsets are derived from the model geometry** by `UpdateConnectorMetrics()` (tightest hilo gap and winding height) so they scale with model size; lead-stub length instead tracks the **view scale** so it stays constant on screen.
- `RebuildConnectors()` re-runs the whole pass; it is triggered by `segments` changes **and on zoom** (menu/button handlers + a `didEndLiveMagnify` observer) and coalesces concurrent requests. Incremental add/remove-connector paths call `SetUpConnectors` directly on the affected segment(s).

## `AxisScale.swift`

Y-axis ticks and labels for the two result graphs. `AxisScale.Ticks(...)` returns the major ticks plus a highlighted tick at each
extreme the simulation reached; `AxisScale.DrawYAxis(...)` draws them and `AxisScale.YAxisWidth(ticks:)` reports how wide a left
margin they need. Major intervals are **25 kV up to a 250 kV crest and 100 kV above that** (`MajorVoltageInterval`), falling back to
a computed 1-2-5 interval when the fixed one does not divide the axis — a single coil of a 550 kV unit only reaches ~50 kV, which
would otherwise get no ticks at all. Extremes are rounded to the nearest kilovolt for a voltage and to two significant figures for
a current (0.1 kA in the kiloamp range, 1 kA in the ten-kiloamp range).

**Both graph views set their `bounds` to the data rectangle and let AppKit do the scaling**, which is why `DrawYAxis` takes a
`pointSize`: everything drawn at a fixed on-screen size has to be multiplied by the view's bounds-to-frame ratio. That only works
because the two views now build their bounds so the ratio is *the same in both directions* — the old code inflated the vertical
margin by `scaleMultiplier.y` as well as by the scale, which made it anisotropic. If you change how the bounds are computed, keep
`bounds.height == frame.height * scale`, or the tick labels come out stretched.

**`AxisScale.DrawXEndLabels(...)` marks only the two ENDS of an x axis**, and is used by exactly one graph — the initial
distribution, whose x axis is axial position and whose ends are "Top" and "Bottom". It is deliberately not a general x-tick
generator: on an axis where the ends say everything, a millimetre scale is clutter. The labels are pushed to the outside of their
own ends (a centred left label would hang over the y axis, the one place on the plot that already has ink) and are hung from the
**bottom of the data rectangle**, not from the zero line the x axis is drawn on — the two coincide only while every value is
positive, and a negative-polarity impulse would otherwise draw them down across the curve. A view that sets
`CoilResultsDisplayView.xEndLabels` gets a taller bottom margin (`AxisScale.XEndLabelHeight`) automatically, the same way the left
margin already grows to fit the y tick labels; leaving it `nil` is byte-identical to before.

The data reaching both views is in **volts or amps**, not pre-multiplied by the caller. Each view applies its own power-of-ten
`yValueMultiplier` on the way into view coordinates (same "keep the numbers near 1000" trick as before), but it has to know the real
values to label them. `AppController.doShowWaveforms` and `CoilResultsDisplayWindow` therefore pass `yQuantity` and
`peakTestVoltage` and hand over raw results. Both views also rescale on `setFrameSize`, so a resized window redraws rather than
stretching; `CoilResultsDisplayView.currentData` is a point array rather than a prebuilt `NSBezierPath` for the same reason.

## `InitialDistributionWindow.swift`

Graphs the **capacitive (initial) distribution**, α, against axial position for the impulsed coil. *Simulate → Show Initial Voltage
Distribution*. Three things about it are deliberate:

- **It needs no simulation run**, only a simulation *model*. α is the s→∞ limit of the sweep's own assembly, so `FrequencyDomainSolver.CapacitiveDistribution` produces it in one extra solve — which is the point, since the steepness at the line end is what decides whether a winding needs interleaving or shields, and that is worth knowing *before* the expensive part. `validateMenuItem` therefore enables it on `currentSimModel != nil` alone, unlike every other item in that menu. A simulation result is used only if one is to hand, and only to scale the y axis from per-unit into volts (`peakVoltage`); with none, the axis is `.unitless` and the note says so.
- **It reads the same α the stress report does**, rather than computing an initial distribution of its own — so this graph and the report's `0+ (initial)` rows cannot disagree.
- **The x axis runs top-to-bottom, left-to-right**, which is why `Distribution.points` carries a *depth below the top of the coil* and not a height above the yoke. That is the textbook orientation and it puts the line end on the left in the usual case, but it is the **opposite** of `CoilResultsDisplayView`'s other two users, whose x is a height — hence the end labels, which exist so the two graphs cannot be confused. "Impulsed coil" means a coil with a node carrying an impulse connector; if there is more than one they all go in the picker. Coils that are not driven are left out on purpose — α there is a small shunt-capacitance residual that would flatten the driven curve into the floor of the plot.

## Dialogs / windows

(`*.swift` + matching `*.xib`): `GetNumberDialog`, `GetSimDetailsDialog`, `ShowCoilResultsDialog`, `ShowWaveFormsDialog`,
`CoilResultsDisplayView/Window`, `WaveFormDisplayView/Window`. `GetSimDetailsDialog` carries the **bandwidth** field (MHz, default
10, clamped 2–200 by `bandwidthInHz`) — the solver's only accuracy control, since there is no longer a step size or error tolerance
to set. Those four dialogs subclass `PCH_DialogBox` from `PchDialogBoxPackage`.

**`GetWoundInShieldDialog` is the exception**: no `.xib`, an `NSAlert` with an accessory `NSGridView` built in code. It has six
read-only fields (insulation, stress, shield radial, build increase, C_s multiple) that all recompute as the user steps the shield
count, and keeping that right in hand-maintained auto-layout is not worth it. It clamps `n` to `floor(N) − 1` and opens on
`round(0.15·N)`.

## Preferences (`Preferences.swift`, `PreferencesDialog.swift`)

*ImpulseDistribution → Preferences…* (⌘,). `Preferences.swift` is the store — a `Preference` case per setting, whose raw value is
its User Defaults key, and a `Definition` giving its title, its explanation, its `Kind` and its factory default.
`PreferencesDialog` is an `NSAlert` with an accessory `NSGridView`, like `GetWoundInShieldDialog` and for a different reason: it
**generates itself from `Preference.allCases`**, so adding a preference is one case plus one `Definition` and no UI work at all.
The how-to is in the file header; keep it accurate, because the whole design is that nobody has to read the dialog to add a
setting.

Three things in there are deliberate:

- **The dialog holds the live values in `edited`, not in its controls.** A text field still being edited when a modal alert's OK
  button is hit has not necessarily committed to the cell, so reading the controls at the end silently drops the last keystrokes.
- **There is no cache in front of `UserDefaults`.** The hottest reader is the dielectric screen, which asks once per layer per
  site, and the reads come from **nonisolated** code (`DielectricStress.StressAllowable.Strike` runs wherever `Scan` was called
  from). `UserDefaults` is thread-safe and keeps its own in-memory copy; a bare global would need synchronization and its own
  invalidation.
- **`runModal()` returns which preferences changed**, so `AppController.handleShowPreferences` can invalidate exactly what went
  stale. Two do today, and they invalidate different amounts. The **dielectric design margin** invalidates the findings: every
  utilization is a fraction of an allowable carrying that margin, so the cached `latestStressChecks` is cleared and an open
  report window is re-run (the screen is milliseconds). **Show corner stresses** invalidates only the *window* — the columns are
  built once in `StressReportWindow`'s initializer and no finding depends on the setting — so an open report is rebuilt from the
  cached checks. Anything else added later that a preference invalidates belongs in that one method.

`Preferences.VerifySelf()` checks the store the same way the other `VerifySelf()`s check their formulas — and it walks
`Preference.allCases`, so a new preference is covered the moment it is added. Run it by calling it from
`AppDelegate.applicationDidFinishLaunching` and reading `defaults read com.huberistech.rabin2021 PreferencesVerification`.

The progress-indicator window (`rb2021_progressIndicatorWindow` in `AppController`) is `PchProgressIndicatorPackage`'s class;
`PCH_GraphingView/Window` and the `old...`-prefixed files are dead — see the target-membership table in `CLAUDE.md`.

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

The compiled target is exactly these 29: `AppController`, `AppDelegate`, `AxisScale`, `BasicSection`, `CoilResultsDisplayView`, `CoilResultsDisplayWindow`, `ConductorImpedance`, `Connector`, `Core`, `DielectricStress`, `FrequencyDomainSolver`, `GetNumberDialog`, `GetSimDetailsDialog`, `GetWoundInShieldDialog`, `InitialDistributionWindow`, `Node`, `NumericalLaplaceTransform`, `PhaseModel`, `Segment`, `SelfTest`, `ShowCoilResultsDialog`, `ShowWaveFormsDialog`, `SimulationModel`, `StressProfileWindow`, `StressReportWindow`, `TransformerView`, `TurnLadderModel`, `WaveFormDisplayView`, `WaveFormDisplayWindow`.

**When adding a `.swift` file, add it to the Compile Sources phase.** Eight files in this folder are already orphaned, and SourceKit reports a misleading `No such module 'PchBasePackage'` on a file that is not in the target — that diagnostic means "not in Compile Sources", not "package missing".

### Scripted end-to-end runs (`SelfTest.swift`)

There is still no test target, but the whole pipeline can now be driven **without a human at the keyboard**, from a launch
argument. This is the thing to reach for when a change needs exercising rather than merely reasoned about; the older
`VerifySelf()` routines (`DielectricStress`, `TurnLadderModel`, `Segment.VerifyWoundInShieldCapacitance`) still cover
single formulas, but they do not load a design file, build a model or solve anything.

```bash
cp <design file>.txt ~/Library/Containers/com.huberistech.Rabin2021/Data/Documents/
.../Debug/ImpulseDistribution.app/Contents/MacOS/ImpulseDistribution -PCH_SelfTest STME0999
cat ~/Library/Containers/com.huberistech.Rabin2021/Data/Documents/SelfTestReport-STME0999.txt
```

Add `-PCH_SelfTestTransient YES` for the frequency-domain sweep as well. A full run of the STME-0999 fixture — parse,
radial build-up, FE phase, eddy losses, inductance, capacitance, terminations, initial distribution and a 2048-step
transient — is **37 seconds**, so there is no reason not to run it.

One name in that argument is not a design: **`STRANDED`** runs `SelfTest.CheckStrandedConnection` instead, which is about the
connections rather than about a winding — it drops a jumper on a node that interleaving is about to swallow and checks that the
guard sees it and that the fold leaves nothing behind. See *Connector / Segment.Connection* below.

Four mechanical points, each forced by something:

- **`NSUserDefaults` parses `-key value` launch arguments itself**, so there is no argument plumbing and the test path
  cannot be reached from a normal launch (`applicationDidFinishLaunching` checks for the key and returns immediately
  when it is absent).
- **The fixture is read from the app's own container**, because the entitlements grant only
  `user-selected.read-write` — a design file anywhere else needs the `NSOpenPanel` that granted access to it. Do *not*
  "fix" this with a `temporary-exception` entitlement: that changes what the shipped app may read in order to run a test.
- **The report is a file, in that same container folder**; only a one-line summary goes to `UserDefaults`
  (`defaults read com.huberistech.Rabin2021 PCH_SelfTestSummary`). A page of report through `defaults read` is one
  enormous escaped line.
- **`PCH_SelfTestStage` is written and flushed before each step.** The pipeline raises `NSAlert`s on failure and a modal
  alert with nobody watching hangs the run forever, so that key is the only evidence of where a hung run stopped.

**A scenario names its connections as `SelfTest.LeadPoint`s, never as (Segment, location) pairs**, and `FindLead` goes and looks
for the lead the point names. Neither half of the pair is knowable from the design file: which Segment is at the bottom of a coil
depends on how many there are, and its lead sits at `.inside_lower`, `.outside_lower` or `.center_lower` depending on winding type
and disc count. A guessed one produces a connector `NodeAt` cannot resolve — which is the failure class this harness exists to
catch, so it must not be able to manufacture it. Two kinds of point exist: `.coilEnd(coil:end:)`, and `.gapLead(coil:gap:side:)`
for the two leads facing each other across an internal tapping/DV gap.

- **Terminations** hand the found location to `AddConnector`, which *replaces* a floating lead rather than appending to it —
  exactly what `TransformerView`'s `mouseDownWithAddGround` / `mouseDownWithAddImpulse` do, minus the hit testing. The
  `ConnectionDestinations` loop after it carries the ground to everything already jumpered to that lead, which is how "tie the two
  centre leads together and ground them" is one termination and not two.
- **Jumpers** (`SelfTest.Jumper`, applied between the restructure and the terminations) are a port of `TransformerView.mouseUp`,
  **cross-product and all**: a lead that already carries jumpers is at the same potential as everything on their far ends, so a
  new jumper is registered on every (Segment, location) pair at each end. Doing less would build a model the UI cannot produce.
  The order is forced from both sides — a restructure sends `UpdateConnectors` through the connectors and would sweep a jumper
  away, and a termination replaces the floating lead a later jumper needs in order to find its end.

**The run re-runs `SetNodes` itself, after the connections are on.** Nothing else does: the node topology a scenario is carrying
was built during the restructure's recalculation, when the coil ends were still floating. That is harmless when every connection
is a coil end, and wrong the moment one is not — a jumper across a tapping gap and a ground on a centre lead both change what
`SetNodes` decides. It calls `PhaseModel.CalculateCapacitanceMatrix` directly rather than `AppController.recalculateModel`,
because that one puts an `NSAlert` up when this throws and a modal alert with nobody at the keyboard hangs the run forever.

#### What the STME-0999 fixture is for

A real 4160Y/2400 V — 69 kV delta unit: 48-turn helical LV, 70-disc continuous HV, no taps and no axial gaps, both LV
leads and the HV neutral grounded and 350 kV full wave on the HV line end. The uniform geometry is the point — it is the
case **DelVecchio 13.5.1, "Uniform Capacitance Model"** (p.389) is written for, so a disagreement is more likely to be
this program's than the book's. The report checks the parse against the design (2.940 mm and 3.925 mm axial gaps for
nominal 3 mm and 4 mm unshrunk, 1379 turns at 19.7 per disc) and compares the computed initial distribution against
`sinh(αx)/sinh(α)`, α = √(C_g/C_s).

**α is reported as a bracket, not a number.** DelVecchio's C_g is capacitance to a grounded surround; a real phase has
another winding in the way, here grounded at both ends and so *nearly* — not exactly — an equipotential. So the report
gives `α` from the C_g booked straight to ground alone and again with the coil-to-coil term folded in, and the answer
should land between them. As of 2026-08-06 the HV coil gives **6.56 / 13.21 with a fitted 11.17**, and the local
d(ln V)/dx sits at 9.8 mid-coil rising to 11.5 near the line end.

#### The three STME-0999 variants

`STME0999`, `STME0999-interleaved` and `STME0999-shield6` differ **only** in `Scenario.restructure` — same core, conductor,
gaps and impulse — so the line-end gradient can be read off three times with nothing else moved. The restructure runs
*before* the terminations, because swapping Segments sends `UpdateConnectors` through the connectors and a ground applied
first would not survive it. `SelfTest.ApplyRestructure` is the model-level half of `doInterleaveSelection` /
`doAddWoundInShields` without the `SegmentPath` selection or the dialogs; it deliberately does **not** re-implement their
guards (already-interleaved, non-contiguous, spans a tapping gap), because it always works on a whole coil of a freshly
loaded model where each is answered by construction. Route anything less regular through the `AppController` versions.

| | C_s per pair | fitted α | line-end gradient | worst section | transient peak |
|---|---|---|---|---|---|
| plain | 3.932e-10 (1.0×) | 11.17 | 30.31× | **65.4 kV** / 1 disc | 1.236 p.u. |
| 6-turn shield | 7.766e-09 (19.8×) | 2.46 | 2.68× | **28.6 kV** / 2 discs | 1.002 p.u. |
| interleaved | 8.917e-09 (22.7×) | 2.28 | 2.59× | **27.6 kV** / 2 discs | 1.002 p.u. |

Three things to know before reading that table:

- **"Section" is not the same amount of winding down the column.** Both restructures rebuild the coil into *two-disc*
  Segments, so the plain row's worst section is one disc and the other two are two. The **line-end gradient is the
  directly comparable number** — it is a voltage per unit of winding height and does not care how the coil is divided.
- **A 6-turn shield gets 86% of the way to full interleaving**, which surprises people. `C_s(n)` is linear in n
  (`VerifyWoundInShieldCapacitance` pins that to 4.4e-16), the slope here is 1.229e-9 F per shield turn, and
  extrapolating hits the interleaved value at **n = 6.94** out of 19.7 turns per disc. So on this design a 7-turn shield
  *is* an interleaved winding as far as C_s is concerned. That is the whole selling point of 12.11 — but it also means
  "somewhere in between" is technically true and practically misleading, and a scenario at n = 2 or 3 would sit nearer
  the middle.
- **The shield is not free and interleaving is.** The shield adds 1.778 mm of bare radial plus 0.305 mm of paper per
  shielded pair, taking the HV radial build from 56.767 to 69.264 mm; `ApplyRadialBuildUp` then grows `legCenters`
  760 → 784.994 mm and the tank depth 1343.3 → 1368.3 mm to hold the clearances. C_g rises only 1.7% because of it.

#### The STME-0999_2 variants, and why they invert the answer

The second fixture is the regime intershielding actually exists for: **25 MVA, 120 kV wye / 26.4 kV delta, both coils
disc-wound in CTC**, 550 kV BIL. CTC is a large stranded conductor, so a disc holds few turns — 688 over 64 discs, 10.75
each — and interleaving a CTC winding is essentially impossible to manufacture. The interleaved scenario here is a
**reference**, not a proposal: it says what the shield is measured against.

**All three hold the HV at the same radial build**, the one the 5-turn shield needs (+10.414 mm = 5 × 2.083 mm over
paper), via `Scenario.matchedBuild` → `PhaseModel.radialBuildUpFloor`. That is not a nicety. Fitting a shield does *two*
things — it adds shield turns and it widens the disc, and a wider disc has more face area, so C_dd rises on its own
(C_dd ∝ R_out²−R_in²). On the first fixture the 6-turn shield widened the HV 22%, worth 24% more face area, and there
was no way to tell from the result how much of the gain was the shield. With the floor set, all three runs come out with
identical ID/OD/build, identical `legCenters` and tank depth, and **identical C_g to 7 figures** — so the only thing left
different is the electrical treatment. `SelfTest.SizeShield` sizes the wire for both the fitting and the matching path,
so a "matched" geometry cannot silently fail to match.

| C_s per pair, identical geometry | | α fitted | line-end gradient | worst section | peak |
|---|---|---|---|---|---|
| plain | 7.063e-10 (1.00×) | 8.22 | 23.09× | 73.1 kV / 1 disc | 1.195 p.u. |
| 5-turn shield | 4.988e-09 (7.06×) | 2.958 | 3.194× | 47.2 kV / 2 discs | 1.002 p.u. |
| interleaved | 5.006e-09 (7.09×) | 2.953 | 3.189× | 47.1 kV / 2 discs | 1.002 p.u. |

**k = 5 of N = 10.75 is 47% of the turns, which is right at the break-even point** — turn terms alone are 4.487·c_t
interleaved against 4.535·c_t shielded, and break-even is k = 4.97. That is why this fixture keeps producing photo
finishes and why it is a poor place to ask "which method is better". At the shield fractions real designs use it is not
close: 28% of the turns puts interleaving 66% ahead, 19% puts it 149% ahead. The first fixture, at n/N = 30%, gives
interleaving **+47%** and is the more representative comparison. See TODO.md §2b for the whole cross-check.

Note what the last three columns say regardless: at α ≈ 3 the initial distribution is already near enough to linear that
more C_s has nothing left to flatten — line-end gradient 3.2 either way, envelope 1.002 p.u. either way. On this design
the choice is a manufacturing decision, not a dielectric one, which is the answer a designer wants and the opposite of
what the C_s column alone suggests.

Note that "plain" in that table is **not the as-designed transformer**: it is the design widened to the shield's build,
which raises its C_s too. It is the right baseline for isolating the shield and the wrong one for costing the design.

**The interleaved row's low section voltage is the disc-to-disc stress only**, and the report says so at that line.
Interleaving buys it by winding electrically distant turns side by side, which *raises* the turn-to-turn voltage inside
each disc — the reason an interleaved winding needs heavier turn paper. Nothing in this harness measures that, and
`TurnLadderModel` refuses interleaved windings on purpose (the position-to-turn map is scheme-dependent).

**The C_g "booked to ground" of the outermost coil is not the tank** — it is the tank *plus the adjacent phases*, which
are **76%** of it here. The report prints the split for exactly that reason; see `OuterShuntCapacitance` and
`adjacentPhaseCount` under the capacitance section above.

Two things learned from the first run, both worth keeping:

- **Fit α on ln(V), never on V.** The distribution spans four decades, so a least-squares fit in V sees only the top two
  or three discs — precisely the least representative ones, since the end disc has its own series capacitance. The
  linear fit returned **14.75** against a winding whose local α is 9.3–10.8, put the answer outside the C_g bracket, and
  so reported a disagreement with DelVecchio that was entirely an artefact of the estimator. This is the same shape of
  error as the `Residual` 1e-9 story under *Calculation & simulation layers*: a diagnostic that fails on a correct model
  is worse than no diagnostic. The table's **local-α column** asks the same question with no fitting at all and should
  be read first.
- **The end disc is not on the curve, and that is real.** `Section Cs` shows the two end discs of the HV at **0.294 of
  the mean** (the helical LV's at 0.511), which is `SeriesCapacitance`'s end-disc branch (DV 12.63-64) doing its job —
  an end disc has a neighbour on one side only. It takes 0.366 p.u. across it at t = 0+, a local α of 36 against the
  winding's 10.8. A **uniform** continuum model cannot represent that, so the departure at x → 1 is expected; what
  would be a real finding is that departure appearing anywhere else, or the end-disc Cs ratio moving.

The line-end gradient is divided by the end section's **own** span in x, not by 1/N: the end nodes sit at the outer face
of the end disc while interior nodes sit at gap midpoints, so end sections are ~12% shorter and 1/N charges them for
length they do not have.

#### The S0738 fixture: a connection, not a winding

`S0738` and `S0738-plain` (`S0738_AndIn.txt`, four coils, 1050 kV on the HV) are the first fixture here that is about **how the
coils are wired together**. Coils 0 and 1 are grounded at both ends; coil 2 is the impulsed 74-disc HV, interleaved in its
entirety in the first variant and left alone in the second; **coil 3 is a double-stacked tap winding** whose two ends are tied to
each other and to the *bottom of coil 2*, and whose two centre leads are tied to each other and grounded. Three things in that are
not reachable from either STME fixture, and all three are node-topology questions rather than capacitance ones:

- a coil with an **internal tapping gap** (`AppController`'s segment-building loop cuts one into any double-stacked coil, and
  gives each side its own `outside_center`/`inside_center` floating lead);
- **both centre leads jumpered together *and* grounded**, which is the combination that erases every floating lead at the gap;
- a coil **fed from another coil** rather than from a ground, an impulse or nothing.

It was written to reproduce a reported failure and did, verbatim: *"segment 168 has a connector at outside_center with no node
there (target: 169)"* — see `IsTappingGap` under *Connector / Segment.Connection*. Both variants now run the whole pipeline
including the transient (82 s with `-PCH_SelfTestTransient YES`).

**The continuum comparison is declined on this fixture, out loud.** DelVecchio 13.5.1 solves a boundary-value problem, and one of
its two boundaries is missing here: coil 2's far end returns through both halves of coil 3 to a centre ground, so it floats at
**0.652 p.u.** at t = 0+ (0.169 p.u. unrestructured) and `V(0) = 0` is simply false. Fitting anyway returned α = 0.010 "inside the
bracket" on a winding whose local α is 0.2 and rising — the same class of artefact as the linear-vs-logarithmic fit above.
`ContinuumComparison` therefore **measures** the far end against `groundedEndTolerance` (1e-6; a grounded node comes back an exact
zero from the row surgery, so there is nothing to tune between that and 0.65) and, when it fails, prints the distribution and the
line-end gradient alone. Those two are what survive the model not applying, and the gradient is still the comparable number:
**25.18× average plain against 0.615× interleaved**.

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

  **`axialPos` is a coordinate, never an index.** `Segment.axialPos` returns `basicSections[0].location.axial` — the *pristine design-file disc index* of the Segment's lowest BasicSection — and is **never renumbered**. It equals the Segment's ordinal position within its coil only while every Segment holds exactly one BasicSection, which the load path guarantees (`AppController:955` wraps each BasicSection in its own Segment) and which a combine, an interleave, or a wound-in-shield pairing destroys: 8 discs interleaved into 4 Segments leaves the coordinates at 0/2/4/6. The **ordinal is a Segment's position in `PhaseModel.CoilSegments()`**, which is what `CreateFePhase` walks to build the FE sections, what `SimulationModel` sizes `vDropInd` by, and what the capacitance assembly indexes. Deriving one from the other — `GetHighestSection(coil:) + …`, or `+ segment.axialPos` — was a real bug at **four** sites (fixed 2026-08-04/05): it crashed *Interleave* inside `PchFePhase.SetSeriesRmsCurrentForSection` with "Index out of range", and when the restructured coil was not the last one it instead wrote one coil's currents over the next coil's sections and returned a plausible, wrong inductance matrix with no error at all. The fourth was `ShowWaveFormsDialog`, which was handed `GetHighestSection` values and rebuilt the flat per-coil offsets itself; it now takes `coilRanges:[ClosedRange<Int>]` from `SegmentRange(coil:)`, which deletes that arithmetic rather than repairing it. **When something needs a range of `CoilSegments()` indices, get it from `SegmentRange(coil:)` — do not recompute it.** `GetHighestSection` is still correct where it is **compared against another `axialPos`** (`TransformerView`'s end-disc tests, `PhaseModel:1483/2189/2245`); it is never a count. `CreateFePhase` asserts the `(radialPos, axialPos)` sort that the ordinal depends on, and `recalculateModel` guards `window.sections.count == coilSegments.count`.
- **`Core`** (struct, `Core.swift`) — core geometry (diameter, window height, leg centers) used by inductance calculations.
- **`Node`** (struct, `Node.swift`) — a connection point between segments. Its `number` is **0-based and doubles as the index into the capacitance matrix**. Shunt capacitances to ground use `toNode = -1`.
- **`Connector`** / **`Segment.Connection`** (`Connector.swift`, `Segment.swift`) — an electrical "jumper". A `Connector` has a `fromLocation`/`toLocation` from the `Connector.Location` enum: eight physical points on a segment (`{inside,center,outside}_{upper,lower}` plus `outside_center`/`inside_center`) and the special *terminations* `floating`, `ground`, `impulse`. A `Segment.Connection` pairs a `Connector` with an optional `segmentID`: non-nil ⇒ a jumper to that segment's location; nil ⇒ a termination on `self`. Coil ends and tapping gaps carry a `floating` lead by default; `AddConnector` **replaces** a floating lead with ground/impulse but **appends** a segment-to-segment jumper (leaving the floating lead in place).

  **A tapping gap breaks the node chain even when it is bridged.** `outside_center`/`inside_center` connectors are created in exactly one place — `AppController:1030-1044`, at tapping/DV gaps — and `Connector.AlternatingLocation` only ever pairs a center location with another center location; a real series connection between adjacent discs always maps an **upper** location to a **lower** one. So a center connector means "tapping gap", always. `SetNodes` therefore gives each side of a gap its own node, testing `IsTappingGap` *as well as* the presence of a connection — matching `NonAdjacentConnections`' rule that gap jumpers "will be adjacent, but for the purposes of the simulation they will not be". The jumper is then tied up explicitly through `finalConnectedNodes` → `mergedNodes` → the `V_eliminated − V_kept = 0` row surgery. Testing only for a connection (as `SetNodes` did until 2026-08-04) made a *bridged* gap look continuous, so `NodeAt` — which resolves a center connector only to a dangling node — could not find the node its own connector described, and `SimulationModel.init` failed. **Both routines must keep using the same predicate** — and `SetNodes` now ends by calling `VerifyNodeTopology()`, which asks `NodeAt` to resolve every connector in the model and throws `.UnresolvableConnector` if one fails. Note what that guard deliberately is *not*: a node **count** check (`nodes == segments + breaks + coils`) is a tautology, because `breaks` comes from the same predicate — it held perfectly while the bug was live. Only a check that crosses the `SetNodes`/`NodeAt` boundary can see a wrong break decision. Relatedly, neither operation that *regroups* a selection (`doInterleaveSelection`, `doAddWoundInShields`' pairing path) may run across a gap: flattening would swallow the break into the middle of a Segment and strand its two center leads. Both call `AppController.SelectionSpansTappingGap` and refuse.

  **`IsTappingGap` recognises a gap by the LOCATION, not by the termination** — and until 2026-08-07 it did the opposite, which
  cost the same failure a second time. Its test was for a *floating* lead facing across the boundary from each side, and
  `AddConnector` **replaces** a floating lead with a ground or an impulse. So a designer doing the ordinary thing with a
  double-stacked winding — tie the two centre leads together, ground them, which is what a centre-grounded tap winding *is* —
  leaves neither side floating and erases the only evidence the gap existed. `SetNodes` then read the bridging jumper as a series
  connection, gave the two sides one shared node, and `NodeAt` could not find the dangling node a centre connector insists on:
  *"segment 168 has a connector at outside_center with no node there (target: 169)"*. Since a centre location is only ever created
  at a gap, the location is permanent evidence and the termination is not, so the predicate now accepts `fromIsCenter` whatever it
  is tied to. **Both sides must still agree**, and that is not belt-and-braces: the Segment *above* a gap carries a centre lead
  facing down, so testing either side alone would report the boundary above *it* as a gap too. `SelfTest`'s **`S0738`** scenario is
  this case end to end.
  **One jumper is stored as up to four connections, and a fold is where that bites.** A node is shared by the two Segments that meet
  at it, and `TransformerView.mouseUp` registers a new jumper on **every** (Segment, location) pair at each of its two ends — the
  whole cross-product, each copy carrying the others in its `equivalentConnections`. So a jumper dropped between discs 10 and 11 lives
  on *both* discs (and on both discs at the far end). While those discs are separate Segments the copies describe the same node and
  are drawn a disc-gap apart, i.e. on top of each other. **Fold the two discs into one Segment and they no longer do**: `NodeAt`
  resolves a connection by upper/lower alone, so disc 10's copy (an *upper* location) comes back on the new Segment's **top** node and
  disc 11's (a *lower* location) on its **bottom** node. That drew two connector lines where the user made one — and
  `SimulationModel.init` unions the node groups a jumper ties together, so it also **shorted the new Segment out**, silently, with a
  plausible answer at the end of it. Three things now stand between that and a wrong answer, and they are meant to be read together:

  - `PhaseModel.UpdateConnectors` inherits **only** the connections at the two surviving terminals (lower-locations from the first old
    Segment, upper-locations from the last) and sweeps away the **mirror** of everything it discards — matching on the old serial
    number *and* the connector, which is what `Segment.RemoveConnectionsMatching` is for. Dropping one half only re-attaches the jumper
    from the other side, so both halves have to go together, and the sweep has to run **before** the serial remap.
  - `AppController.SelectionStrandedConnection` refuses the operation first, so the loss is the user's decision rather than a silent
    one. It is called by *Combine*, *Interleave* and the wound-in-shield **rebuild** path, and is conservative over the whole selection
    for the same reason `SelectionSpansTappingGap` is.
  - `SegmentPath.SetUpConnectors` draws **one line per equivalence class**, so the redundant copies never reach the screen (and
    `assignLane` stops spreading them into parallel lanes as though they were separate connections).

  `SelfTest`'s **`STRANDED`** run (`-PCH_SelfTest STRANDED`) puts a jumper on a node interleaving is about to swallow and checks all
  three: the guard sees it, neither end still names the other afterwards, and no node group ties the merged Segment's two terminals.

- **`PhaseModel`** (`actor`, `PhaseModel.swift`) — the central model object. Owns the sorted `segmentStore`, the `nodeStore`, and the `core`. All model mutation/queries go through it. Throws `PhaseModelError`.
  - It also holds `voltsPerTurn`, set by `AppController.recalculateModel` from the design file. It is the one place the model knows an *actual* operating voltage rather than a per-unit one; only the wound-in-shield paper sizing uses it so far.
  - **Live vs pristine radial geometry.** A `BasicSection`'s rect holds the **pristine** radii read from the design file and is never rewritten; the **live** geometry is the owning `Segment`'s `rect`. `PhaseModel.ApplyRadialBuildUp()` recomputes every Segment's rect from pristine + the current wound-in-shield set, widening each shielded coil by its widest disc's requirement, pushing everything outside it straight out (preserving the hilos, which are withstand-driven minimums), and growing `core.legCenters` and `tankDepth` by twice the total. Because it works from pristine absolutes it is idempotent and exactly reversible, so `AppController.recalculateModel` just calls it unconditionally — which also repairs the geometry after a combine/split/interleave. `basicSections` stays a `let` deliberately: `validateMenuItem` reads it synchronously from the main actor and cannot `await`.

### Calculation & simulation layers

- **`EslamianVahidiModel.swift`** (`EslamianVahidiSegment`) — an **alternative inductance-matrix implementation that is not compiled into the app** (see the target-membership table above) using the double-Fourier-series method from the Eslamian & Vahidi paper ("New Methods for Computation of the Inductance Matrix of Transformer Windings for Very Fast Transients Studies"), covering both inside- and outside-the-core-window cases. The active code path computes the inductance matrix via the finite-element package (`PchFiniteElementPackage`) instead; this file is kept for reference/comparison only.
- **The capacitance matrix** is built by `Segment.SeriesCapacitance` (the series capacitance of each segment) and `PhaseModel.CalculateCapacitanceMatrix` (shunt capacitances + assembly). The authorities are **DelVecchio, *Transformer Design Principles*, chapter 12** for everything series/disc-related, and **Kulkarni & Khaparde, *Transformer Engineering*, chapter 7** for the coil-to-tank and phase-to-phase terms. Both PDFs live in `~/Documents/MyProjects/Claude/`. A full conformance audit was done 2026-08-02/03; see `TODO.md` for what is still known to deviate.

  | quantity | equation | where |
  |---|---|---|
  | C_tt turn-turn | DV 12.47 | `Segment.CapacitanceTurnToTurn` |
  | C_s = C_tt(N−1)/N² | DV 12.49 | `Segment.BasicSectionSeriesCapacitance` |
  | C_dd disc-disc, f_ks | DV 12.52, 12.50 | `Segment.DiscToDiscSeriesCapacitance` |
  | general / Stein / static ring / end disc | DV 12.53-54, 12.35, 12.62, 12.63-64 | `Segment.SeriesCapacitance`, `.disc` branch |
  | helical (C_s = 0) | DV 12.41, generalized to unequal gaps | same, `.helical` branch |
  | wound-in shields | DV 12.96-99 | `Segment.WoundInShieldSeriesCapacitance`, `.WoundInShieldPairCapacitance` |
  | shield wire paper | τ_w = τ_p (see below) | `Segment.WoundInShieldWire.Standard` |
  | C_ll layer-layer | DV 12.60-61, transposed | `Segment.LayerToLayerCapacitance` |
  | coil-to-coil ground capacitance | DV 12.60-61 | `PhaseModel.CoilInnerShuntCapacitance` |
  | coil-to-tank, phase-to-phase | K&K 7.15 (+ App. D.28/D.30) | `PhaseModel.OuterShuntCapacitance` |

  **The τ_p convention is the landmine in this code.** DelVecchio's τ_p is the **two-sided** paper thickness of a turn (his worked example: "The 2-sided paper thickness is 1 mm", then τ_p = 0.001), and the Excel design file's insulation fields are two-sided totals as well. Three places depend on that silently: `tp` in `DiscToDiscSeriesCapacitance`, `tau` in `CapacitanceTurnToTurn`, and the `height - tp` that turns disc height into bare copper height in the same function. C_tt goes as 1/τ_p, so a stray factor of 2 moves **every** disc capacitance in the model by 2×. Both sites carried a commented-out `2.0 *` for years; do not put it back. Two exceptions, each deliberate and noted at its declaration: `Segment.staticRingInsulationPerSide` is a **per-side** figure (3 mm), and `woundInShieldMinInsulationPerSide` likewise (0.006") — everything downstream of it doubles it. `WoundInShieldWire.insulation` is two-sided like the rest.

  Note the interaction with `CapacitanceTurnToTurn(effectiveInsulation:)`: that parameter overrides the **gap** (τ_avg = ½(τ_p + τ_w), for a coil turn facing a shield turn) but `h` keeps using the coil turn's own τ_p, because h is the coil turn's bare copper height and does not change because a shield sits beside it. With the default `nil` the two are the same number and the behaviour is byte-identical to before.

  **`OuterShuntCapacitance` is two terms, and on a tight design the one nobody expects is the larger.** It returns the tank and
  phase-to-phase capacitances **split**, because they are routinely mistaken for each other: on the STME-0999 fixture *each*
  neighbouring phase contributes 1.759e-10 against the tank's 1.085e-10, so at the default two neighbours the phase-to-phase term is
  **76%** of the total. 760 mm leg centres against a 693.9 mm outermost OD leave 66 mm between phases, and `acosh` is steep near 1 —
  `acosh(1.0953) = 0.433` against `acosh(1.936) = 1.279`. A hand calculation of coil-to-tank checked against the sum looks wrong by
  4× when nothing is. The caller adds them straight back together and books both to ground, which assumes **the adjacent phases are
  at ground potential** — true in an impulse test, where the untested phases are grounded, but an assumption and not a geometric fact.

  **`PhaseModel.adjacentPhaseCount` is 2, i.e. the CENTRE leg, on purpose.** That is the highest C_g the geometry can give, so the
  highest α = √(C_g/C_s), so the steepest initial distribution. `AppController.recalculateModel` sets it from the design file: 2 for
  a polyphase unit, **0 for a single-phase one**, which has no neighbour and used to be charged for one anyway.

  Two things not to overclaim about that "worst case", both measured on the fixture when the default changed from 1 neighbour to 2:

  - **It is worst for the dielectric numbers, not for everything.** The line-end gradient went 29.05 → 30.31 × average and the worst
    section voltage 63.0 → 65.4 kV, which is the point. But the mid-winding envelope went *down*, 1.247 → 1.236 p.u.: more shunt C
    diverts more of the surge to ground, and the classical "envelope grows with α" is a result for a lossless uniform line, not for
    this network. The move is under 1% either way, so the honest summary is **conservative for turn-to-turn stress, neutral for the
    envelope**.
  - **The tank term does not distinguish the legs at all.** It uses `tankDepth/2`, the distance to the **front and back** walls,
    which is the same for every leg; the tank's **end** walls, which only an outer leg is near, are not modelled. So an outer leg is
    missing a term the centre leg genuinely does not have. It is much smaller than a whole phase-to-phase gap, so the centre leg is
    still worst — by less than the arithmetic suggests.

  **A shield turn is papered like the coil turn it sits against** — `WoundInShieldWire.Standard` takes the largest of the coil
  turn's own covering, what the working stress needs, and the shop minimum, then rounds up to a whole wrap. This is not cosmetic:
  **c_w/c_t is exactly τ_p/½(τ_p + τ_w)**, so τ_w = τ_p gives c_w = c_t and a shield-to-turn interface identical to a turn-to-turn
  one, while a thin-papered shield sits *closer* to the coil copper than another coil turn would and drives c_w/c_t towards 2.

  That single ratio decides whether shields or interleaving win, because at n ≈ N/2 the two methods are within 7% on interface
  count alone — interleaving's `c_t(N−1)/2` against a shield's `n·c_w·[4β²+1−1/N+1/2N²]`, i.e. 4.875 against 4.557 at N = 10.75,
  n = 5. Until 2026-08-06 `Standard` clamped τ_w to `woundInShieldMinInsulationPerSide` (0.006″/side) whenever the coil's own paper
  already satisfied the stress check, which on a CTC coil with τ_p = 1.638 mm gave τ_w = 0.305 mm, c_w/c_t = 1.55, and a 5-turn
  shield *beating a fully interleaved winding*. Interleaving is the higher-capacitance method; the model now says so. The minimum
  is still there as a floor and now only bites on a coil whose own covering is under 0.012″ two-sided.

  The fix costs radial build, which is the honest trade: the shield wire goes from 2.083 mm over-paper to 3.454 mm, so five turns
  take 17.272 mm instead of 10.414 mm.

  The implementation of 12.96-99 itself was checked against the printed page during this and is **exact**: 12.84-12.91 give four
  voltage differences per shield turn — (V−V_bias), (V−V_bias−ΔV), V_bias, (V_bias−ΔV) — whose squares sum to precisely the code's
  `4β²+1−2δ+2δ²`. Note 12.90's "This does not depend on i": the shield crosses over at the *outermost* turn while the coil crosses
  at the innermost, so the shield ramps opposite to the coil and every shield turn holds ~V/2 whatever its radial position. That is
  structurally the same trick as interleaving, which is why the two land so close at n ≈ N/2 and why c_w/c_t is decisive. Table 12.1
  is measured on two disks of **10 turns/disk at n = 0, 3, 5, 7, 9**, so n/N up to 0.9 is inside his validated range, not an
  extrapolation.

  **The interleaved branch takes the interturn capacitance alone — no Stein, no disc-disc term.** K&K 7.3.5: "it is sufficient to
  consider only the interturn capacitances for the calculation of the series capacitance of interleaved windings." It used to fall
  through to the Stein branch, which was wrong twice: Stein assumes one radial traverse where a two-disc unit makes two (the same
  objection that earned the shielded pair its own route), and the disc-disc energy it added was 24% of the interleaved total. The
  turn term itself is now **K&K 7.39 exact**, `(C_T/4)[N + ((N−1)/N)²(N−2)]`, rather than his 7.40 `N ≫ 1` form — which is what
  Veverka 6.4 is, and which runs 4.9% high at N = 19.7 and 8.6% high at N = 10.75, worst exactly where CTC coils live.

  Because `Cs` is now the whole answer for an interleaved unit, `endDisc` and `adjStaticRing` no longer do anything on that path:
  both exist only to modify the disc-disc term. An interleaved unit at a coil end is no longer reduced, which is right — there is
  nothing left for the end condition to act on.

  **Both two-disc units get their disc-disc energy from `Segment.TwoDiscPairCapacitance`** — the interleaved pair and the
  wound-in-shield pair alike, using DelVecchio's linear-voltage `Cs + Cdd_int/3 + (Cdd_below + Cdd_above)/6`. They are structurally
  the same object (two discs wound as one thing, one internal gap, one external gap per face), and letting them get that term from
  different places is how a comparison between the two methods ends up measuring the bookkeeping rather than the physics — which is
  what happened when the interleaved path followed K&K 7.3.5 and dropped it: the resulting 17% gap on STME-0999_2 was *entirely* the
  asymmetry, since the turn terms there are a dead heat. The shielded pair passes an `internalCddScale` below 1; an interleaved pair
  passes 1, because every turn in its discs is a coil turn.

  Other structural facts worth knowing before editing:
  - **`DiscToDiscSeriesCapacitance` gaps are measured between *insulated* surfaces.** A disc's `z1`/`z2` are over-paper and a static ring's rect is its overall wrapped thickness (`stdStaticRingThickness`, 5/8"), so the gap handed in is pure key-spacer/oil and every solid layer is added separately. That is exactly why 12.52 uses τ_p and not 2τ_p for a disc-disc gap: each disc contributes half of its two-sided paper. It takes `innerRadius`/`outerRadius` as **explicit parameters** rather than reading them off the `BasicSection`, because a BasicSection carries the pristine design-file radii while the live geometry lives on the Segment — pass `self.r1`/`self.r2`.
  - **The multi-unit loop in `SeriesCapacitance` iterates *units*, not BasicSections.** A unit is one disc normally and a **double disc when interleaved or spanned by a wound-in shield**. The spans are *not* a fixed stride — `SeriesCapacitanceUnits()` builds an explicit `[(range, shieldTurns)]` list, because a shielded pair whose `n` is 0 is emitted as two single discs so it keeps the plain path's Stein/end-disc/static-ring treatment. Derive indices from the unit's own range, never by arithmetic on the loop counter; doing the latter made interleaved segments silently read the wrong sections, which was a real bug.
  - **The temporary Segments built by that recursion need `SetRadialGeometry` handed down.** `Segment.init` takes its rect from the BasicSections, and those hold the **pristine** design-file radii — the live radii live on the Segment's `rect` (see below). Skip this and a built-up coil is measured at the radius it had before the build-up.
  - **Wound-in shields (DV 12.11).** `Segment.WoundInShield` carries a coil-level `WoundInShieldWire` (connection, bare radial, insulation) plus a **per-disc-pair** `turnsPerDisc: [Int]`, so a graded scheme is a data change rather than a code change. The pair — not the disc — is the unit, because a shield crosses over at the outermost turn of a pair. A shielded pair does **not** go through Stein: Stein assumes one radial traverse and a pair makes two, which over-counts the disc-disc energy 2× and drops the pair's internal gap. It uses DelVecchio's linear-voltage form, `Cs + (1/3)·Cdd_internal + (1/6)·(Cdd_below + Cdd_above)` — the per-gap split of his "(2/3)·c_d embedded". That assumption costs +2.96% at n=1 and 0.47% at n=3, but +117% at n=0, which is why n=0 is routed to the plain path. `Segment.VerifyWoundInShieldCapacitance()` re-measures all of this; the doc comment says how to run it.

    Because the pair is the unit, **a shield can only exist inside a Segment that holds an even number of discs** — `SeriesCapacitanceUnits()` emits units within one Segment, so a pair straddling two Segments is not representable. The load path gives every disc its own Segment, so `AppController.doAddWoundInShields` **rebuilds an odd selection into two-disc Segments** (flatten → pair → `updateModel(oldSegments:newSegments:)`), exactly as `doInterleaveSelection` does, and sets the shield on each new Segment *before* handing it to `updateModel` so the geometry and matrices are recomputed once rather than twice. A selection whose Segments are already all-even is left structurally alone. `validateMenuItem` therefore accepts **either** an even segment count (rebuild path) **or** all-even disc counts (no rebuild); testing only one of the two disabled the item on, respectively, every freshly loaded model and every already-combined Segment.
  - **Only the two end units of a segment can be at a coil end or beside a static ring**, and only on their outward face. The recursion passes a non-nil tuple with the far side cleared, so both the `endDisc` and `adjStaticRing` tests need the `!= (false, false)` guard — a missing one on the static-ring side was a real bug.
  - **`.sheet` correctly has no shunt term**; `.layer` genuinely needs one. A sheet winding is a single BasicSection spanning the full height, so its radial neighbours are *other coils* (a shunt path, handled in `PhaseModel`), whereas adjacent *layers* belong to the same winding at different potentials and are true series energy. Layer windings use the "Huber method" — DelVecchio's disc treatment turned on its side, with C_dd → C_ll — and are outside the book entirely.
  - **Verification is by hand.** There is no test target, so two checks carry the weight. First, `DiscToDiscSeriesCapacitance` must reproduce DelVecchio's own worked example (p.337: R_in 0.3, R_out 0.37, f_ks 0, τ_p 0.001, τ_ks 0.005 ⇒ C_dd = 5.0991e-10 F) — re-run it mentally after touching that function. Second, **`Segment.VerifyWoundInShieldCapacitance()`** is a runnable self-check for the 12.11 path; its doc comment gives the one-liner for `AppDelegate` and the `defaults read` that gets the report back out (the app is sandboxed, so `print` and `/tmp` are both dead ends). It asserts three things, all passing as of 2026-08-03: 12.96 at n = 0 equals two plain discs in series **exactly**; the pair capacitance is linear in n at fixed radius to 4.4e-16; and the linear-voltage assumption costs +2.96% at n = 1, falling to +0.47% at n = 3.
  - **The 12.11 comparison against Table 12.1 was done separately** (his air constants, ε_p 1.5 / ε_ks 4.0, not the program's oil values) and lands high by a flat 4.6–6.0% across all 13 entries and all three connections. That is DelVecchio's own winding-looseness correction — p.357, "about a 5% correction" — and it must **not** be built into the code, since it is a property of his loose two-disc test coil. The thing to check after editing is that the residual stays *flat*; a residual that varies with n is a real error.

- **The transient is solved in the frequency domain**, not by time-marching. This is the live path, and it replaced the RK45 integrator (2026-08-01). Three files:
  - **`ConductorImpedance.swift`** — R(ω) from Dowell's exact 1-D skin (`F_R`) and proximity (`G_R`) functions, each normalized by its own value at 60 Hz so the Excel design file's per-unit eddy data is reproduced exactly at 60 Hz. These *replace* DelVecchio 12.103/12.104 — but note the old expressions are precisely the **high-frequency asymptotes of this same normalized model** (the identity `2·ξ₆₀/G_R(ξ₆₀) = 6/ξ₆₀³` holds exactly), so above ~100 kHz the two agree to 1 part in 10⁴. Only the sub-crossover range changed, where the old form over-predicted eddy loss (6× at 1 kHz, 466× at 60 Hz) and could return R_ac < R_dc or NaN.
  - **`NumericalLaplaceTransform.swift`** — damped-contour NILT (`s = σ + jmΔω`, σT = 5, record twice the displayed span). Knows nothing about transformers, so it is verified standalone against closed-form transforms. **Default window is `.none`**: the dominant error is a missing-tail bias, not Gibbs ringing, so a window makes it 2–10× worse.
  - **`FrequencyDomainSolver.swift`** — assembles `[sC', −Ā; −B, sM+Z(s)]` and sweeps. **It subtracts the s→∞ asymptote before inverting** — `α = C'⁻¹E`, the classical capacitive initial distribution — because inverting `V(s)` directly converges only as 1/f_max (1.7e-2 at 10 MHz; ~2 GHz would be needed for 1e-4). The subtraction takes the spectrum from 1/s² to 1/s⁴ and is 15–40× more accurate at identical cost. Do not remove it.

  Two consequences worth knowing: every frequency sees its **own** R, so there is no "fundamental frequency" estimate and no two-pass scheme; and **bandwidth is a real accuracy control**, exposed in the simulation dialog, not a free parameter.

  **Validation results** (synthetic 5-node/4-segment ladder; re-run these if the assembly is ever touched):

  | check | result |
  |---|---|
  | solve residual ‖Ax−b‖/‖b‖ | 3.1e-16 |
  | α at impulsed / grounded node | exactly 1.0 / 0.0 |
  | vs. independent RK4 of the same ODEs | 2.4e-4 of peak |
  | **vs. ngspice `.ac`**, 161 freqs, 1 kHz–10 MHz | **3.3e-7** |
  | vs. ngspice `.tran`, t ≥ 1 µs | 2.5e-4 |
  | vs. ngspice `.tran`, first sample (49 ns) | 5.2e-3 |

  The `.ac` result is the important one: it isolates the **assembly** (signs, row surgery, block offsets) from the transform, and 3.3e-7 is the precision of ngspice's own printed output — i.e. exact agreement. The `.tran` residual is entirely the NILT's known wavefront-truncation behaviour, which is why it collapses from 5.2e-3 at the first sample to a flat 2.5e-4 past 1 µs. A future `.tran` regression that does *not* show that shape is a real bug, not transform error.

  **Do not calibrate diagnostics on that ladder.** It is tiny, per-unit and well scaled; a real winding is none of those. `Residual` originally tested ‖Ax−b‖/‖b‖ against 1e-9, which the ladder passed at 3.1e-16 and every production run failed at ~1e-8 — a false alarm, not a defect. `Assemble` writes a nonzero RHS **only at the impulsed nodes**, so ‖b‖ is exactly |U(s)|, which falls as 1/s² (~3e4 across a 10 MHz band); meanwhile nothing equilibrates the `s·C` node rows against the `s·M` segment rows. Dividing a residual bounded by ‖A‖‖x‖ by a collapsing ‖b‖ inflates it by `scaleRatio`. The test is now the **Rigal–Gaches normwise backward error** ‖Ax−b‖/(‖A‖‖x‖+‖b‖) against 1e-12, which is scale-invariant; `ResidualReport` carries all three numbers and `Sweep` logs them with the contour point and frequency that produced them. Note this measures neither conditioning (partial pivoting is backward stable — κ=1e14 still gives η≈ε) nor assembly correctness; only *Compare Solvers* tests the latter.

### Dielectric stress screening (`DielectricStress.swift`, `TurnLadderModel.swift`)

Turns a simulation result into **electric stress in V/m**, to locate the places in a design that need redesign or extra care in
manufacture. It is not a substitute for finite element, and it is explicit about that. Reached from *Simulate → Show Dielectric
Stress Report / Show Radial Stress Profiles / Turn Ladder for Selected Disc*.

**It needs no new physics, because the capacitance code already contains the field solution.** Every capacitance routine here is a
series-dielectric reduction; `Segment.DiscToDiscSeriesCapacitance` forms Σ(ℓ/ε) over the layers in a gap, and continuity of normal
**D** turns that straight into the field: `E_i = V/(ε_i·Σ(ℓⱼ/εⱼ))`. So the screen reuses the same geometry, and a full run is
milliseconds against hours for an FE solve per time step.

Two extractions exist purely so the stress and the capacitance can never disagree about what is in a gap — the same discipline
`FrequencyDomainSolver.CapacitiveDistribution` follows for the assembly. **`Segment.DiscToDiscLayerStack`** returns the layers in
physical order and `DiscToDiscSeriesCapacitance` builds its Σ(ℓ/ε) from it; **`Segment.SteinParameters`** holds α/Ya/Yb and
collapses what used to be three inline copies in `SeriesCapacitance`'s `.disc` branch. Both refactors were verified exactly
value-preserving (worst 3.5e-16 over 160 gap cases, 1.8e-16 over all 432 endDisc/staticRing combinations), and the three branches
are one formula because 12.63's `Cs·α/tanh α` **is** 12.53 at Ya = 1, Yb = 0.

| accuracy vs. FE | |
|---|---|
| average field across a laminar gap | **2–5%**; the reduction is analytically exact, the error is the finite disc width |
| peak field at a conductor corner | **20–30%, biased high** (conservative — do not "fix" it) |
| end regions with no static ring | genuinely 2-D; weakest case, flagged rather than valued |
| **ranking gaps worst-first** | **reliable** — this is what the feature is for |

**The allowables are DelVecchio chapter 13**, "Voltage Breakdown Theory and Practice", and they are **functions of distance, not
constants** — a single number would be wrong by a factor of two across the gaps in one coil. That distance dependence is also what
makes the screen match the book's own procedure for non-uniform fields (p.371): subdivide the path, average the field over each
subdivision, compare against the breakdown value *for that subdivision's length*. Each dielectric layer is one such subdivision.

All eight were **read off the printed page** (poppler is installed, so the Read tool renders PDF pages as images) rather than
decoded from the text layer — the equations are set in a subsetted math font with no `ToUnicode` CMap, so extracted text loses the
decimal points. Verify any change the same way; do not trust `pdftotext` for the formulas.

| | eq. | kV/mm, d in mm |
|---|---|---|
| oil, planar, impulse peak | 13.30 | 50·d^−0.36 |
| oil, planar, a.c. rms | 13.27 | 17.8·d^−0.36 |
| kraft, impulse peak (90 °C) | 13.4 | 79.43·d^−0.275 |
| kraft, a.c. rms | 13.5 | 32.8·d^−0.33 |
| pressboard, impulse peak (90 °C) | 13.8 | 91.2·d^−0.26 |
| pressboard, a.c. rms (90 °C) | 13.8 | 27.5·d^−0.26 |
| **creep**, a.c. rms, by distance | 13.16 | 16.6·d_c^−0.46 |
| **creep**, a.c. rms, by area | 13.15 | **16.0 − 1.09·ln A_c** |

**The screen is strike-only — the two creep rows are present but unused (2026-08-06).** The creep *allowables* are fine and
`VerifySelf` still pins all three; what was wrong was the *geometry* fed to them. A creep path was taken as the straight axial run
between the electrodes: the gap itself for a key spacer, and for a hilo barrier the **difference in the two coils' end heights**.
That last one is what removal was really about — it is not the hilo at all, so a design with a 19 mm hilo and coil ends a
millimetre apart got a 1 mm path carrying the full end-to-end voltage, judged at a 1 mm path's strength, and duly sorted to the top
of the table. A real creep path runs up one face of the barrier, **around its overhang past the coil end** and back down, longer
again where angle rings and caps are fitted at high voltage. None of that structure is in `PhaseModel`, so **bringing creep back
starts with the geometry, not with `DielectricStress.swift`** — see the long note above `StressAllowable.CreepPowerFrequency`. Until
then the summary line in `StressReportWindow` says "strike only" out loud, because "0 over allowable" otherwise reads as a clean
bill of health on a check that was never made.

Two traps in that table. **13.15 is logarithmic in area, not a power law** — 16.0 and 1.09 in a subtraction, not 16.0 and 0.09 in an
exponent; 13.9 (oil by volume) has the same shape, and both eventually go negative, which the book flags for 13.9 on p.370 and
which `CreepPowerFrequencyByArea` clamps. And **pressboard uses 13.8 (90 °C), not 13.7 (room temperature)** — 13.8 is the more
conservative of the two everywhere in range and keeps the temperature assumption consistent with the paper figures, where 13.4 is
also a 90 °C measurement whose 10% room-temperature bonus is deliberately declined. 13.7 remains available as
`PressboardImpulseRoomTemperature`.

Four distinctions in there must never be collapsed: **strike vs. creep** (different formulas and much steeper creep exponent — which
is why a short creep path carrying a large voltage so often governs, and why the missing creep check above is not a small gap);
**power frequency vs. impulse** (ratio ≈2.8 for oil, 2.7 for
paper, 3.0 for pressboard); **rms vs. peak** (the a.c. forms are rms, the impulse forms peak, and the simulation gives instantaneous
volts, so the impulse forms compare like with like); and **50% breakdown vs. design level** (p.368 — the book's data are the former,
so `StressAllowable.designMargin`, default 0.80 after the book's own Figure 13.5, brings it to the latter).

**`Segment.woundInShieldMaxWorkingStress` (2755 V/mm, 70 V/mil) must never be used here.** It is a *power-frequency working*
turn-to-turn stress for sizing wound-in-shield paper, not an impulse allowable. An earlier version of this file cited it as the
model for the allowables and shipped invented numbers alongside; both are gone.

**Only the average field carries a margin.** The corner column reports an *enhancement ratio*, not a percentage of an allowable,
because chapter 13's data are uniform-gap measurements judged against average fields — there is no sourced criterion for a corner
peak. That is precisely where the book says (p.16) "there is usually some judgment involved", and where an FE run earns its keep.
The one figure here that is an extrapolation rather than a citation is `creepImpulseRatio` (the book gives creep only at power
frequency); it is isolated as a named constant for that reason, and is on the unused creep path.

**The corner model is geometry, not a tabulated factor.** `CoaxialField` does double duty: at r ≈ 0.3 m it is the hilo, at
r = `cornerRadiusOnCopper` (0.81 mm, ≈ 1/32″, a documented editable constant) it *is* the corner. The paper follows the corner, so
the paper's field is read at the copper radius and the oil's at the paper's outer radius. Anchor to re-check after any edit: a 4 mm
duct with 0.4 mm paper per face gives **2.12×** over laminar.

Two physics points that decide right from wrong answers:

- **A continuous-disc gap sees twice the disc voltage and spans two node steps.** Disc A winds ID→OD, B winds OD→ID, joined at the
  OD; B's potential at radial position *x* is (2−x)V against A's xV, so ΔV is 2V(1−x) — zero at the crossover, **2V at the far
  end**, which alternates ID/OD gap by gap. Reading the adjacent diagonal of `MaximumInternodalVoltages` understates this by ~2×.
  The rule is applied only to plain continuous discs; interleaved and multi-disc Segments fall back to the single node step and the
  location string says so.
- **Max stress is not at max voltage.** Turn-to-turn peaks at t→0⁺ and ground stress peaks late, so every step is scanned and each
  site keeps its own worst instant. The t = 0+ capacitive distribution is prepended as an extra sample (from
  `FrequencyDomainSolver.CapacitiveDistribution`) because the uniform grid's first sample has already missed the steepest part.
  Because the field is linear in the driving voltage, the reduction runs once per site rather than once per site per step — exact,
  but it assumes time-invariant geometry.

**Turn-to-turn is screened by α and resolved by the ladder.** `SteinParameters.gradientEnhancement` returns
`1 + (α/tanh α − 1)·|Ya − Yb|`, an interpolation that is *exact* at both ends: an interior disc whose neighbours ramp in step with
it (Ya = Yb) is exactly linear — the case people get wrong by applying α/tanh α everywhere — and a one-sided disc (Ya = 1) is
exactly α/tanh α. `TurnLadderModel` then solves the real turn network for **one disc**, with the neighbours as boundary potentials
from the lumped model. It is one disc and not a group deliberately: with turns as free nodes and no capacitance between two discs
those discs disconnect, which is right for that network but at odds with the lumped model's series-through-Cs picture, and fixing it
needs the crossover conductor modelled. Continuous discs only — an interleaved winding's position-to-turn map is scheme-dependent
and guessing it would give a confidently wrong answer.

**Verification is by hand**, as everywhere else here. `DielectricStress.VerifySelf()` and `TurnLadderModel.VerifySelf()` write to
`UserDefaults` (the app is sandboxed, so `print` and `/tmp` are dead ends); each doc comment gives the `defaults read` line. Both
pass as of 2026-08-05. The ladder asserts its **convergence rate** rather than a bare threshold — the scheme is first order, since
the shunt lands only on interior turns, so doubling N must halve the departure from `sinh(αx)/sinh(α)`; measured ratio 2.0029. That
distinction matters: a discretisation error shrinks with N, an assembly error does not.

- **`SimulationModel.swift`** (`actor SimulationModel`) — built from a `PhaseModel`. Its `init` does the work that both solvers depend on: resolving jumpers into merged node groups, building the `vDropInd`/`iDropInd` incidence arrays, and applying the boundary-condition row surgery to the capacitance matrix. It owns `M` (Cholesky-factorized, for the RK45 path) and **`unfactoredM`** (the matrix itself, which the frequency-domain solver needs — reading `M` there would assemble the Cholesky factor as though it were the inductance). `Snapshot()` extracts a `Sendable` `NetworkSnapshot` so the frequency sweep can run with no actor hops in its inner loop.
  - `SolveFrequencyDomain(waveForm:displaySpan:maximumFrequency:progress:)` is the **live entry point**. Results come back on a **uniform** time grid.
  - `SimulateRK45` / `DifferentialFormula` remain as an **independent cross-check**, reached via *Simulate → Compare Solvers (Debug)*. Both solvers return an **empty array for cancellation as well as failure**, so callers must check `Task.isCancelled` to tell the two apart.

  **Why RK45 is kept.** The frequency-domain solver cannot detect its own assembly errors: a flipped incidence sign or mis-ordered row surgery yields a well-conditioned system that solves to machine precision and returns a smooth, plausible, wrong answer. RK45 reaches the answer by a completely different route while sharing the same matrices, so agreement is real evidence. `CompareSolvers` pins **both** to the same constant resistance via `NetworkSnapshot.resistanceFrequencyOverride` — otherwise they are solving different equations and a disagreement means nothing. Leave that override `nil` for production runs.

  `SimulateRK45`'s repaired step control: error is now checked on **both** V and I (`f6.dIdt` was always computed and discarded, so this was free), the step factor δ is clamped to [0.1, 4], and there is an `hMin` plus a consecutive-rejection cap so a non-converging run fails instead of looping forever. `DifferentialFormula` returns an **Optional** — the old `([], [])` error return was silently destructive, because the `zip`-based vector operators in that file *truncate* rather than trap, so an empty derivative quietly emptied V and I and surfaced several steps later as "Could not get max value!".
- **`PchMatrix`** — the matrix class wrapping Accelerate BLAS/LAPACK for `Double` and `Complex<Double>`, including sparse (coordinate-form) matrices. The live version is in **`PchMatrixPackage`**, not the uncompiled `Rabin2021/PchMatrix.swift` copy — change it in the package. Read the long header comment before touching it — it documents the `OpaquePointer`/`with...Pointer` idioms forced by Apple's LAPACK headers.

## App / UI layer

- **`AppDelegate.swift`** — standard NSApplication delegate (entry point).
- **`AppController.swift`** — the main controller: menu/IBActions, User Defaults, and file loading. Input comes from Excel transformer **design files** (`PchExcelDesignFilePackage`); `.cir` (`PCH_CIR_FILETYPE`) is **export only** — `doCreateCirFile` writes a SPICE netlist for external validation. It emits R+L series branches with the segment series capacitance in parallel, `K` cards for every mutual pair, shunt capacitances, an `EXP()` source that reproduces the full wave exactly, and both `.ac` and `.tran` cards. **Run `.ac` first** — the solver *is* a frequency-domain solve, so an AC sweep compares like with like and localises any mismatch to an assembly error; `.tran` afterwards checks only the inverse transform. **Export a small model (10–20 segments):** coupling is one `K` card per pair, so ~190 at 20 segments but ~20,000 at 200, where SPICE becomes numerically fragile as k → 1. Correctness is size-independent, and the large case is precisely what SPICE cannot do — which is why this program computes the inductance matrix itself. Use ngspice. Iteration constants like `PCH_RABIN2021_IterationCount = 200` live here. It also owns the two long-running calculations' UI:
  - **`recalculateModel(reinitialize:includeInductance:)` is the recalculation pipeline**, split out of `updateModel`'s tail: radial build-up → FE phase → eddy losses → inductance → capacitance → `updateViews()`. Anything that changes the model *without* swapping Segments calls it directly, because `updateModel` cannot be reached with empty segment arrays (`PhaseModel.UpdateConnectors` throws on those). It always calls `ApplyRadialBuildUp()` first — cheap, idempotent, and it means no caller has to reason about when geometry went stale. `includeInductance: false` recomputes only the capacitance, which is what a geometry search wants: the inductance dominates the cost and barely moves when a coil widens by millimetres.
  - The main window's two progress bars (`indCalcProgInd`, `simCalcProgInd`) are **determinate** and driven by the progress streams described under *Concurrency*. Set up at launch, reset in `didFinishInductanceCalculation()` / `didFinishSimulationRun()`. The bar's `toolTip` carries the detail text (which pass, which section) because `workingLabel` is *shared* by both calculations — don't write per-calculation text into it.
  - Both are cancellable via `runningInductanceTask` / `runningSimulationTask` and the **Cancel Inductance Calculation** (Inductance menu) and **Cancel Simulation** (Simulate menu, ⌘.) items, enabled by `validateMenuItem` only while the matching task is live. The inductance calculation is wrapped in its own `Task` inside `recalculateModel` purely to get a cancel handle — none of its callers retains a `Task`. A user cancellation is **not** an error: no alert, but `inductanceIsValid` is forced false (a previous successful run could otherwise leave it stale-true) and the view is still refreshed, since the segment edits that triggered the update have already been applied to the model.
- **`TransformerView.swift`** — the `NSView` that draws the winding cross-section (adapted from the author's earlier *AndersenFE_2020* project). All drawn dimensions are multiplied by the file-scope `dimensionMultiplier` (`1000`) because `NSView` misbehaves with sub-1 (meter-scale) coordinates. It also contains the **connector-routing subsystem**:
  - `@MainActor struct SegmentPath` wraps a `Segment` for drawing; `SegmentPath.SetUpConnectors(...)` builds a `ViewConnector` (path + optional ground/impulse image) for each of a segment's `Connection`s. It classifies each connection (adjacent same-coil, non-adjacent same-coil, coil-to-coil, or termination) and routes accordingly: connectors avoid crossing coils by running in the radial gaps and crossing over/under the winding, choosing over-vs-under by shortest total travel (`ConnectorCrossover`); overlapping runs are spread into parallel **lanes** (`ViewConnector.assignLane` + `ConnectorChannel`); connectors attach to the tip of an existing `floating` lead rather than drawing a new stub.
  - Routing **offsets are derived from the model geometry** by `UpdateConnectorMetrics()` (tightest hilo gap and winding height) so they scale with model size; lead-stub length instead tracks the **view scale** so it stays constant on screen.
  - `RebuildConnectors()` re-runs the whole pass; it is triggered by `segments` changes **and on zoom** (menu/button handlers + a `didEndLiveMagnify` observer) and coalesces concurrent requests. Incremental add/remove-connector paths call `SetUpConnectors` directly on the affected segment(s).
- **`AxisScale.swift`** — y-axis ticks and labels for the two result graphs. `AxisScale.Ticks(...)` returns the major ticks plus a highlighted tick at each extreme the simulation reached; `AxisScale.DrawYAxis(...)` draws them and `AxisScale.YAxisWidth(ticks:)` reports how wide a left margin they need. Major intervals are **25 kV up to a 250 kV crest and 100 kV above that** (`MajorVoltageInterval`), falling back to a computed 1-2-5 interval when the fixed one does not divide the axis — a single coil of a 550 kV unit only reaches ~50 kV, which would otherwise get no ticks at all. Extremes are rounded to the nearest kilovolt for a voltage and to two significant figures for a current (0.1 kA in the kiloamp range, 1 kA in the ten-kiloamp range).

  **Both graph views set their `bounds` to the data rectangle and let AppKit do the scaling**, which is why `DrawYAxis` takes a `pointSize`: everything drawn at a fixed on-screen size has to be multiplied by the view's bounds-to-frame ratio. That only works because the two views now build their bounds so the ratio is *the same in both directions* — the old code inflated the vertical margin by `scaleMultiplier.y` as well as by the scale, which made it anisotropic. If you change how the bounds are computed, keep `bounds.height == frame.height * scale`, or the tick labels come out stretched.

  **`AxisScale.DrawXEndLabels(...)` marks only the two ENDS of an x axis**, and is used by exactly one graph — the initial
  distribution, whose x axis is axial position and whose ends are "Top" and "Bottom". It is deliberately not a general x-tick
  generator: on an axis where the ends say everything, a millimetre scale is clutter. The labels are pushed to the outside of their
  own ends (a centred left label would hang over the y axis, the one place on the plot that already has ink) and are hung from the
  **bottom of the data rectangle**, not from the zero line the x axis is drawn on — the two coincide only while every value is
  positive, and a negative-polarity impulse would otherwise draw them down across the curve. A view that sets
  `CoilResultsDisplayView.xEndLabels` gets a taller bottom margin (`AxisScale.XEndLabelHeight`) automatically, the same way the left
  margin already grows to fit the y tick labels; leaving it `nil` is byte-identical to before.

  The data reaching both views is now in **volts or amps**, not pre-multiplied by the caller. Each view applies its own power-of-ten `yValueMultiplier` on the way into view coordinates (same "keep the numbers near 1000" trick as before), but it has to know the real values to label them. `AppController.doShowWaveforms` and `CoilResultsDisplayWindow` therefore pass `yQuantity` and `peakTestVoltage` and hand over raw results. Both views also rescale on `setFrameSize`, so a resized window redraws rather than stretching; `CoilResultsDisplayView.currentData` is a point array rather than a prebuilt `NSBezierPath` for the same reason.

- **`InitialDistributionWindow.swift`** — graphs the **capacitive (initial) distribution**, α, against axial position for the
  impulsed coil. *Simulate → Show Initial Voltage Distribution*. Three things about it are deliberate:
  - **It needs no simulation run**, only a simulation *model*. α is the s→∞ limit of the sweep's own assembly, so
    `FrequencyDomainSolver.CapacitiveDistribution` produces it in one extra solve — which is the point, since the steepness at the
    line end is what decides whether a winding needs interleaving or shields, and that is worth knowing *before* the expensive part.
    `validateMenuItem` therefore enables it on `currentSimModel != nil` alone, unlike every other item in that menu. A simulation
    result is used only if one is to hand, and only to scale the y axis from per-unit into volts (`peakVoltage`); with none, the
    axis is `.unitless` and the note says so.
  - **It reads the same α the stress report does**, rather than computing an initial distribution of its own — so this graph and the
    report's `0+ (initial)` rows cannot disagree.
  - **The x axis runs top-to-bottom, left-to-right**, which is why `Distribution.points` carries a *depth below the top of the coil*
    and not a height above the yoke. That is the textbook orientation and it puts the line end on the left in the usual case, but it
    is the **opposite** of `CoilResultsDisplayView`'s other two users, whose x is a height — hence the end labels, which exist so the
    two graphs cannot be confused. "Impulsed coil" means a coil with a node carrying an impulse connector; if there is more than one
    they all go in the picker. Coils that are not driven are left out on purpose — α there is a small shunt-capacitance residual that
    would flatten the driven curve into the floor of the plot.
- Dialogs / windows (`*.swift` + matching `*.xib`): `GetNumberDialog`, `GetSimDetailsDialog`, `ShowCoilResultsDialog`, `ShowWaveFormsDialog`, `CoilResultsDisplayView/Window`, `WaveFormDisplayView/Window`. `GetSimDetailsDialog` carries the **bandwidth** field (MHz, default 10, clamped 2–200 by `bandwidthInHz`) — the solver's only accuracy control, since there is no longer a step size or error tolerance to set. Those four dialogs subclass `PCH_DialogBox` from `PchDialogBoxPackage`. **`GetWoundInShieldDialog` is the exception**: no `.xib`, an `NSAlert` with an accessory `NSGridView` built in code. It has six read-only fields (insulation, stress, shield radial, build increase, C_s multiple) that all recompute as the user steps the shield count, and keeping that right in hand-maintained auto-layout is not worth it. It clamps `n` to `floor(N) − 1` and opens on `round(0.15·N)`. The progress-indicator window (`rb2021_progressIndicatorWindow` in `AppController`) is `PchProgressIndicatorPackage`'s class; `PCH_GraphingView/Window` and the `old...`-prefixed files are dead — see the target-membership table above.

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

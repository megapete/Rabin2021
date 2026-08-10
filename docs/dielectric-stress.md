# Dielectric stress screening (`DielectricStress.swift`, `TurnLadderModel.swift`)

Read this before touching the stress report, the stress profiles, the turn ladder, or any breakdown allowable.

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

## The allowables are DelVecchio chapter 13

"Voltage Breakdown Theory and Practice", and they are **functions of distance, not constants** — a single number would be wrong by
a factor of two across the gaps in one coil. That distance dependence is also what makes the screen match the book's own procedure
for non-uniform fields (p.371): subdivide the path, average the field over each subdivision, compare against the breakdown value
*for that subdivision's length*. Each dielectric layer is one such subdivision.

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
so `StressAllowable.designMargin` brings it to the latter; see the next section).

## The design margin is a preference, and the book barely supports a number

`StressAllowable.designMargin` is **`Preference.dielectricDesignMargin`, a user setting (⌘,) whose factory default is 0.65** — see
`docs/ui-layer.md` for the preferences mechanism. It is a preference because it is the one figure in this file that is a house rule
rather than a citation, and the book was re-checked on 2026-08-09 to see how much it actually says:

- **That a margin is needed: stated, unquantified.** p.368 — "Generally, the breakdown voltages are those for which the
  probability of breakdown is 50%. Thus, some margin below these levels would be needed in actual design."
- **The number 20%: one worked example.** p.382, the cylinder-to-ground-plane calculation, whose Figure 13.5 is captioned
  "Breakdown kV with a 20% margin". That is the only number in the chapter, it is a different geometry, and the disk–disk
  examples on the very next page (p.383: 30.0, 34.0, 40.0 kV/mm impulse) carry **no margin at all**.

So the old 0.80 was one figure's choice, not a recommendation, and an earlier version of this file overstated it by calling
Figure 13.5 its basis. For calibration: the author's long-standing empirical disc-to-disc formula — 43·(rs_t/0.11)^0.7 +
25·(cp_t/0.02)^0.75 kV, dimensions in inches — lands at **0.67–0.90 of this screen's allowable** across the practical range (ducts
2.5–12.7 mm, paper 0.25–2 mm total), an effective margin of roughly 0.6–0.8 on the book's 50% level, so 0.65 sits inside house
practice rather than beside it.

What the setting does and does not do is worth keeping straight: every allowable is multiplied by it, so **every utilization scales
as 1/margin**. It moves the pass/fail line and **cannot change the worst-first ranking**, which is what the screen is for. At 1.00
the report reads as a straight percentage of the book's 50%-breakdown level. `StressReportWindow`'s summary line prints the margin
in force, so a screenshot of a report is self-describing.

**`Segment.woundInShieldMaxWorkingStress` (2755 V/mm, 70 V/mil) must never be used here.** It is a *power-frequency working*
turn-to-turn stress for sizing wound-in-shield paper, not an impulse allowable. An earlier version of this file cited it as the
model for the allowables and shipped invented numbers alongside; both are gone.

**Only the average field carries a margin.** The corner column reports an *enhancement ratio*, not a percentage of an allowable,
because chapter 13's data are uniform-gap measurements judged against average fields — there is no sourced criterion for a corner
peak. That is precisely where the book says (p.16) "there is usually some judgment involved", and where an FE run earns its keep.
The one figure here that is an extrapolation rather than a citation is `creepImpulseRatio` (the book gives creep only at power
frequency); it is isolated as a named constant for that reason, and is on the unused creep path.

**The corner model is geometry, not a tabulated factor — but the radius it turns on *is* tabulated.** `CoaxialField` does double
duty: at r ≈ 0.3 m it is the hilo, at the strand's corner radius it *is* the corner. The paper follows the corner, so the paper's
field is read at the copper radius and the oil's at the paper's outer radius. Anchor to re-check after any edit: a 4 mm duct with
0.4 mm paper per face, at the 0.81 mm fallback radius, gives **2.12×** over laminar.

`DielectricStress.CornerRadius(thickness:width:)` reads the radius off **Essex *Magnet Wire / Winding Wire Engineering Data* p. 54**
("RECTANGULAR, BARE WIRE — DIMENSIONAL LIMITS"), which cites **ASTM B 48**, so it is the industry limit rather than one shop's
practice. The PDF is `~/Documents/MyProjects/Claude/EssexCornerRadius.pdf`. It takes the **bare strand's own two dimensions**
(`TurnData.strandRadial`/`strandAxial`) — not the turn, not the cable: a CTC presents each strand's corner to the gap. `StressSite`
and `StressCheck` both carry the radius that was used, and the report shows it as a tooltip on the two corner columns.

The table is genuinely two-dimensional and the spread is large — 0.81 mm for a 4 × 10 mm strand, 1.02 mm at 6 × 10 mm, 3.18 mm at
12 × 25 mm — a factor of four across sizes that all appear in ordinary disc coils, and the peak field goes as 1/√r. That is why one
constant would not do. Four things in the reading are easy to get wrong, and `VerifySelf` pins all of them:

- **Thickness is the smaller dimension**; the arguments are sorted, not trusted.
- Bands are **closed at the bottom, open at the top** ("Under 0.226 to 0.166 Incl." means 0.166 ≤ t < 0.226).
- **"Rounded Edge" is not a radius.** The page's own note — an edge with "corner radii that are essentially half the thickness of
  the wire" — is what those cells return.
- **The square-wire footnote overrides the table** and is applied first: square wire ≤ 0.072 in. (1.83 mm) gets 0.012 in. (0.30 mm).

The printed **mm** values are used for the radii (the page's inch and mm columns disagree slightly in two cells — 0.039 in. printed
as 1.02 mm, 0.031 in. as 0.81 mm) and exact **inch** conversions for the band boundaries. `defaultCornerRadiusOnCopper` (0.81 mm)
survives only as the fallback for a site with no strand data — a static ring, a radial shield, a design file with no cable
definition.

## A hilo is a stack of ducts, and lumping it is only legal for the capacitance (2026-08-09)

`PhaseModel.HiloLayerStack` returns the oil column **duct by duct** — `Npress` barriers of 0.080″ from the shop heuristic
`round(hilo/0.0084 − 0.5)`, with oil against *both* winding surfaces, so `Npress + 1` ducts share the remaining space. It used to
return one lumped board layer and one lumped oil layer, the way `CoilInnerShuntCapacitance` does. **That is exact for a capacitance
and wrong for a withstand**: a series reduction is Σ(ℓ/ε), which does not care how a material is subdivided, but
`StressAllowable.Strike` is a function of the layer's own thickness. On STME-0999 the 35.506 mm HV/LV hilo came back as a single
27.4 mm oil gap allowed 12.15 kV/mm where the five real 5.48 mm ducts earn 21.69, and **every coil-to-coil finding on that report
was manufactured by the lumping** — utilization 0.820 against a true 0.470, a factor of **1.75**. The 15.875 mm LV hilo is out by
1.29. Note the field barely moves (9.97 → 10.19 kV/mm, the innermost duct now sitting at a smaller radius); essentially the whole
error was the allowable. The **stick** column stays one solid `Pressboard(hilo)` layer deliberately — where a stick bridges the gap
the path is board the whole way across, barrier and stick alike, so its allowable belongs at the full thickness.
`AppendRadialSites` also now puts the **inner** coil's half-wrap on the front of the stack (and starts the stack half a wrap
further in, at that coil's copper), which `HiloLayerStack`'s doc comment had promised the caller would do and no caller did; it is
worth about 1%, and it is skipped when a radial shield stands in the gap.

## Two physics points that decide right from wrong answers

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

## Turn-to-turn is screened by α and resolved by the ladder

`SteinParameters.gradientEnhancement` returns `1 + (α/tanh α − 1)·|Ya − Yb|`, an interpolation that is *exact* at both ends: an
interior disc whose neighbours ramp in step with it (Ya = Yb) is exactly linear — the case people get wrong by applying α/tanh α
everywhere — and a one-sided disc (Ya = 1) is exactly α/tanh α. `TurnLadderModel` then solves the real turn network for **one
disc**, with the neighbours as boundary potentials from the lumped model. It is one disc and not a group deliberately: with turns
as free nodes and no capacitance between two discs those discs disconnect, which is right for that network but at odds with the
lumped model's series-through-Cs picture, and fixing it needs the crossover conductor modelled. Continuous discs only — an
interleaved winding's position-to-turn map is scheme-dependent and guessing it would give a confidently wrong answer.

**Verification is by hand**, as everywhere else here. `DielectricStress.VerifySelf()` and `TurnLadderModel.VerifySelf()` write to
`UserDefaults` (the app is sandboxed, so `print` and `/tmp` are dead ends); each doc comment gives the `defaults read` line. Both
pass as of 2026-08-05. The ladder asserts its **convergence rate** rather than a bare threshold — the scheme is first order, since
the shunt lands only on interior turns, so doubling N must halve the departure from `sinh(αx)/sinh(α)`; measured ratio 2.0029. That
distinction matters: a discretisation error shrinks with N, an assembly error does not.

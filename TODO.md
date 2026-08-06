# TODO

Known gaps and deviations, with enough context to pick any of them up cold. See `CLAUDE.md` for how the
surrounding code is organised.

## Capacitance

From the conformance audit against DelVecchio *Transformer Design Principles* ch. 12 and Kulkarni &
Khaparde *Transformer Engineering* ch. 7 (2026-08-02/03). Both PDFs are in `~/Documents/MyProjects/Claude/`.

Everything below is a **known** deviation. The audit found the disc path otherwise faithful: 12.47, 12.49,
12.50, 12.52, 12.53/12.54, 12.62 and 12.63 are all implemented correctly, and 12.52 reproduces the book's
own worked example exactly.

### 1. Two end static rings (DV 12.9) and a ring between the first two discs (DV 12.10)

`PhaseModel.CalculateCapacitanceMatrix` throws `.OnlyOneStaticRingAllowed` rather than handling either
configuration. This is **not** just a missing formula. 12.78-12.81 show the first two discs become
electrostatically coupled *through* the rings, producing a mutual C₁₃ that bypasses the intermediate node.
A scalar `Segment.seriesCapacitance` cannot represent that, so supporting it means adding an off-diagonal
term to the C matrix, not just a new branch in `SeriesCapacitance`.

### 2. Interleaved, wound-in-shield and multi-start windings

- Interleaved discs use **Veverka eq. 6.4** (`Cs = Ctt·(N−1)`, halved by the caller), not DelVecchio, who
  covers only wound-in-shields and multi-start in ch. 12. It also drops the (N−1)/N voltage-fraction
  argument that 12.48 applies to plain discs — see the comment in `BasicSectionSeriesCapacitance`.
  Note also that an interleaved unit is **two discs** but is still run through the ordinary `.disc`
  branch, whose Stein machinery assumes a single radial traverse. That over-counts the disc-disc energy
  by 2× at small α. The wound-in-shield path avoids this by using DelVecchio's linear-voltage form
  instead (see `Segment.WoundInShieldPairCapacitance`); the interleaved path has not been revisited.
- **Multi-start (DV 12.12)** — unimplemented. A `.multistart` BasicSection type exists and is produced by
  `AppController` from the design file, but `CapacitanceTurnToTurn` throws `.UnimplementedWdgType` for it.

### 2a. Wound-in shields — implemented, with two known gaps

DV 12.11 is now implemented (`Segment.WoundInShieldSeriesCapacitance` / `.WoundInShieldPairCapacitance`,
`PhaseModel.ApplyRadialBuildUp`, *Add wound-in shields…* in the Segments menu). Remaining gaps:

- **A shielded pair beside a static ring** keeps its (1/6)·Cdd term with `DiscToDiscSeriesCapacitance`'s
  static-ring solid term. DelVecchio has nothing for this combination; the treatment is a plausible
  extension, not something from the book.
- **Combine / split / interleave refuse to operate on shielded Segments** rather than carrying the
  shields across. They rebuild Segments from their BasicSections, which would drop the shield silently.
  Carrying it would mean re-slicing `turnsPerDisc` to the new grouping.

### 3. Hilo stick count is borrowed from the disc's key spacers

`PhaseModel.CoilInnerShuntCapacitance` sets `Ns = numAxialColumns` (the *disc's* key-spacer columns) and
hard-codes `ws = 0.75"`, where DV 12.61 wants the number and width of the **sticks in that hilo**. The
`Npress = round(hilo/0.0084 − 0.5)` barrier count is likewise a shop heuristic with no counterpart in the
book. `Segment.LayerToLayerCapacitance` makes the same substitution deliberately, for consistency.

### 4. Shunt capacitance is always split 50/50 onto the two end nodes

DV 12.71 gives `C₁ₐ = Cs·γa(α/tanh α − α/sinh α)`; 12.72 says only that this *approaches* Ca/2 for small α,
which is where the π model comes from. `PhaseModel.CalculateCapacitanceMatrix` applies the π split
unconditionally. Harmless while segments are one or two discs; the error grows if segments get long.

### 5. `EffectiveHeight`'s 75 mm rule

`PhaseModel.EffectiveHeight` drops any axial gap larger than 75 mm from the height used for the ground
capacitance. A house rule with no book counterpart, and the threshold is arbitrary (it is commented as
such).

### 6. Super Duper Shunt Capacitance Algorithm™

`PhaseModel.CalculateCapacitanceMatrix`, the `capLink` loop. Matches up mis-aligned node sets on two
adjacent coils and distributes the total inter-coil capacitance between them. Entirely original — neither
book gives a procedure for this. It does conserve the total by construction. **Parked deliberately**: PCH
wants to discuss the approach before anything is changed here.

## Dielectric stress screen

Added 2026-08-05 (`DielectricStress.swift`, `TurnLadderModel.swift`). See `CLAUDE.md` for the method and its accuracy. Known gaps:

### 7. Two open questions on the chapter 13 allowables

`DielectricStress.StressAllowable` now uses DelVecchio ch. 13 (see `CLAUDE.md` for the table and citations). Two things in it are
not straight from the book:

- **`creepImpulseRatio` (2.8)** — the book gives creep breakdown only at power frequency (13.15, 13.16). The impulse creep figure
  here is 13.16 scaled by the oil impulse ratio, on the grounds that creep along a pressboard surface in oil is an oil-adjacent
  process. It is isolated as a named constant so it can be replaced if a real impulse creep source turns up.
- **`designMargin` (0.80)** — ch. 13's data are 50%-breakdown levels (p.368 says explicitly that a margin is needed). 0.80 comes
  from the book's own Figure 13.5, which is drawn "with a 20% margin". This is the single number that decides how much of the
  breakdown level a design is allowed to use, and it is the first thing to review against house practice.

**All four creep allowables are now unused** — see item 12 below. `creepImpulseRatio` therefore no longer affects any reported
number, though it remains the thing to replace first if creep comes back.

All eight coefficients were verified against the printed page on 2026-08-05 and the self-check pins each one. Do not re-derive them
from `pdftotext`: the equations are set in a subsetted math font with no `ToUnicode` CMap, so the text layer drops decimal points
and cannot distinguish `16.0 − 1.09·ln A` from `16.0·A^−0.09`. That exact confusion produced a wrong 13.15 in the first version.
Render the page instead (poppler is installed; the Read tool does this).

### 8. The turn ladder covers one disc, and only continuous discs

`TurnLadderModel` solves a single disc with its neighbours as boundary potentials from the lumped model. Two extensions were looked
at and deliberately not done:

- **A group of discs** cannot be solved with turns as free nodes: absent a capacitance between two discs they become disconnected
  components, which is correct for that network but disagrees with the lumped model, where discs are in series through Cs. Doing it
  properly means modelling the crossover conductor explicitly.
- **Interleaved and wound-in-shield discs** are refused rather than guessed. The map from physical radial position to electrical
  turn is scheme-dependent, and a wrong map produces a confidently wrong number instead of an error.

### 9. `SteinParameters.gradientEnhancement` interpolates the intermediate case

It is exact at Ya = Yb (linear, an interior disc with equal gaps) and at Ya = 1, Yb = 0 (α/tanh α, a one-sided disc) and
interpolates on |Ya − Yb| between them. The exact general case needs the boundary-value problem solved for the Ya/Yb-weighted
environment potential. The turn ladder is the intended escape hatch when the exact answer matters.

### 10. Disc-to-disc uses the two-node span only for plain continuous discs

Interleaved Segments, and Segments holding more than one disc, fall back to the single node step across the gap (the location
string says which was used). The 2V crossover argument does not carry over unchanged to those winding orders. Gaps *inside* a
multi-disc Segment are driven at 2·ΔV_segment/n, which is the same argument applied to the Segment's own span.

### 11. Coil-end radial fields are flagged, not valued

Past the end of a shorter adjacent coil the field is genuinely two-dimensional. The screen holds the nearest inner potential, marks
the finding "beyond end of …, value indicative only", and the profile graph names the height. No Schwaiger-type end enhancement and
no oblique-spill estimate is attempted — both were considered and declined.

### 12. There is no creep check — the screen is strike-only

Creep sites were built until **2026-08-06** and were removed, because the model has no way to measure a creep path. The screen used
the straight axial run between the two electrodes, which for a hilo barrier meant the **difference in the two coils' end heights** —
not the hilo, and not a path anything creeps along. A design with a 19 mm hilo and coil ends 0.8 mm apart got a 0.8 mm path carrying
the full end-to-end voltage, judged against 13.16 at 0.8 mm, and sorted straight to the top of the report. The key-spacer and
tapping-gap sites used the gap itself, which is short for the same reason.

The allowables (13.15, 13.16, `creepImpulseRatio`) stay in `StressAllowable`, unused, and `VerifySelf` still pins them. What has to
come first is **geometry that is not in `PhaseModel` today**:

- a hilo barrier **extends past the coil ends**, so the path is up one face, around the overhang and back down the other;
- at high voltage that end carries **angle rings and caps**, which lengthen it further;
- a key spacer's path runs around the spacer, bounded by the disc faces clamping it.

Note also that some creep paths are better judged on **area** than length — a stick surface bridging a hilo, say — which is what
`CreepPowerFrequencyByArea` (13.15) was implemented for and why it is worth keeping.

Meanwhile the report's summary line says "strike only" explicitly, because a reader who sees "0 over allowable" will otherwise take
it as a clean bill of health on a check that was never made — and creep strength falls with distance far faster than strike strength
does, so a short creep path carrying a large voltage is exactly the case most likely to govern.

## Notes

- There is no test target, so numerical changes are verified by hand against the books' worked examples.
  `CLAUDE.md` records the one for `DiscToDiscSeriesCapacitance`.
- The frequency-domain solver's validation table (also in `CLAUDE.md`) uses a synthetic ladder and is
  unaffected by capacitance-model changes — but exported `.cir` netlists will change whenever these do.

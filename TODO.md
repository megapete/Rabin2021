# TODO

**Open** gaps and deviations, with enough context to pick any of them up cold. See `CLAUDE.md` for how the
surrounding code is organised, `docs/capacitance.md` and `docs/dielectric-stress.md` for the physics as it
stands, and **`docs/decisions.md` for investigations that are already settled** — several items below were
partly closed and keep only their outstanding half here.

Item numbers are stable and are cited from elsewhere in the repo; do not renumber them.

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

`AddStaticRing` refuses the configuration up front, so the user is told at the point of fitting the second
ring. Workaround for a single Segment carrying a whole coil: split it into at least 2 Segments, which puts
the two rings on different discs and out of 12.78-81's way. → `docs/decisions.md` §1 for how this used to
fail.

### 2. Interleaved and multi-start windings

- Interleaved discs use **Veverka eq. 6.4** (`Cs = Ctt·(N−1)`, halved by the caller), not DelVecchio, who
  covers only wound-in-shields and multi-start in ch. 12. It also drops the (N−1)/N voltage-fraction
  argument that 12.48 applies to plain discs — see the comment in `BasicSectionSeriesCapacitance`.
- **Multi-start (DV 12.12)** — unimplemented. A `.multistart` BasicSection type exists and is produced by
  `AppController` from the design file, but `CapacitanceTurnToTurn` throws `.UnimplementedWdgType` for it.

#### 2b. Cross-check against Kulkarni & Khaparde §7.3 — **closed 2026-08-06**

Nothing outstanding. The two books were shown to agree term for term, three deviations were found and all
three were applied, and the interleaved/shielded ranking now matches the texts at realistic shield
fractions (interleaving +47% on STME-0999 at n/N = 30%, +0.4% on STME-0999_2 at 47%). The full
cross-check, the measured tables and the shield-fraction analysis are in **`docs/decisions.md` §2b**.

### 2a. Wound-in shields — implemented, with two known gaps

DV 12.11 is implemented. Remaining gaps:

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

The barrier count now carries more weight than it did, because `PhaseModel.HiloLayerStack` builds the
stress stack duct by duct from it (`Npress` barriers, `Npress + 1` oil ducts, oil against both winding
surfaces) rather than lumping — and the oil allowable goes as `d^−0.36`, so one barrier more or fewer moves
the reported coil-to-coil utilization by several percent. The capacitance is unaffected either way (Σ(ℓ/ε)
is subdivision-independent). If the heuristic is ever replaced by a real barrier schedule, the stress
report is what will notice.

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

Added 2026-08-05 (`DielectricStress.swift`, `TurnLadderModel.swift`). See `docs/dielectric-stress.md` for the method and its
accuracy. Known gaps:

### 7. One open question on the chapter 13 allowables

`DielectricStress.StressAllowable` uses DelVecchio ch. 13 (see `docs/dielectric-stress.md` for the table and citations). One thing
in it is not straight from the book:

- **`creepImpulseRatio` (2.8)** — the book gives creep breakdown only at power frequency (13.15, 13.16). The impulse creep figure
  here is 13.16 scaled by the oil impulse ratio, on the grounds that creep along a pressboard surface in oil is an oil-adjacent
  process. It is isolated as a named constant so it can be replaced if a real impulse creep source turns up. All four creep
  allowables are currently unused (item 12), so this affects no reported number today.

**`designMargin` is settled (2026-08-09): it is a user preference, factory default 0.65.** It was 0.80 on the strength of the
book's Figure 13.5; re-reading ch. 13 showed that the only quantified margin in it is that one worked example in a different
geometry, and that the disk–disk examples on p.383 carry none. Since it is a house rule and not a citation, it became a setting —
see `docs/dielectric-stress.md` and `docs/ui-layer.md`.

All eight coefficients were verified against the printed page on 2026-08-05 and the self-check pins each one. Do not re-derive them
from `pdftotext`: the equations are set in a subsetted math font with no `ToUnicode` CMap, so the text layer drops decimal points
and cannot distinguish `16.0 − 1.09·ln A` from `16.0·A^−0.09`. That exact confusion produced a wrong 13.15 in the first version.
Render the page instead (poppler is installed; the Read tool does this).

### 8. The turn ladder covers one disc, and only continuous discs

`TurnLadderModel` solves a single disc with its neighbours as boundary potentials from the lumped model. Extending it to a group of
discs needs the crossover conductor modelled explicitly; interleaved and wound-in-shield discs are refused rather than guessed. Both
extensions were considered and declined — reasoning in `docs/decisions.md` §8.

### 9. `SteinParameters.gradientEnhancement` interpolates the intermediate case

It is exact at Ya = Yb (linear, an interior disc with equal gaps) and at Ya = 1, Yb = 0 (α/tanh α, a one-sided disc) and
interpolates on |Ya − Yb| between them. The exact general case needs the boundary-value problem solved for the Ya/Yb-weighted
environment potential. The turn ladder is the intended escape hatch when the exact answer matters.

### 10. Disc-to-disc uses the two-node span only for plain continuous discs

Interleaved Segments, and Segments holding more than one disc, fall back to the single node step across the gap (the location
string says which was used). The 2V crossover argument does not carry over unchanged to those winding orders. Gaps *inside* a
multi-disc Segment are driven at 2·ΔV_segment/n, which is the same argument applied to the Segment's own span.

### 11. Coil-end radial fields are flagged, not valued

Past the end of a shorter adjacent coil the field is genuinely two-dimensional. The screen holds the nearest inner potential and
marks the finding "value indicative only". No Schwaiger-type end enhancement and no oblique-spill estimate is attempted — both were
considered and declined (`docs/decisions.md` §11).

### 12. There is no creep check — the screen is strike-only

Creep sites were built and then removed on 2026-08-06 (`docs/decisions.md` §12), because the model has no way to measure a creep
path. The allowables (13.15, 13.16, `creepImpulseRatio`) stay in `StressAllowable`, unused, and `VerifySelf` still pins them.

What has to come first is **geometry that is not in `PhaseModel` today**:

- a hilo barrier **extends past the coil ends**, so the path is up one face, around the overhang and back down the other;
- at high voltage that end carries **angle rings and caps**, which lengthen it further;
- a key spacer's path runs around the spacer, bounded by the disc faces clamping it.

Note also that some creep paths are better judged on **area** than length — a stick surface bridging a hilo, say — which is what
`CreepPowerFrequencyByArea` (13.15) was implemented for and why it is worth keeping.

## Notes

- There is no test target, so numerical changes are verified by hand against the books' worked examples.
  `docs/capacitance.md` records the one for `DiscToDiscSeriesCapacitance`.
- The frequency-domain solver's validation table (`docs/solver.md`) uses a synthetic ladder and is
  unaffected by capacitance-model changes — but exported `.cir` netlists will change whenever these do.

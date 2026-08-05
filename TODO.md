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

## Notes

- There is no test target, so numerical changes are verified by hand against the books' worked examples.
  `CLAUDE.md` records the one for `DiscToDiscSeriesCapacitance`.
- The frequency-domain solver's validation table (also in `CLAUDE.md`) uses a synthetic ladder and is
  unaffected by capacitance-model changes — but exported `.cir` netlists will change whenever these do.

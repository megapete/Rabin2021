# Settled investigations

Questions that were opened, chased down and **closed**. They are kept because the reasoning is expensive to reconstruct and
because each one explains why the code looks the way it does — but none of them is outstanding work. Open items live in
`TODO.md`; the physics as it stands now is in `docs/capacitance.md` and `docs/dielectric-stress.md`.

Each entry names the `TODO.md` item it came from, so a reference to "§2b" still lands somewhere useful.

---

## §1 — the static-ring restriction was unreachable until 2026-08-08

The one-static-ring restriction (`.OnlyOneStaticRingAllowed`) is still an open limitation — see `TODO.md` §1. What is settled is
how it used to fail.

As of 2026-08-08 `AddStaticRing` refuses the configuration up front, so the user is told at the point of fitting the second ring
rather than at the next recalculation. Note that until the same date the restriction was **unreachable**: `SegmentAt` was searching
`CoilSegments()`, which filters shielding elements out, so `StaticRingAbove`/`StaticRingBelow` returned nil for every static ring in
every model and no ring reached the capacitance calculation at all. A single Segment carrying the whole coil with a ring at each end
is now also representable and now also throws — the error's own `info` string ("consider splitting it into at least 2 Segments") is
the workaround for that one, and it is a real one: two Segments put the two rings on different discs and out of 12.78-81's way.

---

## §2b — cross-check against Kulkarni & Khaparde §7.3 (2026-08-06), and the three fixes that came out of it

Done because a 5-turn floating shield came out *ahead* of full interleaving on a CTC coil, which the
literature says should not happen. **Neither series-capacitance formula is wrong**, and the two books
agree with each other exactly:

- **K&K 7.44/7.47/7.50 reduce, term for term, to DelVecchio's 12.96.** Kulkarni's shield energy
  `2k·½C_sh[(V/2)² + (V/2 − ΔV)²]` gives `k·C_sh[1 − 1/N_D + 1/(2N_D²)]`, which is exactly the coded
  bracket at β = 0, and his `2(N_D−k−1)` turn-to-turn pairs give exactly the coded
  `c_t(N−n−1)/(2N²)`. Two independent derivations, same answer.
- **K&K 7.40 `C_se = (C_T/2)(N_D − 1)` is literally the Veverka 6.4 the code uses** for interleaving.

So the surprise is not a coding error. At `C_sh = C_T` the break-even shield count against K&K's *exact*
7.39 is **k = 4.92 of N_D = 10.75 (46% of the turns)** — i.e. the 5-turn scenario sits within 2% of the
crossover, which is why it looked like a photo finish. Below that k interleaving wins, as the texts say.

Three real deviations came out of the comparison:

1. **The code uses K&K 7.40, the `N_D ≫ 1` approximation, where 7.39 is exact.** 7.39 is
   `(C_T/4)[N_D + ((N_D−1)/N_D)²(N_D−2)]`. The code is **8.6% high at N_D = 10.75** and 4.9% high at
   19.7 — worst exactly where CTC coils live. Cheap fix, one line in
   `BasicSectionSeriesCapacitance`.
2. **K&K says to drop the interdisk term entirely for an interleaved winding** (§7.3.5: "it is
   sufficient to consider only the interturn capacitances"). The code adds it through Stein, worth
   **24% of the interleaved total** on STME-0999_2. This compounds with a second objection standing at the
   time — an interleaved unit is *two discs* but was run through the ordinary `.disc` branch, whose Stein
   machinery assumes a single radial traverse, over-counting the disc-disc energy by 2× at small α, where
   the wound-in-shield path already avoided that by using DelVecchio's linear-voltage form (see
   `Segment.WoundInShieldPairCapacitance`). Both pointed the same way: the interleaved figure is too high.
3. **K&K says C_DU for a shielded pair must exclude the shield turns' radial depth** (p.317: "there is
   no contribution to the energy by the capacitances between the shield turns of the two disks at same
   radial depth, since their potentials are equal"). The code takes C_dd over the full built-up radial
   depth, so on STME-0999_2 the shielded pair's C_dd is **~17% high**. Note his "potentials are equal"
   is exact only for the first shield turn — 7.42 and 7.46 differ by 2(i−1)ΔV — so this is a good
   approximation rather than an identity.

**All three applied 2026-08-06.** My estimate above was wrong: I costed deviation 2 as *switching* the
interleaved pair to the shielded pair's linear-voltage form, but K&K's rule is to drop the interdisk term
outright, which is worth −30% on interleaving where the shield correction is only −1.2%. Measured:

| | N, k | interleaved | shielded | |
|---|---|---|---|---|
| STME-0999 | 19.7, 6 (30%) | 7.712e-9 | 5.517e-9 | interleaving **+40%** |
| STME-0999_2 | 10.75, 5 (47%) | 4.263e-9 | 4.988e-9 | shield **+17%** |

So the fixes restored the expected ranking at a realistic shield fraction and left it inverted at k ≈ N/2.

**The disc-disc asymmetry that this left has since been closed** (also 2026-08-06). Both two-disc units now
go through `Segment.TwoDiscPairCapacitance`, so the interleaved pair gets the same linear-voltage
`Cs + Cdd_int/3 + (Cdd_below + Cdd_above)/6` the shielded pair has always used. K&K's licence to drop the
interdisk term is that it is "relatively low", which is not true here — 16% of the interleaved total — and it
costs nothing to evaluate. The extraction was **exactly value-preserving on the shielded path**: 5.516902e-9
and 4.988040e-9 before and after, to the last digit. Final:

| | N, k | interleaved | shielded | |
|---|---|---|---|---|
| STME-0999 | 19.7, 6 (30%) | 8.138e-9 | 5.517e-9 | interleaving **+47%** |
| STME-0999_2 | 10.75, 5 (47%) | 5.006e-9 | 4.988e-9 | interleaving **+0.4%** |

Interleaving is ahead on both, by a margin that grows as the shield fraction falls — which is the behaviour
the texts describe.

**Shield fraction is what actually settles the question.** Turn terms only, at c_w ≈ c_t and N = 10.75:

| k | % of turns | shield | vs interleaved 4.487·c_t |
|---|---|---|---|
| 2 | 19% | 1.806·c_t | interleaving +149% |
| 3 | 28% | 2.708·c_t | interleaving +66% |
| 4 | 37% | 3.611·c_t | interleaving +24% |
| 5 | 47% | 4.514·c_t | dead heat |

Real designs shield far fewer than half the turns — enough to pass the test and no more, since every shield
turn costs radial build (3.454 mm each here). That is why "interleaving always beats wound-in shields" is
sound practical guidance without being a property of the equations.

**On connected shields beating interleaving:** they do, and it is measured, not just derived.
DelVecchio's Table 12.1 (two disks, 10 turns/disk) gives, at n = 5, 1.78 nF floating against 3.53 nF
attached at the crossover and 6.07 nF attached at the top end. So the ranking the model produces for the
connected options is backed by his experiment, however counterintuitive it looks.

---

## §2a — wound-in shields (DV 12.11) are implemented

DV 12.11 is implemented (`Segment.WoundInShieldSeriesCapacitance` / `.WoundInShieldPairCapacitance`,
`PhaseModel.ApplyRadialBuildUp`, *Add wound-in shields…* in the Segments menu). Two gaps remain open and are listed in `TODO.md`
§2a.

---

## §12 — creep sites were built and then removed (2026-08-06)

The decision to make the stress screen strike-only is settled; what is still open is the geometry work needed to bring creep back,
which is `TODO.md` §12.

Creep sites were built until 2026-08-06 and were removed, because the model has no way to measure a creep path. The screen used
the straight axial run between the two electrodes, which for a hilo barrier meant the **difference in the two coils' end heights** —
not the hilo, and not a path anything creeps along. A design with a 19 mm hilo and coil ends 0.8 mm apart got a 0.8 mm path carrying
the full end-to-end voltage, judged against 13.16 at 0.8 mm, and sorted straight to the top of the report. The key-spacer and
tapping-gap sites used the gap itself, which is short for the same reason.

Meanwhile the report's summary line says "strike only" explicitly, because a reader who sees "0 over allowable" will otherwise take
it as a clean bill of health on a check that was never made — and creep strength falls with distance far faster than strike strength
does, so a short creep path carrying a large voltage is exactly the case most likely to govern.

---

## §8 — two turn-ladder extensions were considered and declined

`TurnLadderModel` solves a single disc with its neighbours as boundary potentials from the lumped model. Two extensions were looked
at and deliberately not done:

- **A group of discs** cannot be solved with turns as free nodes: absent a capacitance between two discs they become disconnected
  components, which is correct for that network but disagrees with the lumped model, where discs are in series through Cs. Doing it
  properly means modelling the crossover conductor explicitly.
- **Interleaved and wound-in-shield discs** are refused rather than guessed. The map from physical radial position to electrical
  turn is scheme-dependent, and a wrong map produces a confidently wrong number instead of an error.

---

## §11 — coil-end radial fields are flagged, not valued

Past the end of a shorter adjacent coil the field is genuinely two-dimensional. The screen holds the nearest inner potential, marks
the finding "beyond end of …, value indicative only", and the profile graph names the height. No Schwaiger-type end enhancement and
no oblique-spill estimate is attempted — both were considered and declined.

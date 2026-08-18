# The solver: frequency domain, `SimulationModel`, and the RK45 cross-check

Read this before touching `FrequencyDomainSolver.swift`, `NumericalLaplaceTransform.swift`, `ConductorImpedance.swift`,
`SimulationModel.swift`, or the SPICE export.

**The transient is solved in the frequency domain**, not by time-marching. This is the live path, and it replaced the RK45
integrator (2026-08-01). Three files:

- **`ConductorImpedance.swift`** — R(ω) from Dowell's exact 1-D skin (`F_R`) and proximity (`G_R`) functions, each normalized by its own value at 60 Hz so the Excel design file's per-unit eddy data is reproduced exactly at 60 Hz. These *replace* DelVecchio 12.103/12.104 — but note the old expressions are precisely the **high-frequency asymptotes of this same normalized model** (the identity `2·ξ₆₀/G_R(ξ₆₀) = 6/ξ₆₀³` holds exactly), so above ~100 kHz the two agree to 1 part in 10⁴. Only the sub-crossover range changed, where the old form over-predicted eddy loss (6× at 1 kHz, 466× at 60 Hz) and could return R_ac < R_dc or NaN.
- **`NumericalLaplaceTransform.swift`** — damped-contour NILT (`s = σ + jmΔω`, σT = 5, record twice the displayed span). Knows nothing about transformers, so it is verified standalone against closed-form transforms. **Default window is `.none`**: the dominant error is a missing-tail bias, not Gibbs ringing, so a window makes it 2–10× worse.
- **`FrequencyDomainSolver.swift`** — assembles `[sC', −Ā; −B, sM+Z(s)]` and sweeps. **It subtracts the s→∞ asymptote before inverting** — `α = C'⁻¹E`, the classical capacitive initial distribution — because inverting `V(s)` directly converges only as 1/f_max (1.7e-2 at 10 MHz; ~2 GHz would be needed for 1e-4). The subtraction takes the spectrum from 1/s² to 1/s⁴ and is 15–40× more accurate at identical cost. Do not remove it.

Two consequences worth knowing: every frequency sees its **own** R, so there is no "fundamental frequency" estimate and no
two-pass scheme; and **bandwidth is a real accuracy control**, exposed in the simulation dialog, not a free parameter.

## Validation results

(Synthetic 5-node/4-segment ladder; re-run these if the assembly is ever touched.)

| check | result |
|---|---|
| solve residual ‖Ax−b‖/‖b‖ | 3.1e-16 |
| α at impulsed / grounded node | exactly 1.0 / 0.0 |
| vs. independent RK4 of the same ODEs | 2.4e-4 of peak |
| **vs. ngspice `.ac`**, 161 freqs, 1 kHz–10 MHz | **3.3e-7** |
| vs. ngspice `.tran`, t ≥ 1 µs | 2.5e-4 |
| vs. ngspice `.tran`, first sample (49 ns) | 5.2e-3 |

The `.ac` result is the important one: it isolates the **assembly** (signs, row surgery, block offsets) from the transform, and
3.3e-7 is the precision of ngspice's own printed output — i.e. exact agreement. The `.tran` residual is entirely the NILT's known
wavefront-truncation behaviour, which is why it collapses from 5.2e-3 at the first sample to a flat 2.5e-4 past 1 µs. A future
`.tran` regression that does *not* show that shape is a real bug, not transform error.

**Do not calibrate diagnostics on that ladder.** It is tiny, per-unit and well scaled; a real winding is none of those. `Residual`
originally tested ‖Ax−b‖/‖b‖ against 1e-9, which the ladder passed at 3.1e-16 and every production run failed at ~1e-8 — a false
alarm, not a defect. `Assemble` writes a nonzero RHS **only at the impulsed nodes**, so ‖b‖ is exactly |U(s)|, which falls as 1/s²
(~3e4 across a 10 MHz band); meanwhile nothing equilibrates the `s·C` node rows against the `s·M` segment rows. Dividing a residual
bounded by ‖A‖‖x‖ by a collapsing ‖b‖ inflates it by `scaleRatio`. The test is now the **Rigal–Gaches normwise backward error**
‖Ax−b‖/(‖A‖‖x‖+‖b‖) against 1e-12, which is scale-invariant; `ResidualReport` carries all three numbers and `Sweep` logs them with
the contour point and frequency that produced them. Note this measures neither conditioning (partial pivoting is backward stable —
κ=1e14 still gives η≈ε) nor assembly correctness; only *Compare Solvers* tests the latter.

## `SimulationModel.swift` (`actor SimulationModel`)

Built from a `PhaseModel`. Its `init` does the work that both solvers depend on: resolving jumpers into merged node groups,
building the `vDropInd`/`iDropInd` incidence arrays, and applying the boundary-condition row surgery to the capacitance matrix. It
owns `M` (Cholesky-factorized, for the RK45 path) and **`unfactoredM`** (the matrix itself, which the frequency-domain solver
needs — reading `M` there would assemble the Cholesky factor as though it were the inductance). `Snapshot()` extracts a `Sendable`
`NetworkSnapshot` so the frequency sweep can run with no actor hops in its inner loop.

**`PchMatrix` is an `actor`, therefore a reference type — `init` must COPY `model.C`, never assign it.** `PhaseModel.C` is the
basic, *unmodified* capacitance matrix, and the whole rebuild-every-run guarantee rests on it staying that way: each run
re-reads it and redoes the row surgery against the terminations and jumpers as they now stand. `baseC` and `modelC` were
assigned straight from `model.C!`, which handed both of them the PhaseModel's own matrix, so the surgery — `ZeroRow`, `AddRow`,
the 1/−1 pair tying a merged node to the one it was kept for — was written into the model. **Every Dirichlet row and every merge
then outlived the connector that asked for it.** Two leads jumpered for one run stayed shorted (their difference identically
zero) for the rest of the session after the jumper was deleted, and a correct answer for a new connection scheme was only
obtainable by making it the *first* scheme simulated after a recalculation — a rebuilt `C`. It corrupted the *Save C Matrix*
export the same way. Both are now `await PchMatrix(srcMatrix: model.C!)`, two separate deep copies: `baseC` is the pristine
network the `NetworkSnapshot`/SPICE export reads, `modelC` is the one operated on. `asSparseMatrix()` at the end of `init`
returns a *new* matrix, which is why only the first run of a session looked right.

- `SolveFrequencyDomain(waveForm:displaySpan:maximumFrequency:progress:)` is the **live entry point**. Results come back on a **uniform** time grid.
- `SimulateRK45` / `DifferentialFormula` remain as an **independent cross-check**, reached via *Simulate → Compare Solvers (Debug)*. Both solvers return an **empty array for cancellation as well as failure**, so callers must check `Task.isCancelled` to tell the two apart.

**Why RK45 is kept.** The frequency-domain solver cannot detect its own assembly errors: a flipped incidence sign or mis-ordered
row surgery yields a well-conditioned system that solves to machine precision and returns a smooth, plausible, wrong answer. RK45
reaches the answer by a completely different route while sharing the same matrices, so agreement is real evidence.
`CompareSolvers` pins **both** to the same constant resistance via `NetworkSnapshot.resistanceFrequencyOverride` — otherwise they
are solving different equations and a disagreement means nothing. Leave that override `nil` for production runs.

`SimulateRK45`'s repaired step control: error is now checked on **both** V and I (`f6.dIdt` was always computed and discarded, so
this was free), the step factor δ is clamped to [0.1, 4], and there is an `hMin` plus a consecutive-rejection cap so a
non-converging run fails instead of looping forever. `DifferentialFormula` returns an **Optional** — the old `([], [])` error
return was silently destructive, because the `zip`-based vector operators in that file *truncate* rather than trap, so an empty
derivative quietly emptied V and I and surfaced several steps later as "Could not get max value!".

## The inductance matrix

The active path computes the inductance matrix by finite element, in `PchAxiSymFE`, driven through the app's own `FePhase`
actor (`Rabin2021/FePhase.swift`) — `FePhase.CalculateInductanceMatrix(progress:)`. Read that file's header before changing the
FE model; the two things in it that are not free choices are recorded there:

- **One terminal per Segment.** The package builds its flux-linkage matrix per *terminal* (`Λ_ts = b_tᵀ x_s`, one solve per
  terminal against one factorization). Giving every Segment its own terminal number — equal to its index in `CoilSegments()` —
  is what turns that into the segment-to-segment self- and mutual-inductance matrix this program runs on. It also means the real
  excitation is expressible in the same model, so the eddy-loss solve and the inductance sweep share one mesh and one
  factorization.
- **The tank is a flux line, the core and yokes are flux-normal.** Rabin's arrangement. Every column of an inductance matrix
  excites one section alone, which is net-ampere-turn *unbalanced*; a model with every boundary flux-normal (Andersen's
  arrangement, correct for a balanced leakage run) is pure Neumann and has no solution for it — the package rejects such an
  excitation rather than let its gauge node absorb the imbalance.

Checked end to end on STME-0999: the leakage inductance the matrix implies at balanced ampere-turns is 0.2295 H referred to the
HV, against 0.2358 H from the classical concentric-winding formula with a 0.95 Rogowski factor — 2.7% below it, which is where a
2D FE answer belongs. Refining the mesh (16k → 64k nodes) moves that by 0.005% and the worst individual self-inductance by 0.08%,
so the sizing in `FePhase` is not the limiting error.

**`EslamianVahidiModel.swift`** (`EslamianVahidiSegment`) is an **alternative inductance-matrix implementation that is not compiled
into the app** using the double-Fourier-series method from the Eslamian & Vahidi paper ("New Methods for Computation of the
Inductance Matrix of Transformer Windings for Very Fast Transients Studies"), covering both inside- and outside-the-core-window
cases. It is kept for reference/comparison only.

## `PchMatrix`

The matrix class wrapping Accelerate BLAS/LAPACK for `Double` and `Complex<Double>`, including sparse (coordinate-form) matrices.
The live version is in **`PchMatrixPackage`**, not the uncompiled `Rabin2021/PchMatrix.swift` copy — change it in the package. Read
the long header comment before touching it — it documents the `OpaquePointer`/`with...Pointer` idioms forced by Apple's LAPACK
headers.

## The SPICE export

`.cir` (`PCH_CIR_FILETYPE`) is **export only** — `AppController.doCreateCirFile` writes a SPICE netlist for external validation. It
emits R+L series branches with the segment series capacitance in parallel, `K` cards for every mutual pair, shunt capacitances, an
`EXP()` source that reproduces the full wave exactly, and both `.ac` and `.tran` cards. **Run `.ac` first** — the solver *is* a
frequency-domain solve, so an AC sweep compares like with like and localises any mismatch to an assembly error; `.tran` afterwards
checks only the inverse transform. **Export a small model (10–20 segments):** coupling is one `K` card per pair, so ~190 at 20
segments but ~20,000 at 200, where SPICE becomes numerically fragile as k → 1. Correctness is size-independent, and the large case
is precisely what SPICE cannot do — which is why this program computes the inductance matrix itself. Use ngspice.

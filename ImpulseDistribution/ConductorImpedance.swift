//
//  ConductorImpedance.swift
//  ImpulseDistribution
//
//  Created by Claude on 2026-08-01.
//
//  ===========================================================================
//  WHAT THIS FILE IMPLEMENTS
//  ===========================================================================
//
//  The frequency dependence of a winding segment's series resistance, R(f).
//
//  Two physical effects raise a conductor's effective resistance as frequency
//  rises:
//
//    1. SKIN EFFECT - the conductor's own current is pushed towards its
//       surface, so less copper carries it.
//
//    2. EDDY (PROXIMITY) LOSS - the leakage field from *other* conductors
//       drives circulating currents inside this strand.
//
//  Both are computed here from Dowell's closed-form one-dimensional solution
//  of the diffusion equation in a conductor:
//
//      P.L. Dowell, "Effects of eddy currents in transformer windings",
//      Proc. IEE, Vol. 113, No. 8, August 1966, pp. 1387-1394.
//
//  ---------------------------------------------------------------------------
//  DEPARTURE FROM DelVecchio - READ THIS BEFORE COMPARING RESULTS
//  ---------------------------------------------------------------------------
//
//  The previous implementation (SimulationModel.Resistance.EffectiveResistanceAt,
//  from DelVecchio 3E eqs. 12.103 & 12.104) used the HIGH-FREQUENCY ASYMPTOTES
//  of these same two effects. Both of its terms scale as sqrt(f). That is
//  correct when the strand is much thicker than the skin depth, and wrong
//  below that crossover, where:
//
//      - the skin term returns R_ac < R_dc, which is not physically possible;
//      - the eddy term returns sqrt(f), where the true low-frequency
//        behaviour is f^2 (eddy loss vanishes quadratically, not as a root).
//
//  Dowell's functions are exact at ALL frequencies for the 1-D geometry and
//  reduce to exactly those sqrt(f) asymptotes at high frequency (see the
//  limit comments on each function below). So high-frequency behaviour is
//  unchanged and comparable with DelVecchio; only the low- and mid-frequency
//  range is corrected.
//
//  Dowell's derivation is for a rectangular foil/layer. Applying it to a
//  rectangular transformer strand, using the strand dimension transverse to
//  the driving field, is the standard engineering adaptation - it is not
//  rigorous for a finite-width strand, but it has the correct limits at both
//  ends and a smooth, monotonic transition between them, which the asymptotic
//  form does not.
//
//  ---------------------------------------------------------------------------
//  SYMBOL GLOSSARY
//  ---------------------------------------------------------------------------
//
//    f        frequency                                            [Hz]
//    rho      resistivity of the conductor material                [ohm-m]
//    mu       magnetic permeability of the conductor               [H/m]
//    delta    skin depth, sqrt(rho / (pi * f * mu))                [m]
//    b        conductor dimension transverse to the driving field  [m]
//    xi       normalized thickness, b / delta                      [dimensionless]
//    F_R(xi)  Dowell skin-effect resistance factor                 [dimensionless]
//    G_R(xi)  Dowell proximity/eddy resistance factor              [dimensionless]
//    R_dc     DC resistance of the segment                         [ohm]
//
//  NOTE ON xi: some texts define the normalized thickness as b/(2*delta) and
//  carry a factor of 2 inside the hyperbolic arguments. That is the SAME
//  function re-parameterized. This file uses xi = b/delta throughout, which is
//  Dowell's own convention. Do not mix the two.
//
//  ===========================================================================

import Foundation
import PchBasePackage

/// Frequency-dependent conductor resistance factors (Dowell 1-D).
///
/// Pure math - no state, no actor isolation needed.
enum ConductorImpedance {

    // MARK: - Branch thresholds
    //
    // Each factor is evaluated by one of three branches. The thresholds below
    // were chosen by comparing every branch against a 60-decimal-digit
    // reference implementation; the value quoted with each is the worst-case
    // relative error anywhere in that branch's range.
    //
    // The low thresholds exist because the direct forms contain a subtractive
    // cancellation:
    //
    //      cosh(xi) - cos(xi)  ->  xi^2       as xi -> 0
    //      sinh(xi) - sin(xi)  ->  xi^3 / 3   as xi -> 0
    //
    // Both differences are formed from quantities of order 1 (or of order xi),
    // so as xi shrinks the result is the small difference of two nearly equal
    // numbers and significant digits are lost. The proximity factor loses them
    // faster (xi^3 vs xi^2), which is why its threshold is lower.
    //
    // Above the thresholds the direct form is the MORE accurate of the two -
    // the series is only a rescue at small xi, not a general-purpose fast path.

    /// Below this, use the series form of `DowellSkinFactor`. Worst-case
    /// relative error: 2.2e-16 (series side), 1.5e-14 (direct side).
    static let skinSeriesLimit = 0.2

    /// Below this, use the series form of `DowellProximityFactor`. Worst-case
    /// relative error: 2.0e-16 (series side), 2.0e-15 (direct side).
    static let proximitySeriesLimit = 0.1

    /// Above this, both factors are replaced by their high-frequency
    /// asymptotes.
    ///
    /// Two reasons, and the second is the one that actually forces the value:
    ///
    ///   1. Accuracy: the correction to the asymptote decays as exp(-xi), NOT
    ///      exp(-2*xi). At xi = 40 the correction is ~1.2e-17, below Double's
    ///      epsilon, so the asymptote is exact to machine precision. (At
    ///      xi = 20 it is still ~6e-9, which is why the threshold is not
    ///      lower than this.)
    ///
    ///   2. Overflow: the direct forms evaluate sinh/cosh, which overflow a
    ///      Double at xi ~ 710. A 2 mm strand at 1 GHz gives xi ~ 957. This
    ///      branch keeps the functions total over the whole positive axis.
    static let asymptoticLimit = 40.0

    // MARK: - Skin depth

    /// Skin depth at a given frequency.
    ///
    ///     delta = sqrt( rho / (pi * f * mu) )        [m]
    ///
    /// Derived from the usual definition delta = sqrt(2*rho / (omega*mu)) by
    /// substituting omega = 2*pi*f; the 2's cancel.
    ///
    /// Sanity anchors, copper at 20 C (rho = 1.7241e-8 ohm-m):
    ///     60 Hz    -> 8.532 mm
    ///     10 MHz   -> 20.90 um
    ///
    /// - parameter frequency: Frequency in Hz. Must be > 0.
    /// - parameter resistivity: Conductor resistivity in ohm-m.
    /// - parameter permeability: Conductor permeability in H/m. Copper is
    ///   non-magnetic, so this is mu0.
    /// - returns: Skin depth in metres, or `Double.infinity` at f <= 0 (which
    ///   drives xi -> 0 and every factor to its DC limit - the physically
    ///   correct degenerate answer rather than a NaN).
    static func SkinDepth(frequency:Double, resistivity:Double = rhoCopper, permeability:Double = µ0) -> Double {

        guard frequency > 0, resistivity > 0, permeability > 0 else {

            return Double.infinity
        }

        return (resistivity / (π * frequency * permeability)).squareRoot()
    }

    /// Normalized conductor thickness, xi = b / delta.
    ///
    /// - parameter thickness: Conductor dimension transverse to the driving
    ///   field, in metres.
    /// - parameter frequency: Frequency in Hz.
    /// - returns: xi, dimensionless. Zero for a non-positive thickness, which
    ///   sends the skin factor to 1 and the eddy factor to 0.
    static func NormalizedThickness(thickness:Double, frequency:Double, resistivity:Double = rhoCopper, permeability:Double = µ0) -> Double {

        guard thickness > 0 else {

            return 0.0
        }

        let delta = SkinDepth(frequency: frequency, resistivity: resistivity, permeability: permeability)

        // delta is +infinity at f <= 0, so this correctly yields xi = 0.
        return thickness / delta
    }

    // MARK: - Dowell skin-effect factor

    /// Dowell's skin-effect resistance factor.
    ///
    ///                 xi     sinh(xi) + sin(xi)
    ///     F_R(xi) =  ---- * --------------------
    ///                  2     cosh(xi) - cos(xi)
    ///
    /// LIMITS (both verified numerically against a 60-digit reference):
    ///
    ///     xi -> 0    F_R -> 1                 R_ac = R_dc. The conductor is
    ///                                         thin compared to the skin depth
    ///                                         and the current is uniform.
    ///
    ///     xi -> inf  F_R -> xi/2 = b/(2*delta)
    ///                                         This is EXACTLY the old
    ///                                         DelVecchio Joule factor
    ///                                         (effRadius/2)*sqrt(pi*mu0*f/rho),
    ///                                         since 1/delta = sqrt(pi*mu0*f/rho).
    ///                                         Hence the sqrt(f) growth is
    ///                                         preserved at high frequency.
    ///
    /// F_R is monotonically increasing and never less than 1, so R_ac < R_dc
    /// is structurally impossible - the failure mode of the old code cannot
    /// occur here regardless of what frequency is passed in.
    ///
    /// - parameter xi: Normalized thickness b/delta. Must be >= 0.
    /// - returns: R_ac/R_dc due to skin effect alone. Always >= 1.
    static func DowellSkinFactor(_ xi:Double) -> Double {

        guard xi > 0, xi.isFinite else {

            // xi = 0 (DC, or zero thickness) -> uniform current -> R_ac = R_dc.
            // A non-finite xi means the caller has a broken geometry; the DC
            // limit is the safe answer and the caller's own guards will have
            // logged it.
            return 1.0
        }

        if xi >= asymptoticLimit {

            return skinAsymptote(xi)
        }

        if xi < skinSeriesLimit {

            return skinSeries(xi)
        }

        return skinDirect(xi)
    }

    /// Maclaurin branch of `DowellSkinFactor`, for small xi.
    ///
    /// Derived by expanding numerator and denominator separately and dividing
    /// the two series:
    ///
    ///     (xi/2)*(sinh + sin) = xi^2 * (1 + xi^4/120 + xi^8/362880  + ...)
    ///     (cosh - cos)        = xi^2 * (1 + xi^4/360 + xi^8/1814400 + ...)
    ///
    /// The leading xi^2 cancels *analytically* - which is exactly the
    /// cancellation the direct form suffers *numerically*, and the whole
    /// reason this branch exists. Dividing the bracketed series gives
    ///
    ///     F_R = 1 + xi^4/180 - xi^8/75600 + O(xi^12)
    ///
    /// At the threshold xi = 0.2 the xi^8 term contributes 1.3e-11 relative
    /// and the first omitted term is far below Double eps.
    private static func skinSeries(_ xi:Double) -> Double {

        let x4 = xi * xi * xi * xi

        return 1.0 + x4 / 180.0 - (x4 * x4) / 75600.0
    }

    /// Direct evaluation of `DowellSkinFactor`.
    ///
    /// Only safe in the middle band: xi < 40 keeps cosh(xi) below 1.2e17 (no
    /// overflow), and xi >= 0.2 keeps the `cosh - cos` cancellation to under
    /// two decimal digits.
    private static func skinDirect(_ xi:Double) -> Double {

        return (xi / 2.0) * (sinh(xi) + sin(xi)) / (cosh(xi) - cos(xi))
    }

    /// High-frequency branch of `DowellSkinFactor`. See `asymptoticLimit` for
    /// why the threshold is where it is.
    private static func skinAsymptote(_ xi:Double) -> Double {

        return xi / 2.0
    }

    // MARK: - Dowell proximity / eddy factor

    /// Dowell's proximity-effect (eddy) resistance factor.
    ///
    ///     G_R(xi) = 2*xi * ( sinh(xi) - sin(xi) ) / ( cosh(xi) + cos(xi) )
    ///
    /// LIMITS (both verified numerically against a 60-digit reference):
    ///
    ///     xi -> 0    G_R -> xi^4 / 3
    ///                                         Since xi is proportional to
    ///                                         sqrt(f), xi^4 is proportional
    ///                                         to f^2 - the textbook
    ///                                         low-frequency eddy loss law,
    ///                                         which the old sqrt(f) form got
    ///                                         wrong.
    ///
    ///     xi -> inf  G_R -> 2*xi              Proportional to sqrt(f), the
    ///                                         same high-frequency growth the
    ///                                         old code had.
    ///
    /// IMPORTANT - WHY THE ABSOLUTE SCALE OF THIS FUNCTION DOES NOT MATTER:
    /// callers use G_R only as the RATIO G_R(xi(f)) / G_R(xi(60 Hz)) (see
    /// `EddyFactorRatio`). Any constant prefactor cancels identically in that
    /// ratio. So the various conventions in the literature for where to put
    /// the 2, the 3, or the (m^2-1) layer term cannot introduce an error here
    /// - only the SHAPE of the function matters. This removes a whole class of
    /// convention mistakes, and it is why no attempt is made to match Dowell's
    /// absolute multi-layer normalization.
    ///
    /// - parameter xi: Normalized thickness b/delta. Must be >= 0.
    /// - returns: Eddy loss shape function. Always >= 0, monotonic increasing.
    static func DowellProximityFactor(_ xi:Double) -> Double {

        guard xi > 0, xi.isFinite else {

            // No thickness or no frequency means no eddy current.
            return 0.0
        }

        if xi >= asymptoticLimit {

            return proximityAsymptote(xi)
        }

        if xi < proximitySeriesLimit {

            return proximitySeries(xi)
        }

        return proximityDirect(xi)
    }

    /// Maclaurin branch of `DowellProximityFactor`, for small xi.
    ///
    ///     sinh - sin = xi^3/3 * (1 + xi^4/840 + xi^8/6652800 + ...)
    ///     cosh + cos = 2      * (1 + xi^4/24  + xi^8/40320   + ...)
    ///
    /// so, with u = xi^4,
    ///
    ///     G_R = (u/3) * (1 - 17*u/420 + 691*u^2/415800 + O(u^3))
    ///
    /// Three terms are needed here, not two: at the threshold xi = 0.1 the
    /// two-term form is only good to 1.7e-11, while three terms reach 2.0e-16.
    /// The extra term costs one multiply and one add.
    private static func proximitySeries(_ xi:Double) -> Double {

        let u = xi * xi * xi * xi

        return (u / 3.0) * (1.0 - 17.0 * u / 420.0 + 691.0 * u * u / 415800.0)
    }

    /// Direct evaluation of `DowellProximityFactor`. Safe in the middle band
    /// for the same reasons as `skinDirect`.
    private static func proximityDirect(_ xi:Double) -> Double {

        return 2.0 * xi * (sinh(xi) - sin(xi)) / (cosh(xi) + cos(xi))
    }

    /// High-frequency branch of `DowellProximityFactor`.
    private static func proximityAsymptote(_ xi:Double) -> Double {

        return 2.0 * xi
    }

    // MARK: - Frequency-scaling ratios
    //
    // These are what the simulation actually calls. Both are normalized to a
    // reference frequency (60 Hz), for a reason worth spelling out:
    //
    // The Excel design file supplies eddy losses as PER-UNIT VALUES AT 60 Hz
    // (Segment.eddyLossRadialPU / eddyLossAxialPU), and the DC resistance at
    // 60 Hz. Normalizing each shape function by its own value at 60 Hz means
    // that at f = 60 Hz the model reproduces the design-file numbers EXACTLY:
    //
    //     R(60) = R_dc * (1 + eddyPURadial + eddyPUAxial)
    //
    // which is the definition of those per-unit values. Every other frequency
    // is then scaled from that anchor by the shape of Dowell's functions. No
    // absolute magnitude calibration is required anywhere, and no unit
    // conversion can silently go wrong, because the only thing carried across
    // frequencies is a dimensionless ratio.
    //
    // RELATIONSHIP TO THE OLD DelVecchio EDDY EXPRESSION
    //
    // The old expression is not mis-scaled - it is EXACTLY the high-frequency
    // asymptote of the very same normalized model implemented here. Rewriting
    // it in terms of skin depth gives
    //
    //      6 * (f/60)^2 * (delta/b)^3   ==   (6 / xi60^3) * sqrt(f/60)
    //
    // and the ratio implemented here, in the xi >> 1 limit, gives
    //
    //      G_R(xi) / G_R(xi60)  ->  2*xi / (xi60^4 / 3)  =  (6 / xi60^3) * sqrt(f/60)
    //
    // because G_R(xi60) = xi60^4/3 for the small xi60 of a real strand at
    // 60 Hz. The two are identical. Verified numerically: for a 2 mm strand
    // they agree to 1 part in 10^4 for every frequency above ~100 kHz.
    //
    // So this change does NOT move high-frequency results. What it changes is
    // the range below the crossover (xi ~ 1, about 1 kHz for a 2 mm strand),
    // where the old form keeps returning its sqrt(f) asymptote and therefore
    // over-predicts eddy loss badly - by 6x at 1 kHz and by 466x at 60 Hz.
    // The old code was correct where it was used and simply had no valid
    // low-frequency limit; that is the defect being repaired, not a
    // calibration error.
    //
    // (The commented-out line in the original EffectiveResistanceAt, which
    // divided by dc*(1 + eddyPUAxial + eddyPURadial), shows this same 60 Hz
    // normalization was the original intent.)

    /// Reference frequency at which the design-file resistance and per-unit
    /// eddy losses are defined.
    static let referenceFrequency = 60.0

    /// Skin-effect resistance ratio between an arbitrary frequency and the
    /// 60 Hz reference:  F_R(xi(f)) / F_R(xi(60)).
    ///
    /// At f = 60 this returns exactly 1.0, so R(60) = R_dc as the design file
    /// intends.
    ///
    /// - parameter thickness: Conductor dimension for skin effect - the
    ///   effective strand radius, in metres.
    /// - parameter frequency: Frequency of interest in Hz.
    static func SkinFactorRatio(thickness:Double, frequency:Double) -> Double {

        guard thickness > 0 else {

            return 1.0
        }

        let atF = DowellSkinFactor(NormalizedThickness(thickness: thickness, frequency: frequency))
        let atRef = DowellSkinFactor(NormalizedThickness(thickness: thickness, frequency: referenceFrequency))

        // F_R >= 1 always, so atRef can never be zero and this cannot divide
        // by zero.
        return atF / atRef
    }

    /// Eddy (proximity) resistance ratio between an arbitrary frequency and
    /// the 60 Hz reference:  G_R(xi(f)) / G_R(xi(60)).
    ///
    /// At f = 60 this returns exactly 1.0, so the design file's per-unit eddy
    /// loss is reproduced unchanged at the reference frequency.
    ///
    /// - parameter thickness: Strand dimension transverse to the field
    ///   driving this eddy component, in metres.
    /// - parameter frequency: Frequency of interest in Hz.
    /// - returns: The scaling ratio, or 0 if the geometry is degenerate.
    static func EddyFactorRatio(thickness:Double, frequency:Double) -> Double {

        guard thickness > 0 else {

            // A zero or missing strand dimension means we have no basis to
            // scale the eddy loss. Returning 0 drops the term rather than
            // producing the infinity the old code's division by b^3 would.
            return 0.0
        }

        let atRef = DowellProximityFactor(NormalizedThickness(thickness: thickness, frequency: referenceFrequency))

        guard atRef > 0 else {

            return 0.0
        }

        return DowellProximityFactor(NormalizedThickness(thickness: thickness, frequency: frequency)) / atRef
    }

    // MARK: - Self-check
    //
    // Left in the code deliberately, per the project's documentation policy:
    // these are the invariants that make the functions above trustworthy, and
    // deleting them once they pass would remove the only evidence that they
    // ever did.

    /// Verifies the mathematical invariants of the Dowell factors.
    ///
    /// A failure means one of the following has broken:
    ///   - a series coefficient has been mistyped (continuity failure at a
    ///     threshold);
    ///   - a threshold has been moved into a range its branch cannot serve;
    ///   - the xi convention has been changed in one place but not another
    ///     (asymptote failure).
    ///
    /// - returns: nil if every check passes, otherwise a description of the
    ///   first failure.
    static func SelfCheck() -> String? {

        // 1. DC limits. These are definitional: no frequency, no effect.
        if abs(DowellSkinFactor(0.0) - 1.0) > 1.0E-15 {

            return "Skin factor at xi=0 should be exactly 1"
        }
        if abs(DowellProximityFactor(0.0)) > 1.0E-15 {

            return "Proximity factor at xi=0 should be exactly 0"
        }

        // 2. Branch agreement. The two formulas that meet at each threshold
        // are evaluated at EXACTLY the threshold and compared.
        //
        // Note this deliberately does not probe at xi +/- eps. Both factors
        // have a non-zero slope at their joins (dF_R/dxi = 1/2 at the
        // asymptotic join, dG_R/dxi = 2), so two probes straddling the
        // threshold differ by the function's own slope times the probe
        // spacing, which is not a discontinuity and would make the test
        // report a false failure. Comparing the branches at one shared point
        // measures the thing we actually care about: do the formulas agree
        // where we switch between them.
        //
        // This is the check that catches a mistyped series coefficient, which
        // is otherwise invisible - the function stays smooth and plausible
        // and merely returns the wrong number.
        let joins:[(name:String, x:Double, lower:(Double) -> Double, upper:(Double) -> Double, tol:Double)] = [
            ("skin series/direct", skinSeriesLimit, skinSeries, skinDirect, 1.0E-13),
            ("skin direct/asymptote", asymptoticLimit, skinDirect, skinAsymptote, 1.0E-15),
            ("proximity series/direct", proximitySeriesLimit, proximitySeries, proximityDirect, 1.0E-13),
            ("proximity direct/asymptote", asymptoticLimit, proximityDirect, proximityAsymptote, 1.0E-15)
        ]

        for join in joins {

            let lower = join.lower(join.x)
            let upper = join.upper(join.x)

            guard lower != 0.0 else { continue }

            if abs(upper - lower) / abs(lower) > join.tol {

                return "Branches disagree at the \(join.name) join (xi=\(join.x)): \(lower) vs \(upper)"
            }
        }

        // 3. High-frequency asymptotes. These are what tie this file back to
        // DelVecchio: if they drift, high-frequency results stop being
        // comparable with the old implementation.
        if abs(DowellSkinFactor(60.0) - 30.0) > 1.0E-12 {

            return "Skin factor should approach xi/2 at large xi"
        }
        if abs(DowellProximityFactor(60.0) - 120.0) > 1.0E-12 {

            return "Proximity factor should approach 2*xi at large xi"
        }

        // 4. Monotonicity. Physically, neither loss mechanism can decrease
        // with frequency. A non-monotonic result means a branch is being
        // selected wrongly.
        var lastSkin = 0.0
        var lastProx = 0.0
        for i in 0...400 {

            // Sweep xi logarithmically from 1e-3 to 1e2, crossing every join.
            let xi = pow(10.0, -3.0 + 5.0 * Double(i) / 400.0)
            let skin = DowellSkinFactor(xi)
            let prox = DowellProximityFactor(xi)

            if skin < lastSkin - 1.0E-12 || skin < 1.0 - 1.0E-12 {

                return "Skin factor is not monotonic (or dropped below 1) at xi=\(xi)"
            }
            if prox < lastProx - 1.0E-12 {

                return "Proximity factor is not monotonic at xi=\(xi)"
            }

            lastSkin = skin
            lastProx = prox
        }

        // 5. The normalization anchor. This is the property the whole
        // frequency-scaling scheme rests on: at the reference frequency the
        // ratios must be exactly 1, so the design file's numbers are
        // reproduced untouched.
        if abs(SkinFactorRatio(thickness: 0.002, frequency: referenceFrequency) - 1.0) > 1.0E-15 {

            return "Skin ratio at the reference frequency should be exactly 1"
        }
        if abs(EddyFactorRatio(thickness: 0.002, frequency: referenceFrequency) - 1.0) > 1.0E-15 {

            return "Eddy ratio at the reference frequency should be exactly 1"
        }

        // 6. Agreement with the old DelVecchio eddy expression at high
        // frequency. This is the compatibility guarantee documented above: the
        // old form is the xi >> 1 asymptote of this same normalized model, so
        // wherever it was valid the two must still agree. If this check ever
        // fails, results computed before this change stopped being comparable
        // with results computed after it, and that needs to be a deliberate
        // decision rather than a surprise.
        //
        //     old(f) = 6 * (f/60)^2 * (delta(f)/b)^3
        //
        // TOLERANCE: 1%, and the residual is the OLD formula's error, not
        // this one's. The identity 6/xi60^3 == 2*xi60 / G_R(xi60) holds only
        // when G_R(xi60) is replaced by its leading term xi60^4/3. The old
        // expression bakes in that leading-order approximation; this code uses
        // the exact G_R(xi60). They therefore differ by the next term of the
        // series, which grows as xi60^4 - about 0.2% for a 4 mm strand
        // (xi60 = 0.47) and negligible for a thin one. Where they differ, this
        // code is the more accurate of the two. Tighten this tolerance and it
        // will fail on thick strands for the wrong reason.
        for (b, f) in [(0.002, 1.0E5), (0.002, 1.0E7), (0.004, 5.0E5)] {

            let deltaF = SkinDepth(frequency: f)
            let old = 6.0 * (f / referenceFrequency) * (f / referenceFrequency) * pow(deltaF / b, 3.0)
            let new = EddyFactorRatio(thickness: b, frequency: f)

            if abs(new - old) / old > 1.0E-2 {

                return "Eddy ratio no longer matches the DelVecchio asymptote at f=\(f), b=\(b): \(new) vs \(old)"
            }
        }

        return nil
    }
}

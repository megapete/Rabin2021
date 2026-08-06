//
//  TurnLadderModel.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2026-08-05.
//
//  A turn-granularity capacitive model of ONE disc, for the question the lumped network cannot answer: how does the voltage
//  actually distribute across the turns of a line-end disc at the wavefront?
//
//  Why this exists. The simulation resolves voltage only at Segment boundaries, so anything inside a disc rests on an assumption.
//  Segment.SteinParameters.gradientEnhancement makes a good one - exact at both ends of its range - but it is an interpolation
//  between those ends, and the first discs of a high-BIL winding are where being approximately right is not good enough.
//
//  THE MODEL. At t = 0+ no current has flowed, so every turn inductance is an open circuit and the only paths are capacitive. Take
//  the turns of one disc as the nodes, at radial positions 0 (inside) to N−1 (outside):
//
//    - a turn-to-turn capacitance Ctt joins each radially adjacent pair;
//    - a share Cdd/N of the disc-to-disc capacitance joins each turn to the turn it faces in the disc above and below;
//    - the disc's own first and last ELECTRICAL turns are held at the potentials the lumped model gives for its two nodes.
//
//  Kirchhoff's current law on that network is a tridiagonal system with a shunt term on the diagonal, which is the discretisation
//  of the continuum equation d²V/dx² = α²·(V − V_env) that Stein's formulas solve in closed form. VerifySelf() checks both limits
//  of that correspondence: with no disc-to-disc capacitance the distribution comes out exactly linear, and with a uniform grounded
//  neighbour it reproduces sinh(αx)/sinh(α).
//
//  WHY ONE DISC AND NOT A GROUP. A group of discs cannot be solved this way. With the turns as free nodes and no capacitance
//  between two discs, those discs become two disconnected components - correct for this network, but at odds with the lumped
//  model, where discs are joined in series through Cs. Resolving that needs the crossover conductor modelled explicitly, which is a
//  larger piece of work. Taking the neighbouring discs as BOUNDARY potentials from the lumped model sidesteps it entirely and is
//  well posed: the neighbours are exactly what the lumped model does resolve.
//
//  SCOPE. Continuous disc windings only. An interleaved or wound-in-shield Segment has a different, scheme-dependent map from
//  physical position to electrical turn, and guessing it would produce a confidently wrong answer rather than no answer, so those
//  are refused explicitly. See TODO.md.
//

import Foundation
import PchBasePackage

/// A turn-level capacitive solve over a single disc.
struct TurnLadderModel:Sendable {

    /// Why a disc could not be modelled.
    enum LadderError:LocalizedError {

        case notContinuousDisc
        case tooFewTurns
        case noCapacitance

        var errorDescription: String? {

            switch self {

            case .notContinuousDisc:
                return "The turn ladder handles plain continuous disc windings only. An interleaved or wound-in-shield segment has a scheme-dependent map from physical position to electrical turn, which this model does not attempt to guess."

            case .tooFewTurns:
                return "The disc has too few turns to resolve a distribution (at least three are needed)."

            case .noCapacitance:
                return "The disc has no turn-to-turn capacitance, so there is nothing to distribute across."
            }
        }
    }

    /// The result of a solve.
    struct Result:Sendable {

        /// Turn potentials in volts, indexed by RADIAL position: 0 is the innermost turn.
        let potentials:[Double]
        let turnCount:Int

        /// The largest voltage between two radially adjacent turns, in volts, and where it is.
        let worstTurnToTurn:Double
        /// The radial position of the inner turn of the worst pair.
        let worstPosition:Int

        /// What the linear assumption would have given for the same disc: the disc's own voltage divided by its turn count.
        let linearTurnToTurn:Double

        /// The enhancement over the linear assumption. This is the number to compare against
        /// Segment.SteinParameters.gradientEnhancement, which is the screening estimate of the same quantity.
        var enhancementOverLinear:Double {

            return linearTurnToTurn > 0.0 ? worstTurnToTurn / linearTurnToTurn : 1.0
        }
    }

    /// Solve one disc, with its neighbours supplied as boundary potentials.
    ///
    /// - Parameter Ctt: the turn-to-turn capacitance of a radially adjacent pair.
    /// - Parameter CddBelow/CddAbove: the disc-to-disc capacitance to the neighbour on each side, or 0 if there is none.
    /// - Parameter windsOutward: true if electrical turn 0 is at radial position 0. A continuous disc winding alternates.
    /// - Parameter vStart/vEnd: the potentials of the disc's first and last ELECTRICAL turns, in volts, from the lumped model.
    /// - Parameter belowProfile/aboveProfile: the potentials, in volts, of the facing turns of the discs below and above, indexed by
    /// RADIAL position. Empty where there is no neighbour.
    static func Solve(turnCount:Int,
                      Ctt:Double,
                      CddBelow:Double,
                      CddAbove:Double,
                      windsOutward:Bool,
                      vStart:Double,
                      vEnd:Double,
                      belowProfile:[Double],
                      aboveProfile:[Double]) throws -> Result {

        guard turnCount >= 3 else {

            throw LadderError.tooFewTurns
        }

        guard Ctt > 0.0 else {

            throw LadderError.noCapacitance
        }

        // Electrical turn 0 sits at radial position 0 when the disc winds outward, and at N−1 when it winds inward. Those two
        // positions are the Dirichlet nodes.
        let startPosition = windsOutward ? 0 : turnCount - 1
        let endPosition = windsOutward ? turnCount - 1 : 0

        let shuntBelow = CddBelow / Double(turnCount)
        let shuntAbove = CddAbove / Double(turnCount)

        // Interior positions are the unknowns. The system is tridiagonal: each interior turn couples to its two radial neighbours
        // through Ctt, and to the facing turns above and below through the shunt shares, which land on the diagonal and the RHS.
        var potentials = [Double](repeating: 0.0, count: turnCount)
        potentials[startPosition] = vStart
        potentials[endPosition] = vEnd

        let lowFixed = min(startPosition, endPosition)
        let highFixed = max(startPosition, endPosition)

        guard highFixed - lowFixed >= 2 else {

            throw LadderError.tooFewTurns
        }

        let free = highFixed - lowFixed - 1

        var sub = [Double](repeating: 0.0, count: free)
        var diag = [Double](repeating: 0.0, count: free)
        var sup = [Double](repeating: 0.0, count: free)
        var rhs = [Double](repeating: 0.0, count: free)

        for i in 0..<free {

            let position = lowFixed + 1 + i

            diag[i] = 2.0 * Ctt + shuntBelow + shuntAbove

            if i > 0 {

                sub[i] = -Ctt
            }
            else {

                // couples to the fixed turn at lowFixed
                rhs[i] += Ctt * potentials[lowFixed]
            }

            if i < free - 1 {

                sup[i] = -Ctt
            }
            else {

                rhs[i] += Ctt * potentials[highFixed]
            }

            if shuntBelow > 0.0, position < belowProfile.count {

                rhs[i] += shuntBelow * belowProfile[position]
            }
            else if shuntBelow > 0.0 {

                // No profile supplied for that side: treat the neighbour as being at this disc's mean, which is the least
                // prejudicial assumption available - it adds no driving term of its own.
                rhs[i] += shuntBelow * (vStart + vEnd) / 2.0
            }

            if shuntAbove > 0.0, position < aboveProfile.count {

                rhs[i] += shuntAbove * aboveProfile[position]
            }
            else if shuntAbove > 0.0 {

                rhs[i] += shuntAbove * (vStart + vEnd) / 2.0
            }
        }

        let interior = SolveTridiagonal(sub: sub, diag: diag, sup: sup, rhs: rhs)

        for i in 0..<free {

            potentials[lowFixed + 1 + i] = interior[i]
        }

        var worst = 0.0
        var worstPosition = 0

        for p in 0..<(turnCount - 1) {

            let difference = abs(potentials[p] - potentials[p + 1])

            if difference > worst {

                worst = difference
                worstPosition = p
            }
        }

        let linear = abs(vEnd - vStart) / Double(turnCount)

        return Result(potentials: potentials,
                      turnCount: turnCount,
                      worstTurnToTurn: worst,
                      worstPosition: worstPosition,
                      linearTurnToTurn: linear)
    }

    /// The Thomas algorithm. The system is a symmetric diagonally-dominant tridiagonal one (every diagonal entry is 2·Ctt plus
    /// non-negative shunts, against off-diagonals summing to 2·Ctt), so it needs no pivoting.
    private static func SolveTridiagonal(sub:[Double], diag:[Double], sup:[Double], rhs:[Double]) -> [Double] {

        let n = diag.count

        guard n > 0 else {

            return []
        }

        var c = [Double](repeating: 0.0, count: n)
        var d = [Double](repeating: 0.0, count: n)

        c[0] = n > 1 ? sup[0] / diag[0] : 0.0
        d[0] = rhs[0] / diag[0]

        for i in 1..<n {

            let m = diag[i] - sub[i] * c[i - 1]
            c[i] = i < n - 1 ? sup[i] / m : 0.0
            d[i] = (rhs[i] - sub[i] * d[i - 1]) / m
        }

        var x = [Double](repeating: 0.0, count: n)
        x[n - 1] = d[n - 1]

        for i in stride(from: n - 2, through: 0, by: -1) {

            x[i] = d[i] - c[i] * x[i + 1]
        }

        return x
    }

    // MARK: Self-check

    /// A runnable self-check, in the same style as DielectricStress.VerifySelf and for the same reason - there is no test target.
    ///
    ///     TurnLadderModel.VerifySelf()
    ///     defaults read com.huberistech.rabin2021 TurnLadderVerification
    ///
    /// It checks the two limits that tie this discrete ladder to the closed-form solution Stein's formulas use:
    ///
    ///  1. With no disc-to-disc capacitance the distribution is exactly linear and the turn-to-turn voltage is exactly 1/N of the
    ///     disc voltage. Anything else means the tridiagonal assembly is wrong.
    ///  2. With a uniform neighbour at 0 V the distribution is sinh(αx)/sinh(α) for α = √(Cshunt_total/Cser_total). This is checked
    ///     at N = 200, where the discretisation error is small; at a realistic N = 20 the discrete answer is a few percent BELOW
    ///     the continuum one, which is not an error - a real winding is discrete, and the continuum derivative at the end turn
    ///     slightly overstates what a finite turn actually sees.
    static func VerifySelf() {

        var report:[String] = []
        var failures = 0

        func check(_ name:String, _ value:Double, _ expected:Double, tolerance:Double) {

            let error = expected == 0.0 ? abs(value) : abs(value - expected) / abs(expected)
            let passed = error <= tolerance

            if !passed { failures += 1 }

            report.append(String(format: "%@ %@: got %.9e, expected %.9e, rel err %.3e (tol %.1e)", passed ? "PASS" : "FAIL", name, value, expected, error, tolerance))
        }

        // 1. No shunt: exactly linear.
        if let flat = try? Solve(turnCount: 20, Ctt: 3.7E-10, CddBelow: 0.0, CddAbove: 0.0, windsOutward: true, vStart: 0.0, vEnd: 1000.0, belowProfile: [], aboveProfile: []) {

            var maxDeviation = 0.0

            for p in 0..<20 {

                maxDeviation = max(maxDeviation, abs(flat.potentials[p] - 1000.0 * Double(p) / 19.0))
            }

            check("no-shunt distribution is linear", maxDeviation, 0.0, tolerance: 1.0E-9)
            check("no-shunt turn-to-turn", flat.worstTurnToTurn, 1000.0 / 19.0, tolerance: 1.0E-12)
        }
        else {

            failures += 1
            report.append("FAIL no-shunt solve threw")
        }

        // 2. Uniform grounded neighbour: must reproduce sinh(alpha x)/sinh(alpha).
        //
        // What is asserted is the CONVERGENCE RATE, not just a threshold, because that is what separates a discretisation error
        // from an assembly error: a discretisation error shrinks with N in a predictable way, an assembly error does not shrink at
        // all. The scheme is FIRST order - the shunt is applied only to the interior turns, since the two end turns are Dirichlet,
        // and that boundary treatment is O(h) - so doubling N should halve the departure from the closed form. Measured: 8.6e-4 at
        // N = 200, 2.1e-4 at N = 800.
        let alpha = 3.0
        let Ctt = 1.0

        func hyperbolicError(N:Int) -> Double? {

            // alpha^2 = Cshunt_total/Cser_total, with Cser_total = Ctt/(N−1) and Cshunt_total = N·shunt.
            let shuntPerTurn = alpha * alpha * Ctt / (Double(N - 1) * Double(N))
            let Cdd = shuntPerTurn * Double(N)

            guard let solved = try? Solve(turnCount: N, Ctt: Ctt, CddBelow: Cdd, CddAbove: 0.0, windsOutward: true, vStart: 0.0, vEnd: 1.0, belowProfile: [Double](repeating: 0.0, count: N), aboveProfile: []) else {

                return nil
            }

            var worstDeviation = 0.0

            for p in 0..<N {

                let x = Double(p) / Double(N - 1)
                let closed = sinh(alpha * x) / sinh(alpha)
                worstDeviation = max(worstDeviation, abs(solved.potentials[p] - closed))
            }

            return worstDeviation
        }

        if let coarse = hyperbolicError(N: 400), let fine = hyperbolicError(N: 800), fine > 0.0 {

            check("hyperbolic profile at N = 800", fine, 0.0, tolerance: 5.0E-4)
            check("first-order convergence (error ratio on doubling N)", coarse / fine, 2.0, tolerance: 0.25)
        }
        else {

            failures += 1
            report.append("FAIL hyperbolic solve threw")
        }

        // The gradient enhancement is the quantity the alpha screen estimates, so this is the one that matters most.
        let N = 800
        let shuntPerTurn = alpha * alpha * Ctt / (Double(N - 1) * Double(N))

        if let solved = try? Solve(turnCount: N, Ctt: Ctt, CddBelow: shuntPerTurn * Double(N), CddAbove: 0.0, windsOutward: true, vStart: 0.0, vEnd: 1.0, belowProfile: [Double](repeating: 0.0, count: N), aboveProfile: []) {

            check("gradient enhancement vs alpha/tanh(alpha)", solved.enhancementOverLinear, alpha / tanh(alpha), tolerance: 0.02)
        }
        else {

            failures += 1
            report.append("FAIL enhancement solve threw")
        }

        report.insert(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED", at: 0)

        UserDefaults.standard.set(report, forKey: "TurnLadderVerification")
    }
}

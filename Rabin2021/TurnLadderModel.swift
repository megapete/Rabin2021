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
        case notRadialWinding
        case tooFewTurns
        case noCapacitance
        case noGaps
        case didNotConverge

        var errorDescription: String? {

            switch self {

            case .notContinuousDisc:
                return "The turn ladder handles plain continuous disc windings only. An interleaved or wound-in-shield segment has a scheme-dependent map from physical position to electrical turn, which this model does not attempt to guess. Sheet and layer windings have their own command - Radial Voltage Profile - because their turns run radially rather than around a disc."

            case .notRadialWinding:
                return "The radial voltage profile handles sheet and layer windings only. A disc winding's turns run around the disc, not out along a radius; use the turn ladder for one of those."

            case .noGaps:
                return "The winding has fewer than two turns radially, so there is no radial gap to report a voltage across."

            case .didNotConverge:
                return "The layer network did not converge. This is a solver failure rather than a modelling one - the capacitance matrix should be positive definite, so please report it."

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

    // MARK: Radial windings - sheet and layer
    //
    // A sheet or layer winding puts its turns out along a RADIUS rather than around a disc, so the question "what is the worst
    // voltage between two adjacent conductors" is a different one and the disc ladder above cannot answer it. Neither winding type
    // is checked anywhere else in the program either: DielectricStress.AppendTurnToTurnSites takes only `.disc`, so before this
    // there was no turn-to-turn or layer-to-layer number for them at all.
    //
    // The two cases are as different from each other as they are from a disc:
    //
    //  - A SHEET winding is a pure series chain. Every turn is a full-height cylinder, so each turn completely screens the next from
    //    everything outside the coil and no interior turn has a capacitance to anything but its two radial neighbours. The
    //    neighbouring coil and the core attach only to the outermost and innermost turns, which are the driven terminals, so they
    //    cannot perturb the interior at all. The same charge passes through every gap and the profile is set entirely by how the gap
    //    capacitance varies with radius - see Segment.SheetGapCapacitances. There is nothing to iterate.
    //
    //  - A LAYER winding is the opposite: its turns run AXIALLY within a layer and the layers stack radially, so a turn's radial
    //    neighbour is a turn of a different layer, hundreds of electrical turns away. That coupling is what makes the initial
    //    distribution non-uniform, and it has to be solved rather than assumed. See SolveLayer.

    /// One radial gap of a sheet or layer winding, as the profile graph plots it.
    struct RadialGap:Sendable {

        /// 0 is the innermost gap - between turns/layers 0 and 1.
        let index:Int
        /// The radius at which the gap sits, in metres.
        let radius:Double
        /// The largest voltage across this gap, in volts.
        let deltaV:Double
        /// The height at which that largest voltage occurs, in metres from the top of the bottom yoke. Nil for a sheet winding,
        /// where a gap carries the same voltage over its whole height.
        let worstHeight:Double?
    }

    /// The radial voltage profile of one sheet or layer winding.
    struct RadialProfile:Sendable {

        /// Innermost gap first.
        let gaps:[RadialGap]
        /// The voltage across the whole Segment that produced this, in volts.
        let segmentVoltage:Double
        /// What the simple assumption gives for every gap, in volts - an even division for a sheet, twice the volts per layer for a
        /// layer winding. The profile is worth drawing precisely where it departs from this.
        let reference:Double
        /// What that assumption is called, for the annotation block.
        let referenceName:String
        /// The potential of every turn, in volts, indexed by ELECTRICAL turn. For a sheet winding this is the running sum of the
        /// gap voltages from zero, since the chain's magnitudes do not depend on which terminal is at the inside; for a layer
        /// winding it is the solved network. Kept mainly so VerifySelf can assert on it.
        let turnPotentials:[Double]
        /// The worst pair of AXIALLY adjacent turns within one layer, for a layer winding.
        ///
        /// A DIFFERENT SITE from the gaps above, and the other half of what a layer winding has to withstand: the gaps are
        /// layer-to-layer, across the interlayer insulation and any duct, while this is turn-to-turn, across one turn's paper. The
        /// volts are far smaller and so is the insulation, so neither one implies the other and both belong in the report.
        ///
        /// Nil for a sheet winding, whose turns ARE the radial gaps - every turn is a full-height cylinder, so its neighbours are
        /// radial and the gaps above already are the turn-to-turn sites.
        let turnToTurn:TurnToTurn?

        /// The worst turn-to-turn pair of a layer winding, and where it is.
        struct TurnToTurn:Sendable {

            /// The volts between the two turns.
            let deltaV:Double
            /// The layer they are in, 0 being the innermost.
            let layer:Int
            /// The height of the pair, in metres from the top of the bottom yoke.
            let height:Double
        }

        var worst:RadialGap? {

            return gaps.max { abs($0.deltaV) < abs($1.deltaV) }
        }

        /// Nil where there is no reference to be over. That is not a degenerate case worth papering over: a coil grounded at both
        /// ends has zero volts across it and so a reference of zero, yet its gaps still carry voltage - the winding beside it drives
        /// them capacitively even though its own terminals are tied together. Reporting "1.00x" there would say the opposite of what
        /// is happening.
        var enhancementOverReference:Double? {

            guard reference > 0.0, let worst else { return nil }

            return abs(worst.deltaV) / reference
        }
    }

    /// The turn-to-turn profile of a SHEET winding.
    ///
    /// The screening argument in the note above makes this a series chain of N − 1 capacitors between two driven terminals, so the
    /// charge Q is common to every gap:
    ///
    ///     ΔV_k = Q/C_k    and    Σ ΔV_k = V    ⟹    ΔV_k = V·(1/C_k) / Σ(1/C_j)
    ///
    /// Note what this does NOT depend on: which terminal is at the inside. Reversing the winding negates every ΔV and leaves the
    /// magnitudes alone, which is why this routine needs no winding-direction argument while SolveLayer does.
    ///
    /// - Parameter gapCapacitances: from Segment.SheetGapCapacitances, innermost first.
    /// - Parameter gapRadii: the radius of each of those gaps, in metres.
    /// - Parameter segmentVoltage: the voltage across the whole Segment, in volts.
    static func SolveSheet(gapCapacitances:[Double], gapRadii:[Double], segmentVoltage:Double) throws -> RadialProfile {

        guard gapCapacitances.count >= 1, gapRadii.count == gapCapacitances.count else {

            throw LadderError.noGaps
        }

        guard gapCapacitances.allSatisfy({ $0 > 0.0 }) else {

            throw LadderError.noCapacitance
        }

        let reciprocalSum = gapCapacitances.reduce(0.0) { $0 + 1.0 / $1 }

        let gaps = (0..<gapCapacitances.count).map { k in

            RadialGap(index: k,
                      radius: gapRadii[k],
                      deltaV: abs(segmentVoltage) * (1.0 / gapCapacitances[k]) / reciprocalSum,
                      worstHeight: nil)
        }

        var potentials = [0.0]

        for gap in gaps {

            potentials.append(potentials[potentials.count - 1] + gap.deltaV)
        }

        return RadialProfile(gaps: gaps,
                             segmentVoltage: segmentVoltage,
                             reference: abs(segmentVoltage) / Double(gapCapacitances.count),
                             referenceName: "even division (V/gaps)",
                             turnPotentials: potentials,
                             turnToTurn: nil)
    }

    /// Everything SolveLayer needs about the winding's geometry.
    struct LayerGeometry:Sendable {

        /// Turns in each layer, innermost layer first. From Segment.LayerTurnCounts. These are NOT whole numbers in general - a
        /// winding of N turns over L layers is L layers of N/L - and the fractional part is what offsets each layer's turns axially
        /// from the previous layer's.
        let turnCounts:[Double]
        /// The layer-to-layer capacitance of each of the L − 1 radial gaps, innermost first. From Segment.LayerGapCapacitances.
        let gapCapacitances:[Double]
        /// The radius of each of those gaps, in metres.
        let gapRadii:[Double]
        /// The AXIAL turn-to-turn capacitance of one adjacent pair within a layer, from Segment.CapacitanceTurnToTurn.
        let Ctt:Double
        /// The total capacitance from the innermost layer to whatever lies inside the coil, and from the outermost layer to
        /// whatever lies outside it. These are what make the distribution non-uniform: without a path out of the winding the
        /// network has only its two terminals and the answer collapses back to linear.
        let innerGroundCapacitance:Double
        let outerGroundCapacitance:Double
        /// The coil's axial extent, in metres from the top of the bottom yoke.
        let zBottom:Double
        let zTop:Double

        /// The turns of the tallest layer, which is what sets the axial pitch: every layer is wound to the same pitch, so a layer
        /// holding fewer turns is short rather than stretched.
        var pitchTurns:Double { max(1.0, self.turnCounts.max() ?? 1.0) }

        /// The axial pitch of the winding, in metres per turn.
        var axialPitch:Double { (self.zTop - self.zBottom) / self.pitchTurns }

        /// The number of axial slots the turn map uses. A part turn still occupies a slot, hence the round up; the tolerance keeps a
        /// whole turn count that has been through a division from producing a spurious empty slot at the top.
        var slotCount:Int { max(1, Int((self.pitchTurns - 1.0E-9).rounded(.up))) }

        /// The height, in metres, of the centre of axial slot s. The topmost slot can be a part slot - the winding stops at zTop
        /// part way through it - so the centre is capped at the top of the coil rather than allowed to run past it.
        func SlotHeight(_ slot:Int) -> Double {

            return self.zBottom + min(Double(slot) + 0.5, self.pitchTurns) * self.axialPitch
        }
    }

    /// The layer-to-layer profile of a LAYER winding, at t = 0+.
    ///
    /// THE NETWORK. Nodes are electrical turns, 0 to N − 1 along the conductor. Three kinds of capacitance join them:
    ///
    ///  - Ctt between consecutive turns of the same layer, which are AXIALLY adjacent. This is the series path.
    ///  - Cll_k/slots between the turn at axial slot s of layer k and the turn at the same slot of layer k + 1. These two are
    ///    radially adjacent but are `turnsPerLayer` apart electrically, which is exactly what makes the problem two-dimensional and
    ///    why it cannot be reduced to a tridiagonal solve the way one disc can. The crossover pair - the last turn of a layer and
    ///    the first of the next - needs no special case: they are at the same slot in adjacent layers, so this term already covers
    ///    them.
    ///  - Cin/slots and Cout/slots from the innermost and outermost layers to what lies beside the coil, at ITS potential rather
    ///    than at ground. That potential is sampled per slot, so an adjacent coil that is not the same height, or is ramping at a
    ///    different rate, is carried properly.
    ///
    /// THE GEOMETRY. Layers alternate direction: layer 0 winds up from the bottom, layer 1 starts at the top and winds down, and so
    /// on, so each layer starts where the previous one ended. Slot s is the same physical height in every layer - the axial pitch is
    /// the coil height over the largest layer's turn count - which is what lets a short final layer sit at the end it actually
    /// occupies rather than being stretched over the full height.
    ///
    /// A layer holds N/L turns and that is generally NOT a whole number, so the layer boundaries do not fall on turn boundaries: the
    /// conductor crosses into the next layer part way through a turn. Each whole turn is assigned to the layer holding its MIDPOINT,
    /// which puts floor(N/L) or ceil(N/L) whole turns in a layer and steps the pattern up the winding by the fractional part - the
    /// real geometry, where each layer's turns sit slightly above the previous layer's. With a whole N/L this is exactly the
    /// rectangular map it replaces.
    ///
    /// WINDING SENSE. `vStart` is taken to be the potential of the first turn, at the INNERMOST layer. The model has no record of
    /// which lead is at the inside of the coil, so this is a convention, not a reading: the ordinary build starts inside at the
    /// bottom. It matters here in a way it does not for a sheet winding - a line end at the inside and a line end at the outside
    /// give genuinely different profiles - so the caller shows it in the annotation.
    ///
    /// THE SOLVE. Kirchhoff's current law at t = 0+ on that network is C·V = b with C a weighted graph Laplacian and the two
    /// terminal turns held fixed. Grounding two nodes makes it symmetric positive definite, so it goes to conjugate gradient, which
    /// is matrix-free and needs no assumption about bandwidth - and the bandwidth here is turnsPerLayer, so a banded solver would be
    /// no better than dense on exactly the windings that are largest.
    ///
    /// - Parameter innerNeighbourPotential: the potential, in volts, of whatever is inside the coil, one entry per axial slot.
    /// - Parameter outerNeighbourPotential: the same for whatever is outside it.
    static func SolveLayer(geometry:LayerGeometry,
                           vStart:Double,
                           vEnd:Double,
                           innerNeighbourPotential:[Double],
                           outerNeighbourPotential:[Double]) throws -> RadialProfile {

        let layerCount = geometry.turnCounts.count

        guard layerCount >= 2 else {

            throw LadderError.noGaps
        }

        guard geometry.gapCapacitances.count == layerCount - 1, geometry.gapRadii.count == layerCount - 1 else {

            throw LadderError.noGaps
        }

        guard geometry.Ctt > 0.0 else {

            throw LadderError.noCapacitance
        }

        guard geometry.turnCounts.allSatisfy({ $0 >= 1.0 }) else {

            throw LadderError.tooFewTurns
        }

        // ---- the turn -> (layer, slot) map ----
        //
        // Turn i occupies [i, i + 1] in turn units along the conductor; boundary[k] is where layer k starts in those same units.
        // The layer a turn belongs to is the one holding its midpoint, i + 1/2.

        var boundary = [Double](repeating: 0.0, count: layerCount + 1)

        for k in 0..<layerCount {

            boundary[k + 1] = boundary[k] + geometry.turnCounts[k]
        }

        let turnCount = Int(boundary[layerCount].rounded())

        guard turnCount >= 3 else {

            throw LadderError.tooFewTurns
        }

        let slotCount = geometry.slotCount
        let pitchTurns = geometry.pitchTurns

        /// The layer each turn is in, and the axial slot it occupies within that layer.
        var layerOfTurn = [Int](repeating: 0, count: turnCount)
        var slotOfTurn = [Int](repeating: 0, count: turnCount)
        /// nodeAtSlot[k][s] is the turn at axial slot s of layer k, or nil where that layer has no turn there.
        var nodeAtSlot = [[Int?]](repeating: [Int?](repeating: nil, count: slotCount), count: layerCount)

        var layer = 0

        for turn in 0..<turnCount {

            let middle = Double(turn) + 0.5

            // The midpoints only increase, so the layer only ever advances.
            while layer + 1 < layerCount, middle >= boundary[layer + 1] { layer += 1 }

            // How far into its layer the turn sits, in turn units, and then how far up from the BOTTOM of the coil. Layer k winds up
            // when k is even, so height runs with the local position; when it winds down the local position is measured from the top.
            // A short layer therefore sits at the end it actually starts from.
            let local = middle - boundary[layer]
            let height = layer % 2 == 0 ? local : pitchTurns - local
            let slot = min(slotCount - 1, max(0, Int(height.rounded(.down))))

            layerOfTurn[turn] = layer
            slotOfTurn[turn] = slot
            nodeAtSlot[layer][slot] = turn
        }

        /// The node number of the turn at axial slot s of layer k, or nil where that layer has no turn there.
        func NodeAt(layer:Int, slot:Int) -> Int? {

            return nodeAtSlot[layer][slot]
        }

        // ---- assembly ----
        //
        // The two terminal turns are Dirichlet. Everything else is a free node; an edge to a fixed or known potential moves that
        // potential to the right-hand side, which is what makes the free system positive definite rather than merely semi-definite.

        let firstNode = 0
        let lastNode = turnCount - 1

        var freeIndex = [Int](repeating: -1, count: turnCount)
        var free = 0

        for node in 0..<turnCount where node != firstNode && node != lastNode {

            freeIndex[node] = free
            free += 1
        }

        guard free > 0 else {

            throw LadderError.tooFewTurns
        }

        var diagonal = [Double](repeating: 0.0, count: free)
        var rhs = [Double](repeating: 0.0, count: free)
        var edges:[(a:Int, b:Int, c:Double)] = []

        func FixedPotential(_ node:Int) -> Double? {

            if node == firstNode { return vStart }
            if node == lastNode { return vEnd }
            return nil
        }

        /// Join two turns through a capacitance.
        func Couple(_ nodeA:Int, _ nodeB:Int, _ c:Double) {

            guard c > 0.0 else { return }

            switch (FixedPotential(nodeA), FixedPotential(nodeB)) {

            case (nil, nil):
                let a = freeIndex[nodeA], b = freeIndex[nodeB]
                diagonal[a] += c
                diagonal[b] += c
                edges.append((a: a, b: b, c: c))

            case (nil, .some(let vB)):
                let a = freeIndex[nodeA]
                diagonal[a] += c
                rhs[a] += c * vB

            case (.some(let vA), nil):
                let b = freeIndex[nodeB]
                diagonal[b] += c
                rhs[b] += c * vA

            case (.some, .some):
                // Both ends held: the branch carries current but constrains nothing.
                break
            }
        }

        /// Join a turn to a known potential outside the winding.
        func Ground(_ node:Int, _ c:Double, _ potential:Double) {

            guard c > 0.0, FixedPotential(node) == nil else { return }

            let f = freeIndex[node]

            diagonal[f] += c
            rhs[f] += c * potential
        }

        // Series: consecutive turns within a layer. The crossover pair - the last turn of a layer and the first of the next - is not
        // axially adjacent and is left to the radial term below, which already joins them: they are at the same slot in adjacent
        // layers.
        for turn in 0..<(turnCount - 1) where layerOfTurn[turn] == layerOfTurn[turn + 1] {

            Couple(turn, turn + 1, geometry.Ctt)
        }

        // Radial: same slot, adjacent layers. Slots where only one of the two layers has a turn face the end region rather than
        // another turn and are left out.
        for k in 0..<(layerCount - 1) {

            let share = geometry.gapCapacitances[k] / Double(slotCount)

            for slot in 0..<slotCount {

                guard let inner = NodeAt(layer: k, slot: slot), let outer = NodeAt(layer: k + 1, slot: slot) else { continue }

                Couple(inner, outer, share)
            }
        }

        // Out of the winding, on both sides.
        let innerShare = geometry.innerGroundCapacitance / Double(slotCount)
        let outerShare = geometry.outerGroundCapacitance / Double(slotCount)

        for slot in 0..<slotCount {

            if let node = NodeAt(layer: 0, slot: slot), slot < innerNeighbourPotential.count {

                Ground(node, innerShare, innerNeighbourPotential[slot])
            }

            if let node = NodeAt(layer: layerCount - 1, slot: slot), slot < outerNeighbourPotential.count {

                Ground(node, outerShare, outerNeighbourPotential[slot])
            }
        }

        // ---- solve ----

        guard let solution = SolveSymmetric(diagonal: diagonal, edges: edges, rhs: rhs) else {

            throw LadderError.didNotConverge
        }

        var potentials = [Double](repeating: 0.0, count: turnCount)
        potentials[firstNode] = vStart
        potentials[lastNode] = vEnd

        for node in 0..<turnCount where freeIndex[node] >= 0 {

            potentials[node] = solution[freeIndex[node]]
        }

        // ---- the profile ----

        var gaps:[RadialGap] = []

        for k in 0..<(layerCount - 1) {

            var worst = 0.0
            var worstSlot = 0

            for slot in 0..<slotCount {

                guard let inner = NodeAt(layer: k, slot: slot), let outer = NodeAt(layer: k + 1, slot: slot) else { continue }

                let difference = abs(potentials[inner] - potentials[outer])

                if difference > worst {

                    worst = difference
                    worstSlot = slot
                }
            }

            gaps.append(RadialGap(index: k,
                                  radius: geometry.gapRadii[k],
                                  deltaV: worst,
                                  worstHeight: geometry.SlotHeight(worstSlot)))
        }

        // The other site in the winding: two AXIALLY adjacent turns of one layer, across one turn's paper. These are the same pairs
        // the Ctt edges were built on, so this reads the answer the network already has rather than modelling anything new. It is
        // worth having beside the gaps because the two do not track each other - the turn-to-turn volts are of order the volts across
        // one turn while a gap carries a whole layer's worth, and the insulation is smaller by about as much, so which of the two is
        // nearer its allowable is a fact about the design rather than something known in advance.
        var worstTurnToTurn:RadialProfile.TurnToTurn? = nil

        for turn in 0..<(turnCount - 1) where layerOfTurn[turn] == layerOfTurn[turn + 1] {

            let difference = abs(potentials[turn] - potentials[turn + 1])

            guard difference > (worstTurnToTurn?.deltaV ?? -1.0) else { continue }

            worstTurnToTurn = RadialProfile.TurnToTurn(deltaV: difference,
                                                       layer: layerOfTurn[turn],
                                                       height: (geometry.SlotHeight(slotOfTurn[turn]) + geometry.SlotHeight(slotOfTurn[turn + 1])) / 2.0)
        }

        // A layer winding's textbook figure. Adjacent layers are wound in opposite directions and joined at one end, so at the far
        // end they are two whole layers of voltage apart - which is the number a designer reaches for, and the thing this solve
        // exists to check rather than assume.
        let voltsPerLayer = abs(vEnd - vStart) / Double(layerCount)

        return RadialProfile(gaps: gaps,
                             segmentVoltage: vEnd - vStart,
                             reference: 2.0 * voltsPerLayer,
                             referenceName: "2 x volts per layer",
                             turnPotentials: potentials,
                             turnToTurn: worstTurnToTurn)
    }

    /// Conjugate gradient with Jacobi preconditioning, on the symmetric positive definite system SolveLayer assembles.
    ///
    /// Matrix-free: the operator is (diagonal ⊙ x) minus the neighbour sum over `edges`, each edge appearing once and acting on both
    /// of its ends. Every diagonal entry is the sum of the capacitances incident on that node and every off-diagonal is the negative
    /// of one of them, so the matrix is weakly diagonally dominant everywhere and strictly so at any node touching a held potential
    /// - which, the winding being connected, makes it positive definite.
    ///
    /// Returns nil if it fails to converge, which should not happen for a well-formed winding.
    private static func SolveSymmetric(diagonal:[Double], edges:[(a:Int, b:Int, c:Double)], rhs:[Double]) -> [Double]? {

        let n = diagonal.count

        guard n > 0 else { return [] }

        func Apply(_ x:[Double]) -> [Double] {

            var result = [Double](repeating: 0.0, count: n)

            for i in 0..<n {

                result[i] = diagonal[i] * x[i]
            }

            for edge in edges {

                result[edge.a] -= edge.c * x[edge.b]
                result[edge.b] -= edge.c * x[edge.a]
            }

            return result
        }

        // Jacobi preconditioner. The diagonal spans several orders of magnitude here - a turn in the middle of a layer carries two
        // Ctt while one at a layer end carries one plus a much smaller Cll share - so this is worth having.
        let inverseDiagonal = diagonal.map { $0 > 0.0 ? 1.0 / $0 : 1.0 }

        var x = [Double](repeating: 0.0, count: n)
        var r = rhs
        var z = (0..<n).map { inverseDiagonal[$0] * r[$0] }
        var p = z
        var rz = zip(r, z).reduce(0.0) { $0 + $1.0 * $1.1 }

        let rhsNorm = sqrt(rhs.reduce(0.0) { $0 + $1 * $1 })

        guard rhsNorm > 0.0 else { return x }

        let tolerance = 1.0E-12 * rhsNorm
        let maximumIterations = max(1000, 4 * n)

        for _ in 0..<maximumIterations {

            let ap = Apply(p)
            let pAp = zip(p, ap).reduce(0.0) { $0 + $1.0 * $1.1 }

            guard pAp > 0.0 else { return nil }

            let alpha = rz / pAp

            for i in 0..<n {

                x[i] += alpha * p[i]
                r[i] -= alpha * ap[i]
            }

            if sqrt(r.reduce(0.0) { $0 + $1 * $1 }) <= tolerance {

                return x
            }

            for i in 0..<n {

                z[i] = inverseDiagonal[i] * r[i]
            }

            let rzNext = zip(r, z).reduce(0.0) { $0 + $1.0 * $1.1 }
            let beta = rzNext / rz
            rz = rzNext

            for i in 0..<n {

                p[i] = z[i] + beta * p[i]
            }
        }

        return nil
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

        // MARK: the radial solves

        // 4. A sheet winding is a series chain, so two things must hold exactly: the gap voltages sum to the terminal voltage, and
        // they are in inverse proportion to the gap capacitances. The second is the whole content of the model - the first would
        // still hold if every gap were given the same capacitance, which is the bug this replaces.
        let sheetRadii = (0..<10).map { 0.200 + Double($0) * 0.003 }
        let sheetCapacitances = sheetRadii.map { 1.0E-7 * $0 / 0.200 }

        if let sheet = try? SolveSheet(gapCapacitances: sheetCapacitances, gapRadii: sheetRadii, segmentVoltage: 10000.0) {

            check("sheet gap voltages sum to the terminal voltage", sheet.gaps.reduce(0.0) { $0 + $1.deltaV }, 10000.0, tolerance: 1.0E-12)

            // C ∝ r, so ΔV ∝ 1/r and the innermost gap beats the outermost by exactly the radius ratio.
            check("sheet innermost/outermost ratio is the radius ratio",
                  sheet.gaps[0].deltaV / sheet.gaps[9].deltaV,
                  sheetRadii[9] / sheetRadii[0],
                  tolerance: 1.0E-12)

            check("sheet worst gap is the innermost", Double(sheet.worst?.index ?? -1), 0.0, tolerance: 1.0E-12)
        }
        else {

            failures += 1
            report.append("FAIL sheet solve threw")
        }

        // A uniform chain must divide evenly - the degenerate case, and the one the old code produced for every winding.
        if let flatSheet = try? SolveSheet(gapCapacitances: [Double](repeating: 1.0E-7, count: 10), gapRadii: sheetRadii, segmentVoltage: 10000.0) {

            check("uniform sheet chain divides evenly", flatSheet.gaps.map { $0.deltaV }.max() ?? 0.0, 1000.0, tolerance: 1.0E-12)
        }
        else {

            failures += 1
            report.append("FAIL uniform sheet solve threw")
        }

        // 5. The layer network, on the two identities that catch an assembly error.
        //
        // 5a. NULL SPACE. Hold both terminals and both neighbours at the same potential and every turn must sit at exactly that
        // potential: a capacitance network has no absolute reference, so a constant vector is in the null space of the Laplacian.
        // This fails the moment a diagonal entry is not the exact sum of the capacitances incident on its node, which is the error
        // an assembly of this shape is most likely to contain.
        let layerTurns = [Double](repeating: 10.0, count: 6)
        let layerGeometry = LayerGeometry(turnCounts: layerTurns,
                                          gapCapacitances: [Double](repeating: 2.0E-10, count: 5),
                                          gapRadii: (0..<5).map { 0.200 + Double($0) * 0.004 },
                                          Ctt: 1.0E-9,
                                          innerGroundCapacitance: 5.0E-11,
                                          outerGroundCapacitance: 5.0E-11,
                                          zBottom: 0.0,
                                          zTop: 1.0)

        let held = [Double](repeating: 100.0, count: 10)

        if let uniform = try? SolveLayer(geometry: layerGeometry, vStart: 100.0, vEnd: 100.0, innerNeighbourPotential: held, outerNeighbourPotential: held) {

            let worstDeviation = uniform.turnPotentials.reduce(0.0) { max($0, abs($1 - 100.0)) }

            check("layer network holds a constant potential", worstDeviation, 0.0, tolerance: 1.0E-9)
            check("layer network has no gap voltage at constant potential", uniform.gaps.map { $0.deltaV }.max() ?? 0.0, 0.0, tolerance: 1.0E-9)

            // The turn-to-turn site comes out of the same solved potentials, and the same argument covers it. Its absence is a
            // failure in its own right: every layer here holds ten turns, so there are pairs to find, and a nil means the scan
            // never ran rather than that the winding has no such site.
            if let pair = uniform.turnToTurn {

                check("layer network has no turn-to-turn voltage at constant potential", pair.deltaV, 0.0, tolerance: 1.0E-9)
            }
            else {

                failures += 1
                report.append("FAIL the layer solve found no turn-to-turn pair in a winding of ten turns per layer")
            }
        }
        else {

            failures += 1
            report.append("FAIL uniform layer solve threw")
        }

        // 5b. MIRROR SYMMETRY. With an even layer count, equal turn counts, equal capacitances and both neighbours at the same
        // potential, reversing the conductor maps every turn onto the turn at the SAME axial slot in the mirrored layer - the two
        // parity flips (layer order and winding direction) cancel. So swapping the terminal potentials must reverse the solution
        // exactly. This is the check on the turn -> (layer, slot) map, which nothing else here would catch: a map that anchored a
        // layer at the wrong end, or failed to alternate, breaks this while leaving 5a untouched.
        let grounded = [Double](repeating: 0.0, count: 10)

        if let forward = try? SolveLayer(geometry: layerGeometry, vStart: 0.0, vEnd: 1000.0, innerNeighbourPotential: grounded, outerNeighbourPotential: grounded),
           let reversed = try? SolveLayer(geometry: layerGeometry, vStart: 1000.0, vEnd: 0.0, innerNeighbourPotential: grounded, outerNeighbourPotential: grounded) {

            var worstDeviation = 0.0
            let turns = forward.turnPotentials.count

            for j in 0..<turns {

                worstDeviation = max(worstDeviation, abs(forward.turnPotentials[j] - reversed.turnPotentials[turns - 1 - j]))
            }

            check("layer solution is symmetric under conductor reversal", worstDeviation, 0.0, tolerance: 1.0E-6)

            // Reversing the conductor maps every adjacent PAIR onto a pair, so the worst turn-to-turn voltage is the same number
            // read off either solution. This catches a scan that walked over a layer boundary - the crossover pair is a turn apart
            // electrically but a whole layer apart radially, and picking it up would break this while leaving the profile alone.
            check("worst turn-to-turn is the same under conductor reversal",
                  forward.turnToTurn?.deltaV ?? 0.0,
                  reversed.turnToTurn?.deltaV ?? -1.0,
                  tolerance: 1.0E-6)

            // And the thing the solve exists to show: with a real path out of the winding the profile is NOT the textbook
            // 2 x volts-per-layer everywhere. If this ever comes back at 1.00 the ground capacitances have stopped reaching the
            // network and the answer has quietly collapsed to the linear one.
            report.append(String(format: "INFO layer enhancement over 2 x volts-per-layer: %.3fx (worst gap %d of %d)",
                                 forward.enhancementOverReference ?? 0.0,
                                 (forward.worst?.index ?? -1) + 1,
                                 forward.gaps.count))
        }
        else {

            failures += 1
            report.append("FAIL mirror-symmetry layer solve threw")
        }

        // 5c. FRACTIONAL LAYERS. A real winding does not have a whole number of turns per layer: 938 turns over 12 layers is twelve
        // layers of 78.1666..., and the whole turns come out 78/78/78/79/78/... as the layer boundary walks through them. Two things
        // must survive that. Every one of the N whole turns must exist exactly once, or a turn has been dropped at a boundary and the
        // conductor is no longer continuous. And no layer may be short by more than one turn - the rounding this replaces produced a
        // final layer of 69 against 79 everywhere else, which is a tenth of a layer's worth of voltage in the wrong place.
        func FractionalGeometry(turns:Int, layers:Int) -> LayerGeometry {

            return LayerGeometry(turnCounts: [Double](repeating: Double(turns) / Double(layers), count: layers),
                                 gapCapacitances: [Double](repeating: 2.0E-10, count: layers - 1),
                                 gapRadii: (0..<(layers - 1)).map { 0.200 + Double($0) * 0.004 },
                                 Ctt: 1.0E-9,
                                 innerGroundCapacitance: 5.0E-11,
                                 outerGroundCapacitance: 5.0E-11,
                                 zBottom: 0.0,
                                 zTop: 1.0)
        }

        let fractionalLayers = 12
        let fractionalTurns = 938
        let fractionalGeometry = FractionalGeometry(turns: fractionalTurns, layers: fractionalLayers)
        let fractionalGround = [Double](repeating: 0.0, count: fractionalGeometry.slotCount)

        if let fractional = try? SolveLayer(geometry: fractionalGeometry, vStart: 0.0, vEnd: 1000.0, innerNeighbourPotential: fractionalGround, outerNeighbourPotential: fractionalGround) {

            check("fractional layer winding keeps every turn", Double(fractional.turnPotentials.count), Double(fractionalTurns), tolerance: 1.0E-12)
        }
        else {

            failures += 1
            report.append("FAIL fractional layer solve threw")
        }

        // The arithmetic of the midpoint rule, stated here as well as used in the map: L equal layers whose whole turns differ by at
        // most one, and never a layer left short by the rounding. This is what the fix exists for, and nothing in a solved profile
        // would show a lopsided map.
        do {

            let perLayer = Double(fractionalTurns) / Double(fractionalLayers)
            var counts = [Int](repeating: 0, count: fractionalLayers)

            for turn in 0..<fractionalTurns {

                counts[min(fractionalLayers - 1, Int(((Double(turn) + 0.5) / perLayer).rounded(.down)))] += 1
            }

            check("fractional layers hold the same turns to within one", Double((counts.max() ?? 0) - (counts.min() ?? 0)), 1.0, tolerance: 1.0E-12)
            check("fractional layers hold all the turns", Double(counts.reduce(0, +)), Double(fractionalTurns), tolerance: 1.0E-12)
        }

        // 5d. And 5b's mirror symmetry again, now with fractional layers, since the map is doing much more work than it was: the
        // midpoint rule is symmetric under i -> N − 1 − i - turn i's distance into its layer maps to N/L minus itself in the mirrored
        // layer, and with an even layer count that flips the winding direction too, so the mirrored turn lands on the same axial slot.
        //
        // 940 turns and not 938, because a midpoint can land EXACTLY on a layer boundary - 938/12 puts one at 234.5 - and such a turn
        // is genuinely half in each layer. The rule sends it up, its mirror image is also a tie and also goes up, and the two choices
        // are not mirror images of each other, so a winding with a tie is asymmetric by that one turn out of 938. That is a real
        // property of the split rather than an assembly error, and testing it here would only pin the tiebreak; 940/12 has no tie.
        let untiedGeometry = FractionalGeometry(turns: 940, layers: fractionalLayers)
        let untiedGround = [Double](repeating: 0.0, count: untiedGeometry.slotCount)

        if let forward = try? SolveLayer(geometry: untiedGeometry, vStart: 0.0, vEnd: 1000.0, innerNeighbourPotential: untiedGround, outerNeighbourPotential: untiedGround),
           let reversed = try? SolveLayer(geometry: untiedGeometry, vStart: 1000.0, vEnd: 0.0, innerNeighbourPotential: untiedGround, outerNeighbourPotential: untiedGround) {

            var worstDeviation = 0.0
            let turns = forward.turnPotentials.count

            for j in 0..<turns {

                worstDeviation = max(worstDeviation, abs(forward.turnPotentials[j] - reversed.turnPotentials[turns - 1 - j]))
            }

            check("fractional layer solution is symmetric under conductor reversal", worstDeviation, 0.0, tolerance: 1.0E-6)
        }
        else {

            failures += 1
            report.append("FAIL fractional mirror-symmetry layer solve threw")
        }

        // 6. Duct placement. Not part of the solve, but it decides which gaps the solve is handed, and on a ducted winding that
        // matters more than anything else in this file: a gap holding an oil duct carries some fifty times the volts of one holding
        // only turn insulation, so a duct in the wrong place - or a duct silently lost - moves the answer by that much.
        //
        // The count is what a rounding change would break. Two ducts rounding onto the same gap costs a duct AND leaves the
        // insulation-only gaps too thin, and it is invisible in the profile unless the count is checked, since three spikes and two
        // spikes both look like a plausible graph.
        let ductPlacement = Segment.DuctGaps(gapCount: 11, ductCount: 3)

        check("3 ducts over 11 gaps are centred at 2, 6, 9", Double(ductPlacement == Set([1, 5, 8]) ? 1 : 0), 1.0, tolerance: 0.0)

        // Both ends must be free. That IS the centred rule - the obvious form, round(j*gaps/n), always ducts the outermost gap.
        check("the centred rule leaves the innermost gap free", Double(ductPlacement.contains(0) ? 0 : 1), 1.0, tolerance: 0.0)
        check("the centred rule leaves the outermost gap free", Double(ductPlacement.contains(10) ? 0 : 1), 1.0, tolerance: 0.0)

        var placementFailures = 0

        for gapCount in 1...40 {

            for requested in 1...45 {

                let expected = Segment.DuctCount(gapCount: gapCount, requested: requested)
                let placed = Segment.DuctGaps(gapCount: gapCount, ductCount: requested)

                // Every duct placed, none lost to a collision, and every one of them inside the winding.
                if placed.count != expected || placed.contains(where: { $0 < 0 || $0 >= gapCount }) {

                    placementFailures += 1
                }
            }
        }

        check("every clamped duct lands on its own gap, over all counts to 40 x 45", Double(placementFailures), 0.0, tolerance: 0.0)

        report.insert(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED", at: 0)

        UserDefaults.standard.set(report, forKey: "TurnLadderVerification")
    }
}

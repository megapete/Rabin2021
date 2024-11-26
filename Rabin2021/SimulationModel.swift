//
//  SimulationModel.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-01-30.
//

import Foundation
import Accelerate
import ComplexModule
import RealModule
import PchBasePackage
import PchMatrixPackage

extension PchMatrix {
    
    func ZeroRow(row:Int) {
        
        if row < 0 || row >= self.rows {
            
            ALog("Bad row index!")
            return
        }
        
        for col in 0..<self.columns {
            
            if self.numType == .Double {
                
                self[row, col] = 0.0
            }
            else if self.numType == .Complex {
                
                self[row, col] = Complex<Double>.zero
            }
            else {
                
                ALog("Unknown type!")
                return
            }
        }
    }
    
    func AddRow(fromIndex:Int, toIndex:Int) {
        
        if fromIndex < 0 || fromIndex >= self.rows || toIndex < 0 || toIndex >= self.rows {
            
            ALog("Bad row index!")
            return
        }
        
        for col in 0..<self.columns {
            
            if self.numType == .Double {
                
                guard let toValue:Double = self[toIndex, col], let fromValue:Double = self[fromIndex, col] else {
                    
                    ALog("Could not get value!")
                    return
                }
                
                let newValue = toValue + fromValue
                self[toIndex, col] = newValue
            }
            else if self.numType == .Complex {
                
                guard let toValue:Complex<Double> = self[toIndex, col], let fromValue:Complex<Double> = self[fromIndex, col] else {
                    
                    ALog("Could not get value!")
                    return
                }
                
                let newValue = toValue + fromValue
                self[toIndex, col] = newValue
            }
            else {
                
                ALog("Unknown type!")
                return
            }
        }
    }
}

private extension Array<Double> {
    
    static func *(scalar:Double, rhs:[Double]) -> [Double] {
        
        return rhs.map({scalar * $0})
    }
    
    static func *(lhs:[Double], scalar:Double) -> [Double] {
        
        return lhs.map({$0 * scalar})
    }
    
    static func +(lhs:[Double], rhs:[Double]) -> [Double] {
        
        // from https://stackoverflow.com/questions/41453942/add-elements-of-two-arrays-in-swift-without-appending-together
        return zip(lhs,rhs).map(+)
    }
    
    static func -(lhs:[Double], rhs:[Double]) -> [Double] {
        
        // from https://stackoverflow.com/questions/41453942/add-elements-of-two-arrays-in-swift-without-appending-together
        return zip(lhs,rhs).map(-)
    }
}

class SimulationModel {
    
    struct WaveForm {
        
        // Only the Full Wave option is actually usable
        enum Types:String, CaseIterable {
            
            case FullWave = "Full Wave (1.2 x 50 µs)"
            case ChoppedWave = "Chopped Wave (1.2 x 3.0 µs)"
            case Switching = "Switching (100 x 1000 µs)"
        }
        
        let pkVoltage:Double
        let type:Types
        
        var timeToPeak:Double {
            
            get {
                
                switch self.type {
                    
                case .FullWave:
                    return 1.2E-6
                    
                case .ChoppedWave:
                    return 1.2E-6
                    
                case .Switching:
                    return 100.0E-6
                }
            }
        }
        
        var timeToZero:Double {
            
            get {
                
                switch self.type {
                    
                case .FullWave:
                    return 100.0E-6
                    
                case .ChoppedWave:
                    return 50.0E-6
                    
                case .Switching:
                    return 1000.0E-6
                }
            }
        }
            
        init(type:Types, pkVoltage:Double) {
            
            self.type = type
            self.pkVoltage = pkVoltage
        }
        
        func V(_ t:Double) -> Double
        {
            if (self.type == Types.FullWave)
            {
                let k1 = 14285.0
                let k2 = 3.3333333E6
                
                let v0 = 1.03 * pkVoltage
                
                return v0 * (e(-k1*t) - e(-k2*t))
            }
            
            ALog("Undefined waveform")
            return 0.0
        }
        
        func dV(_ t:Double) -> Double
        {
            if (self.type == Types.FullWave)
            {
                let k1 = 14285.0
                let k2 = 3.3333333E6
                
                let v0 = 1.03 * pkVoltage
                
                let result = v0 * (k2 * e(-k2 * t) - k1 * e(-k1 * t))
                
                return result
            }
            
            ALog("Undefined waveform")
            return 0.0
        }
    }
    
    let M:PchMatrix
    let baseC:PchMatrix
    var modelC:PchMatrix
    
    // The A and B matrices store their 1's and -1's in the column-major banded-matrix form defined in the BLAS
    let A:[Double] = []
    let B:[Double] = []
    
    /// vDropInd is the voltage drop across a segment represented as an array with the segment index as the index into the COIL-SEGMENT array, and a 2-element tuple as the value. The tuple holds the node indices: (i-1, i), where 'i' is as defined in DelVecchio
    var vDropInd:[(belowNode:Int, aboveNode:Int)] = []
    /// iDrop is the current drop at a node represented as an array with the node index as the index into the NODE array, and a 2-element tuple as the value. The tuple holds the segment indices: (j, j+1), where 'j' is as defined in Delvecchio
    var iDropInd:[(belowSeg:Int, aboveSeg:Int)] = []
    
    struct Resistance {
        
        let dc:Double
        let effRadius:Double
        let eddyPURadial:Double
        let eddyPUAxial:Double
        let strandRadial:Double
        let strandAxial:Double
        let freq:Double = 60.0
        
        // This comes from DelVecchio Eqs: 12.103 & 12.104
        func EffectiveResistanceAt(newFreq:Double) -> Double {
            
            // rhoCopper is 1/conductivity_of_copper
            let jouleFactor = effRadius / 2 * sqrt(π * µ0 * newFreq / rhoCopper)
            let jouleResAtNewFreq = jouleFactor * dc
            
            let bAx = strandAxial
            let bRa = strandRadial
            let eddyBaseFactor = 6.0 * sqrt(newFreq) / (pow(π * µ0 / rhoCopper, 1.5) * (freq * freq))
            let eddyRadialFactor = eddyBaseFactor / (bAx * bAx * bAx)
            let eddyAxialFactor = eddyBaseFactor / (bRa * bRa * bRa)
            
            let eddyResAtNewFreq = dc * (eddyRadialFactor * eddyPURadial + eddyAxialFactor * eddyPUAxial)
            
            // let newResistanceFactor = (jouleResAtNewFreq + eddyResAtNewFreq) / (dc * (1 + eddyPUAxial + eddyPURadial))
            
            return jouleResAtNewFreq + eddyResAtNewFreq
        }
    }
    
    var R:[Resistance] = []
    // The frequency for each disc at each time step needs to be calculated properly. First time through we'll give everybody the same number based on what is written in DelVecchio (3E) 12.11.2 (between eqs 12.103 and 12.104)
    static let defaultEddyFreq = 0.15E6
    
    var eddyFreqs:[Double]? = nil
    
    var impulsedNodes:Set<Node> = []
    var groundedNodes:Set<Node> = []
    var floatingNodes:Set<Node> = []
    
    /// User-settable value to represent the resistance of a "floating" node (required to avoid problems with zeroes and infinities)
    var floatingResistanceToGround = 1.0E50
    
    var finalConnectedNodes:[Node:Set<Node>] = [:]
    
    /// Initialize the simulation model using the PhaseModel
    /// - parameter model: A properly set-up phase model, complete with grounding and impulsed nodes
    init?(model:PhaseModel) {
        
        guard !model.nodes.isEmpty, !model.segments.isEmpty, model.M != nil, model.C != nil else {
            
            DLog("Model is not complete!")
            return nil
        }
        
        self.M = model.M!
        self.baseC = model.C!
        self.modelC = model.C!
        
        // We will need to find impulsed nodes (at least one required) and ground nodes (at least one required) and alter the 'modelC' matrix accordingly. We'll check for floating nodes but just raise a warning (DEBUG builds only)
        impulsedNodes = Set(model.NodesOfType(connType: .impulse))
        groundedNodes = Set(model.NodesOfType(connType: .ground))
        floatingNodes = Set(model.NodesOfType(connType: .floating))
        
        guard !impulsedNodes.isEmpty && !groundedNodes.isEmpty else {
            
            DLog("Model requires at least one impulsed and one grounded node!")
            return nil
        }
        
        if !floatingNodes.isEmpty {
            
            DLog("There are floating nodes in the model!")
        }
        
        // Nodes that have connections to non-adjacent other nodes. We'll use a set to avoid copies
        var connectedNodes:[Node:Set<Node>] = [:]
        
        for nextSegment in model.CoilSegments() {
            
            let nextRes = Resistance(dc: nextSegment.resistance(), effRadius: nextSegment.turnEffectiveRadius(), eddyPURadial: nextSegment.eddyLossRadialPU, eddyPUAxial: nextSegment.eddyLossAxialPU, strandRadial: nextSegment.strandRadial, strandAxial: nextSegment.strandAxial)
            R.append(nextRes)
            
            let nonAdjConns = model.NonAdjacentConnections(segment: nextSegment)
            if !nonAdjConns.isEmpty {
                
                for nextConnection in nonAdjConns {
                    
                    if let nodeKey = model.NodeAt(segment: nextSegment, connection: nextConnection) {
                        
                        if let connSegment = nextConnection.segment {
                            
                            if let nodeValue = model.NodeAt(segment: connSegment, connection: nextConnection) {
                                
                                if var connArray = connectedNodes[nodeKey] {
                                    
                                    connArray.insert(nodeValue)
                                    connectedNodes[nodeKey] = connArray
                                }
                                else {
                                    
                                    connectedNodes[nodeKey] = [nodeValue]
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // At this point, we have a bunch of nodal connections. We want to reduce these to the minimum possible before going on.
        // First we need to get an array of the keys
        var connKeys:[Node] = Array(connectedNodes.keys)
        
        while !connectedNodes.isEmpty {
            
            let nextNewKey = connKeys.removeFirst()
            var removeKeys:[Node] = []
            if var nextConnSet = connectedNodes.removeValue(forKey: nextNewKey) {
                
                for (nextKey, nextSet) in connectedNodes {
                    
                    if nextSet.contains(nextNewKey) {
                        
                        nextConnSet.formUnion(nextSet)
                        nextConnSet.insert(nextKey)
                        nextConnSet.remove(nextNewKey)
                        removeKeys.append(nextKey)
                    }
                }
                
                finalConnectedNodes[nextNewKey] = nextConnSet
            }
            
            for nextBadKey in removeKeys {
                
                connectedNodes.removeValue(forKey: nextBadKey)
            }
        }
        
        connectedNodes = finalConnectedNodes
        connKeys = Array(connectedNodes.keys)
        // If any of the nodes (including the key) in a finalConnectedNode is connected to ground (or impulse), all of the nodes (including the key) are added to the groundedNodes (impulsedNodes) Set and the key is removed from finalConnectedNodes
        while !connectedNodes.isEmpty {
            
            let nextNewKey = connKeys.removeFirst()
            if var nextConnSet = connectedNodes.removeValue(forKey: nextNewKey) {
                
                nextConnSet.insert(nextNewKey)
                
                var foundGround = false
                var foundImpulse = false
                for nextNode in nextConnSet {
                    
                    if groundedNodes.contains(nextNode) {
                        
                        foundGround = true
                        break
                    }
                    
                    if impulsedNodes.contains(nextNode) {
                        
                        foundImpulse = true
                        break
                    }
                }
                
                if foundGround {
                    
                    groundedNodes = groundedNodes.union(nextConnSet)
                    
                    finalConnectedNodes.removeValue(forKey: nextNewKey)
                }
                else if foundImpulse {
                    
                    impulsedNodes = impulsedNodes.union(nextConnSet)
                    
                    finalConnectedNodes.removeValue(forKey: nextNewKey)
                }
            }
        }
        
        vDropInd = Array(repeating: (-1,-1), count: model.CoilSegments().count)
        iDropInd = Array(repeating: (-1,-1), count: model.nodes.count)
        
        // Populate the xDrop arrays. Note that after this loop, any tuple entry with a '-1' in it should be ignored (there shouldn't be any in vDropInd, but there will be some in iDropInd)
        for nextNode in model.nodes {
            
            if let belowSegment = nextNode.belowSegment, !belowSegment.isStaticRing, !belowSegment.isRadialShield {
                
                do {
                    
                    let belowSegIndex = try model.SegmentIndex(segment: belowSegment)
                    vDropInd[belowSegIndex].aboveNode = nextNode.number
                    iDropInd[nextNode.number].belowSeg = belowSegIndex
                }
                catch {
                    
                    PCH_ErrorAlert(message: error.localizedDescription)
                    return nil
                }
            }
            
            if let aboveSegment = nextNode.aboveSegment, !aboveSegment.isStaticRing, !aboveSegment.isRadialShield {
                
                do {
                    
                    let aboveSegIndex = try model.SegmentIndex(segment: aboveSegment)
                    vDropInd[aboveSegIndex].belowNode = nextNode.number
                    iDropInd[nextNode.number].aboveSeg = aboveSegIndex
                }
                catch {
                    
                    PCH_ErrorAlert(message: error.localizedDescription)
                    return nil
                }
            }
        }
        
        // Now we finally have enough data to create the modified (C') capacitance matrix
        DLog("Modifying C-matrix")
        let fixedNodes = impulsedNodes.union(groundedNodes)
        for nextNode in fixedNodes {
            
            let nextNodeIndex = nextNode.number
            modelC.ZeroRow(row: nextNodeIndex)
            modelC[nextNodeIndex, nextNodeIndex] = 1.0
        }
        
        for (nextNode, connNodes) in finalConnectedNodes {
            
            for nextConnNode in connNodes {
                
                let toIndex = nextNode.number
                let fromIndex = nextConnNode.number
                
                modelC.AddRow(fromIndex: fromIndex, toIndex: toIndex)
                modelC.ZeroRow(row: fromIndex)
                modelC[fromIndex, fromIndex] = 1.0
                modelC[fromIndex, toIndex] = -1.0
            }
        }
        
        model.fixedC = modelC
        
        DLog("Sparsity of C': \(modelC.Sparsity())")
        guard let sparseC = modelC.asSparseMatrix() else {
            
            DLog("Could not create sparse version of C'!")
            return nil
        }
        
        modelC = sparseC
    }
    
    struct SimulationStepResult {
        
        let volts:[Double]
        let amps:[Double]
        let time:Double
    }
    
    func DoSimulate(waveForm:WaveForm, startTime:Double, endTime:Double, epsilon:Double, deltaT:Double = 0.05E-6, Vstart:[Double]? = nil, Istart:[Double]? = nil) -> [SimulationStepResult] {
        
        // We run the simulation twice: the first time with the default fundamental frequency at each disc, then calculate the real fundamental frequencies (storing them), then run the sim a second time with the calculated fundamental frequencies
        
        let interimResult = SimulateRK45(waveForm: waveForm, startTime: startTime, endTime: endTime, epsilon: epsilon, deltaT: deltaT, Vstart: Vstart, Istart: Istart)
        
        guard !interimResult.isEmpty else {
            
            return []
        }
        
        var segmentAmps:[[Double]] = Array(repeating: [], count: interimResult[0].amps.count)
        for nextResult in interimResult {
            
            for i in 0..<segmentAmps.count {
                
                segmentAmps[i].append(nextResult.amps[i])
            }
        }
        
        var newEddyFreqs = Array(repeating: SimulationModel.defaultEddyFreq, count: segmentAmps.count)
        for nextSignal in 0..<segmentAmps.count {
            
            newEddyFreqs[nextSignal] = GetFundamentalFrequency(Isignal: segmentAmps[nextSignal], startTime: startTime, endTime: endTime)
        }
        
        eddyFreqs = newEddyFreqs
        
        let result = SimulateRK45(waveForm: waveForm, startTime: startTime, endTime: endTime, epsilon: epsilon, deltaT: deltaT, Vstart: Vstart, Istart: Istart)
        
        return result
    }
    
    func GetFundamentalFrequency(Isignal:[Double], startTime:Double, endTime:Double) -> Double {
        
        // get rid of the dc-component of the signal (from https://sam-koblenski.blogspot.com/2015/11/everyday-dsp-for-programmers-dc-and.html)
        var signal:[Float] = []
        
        let alpha:Float = 0.9
        var wPrev:Float = 0.0
        for x_t in Isignal {
            
            let wNew = Float(x_t) + alpha * wPrev;
            signal.append(wNew - wPrev)
            wPrev = wNew
        }
        
        // This next bunch of stuff is essential cut-and-paste from Apple's documentation. It could probably be optimized but for now I'll just use it as-is
        let n = signal.count
        let log2n = vDSP_Length(log2(Float(n)))
        
        guard let fftSetUp = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else {
                                        
            ALog("Can't create FFT Setup.")
            return Double.greatestFiniteMagnitude
        }
        
        let halfN = Int(n / 2)
        var forwardInputReal = [Float](repeating: 0, count: halfN)
        var forwardInputImag = [Float](repeating: 0, count: halfN)
        var forwardOutputReal = [Float](repeating: 0, count: halfN)
        var forwardOutputImag = [Float](repeating: 0, count: halfN)
        
        forwardInputReal.withUnsafeMutableBufferPointer { forwardInputRealPtr in
            forwardInputImag.withUnsafeMutableBufferPointer { forwardInputImagPtr in
                forwardOutputReal.withUnsafeMutableBufferPointer { forwardOutputRealPtr in
                    forwardOutputImag.withUnsafeMutableBufferPointer { forwardOutputImagPtr in
                        
                        // Create a `DSPSplitComplex` to contain the signal.
                        var forwardInput = DSPSplitComplex(realp: forwardInputRealPtr.baseAddress!,
                                                           imagp: forwardInputImagPtr.baseAddress!)
                        
                        // Convert the real values in `signal` to complex numbers.
                        signal.withUnsafeBytes {
                            vDSP.convert(interleavedComplexVector: [DSPComplex]($0.bindMemory(to: DSPComplex.self)),
                                         toSplitComplexVector: &forwardInput)
                        }
                        
                        // Create a `DSPSplitComplex` to receive the FFT result.
                        var forwardOutput = DSPSplitComplex(realp: forwardOutputRealPtr.baseAddress!,
                                                            imagp: forwardOutputImagPtr.baseAddress!)
                        
                        // Perform the forward FFT.
                        fftSetUp.forward(input: forwardInput,
                                         output: &forwardOutput)
                    }
                }
            }
        }
        
        var xFFT:[Double] = []
        var maxIndex = -1
        var maxMag = 0.0
        for i in 0..<halfN {
            
            let compVal = Complex(Double(forwardOutputReal[i]), Double(forwardOutputImag[i]))
            let mag = compVal.length
            if mag > maxMag {
                
                maxMag = mag
                maxIndex = i
            }
            
            xFFT.append(mag)
        }
        
        let fundFreq = Double(maxIndex) / (endTime - startTime)
        DLog("Fundamental frequency: \(fundFreq) Hz")
        
        return fundFreq
    }
    
    /// Call to simulate the impulse shot using the given parameters and 'self'
    /// - Note: !!!!!!!! Do not use this call, preference should be given to SimulateRK45() !!!!!!!!!!!!!!!!!!!!!
    func Simulate(waveForm:WaveForm, startTime:Double, endTime:Double, deltaT:Double) -> [SimulationStepResult] {
        
        // var result:[SimulationStepResult] = []
        var currentTime = startTime
        // Arrays that need to be updated at every time step of the simulation
        var V:[Double] = Array(repeating: 0.0, count: baseC.rows)
        var voltageDrop:[Double] = Array(repeating: 0.0, count: M.rows)
        
        var I:[Double] = Array(repeating: 0.0, count: M.rows)
        var currentDrop:[Double] = Array(repeating: 0.0, count: baseC.rows)
        var result:[SimulationStepResult] = [SimulationStepResult(volts: V, amps: I, time: currentTime)]
        
        
        
        let rkFactor:[Double] = [0.0, 0.5, 0.5, 1.0, 0.0]
        
        while currentTime < endTime {
            
            // variables used by RK4
            var interimI = I
            var interimV = V
            
            var kV:[[Double]] = Array(repeating: Array(repeating: 0.0, count: baseC.rows), count: 4)
            var kI:[[Double]] = Array(repeating: Array(repeating: 0.0, count: M.rows), count: 4)
            
            // RK4 algorithm
            for interimStep in 0..<4 {
                
                // Solve for dV/dt
                for i in 0..<currentDrop.count {
                    
                    let indexBase = iDropInd[i]
                    let Ij:Double = indexBase.belowSeg < 0 ? 0 : interimI[indexBase.belowSeg]
                    let Ij1:Double = indexBase.aboveSeg < 0 ? 0 : interimI[indexBase.aboveSeg]
                    currentDrop[i] = Ij - Ij1
                }
                
                // Set the grounded node rhs values to 0
                for nextGround in groundedNodes {
                    
                    let index = nextGround.number
                    currentDrop[index] = 0.0
                }
                
                // Set the impulsed node rhs values to the derivative of the impulse equation at the current time
                for nextImpulse in impulsedNodes {
                    
                    let index = nextImpulse.number
                    currentDrop[index] = waveForm.dV(currentTime + deltaT * rkFactor[interimStep])
                }
                
                // Add the currentDrops of connected terminals to the "parent" terminal and then set the connected-terminal's currentDrop to 0
                for (nextNode, connNodes) in finalConnectedNodes {
                    
                    let toNode = nextNode.number
                    for nextConnNode in connNodes {
                        
                        let fromNode = nextConnNode.number
                        currentDrop[toNode] += currentDrop[fromNode]
                        currentDrop[fromNode] = 0.0
                    }
                }
                
                let Crhs = PchMatrix(vectorData: currentDrop)
                guard let dVdt = modelC.SolveSparse(B: Crhs) else {
                    
                    DLog("Sparse solve failed!")
                    return []
                }
                
                // we use the method of the paper "rungekutta_adaptive_stepsize" (multiplying the k's by 'h' here instead of later)
                kV[interimStep] = QuickScalarVectorMultiply(scalar: deltaT, vector: dVdt.buffer)
                
                // Solve for dI/dt
                // Start by getting the voltage drops ('BV')
                for i in 0..<voltageDrop.count {
                    
                    let indexBase = vDropInd[i]
                    voltageDrop[i] = interimV[indexBase.belowNode] - interimV[indexBase.aboveNode]
                }
                
                let Mrhs = QuickVectorSubtract(lhs: voltageDrop, rhs: QuickRI(I: interimI, freqs: eddyFreqs))
                guard let dIdt = M.SolvePositiveDefinite(B: PchMatrix(vectorData: Mrhs)) else {
                    
                    DLog("Pos/Def Solve failed!")
                    return []
                }
                
                kI[interimStep] = QuickScalarVectorMultiply(scalar: deltaT, vector: dIdt.buffer)
                
                interimI = QuickVectorAdd(lhs: I, rhs: QuickScalarVectorMultiply(scalar: rkFactor[interimStep + 1], vector: kI[interimStep]))
                interimV = QuickVectorAdd(lhs: V, rhs: QuickScalarVectorMultiply(scalar: rkFactor[interimStep + 1], vector: kV[interimStep]))
                
            } // interimStep (end RK4)
            
            V = QuickVectorAdd(lhs: V, rhs: QuickScalarVectorMultiply(scalar: 1 / 6, vector: kV[0]))
            V = QuickVectorAdd(lhs: V, rhs: QuickScalarVectorMultiply(scalar: 1 / 3, vector: kV[1]))
            V = QuickVectorAdd(lhs: V, rhs: QuickScalarVectorMultiply(scalar: 1 / 3, vector: kV[2]))
            V = QuickVectorAdd(lhs: V, rhs: QuickScalarVectorMultiply(scalar: 1 / 6, vector: kV[3]))
            
            I = QuickVectorAdd(lhs: I, rhs: QuickScalarVectorMultiply(scalar: 1 / 6, vector: kI[0]))
            I = QuickVectorAdd(lhs: I, rhs: QuickScalarVectorMultiply(scalar: 1 / 3, vector: kI[1]))
            I = QuickVectorAdd(lhs: I, rhs: QuickScalarVectorMultiply(scalar: 1 / 3, vector: kI[2]))
            I = QuickVectorAdd(lhs: I, rhs: QuickScalarVectorMultiply(scalar: 1 / 6, vector: kI[3]))
            
            result.append(SimulationStepResult(volts: V, amps: I, time: currentTime))
            
            currentTime += deltaT
            
        } // done simulation
        
        return result
    }
    
    /// Use the RK45 method (with adaptive timesteps) to simulate the impulse shot. Note that the 'deltaT' argument is only used as a startng point. It has a default value of 0.05E-6
    /// - parameter waveForm: A valid WaveForm to use for the simulation
    /// - parameter startTime: The beginning time of the simulation, usually 0
    /// - parameter endTime: The ending time of the simulation
    /// - parameter epsilon: The acceptable error value of a single time step, in V/s. For example, to limit the voltage error in a single step to approximately 100V, pass 100/∆t for this value
    /// - parameter deltaT: The suggested time-step in seconds. The routine uses this to start, then refines the value as necessary. This value defaults to 0.05E-6.
    /// - parameter Vstart: An optional set of initial voltages at time 'startTime'. If 'nil', then it is assumed that initial voltages are 0
    /// - parameter Istart: An optional set of initial currents at time 'startTime'. If 'nil', then it is assumed that initial currents are 0
    /// - returns: An array of SimulationStepResults
    /// - Note: Only the voltage is used to determine whether the calculation is within tolerance (ie: current is not used)
    func SimulateRK45(waveForm:WaveForm, startTime:Double, endTime:Double, epsilon:Double, deltaT:Double = 0.05E-6, Vstart:[Double]? = nil, Istart:[Double]? = nil) -> [SimulationStepResult] {
        
        guard startTime < endTime else {
            
            DLog("Start must be less than end!")
            return []
        }
        
        var V:[Double] = Vstart == nil ? Array(repeating: 0.0, count: baseC.rows) : Vstart!
        var I:[Double] = Istart == nil ? Array(repeating: 0.0, count: M.rows) : Istart!
        
        var result:[SimulationStepResult] = [SimulationStepResult(volts: V, amps: I, time: startTime)]
        
        var currentTime = startTime
        var h = deltaT
        var unusedSteps = 0
        
        while currentTime < endTime {
            
            h = min(h, endTime - currentTime)
            
            // This all comes from the pdf document "rungekutta_adaptive_timestep"
            let f1 = DifferentialFormula(waveForm: waveForm, t: currentTime, V: V, I: I)
            let dVk1 = h * f1.dVdt
            let dIk1 = h * f1.dIdt
            
            let f2 = DifferentialFormula(waveForm: waveForm, t: currentTime + h / 4, V: V + (0.25 * dVk1), I: I + (0.25 * dIk1))
            let dVk2 = h * f2.dVdt
            let dIk2 = h * f2.dIdt
            var dV = 3.0/32.0 * dVk1
            dV = dV + 9.0/32.0 * dVk2
            var dI = 3.0/32.0 * dIk1
            dI = dI + 9.0/32.0 * dIk2
            
            let f3 = DifferentialFormula(waveForm: waveForm, t: currentTime + 3 * h / 8, V: V + dV, I: I + dI)
            let dVk3 = h * f3.dVdt
            let dIk3 = h * f3.dIdt
            dV = 1932.0/2197.0 * dVk1 
            dV = dV - 7200.0/2197.0 * dVk2
            dV = dV + 7296.0/2197.0 * dVk3
            dI = 1932.0/2197.0 * dIk1
            dI = dI - 7200.0/2197.0 * dIk2
            dI = dI + 7296.0/2197.0 * dIk3
            
            let f4 = DifferentialFormula(waveForm: waveForm, t: currentTime + 12 * h / 13, V: V + dV, I: I + dI)
            let dVk4 = h * f4.dVdt
            let dIk4 = h * f4.dIdt
            dV = 439.0/216.0 * dVk1 
            dV = dV - 8.0 * dVk2
            dV = dV + 3680.0/513.0 * dVk3
            dV = dV - 845.0/4104.0 * dVk4
            dI = 439.0/216.0 * dIk1 
            dI = dI - 8.0 * dIk2
            dI = dI + 3680.0/513.0 * dIk3
            dI = dI - 845.0/4104.0 * dIk4
            
            let f5 = DifferentialFormula(waveForm: waveForm, t: currentTime + h, V: V + dV, I: I + dI)
            let dVk5 = h * f5.dVdt
            let dIk5 = h * f5.dIdt
            dV = -8.0/27.0 * dVk1
            dV = dV + 2.0 * dVk2
            dV = dV - 3544.0/2565.0 * dVk3
            dV = dV + 1859.0/4104.0 * dVk4
            dV = dV - 11.0/40.0 * dVk5
            dI = -8.0/27.0 * dIk1
            dI = dI + 2.0 * dIk2
            dI = dI - 3544.0/2565.0 * dIk3
            dI = dI + 1859.0/4104.0 * dIk4
            dI = dI - 11.0/40.0 * dIk5
            let f6 = DifferentialFormula(waveForm: waveForm, t: currentTime + h / 2, V: V + dV, I: I + dI)
            let dVk6 = h * f6.dVdt
            // let dIk6 = h * f6.dIdt
            
            var newV = V + 25.0/216.0 * dVk1
            newV = newV + 1408.0/2565.0 * dVk3
            newV = newV + 2197.0/4104.0 * dVk4
            newV = newV - 1.0/5.0 * dVk5
            
            var newI = I + 25.0/216.0 * dIk1
            newI = newI + 1408.0/2565.0 * dIk3
            newI = newI + 2197.0/4104.0 * dIk4
            newI = newI - 1.0/5.0 * dIk5
            
            var checkV = V + 16.0/135.0 * dVk1
            checkV = checkV + 6656.0/12825.0 * dVk3
            checkV = checkV + 28561.0/56430.0 * dVk4
            checkV = checkV - 9.0/50.0 * dVk5
            checkV = checkV + 2.0/55.0 * dVk6
            /*
            var checkI = I + 16.0/135.0 * dIk1
            checkI = checkI + 6656.0/12825.0 * dIk3
            checkI = checkI + 28561.0/56430.0 * dIk4
            checkI = checkI - 9.0/50.0 * dIk5
            checkI = checkI + 2.0/55.0 * dIk6
            */
            
            let vR = (1.0 / h) * (checkV - newV).map(abs)
            // let iR = (1.0 / h) * (checkI - newI).map(abs)
            
            guard let max_vR = vR.max() /*, let max_iR = iR.max() */ else {
                
                DLog("Could not get max value!")
                return []
            }
            
            let delV = 0.84 * pow(epsilon / max_vR, 0.25)
            // let delI = 0.84 * pow(epsilon / max_iR, 0.25)
            
            if max_vR <= epsilon /* && max_iR <= epsilon */ {
                
                currentTime += h
                V = newV
                I = newI
                
                let nextStepResult = SimulationStepResult(volts: V, amps: I, time: currentTime)
                result.append(nextStepResult)
            }
            else {
                
                DLog("Error too great at time \(currentTime * 1.0E6) µs; Step: \(h * 1.0E6) µs. Adjusting step and trying again!")
                unusedSteps += 1
            }
            
            h = delV * h
        }
        
        DLog("Total number of unused steps: \(unusedSteps)")
        return result
    }
    
    
    private func DifferentialFormula(waveForm:WaveForm, t:Double, V:[Double], I:[Double]) -> (dVdt:[Double], dIdt:[Double]) {
        
        var voltageDrop:[Double] = Array(repeating: 0.0, count: M.rows)
        var currentDrop:[Double] = Array(repeating: 0.0, count: baseC.rows)
        
        // Solve for dV/dt
        for i in 0..<currentDrop.count {
            
            let indexBase = iDropInd[i]
            let Ij:Double = indexBase.belowSeg < 0 ? 0 : I[indexBase.belowSeg]
            let Ij1:Double = indexBase.aboveSeg < 0 ? 0 : I[indexBase.aboveSeg]
            currentDrop[i] = Ij - Ij1
        }
        
        // Set the grounded node rhs values to 0
        for nextGround in groundedNodes {
            
            let index = nextGround.number
            currentDrop[index] = 0.0
        }
        
        // Set the impulsed node rhs values to the derivative of the impulse equation at the current time
        for nextImpulse in impulsedNodes {
            
            let index = nextImpulse.number
            currentDrop[index] = waveForm.dV(t)
        }
        
        // Add a huge resistance (Rs) to ground for any "floating nodes". According to DelVecchio 3E (in the paragraph immediately after equation 14.5), the value Vi/Rs is added to the left-hand side (so, subtracted from the RHS)
        for nextFloater in floatingNodes {
            
            let index = nextFloater.number
            let Rs = self.floatingResistanceToGround
            currentDrop[index] -= (V[index] / Rs)
        }
        
        // Add the currentDrops of connected terminals to the "parent" terminal and then set the connected-terminal's currentDrop to 0
        for (nextNode, connNodes) in finalConnectedNodes {
            
            let toNode = nextNode.number
            for nextConnNode in connNodes {
                
                let fromNode = nextConnNode.number
                currentDrop[toNode] += currentDrop[fromNode]
                currentDrop[fromNode] = 0.0
            }
        }
        
        let Crhs = PchMatrix(vectorData: currentDrop)
        guard let dVdt = modelC.SolveSparse(B: Crhs) else {
            
            DLog("Sparse solve failed!")
            return ([], [])
        }
        
        // Solve for dI/dt
        // Start by getting the voltage drops ('BV')
        for i in 0..<voltageDrop.count {
            
            let indexBase = vDropInd[i]
            voltageDrop[i] = V[indexBase.belowNode] - V[indexBase.aboveNode]
        }
        
        let Mrhs = QuickVectorSubtract(lhs: voltageDrop, rhs: QuickRI(I: I, freqs: eddyFreqs))
        guard let dIdt = M.SolvePositiveDefinite(B: PchMatrix(vectorData: Mrhs)) else {
            
            DLog("Pos/Def Solve failed!")
            return ([], [])
        }
        
        return (dVdt.buffer, dIdt.buffer)
    }
    
    /// Multiply all values in a buffer (vector) by a scalar
    func QuickScalarVectorMultiply(scalar:Double, vector:[Double]) -> [Double] {
        
        var result:[Double] = Array(repeating: 0.0, count: vector.count)
        
        for i in 0..<vector.count {
            
            result[i] = scalar * vector[i]
        }
        
        return result
    }
    
    func QuickVectorAdd(lhs:[Double], rhs:[Double]) -> [Double] {
        
        var result:[Double] = Array(repeating: 0.0, count: lhs.count)
        
        for i in 0..<lhs.count {
            
            result[i] = lhs[i] + rhs[i]
        }
        
        return result
    }
    
    /// Subtract one vector from another. Note that this routine does no dimension checking (or any checking of any kind)
    func QuickVectorSubtract(lhs:[Double], rhs:[Double]) -> [Double] {
        
        var result:[Double] = Array(repeating: 0.0, count: lhs.count)
        
        for i in 0..<lhs.count {
            
            result[i] = lhs[i] - rhs[i]
        }
        
        return result
    }
    
    /// Multiply the (diagonal) R matrix by the vector I. Note that this routine does no dimension checking (or any checking of any kind, for that matter)
    func QuickRI(I:[Double], freqs:[Double]?) -> [Double] {
        
        var result:[Double] = Array(repeating: 0.0, count: I.count)
        for i in 0..<I.count {
            
            let frequency = freqs == nil ? SimulationModel.defaultEddyFreq : freqs![i]
            result[i] = R[i].EffectiveResistanceAt(newFreq: frequency) * I[i]
        }
        
        return result
    }
}

//
//  SimulationModel.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-01-30.
//

import Foundation
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

struct SimulationModel {
    
    struct WaveForm {
        
        // For now, only the FullWave option is defined, and assumes a 1.2 x 50 µs waveform
        enum Types {
            
            case FullWave
        }
        
        let pkVoltage:Double
        let type:Types
            
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
    
    /// vDropInd is the voltage drop across a segment represented as an array with the segment index as the index into the array, and a 2-element tuple as the value. The tuple holds the node indices: (i-1, i)
    var vDropInd:[(belowNode:Int, aboveNode:Int)] = []
    /// iDrop is the current drop at a node represented as an array with the node index as the index into the array, and a 2-element tuple as the value. The tuple holds the segment indices: (j, j+1)
    var iDropInd:[(belowSeg:Int, aboveSeg:Int)] = []
    
    struct Resistance {
        
        let dc:Double
        let eddyPU:Double
        let freq:Double = 60.0
        
        func EffectiveResistanceAt(newFreq:Double) -> Double {
            
            let effEddyPU = eddyPU * (newFreq * newFreq) / (freq * freq)
            return dc * (1 + effEddyPU)
        }
    }
    
    var R:[Resistance] = []
    
    var impulsedNodes:Set<Node> = []
    var groundedNodes:Set<Node> = []
    var floatingNodes:Set<Node> = []
    
    var finalConnectedNodes:[Node:Set<Node>] = [:]
    
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
            
            let nextRes = Resistance(dc: nextSegment.resistance(), eddyPU: nextSegment.eddyLossPU)
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
        
        vDropInd = Array(repeating: (-1,-1), count: model.segments.count)
        iDropInd = Array(repeating: (-1,-1), count: model.nodes.count)
        
        // Populate the xDrop arrays. Note that any tuple entry with a '-1' in it should be ignored (there shouldn't be any in vDropInd, but there will be some in iDropInd)
        for nextNode in model.nodes {
            
            if let belowSegment = nextNode.belowSegment {
                
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
            
            if let aboveSegment = nextNode.aboveSegment {
                
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
    
    // Call to simulate the impulse shot using the given parameters and 'self'
    func Simulate(waveForm:WaveForm, startTime:Double, endTime:Double, deltaT:Double) -> [SimulationStepResult] {
        
        var result:[SimulationStepResult] = []
        var currentTime = startTime
        // Arrays that need to be updated at every time step of the simulation
        var V:[Double] = Array(repeating: 0.0, count: baseC.rows)
        var voltageDrop:[Double] = Array(repeating: 0.0, count: M.rows)
        
        var I:[Double] = Array(repeating: 0.0, count: M.rows)
        var currentDrop:[Double] = Array(repeating: 0.0, count: baseC.rows)
        let firstStepResult = SimulationStepResult(volts: V, amps: I, time: currentTime)
        
        // The frequency for each disc at each time step needs to be calculated properly. For now, we'll just give everybody the same number, based on a wavelength of 1/200µs
        let eddyFreq = 1.0 / 200.0E-6
        while currentTime < endTime {
            
            // First, we solve for dI/dt
            // Start by getting the voltage drops ('BV')
            for i in 0..<voltageDrop.count {
                
                let indexBase = vDropInd[i]
                voltageDrop[i] = V[indexBase.belowNode] - V[indexBase.aboveNode]
            }
            
            let Mrhs = QuickVectorSubtract(lhs: voltageDrop, rhs: QuickRI(I: I, freq: eddyFreq))
            
            let dIdt = M.SolvePositiveDefinite(B: Mrhs)
            
            // And now, dV/dt
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
                currentDrop[index] = waveForm.dV(currentTime)
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
            
            
            
            
            currentTime += deltaT
        }
        
        return result
    }
    
    /// Subtract one vector from another. Note that this routine does no dimension checking (or any checking of any kind)
    func QuickVectorSubtract(lhs:[Double], rhs:[Double]) -> PchMatrix {
        
        var result:[Double] = Array(repeating: 0.0, count: lhs.count)
        
        for i in 0..<lhs.count {
            
            result[i] = lhs[i] - rhs[i]
        }
        
        return PchMatrix(vectorData: result)
    }
    
    /// Multiply the (diagonal) R matrix by the vector I. Note that this routine does no dimension checking (or any checking of any kind, for that matter)
    func QuickRI(I:[Double], freq:Double = 60.0) -> [Double] {
        
        var result:[Double] = Array(repeating: 0.0, count: I.count)
        for i in 0..<I.count {
            
            result[i] = R[i].EffectiveResistanceAt(newFreq: freq) * I[i]
        }
        
        return result
    }
}

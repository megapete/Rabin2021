//
//  SimulationModel.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-01-30.
//

import Foundation
import PchBasePackage
import PchMatrixPackage

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
    let modelC:PchMatrix
    
    // The A and B matrices store their 1's and -1's in the column-major banded-matrix form defined in the BLAS
    let A:[Double] = []
    let B:[Double] = []
    
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
    
    var impulsedNodes:[Node] = []
    var groundedNodes:[Node] = []
    var floatingNodes:[Node] = []
    
    init?(model:PhaseModel) {
        
        guard !model.nodes.isEmpty, !model.segments.isEmpty, model.M != nil, model.C != nil else {
            
            DLog("Model is not complete!")
            return nil
        }
        
        self.M = model.M!
        self.baseC = model.C!
        self.modelC = model.C!
        
        // We will need to find impulsed nodes (at least one required) and ground nodes (at least one required) and alter the 'modelC' matrix accordingly. We'll check for floating nodes but just raise a warning (DEBUG builds only)
        impulsedNodes = model.NodesOfType(connType: .impulse)
        groundedNodes = model.NodesOfType(connType: .ground)
        floatingNodes = model.NodesOfType(connType: .floating)
        
        guard !impulsedNodes.isEmpty && !groundedNodes.isEmpty else {
            
            DLog("Model requires at least one impulsed and one grounded node!")
            return nil
        }
        
        if !floatingNodes.isEmpty {
            
            PCH_ErrorAlert(message: "There are floating nodes in the model!")
        }
        
        // Nodes that have connections to non-adjacent other nodes. We'll use a set to avoid copies
        var connectedNodes:[Node:Set<Node>] = [:]
        
        for nextSegment in model.segments {
            
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
        
        var finalConnectedNodes:[Node:Set<Node>] = [:]
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
    
        
    }
}

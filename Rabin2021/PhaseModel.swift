//
//  PhaseModel.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-13.
//

import Foundation

class PhaseModel:Codable {
    
    /// The segments that make up the model
    var segments:[Segment]
    
    /// An array of arrays where the first index is the segment number and the second index (i) is J[i] for the segment
    var J:[[Double]] = []
    
    var useWindowHeight:Double {
        get {
            if self.segments.count == 0 {
            
                return 0.0
            }
            
            return self.segments[0].useWindowHeight
        }
    }
    
    var realWindowHeight:Double {
        get {
            if self.segments.count == 0 {
            
                return 0.0
            }
            
            return self.segments[0].realWindowHeight
        }
    }
    
    init(segments:[Segment]) {
        
        self.segments = segments
        
        for nextSegment in segments {
            
            self.J.append(nextSegment.CreateFourierJ())
        }
    }
    
    
    /// Get the current density of the given coil at the given height, using equation 9.10 of DelVecchio
    func J(radialPos:Int, realZ:Double) -> Double {
        
        let coilJ = self.CoilJ(radialPos: radialPos)
        let z = realZ + segments[0].zWindHtAdder
        let L = segments[0].L
        
        var result = coilJ[0]
        
        for n in 1...PCH_RABIN2021_IterationCount {
            
            let nn = Double(n)
            let nextHarmonic = coilJ[n] * cos(nn * π * z / L)
            
            result += nextHarmonic
        }
        
        return result
    }
    
    /// Get the Fourier series representation of the current density for the coil
    func CoilJ(radialPos:Int) -> [Double]
    {
        var result:[Double] = Array(repeating: 0.0, count: PCH_RABIN2021_IterationCount + 1)
        
        for nextSegment in self.segments {
            
            if nextSegment.radialPos == radialPos {
                
                for i in 0...PCH_RABIN2021_IterationCount {
                    
                    result[i] += self.J[nextSegment.serialNumber][i]
                }
            }
        }
        
        return result
    }
}

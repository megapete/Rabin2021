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
    
    init(segments:[Segment]) {
        
        self.segments = segments
        
        for nextSegment in segments {
            
            self.J.append(nextSegment.CreateFourierJ())
        }
    }
    
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

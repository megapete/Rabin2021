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
    
    /// The core for the model
    let core:Core
    
    /// An array of arrays where the first index is the segment number and the second index (i) is J[i] for the segment (used for DelVecchio only)
    var J:[[Double]] = []
    
    /// An array of Eslamian Vahidi segments
    var evSegments:[EslamianVahidiSegment] = []
    
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
    
    var numCoils:Int {
        get {
            
            guard self.segments.count > 0 else {
                return 0
            }
            
            return self.J.count
        }
    }
    
    struct PhaseModelError:LocalizedError
    {
        enum errorType
        {
            case EmptyModel
            case IllegalMatrix
        }
        
        let info:String
        let type:errorType
        
        var errorDescription: String?
        {
            get
            {
                if self.type == .EmptyModel
                {
                   return "There are no segments in the model!"
                }
                else if self.type == .IllegalMatrix {
                    
                    return "The inductance matrix is not positive-definite!"
                }
                
                return "An unknown error occurred."
            }
        }
    }
    
    init(segments:[Segment], core:Core, useEslamianVahidi:Bool = true) {
        
        self.segments = segments
        self.core = core
        
        if useEslamianVahidi {
            
            if segments.count > 0 {
                
                self.evSegments = EslamianVahidiSegment.Create_EV_Array(segments: segments, core: self.core)
            }
            
        } else {
            
            for nextSegment in segments {
                
                self.J.append(nextSegment.CreateFourierJ())
            }
        }
    }
    
    func InductanceMatrix(useEslamianVahidi:Bool = true) throws -> PCH_BaseClass_Matrix  {
        
        guard self.evSegments.count > 0 else {
            
            throw PhaseModelError(info: "", type: .EmptyModel)
        }
        
        guard let result = EslamianVahidiSegment.InductanceMatrix(evSegments: self.evSegments) else {
            
            throw PhaseModelError(info: "", type: .IllegalMatrix)
        }
        
        return result
    }
    
    
    /// Get the current density of the given coil at the given height, using equation 9.10 of DelVecchio
    func J(radialPos:Int, realZ:Double) -> Double {
        
        let coilJ = self.CoilJ(radialPos: radialPos)
        let z = realZ + segments[0].zWindHtAdder
        let L = segments[0].L
        
        var result = coilJ[0]
        
        // var gotFirst = false
        // var lastHarmonic = 0.0
        
        for n in 1...PCH_RABIN2021_IterationCount {
            
            let nn = Double(n)
            let nextHarmonic = coilJ[n] * cos(nn * π * z / L)
            
            /* if gotFirst {
                
                if abs(nextHarmonic) / abs(lastHarmonic) > 1.0 {
                    print("NOT CONVERGING!")
                }
            }
            else {
                gotFirst = true
            } */
            
            result += nextHarmonic
            // lastHarmonic = nextHarmonic
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

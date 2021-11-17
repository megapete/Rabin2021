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
    
    /// The window height to actually use
    var useWindowHeight:Double {
        
        return self.core.adjustedWindHt
    }
    
    /// The real window height of the core
    var realWindowHeight:Double {
        
        return self.core.realWindowHeight
    }
    
    /// Errors that can be thrown by some routines
    struct PhaseModelError:LocalizedError
    {
        /// The different error types that are available
        enum errorType
        {
            case UnimplementedInductanceMethod
            case EmptyModel
            case IllegalMatrix
            case CoilDoesNotExist
            case NotADiscCoil
            case IllegalAxialGap
        }
        
        /// Specialized information that can be added to the descritpion String (can be the empty string)
        let info:String
        /// The error type
        let type:errorType
        
        /// The error string to return with the error
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
                else if self.type == .UnimplementedInductanceMethod {
                    
                    return "DelVecchio inductance calculation method is not implemented!"
                }
                else if self.type == .CoilDoesNotExist {
                    
                    return "The coil does not exist!"
                }
                else if self.type == .NotADiscCoil {
                    
                    return "Expected a disc coil!"
                }
                else if self.type == .IllegalAxialGap {
                    
                    return "The axial gap is illegal. \(info)"
                }
                
                return "An unknown error occurred."
            }
        }
    }
    
    /// Designated initializer. Depending on the value of the 'useEslamianVahidi' parameter either a DelVecchio or EV-tyoe model will be created
    /// - Parameter segments: The segments that make up the basis for the model
    /// - Parameter core: The core (duh)
    /// - Parameter useEslamianVahidi: A Boolean to indicate whether the inductance model should be per the Eslamian & Vahidi paper (the default), or per the DelVecchio book.
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
    
    /// Get the axial index of the highest (max Z) section for the given coil
    func GetHighestSection(coil:Int) throws -> Int {
        
        guard let _ = Segment.SegmentAt(location: LocStruct(radial: coil, axial: 0), segments: self.segments) else {
            
            throw PhaseModelError(info: "", type: .CoilDoesNotExist)
        }
        
        var result = 0
        
        while Segment.SegmentAt(location: LocStruct(radial: coil, axial: result + 1), segments: self.segments) != nil {
            
            result += 1
        }
        
        return result
    }
    
    /// Get the gap between the bottom-most section of a coil and the next adjacent section.  If the coil at the given radial position is not a disc coil, an error is thrown.
    func StandardAxialGap(coil:Int) throws -> Double {
        
        guard let bottomMostDisc = Segment.SegmentAt(location: LocStruct(radial: coil, axial: 0), segments: self.segments) else {
            
            throw PhaseModelError(info: "", type: .CoilDoesNotExist)
        }
        
        if bottomMostDisc.wdgType != .disc && bottomMostDisc.wdgType != .helix {
            
            throw PhaseModelError(info: "", type: .NotADiscCoil)
        }
        
        guard let nextDisc = Segment.SegmentAt(location: LocStruct(radial: coil, axial: 1), segments: self.segments) else {
            
            throw PhaseModelError(info: "", type: .CoilDoesNotExist)
        }
        
        let result = nextDisc.z1 - bottomMostDisc.z2
        
        if result < 0.0 {
            
            throw PhaseModelError(info: "It is negative", type: .IllegalAxialGap)
        }
        
        return result
    }
    
    /// Calculate the inductance (M) matrix for the model, using the Eslamian & Vahidi method (DelVecchio is not implemented). Always pass 'true' to the parameter (or ignore it and it defaults it to true).
    func InductanceMatrix(useEslamianVahidi:Bool = true) throws -> PCH_BaseClass_Matrix  {
        
        // The DelVecchio method is not implemented so return an error if the useEslamianVahidi parameter is false
        if !useEslamianVahidi {
            
            throw PhaseModelError(info: "", type: .UnimplementedInductanceMethod)
        }
        
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
    
    /// Get the Fourier series representation of the current density for the coil (DelVecchio)
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

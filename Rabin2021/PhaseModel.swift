//
//  PhaseModel.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-13.
//

import Foundation

class PhaseModel:Codable {
    
    /// The segments that make up the model. This array is kept sorted by the LocStruct of the segments (radial first, then axial).
    private var segmentStore:[Segment]
    
    /// read-only access to the segment store
    var segments:[Segment] {
        get {
            return segmentStore
        }
    }
    
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
            case SegmentExists
            case SegmentNotInModel
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
                else if self.type == .SegmentExists {
                    
                    return "A segment already exists at location \(info)!"
                }
                else if self.type == .SegmentNotInModel {
                    
                    return "The segment does not exist in the model"
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
        
        self.segmentStore = segments.sorted(by: { lhs, rhs in
            
            if lhs.radialPos != rhs.radialPos {
                
                return lhs.radialPos < rhs.radialPos
            }
            
            return lhs.axialPos < rhs.axialPos
        })
        
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
    
    /// Insert a new Segment into the correct spot in the model to keep the segmentStore array sorted. If there is an existing Segment with the same LocStruct as the new one, this function throws an error.
    func InsertSegment(newSegment:Segment) throws {
        
        // use binary search method to insert (probably unnecessary, but what the hell)
        var lo = 0
        var hi = self.segmentStore.count - 1
        while lo <= hi {
            
            let mid = (lo + hi) / 2
            if self.segmentStore[mid].location < newSegment.location {
                
                lo = mid + 1
            }
            else if newSegment.location < self.segmentStore[mid].location {
                
                hi = mid - 1
            }
            else {
                
                // The location already exists, throw an error
                throw PhaseModelError(info: "\(newSegment.location)", type: .SegmentExists)
            }
        }
        
        self.segmentStore.insert(newSegment, at: lo)
    }
    
    /// Return the spaces above and below the given segment. If the segment is not in the model, throw an error.
    func SpacesAboutSegment(segment:Segment) throws -> (above: Double, below: Double) {
        
        guard let segIndex = self.segmentStore.firstIndex(of: segment) else {
            
            throw PhaseModelError(info: "", type: .SegmentNotInModel)
        }
        
        var aboveResult:Double = -1.0
        var belowResult:Double = -1.0
        
        do {
            
            if let staticRingAbove = try self.StaticRingAbove(segment: segment, recursiveCheck: true) {
                
                aboveResult = staticRingAbove.z1 - segment.z2
            }
            
            if let staticRingBelow = try self.StaticRingBelow(segment: segment, recursiveCheck: true) {
                
                belowResult = segment.z1 - staticRingBelow.z2
            }
            
            if aboveResult < 0.0 {
                
                let highest = try self.GetHighestSection(coil: segment.radialPos)
                if segment.axialPos == highest {
                    
                    aboveResult = segment.realWindowHeight - segment.z2
                }
                else {
                    
                    aboveResult = self.segmentStore[segIndex + 1].z1 - segment.z2
                }
            }
            
            if belowResult < 0.0 {
                
                if segment.axialPos == 0 {
                    
                    belowResult = segment.z1
                }
                else {
                    
                    belowResult = segment.z1 - self.segmentStore[segIndex - 1].z2
                }
            }
            
            return (aboveResult, belowResult)
        }
        catch {
            
            throw error
        }
    }
    
    /// Check if there is a static ring  above the given segment, and if so, return the segment - otherwise return nil. If the segment is not in the model, this function throws an error.
    /// - Parameter segment: The segment that we want to check
    /// - Parameter recursiveCheck: A Boolean to indicate whether we should check below the next segment as well (needed to avoid infinite loops)
    func StaticRingAbove(segment:Segment, recursiveCheck:Bool) throws -> Segment? {
        
        guard let segIndex = self.segmentStore.firstIndex(of: segment) else {
            
            throw PhaseModelError(info: "", type: .SegmentNotInModel)
        }
        
        var staticRingAbove:Segment? = nil
        
        // check the easy thing first, looking for a direct reference to a static ring
        let srAxial = segment.axialPos == 0 ? Int.min : -segment.axialPos
        let srLocation = LocStruct(radial: segment.radialPos, axial: srAxial)
        if let srSegment = self.SegmentAt(location: srLocation) {
            
            if srSegment.z1 > segment.z1 {
                
                staticRingAbove = srSegment
            }
        }
        
        // if this is the last segment, just return
        guard segIndex + 1 < self.segmentStore.count else {
            
            return staticRingAbove
        }
        
        // there might still be a static ring above, but it's been defined as being below the next segment in the array
        if staticRingAbove == nil && recursiveCheck && self.segmentStore[segIndex + 1].radialPos == segment.radialPos {
            
            staticRingAbove = try? StaticRingBelow(segment: self.segmentStore[segIndex + 1], recursiveCheck: false)
        }
        
        return staticRingAbove
    }
    
    /// Check if there is a static ring  below the given segment, and if so, return the segment - otherwise return nil. If the segment is not in the model, this function throws an error.
    /// - Parameter segment: The segment that we want to check
    /// - Parameter recursiveCheck: A Boolean to indicate whether we should check above the next segment as well (needed to avoid infinite loops)
    func StaticRingBelow(segment:Segment, recursiveCheck:Bool) throws -> Segment? {
        
        guard let segIndex = self.segmentStore.firstIndex(of: segment) else {
            
            throw PhaseModelError(info: "", type: .SegmentNotInModel)
        }
        
        var staticRingBelow:Segment? = nil
        
        // check the easy thing first, looking for a direct reference to a static ring
        let srAxial = segment.axialPos == 0 ? Int.min : -segment.axialPos
        let srLocation = LocStruct(radial: segment.radialPos, axial: srAxial)
        if let srSegment = self.SegmentAt(location: srLocation) {
            
            if srSegment.z1 < segment.z1 {
                
                staticRingBelow = srSegment
            }
        }
        
        // if this is the bottom-most segment of a coil, just return
        guard segment.axialPos > 0 else {
            
            return staticRingBelow
        }
        
        // there might still be a static ring below, but it's been defined as being above the previous segment in the array
        if staticRingBelow == nil && recursiveCheck && self.segmentStore[segIndex - 1].radialPos == segment.radialPos {
            
            staticRingBelow = try? StaticRingAbove(segment: self.segmentStore[segIndex - 1], recursiveCheck: false)
        }
        
        return staticRingBelow
    }
    
    
    /// Check if there is a Segment at the specified location and if so, return it (otherwise, return nil)
    func SegmentAt(location:LocStruct) -> Segment? {
        
        return self.segmentStore.first(where: {$0.location == location})
    }
    
    
    /// Get the axial index of the highest (max Z) section for the given coil
    func GetHighestSection(coil:Int) throws -> Int {
        
        guard let _ = self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "", type: .CoilDoesNotExist)
        }
        
        // I believe that this is in order but it should be tested
        let coilSections = self.segmentStore.filter({$0.radialPos == coil})
        
        return coilSections.last!.axialPos
    }
    
    
    /// Get the gap between the bottom-most section of a coil and the next adjacent section.  If the coil at the given radial position is not a disc coil, an error is thrown.
    func StandardAxialGap(coil:Int) throws -> Double {
        
        guard let bottomMostDisc = self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "", type: .CoilDoesNotExist)
        }
        
        if bottomMostDisc.wdgType != .disc && bottomMostDisc.wdgType != .helical {
            
            throw PhaseModelError(info: "", type: .NotADiscCoil)
        }
        
        guard let nextDisc = self.SegmentAt(location: LocStruct(radial: coil, axial: 1)) else {
            
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

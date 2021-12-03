//
//  PhaseModel.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-13.
//

import Foundation
import AppKit
import Accelerate

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
    
    /// An array of Eslamian Vahidi segments. Ultimately, there will probably be no reason to keep this around and it should be removed from the class.
    var evSegments:[EslamianVahidiSegment] = []
    
    /// The inductance matrix for the model
    var M:PCH_BaseClass_Matrix? = nil
    
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
            case ShieldingElementExists
            case NoRoomForShieldingElement
            case NotAShieldingElement
            case ArgAIsNotAMultipleOfArgB
            case OldSegmentCountIsNotOne
            case UnequalBasicSectionsPerSet
            case ArgumentIsZeroCount
            case IllegalLocation
            case IllegalConnector
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
                    
                    return "The coil '\(info)' does not exist!"
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
                else if self.type == .ShieldingElementExists {
                    
                    return "A \(info) already exists adjacent to the segment!"
                }
                else if self.type == .NoRoomForShieldingElement {
                    
                    return "There is no room for a \(info) adjacent to the segment!"
                }
                else if self.type == .NotAShieldingElement {
                    
                    return "The selected segment is not a \(info)"
                }
                else if self.type == .ArgAIsNotAMultipleOfArgB {
                    
                    return "The count of the larger of the arrays must be a multiple of the count of the other!"
                }
                else if self.type == .ArgumentIsZeroCount {
                    
                    return "At least one of the arrays passed to the routine have a count equal to zero."
                }
                else if self.type == .OldSegmentCountIsNotOne {
                    
                    return "Can only split one segment at a time"
                }
                else if self.type == .UnequalBasicSectionsPerSet {
                    
                    return "The number of basic sections in each segment must be the same!"
                }
                else if self.type == .IllegalLocation {
                    
                    return "The new segment is at an illegal location: \(info)"
                }
                
                
                return "An unknown error occurred."
            }
        }
    }
    
    /// Designated initializer.
    /// - Parameter segments: The segments that make up the basis for the model
    /// - Parameter core: The core (duh)
    init(segments:[Segment], core:Core) {
        
        self.segmentStore = segments.sorted(by: { lhs, rhs in
            
            if lhs.radialPos != rhs.radialPos {
                
                return lhs.radialPos < rhs.radialPos
            }
            
            return lhs.axialPos < rhs.axialPos
        })
        
        self.core = core
    }
    
    /// Function to check if two Segments are adjacent in the current model. This function assumes that the segmentStore is sorted according to location.
    func SegmentsAreAdjacent(segment1:Segment, segment2:Segment) -> Bool {
        
        guard segment1.radialPos == segment2.radialPos else {
            
            return false
        }
        
        guard let seg1index = self.segments.firstIndex(of: segment1), let seg2index = self.segments.firstIndex(of: segment2) else {
            
            return false
        }
        
        return abs(seg1index - seg2index) == 1
    }
    
    /// A routine to change the connectors in the model when newSegment(s) take(s) the place of oldSegment(s). It is assumed that the Segment arrays are contiguous and in order. The count of oldSegments must be a multiple of newSegments or the count of newSegmenst must be a multiple of oldSegments.  If both arguments only have a single Segment, it is assumed that the one in newSegment replaces the one in oldSegment. It is further assumed that the new Segments have _NOT_ been added to the model yet, but will be soon after calling this function. Any connector references to oldSegments that should be set to newSegments will be replaced in the model - however, the model itself (ie: the array of Segments in segmentStore) will not be changed.
    ///  - Note: If there is only a single oldSegment, only adjacent-segment connections are retained, and connections to non-Segments (like ground, etc) are trashed.
    func UpdateConnectors(oldSegments:[Segment], newSegments:[Segment]) throws {
        
        guard oldSegments.count > 0 && newSegments.count > 0 else {
            
            throw PhaseModelError(info: "", type: .ArgumentIsZeroCount)
        }
        
        var segmentMap:[Int:Segment] = [:]
        
        if newSegments.count <= oldSegments.count {
            
            if oldSegments.count % newSegments.count != 0 {
                
                throw PhaseModelError(info: "", type: .ArgAIsNotAMultipleOfArgB)
            }
            
            let oldSectionsPerNew = oldSegments.count / newSegments.count
            
            for newIndex in 0..<newSegments.count {
                
                let currentOldSegments = oldSegments[newIndex * oldSectionsPerNew..<newIndex * oldSectionsPerNew + oldSectionsPerNew]
                let firstOldSeg = currentOldSegments.first!
                let lastOldSeg = currentOldSegments.last!
                
                let newSeg = newSegments[newIndex]
                
                segmentMap[firstOldSeg.serialNumber] = newSeg
                segmentMap[lastOldSeg.serialNumber] = newSeg
                
                newSeg.connections = firstOldSeg.connections
                newSeg.connections.append(contentsOf: lastOldSeg.connections)
                
                // there may be old-segment references in the newSeg.connections array, get rid of them
                for nextOldSegment in currentOldSegments {
                    
                    newSeg.connections.removeAll(where: {$0.segment == nextOldSegment})
                }
            }
            
            for nextSegment in newSegments {
                
                for i in 0..<nextSegment.connections.count {
                    
                    if let refSeg = nextSegment.connections[i].segment {
                        
                        if let mappedSegment = segmentMap[refSeg.serialNumber] {
                            
                            nextSegment.connections[i].segment = mappedSegment
                        }
                    }
                }
            }
            
            for nextSegment in self.segments {
                
                for i in 0..<nextSegment.connections.count {
                    
                    if let refSeg = nextSegment.connections[i].segment {
                        
                        if let mappedSegment = segmentMap[refSeg.serialNumber] {
                            
                            nextSegment.connections[i].segment = mappedSegment
                        }
                    }
                }
            }
        }
        else if oldSegments.count == 1 {
            
            guard oldSegments[0].basicSections.count % newSegments.count == 0 else {
                
                throw PhaseModelError(info: "", type: .UnequalBasicSectionsPerSet)
            }
            
            let firstNewSegment = newSegments.first!
            let lastNewSegment = newSegments.last!
            
            // now we worry about replacing the old segment connections
            var connectionsWithSegments = oldSegments[0].connections.drop(while: { $0.segment == nil })
            
            do {
                
                for nextConnection in connectionsWithSegments {
                    
                    let compPos = try self.ComparativePosition(fromSegment: oldSegments[0], toSegment: nextConnection.segment!)
                    if compPos == .adjacentBelow {
                        
                        let prevSegment = nextConnection.segment!
                        for i in 0..<prevSegment.connections.count {
                            
                            if let nextPrevConnSeg = prevSegment.connections[i].segment {
                                
                                if nextPrevConnSeg == oldSegments[0] {
                                    
                                    prevSegment.connections[i].segment = firstNewSegment
                                    firstNewSegment.connections.append(nextConnection)
                                }
                            }
                        }
                    }
                    else if compPos == .adjacentAbove {
                        
                        let nextSegment = nextConnection.segment!
                        for i in 0..<nextSegment.connections.count {
                            
                            if let nextNextConnSeg = nextSegment.connections[i].segment {
                                
                                if nextNextConnSeg == oldSegments[0] {
                                    
                                    nextSegment.connections[i].segment = lastNewSegment
                                    lastNewSegment.connections.append(nextConnection)
                                }
                            }
                        }
                    }
                }
                
                // At this point, there are a few possibilities:
                // firstNewSegment either has no connections or exactly one. If it has one, we can go on. Otherwise, it means that it needs a floating 'toLocation' (it is the lowest of the axial sections for the coil). The actual location depends on whether lastNewSegment has a toLocation in it. If so (it may ALSO have no connections), the toLocation for firstNewSegment can be calculated depending on the coil type and (in the case of a disc coil), whether there are an even or odd number of new segments being added to the model. Similarly, if firstNewSegmnent has a connection, then its location can be used to determine lastNewSegments' toLocation connection.
                
                
                
            }
            catch {
                
                throw error
            }
            
        }
        else { // oldSegments.count < newSegments.count
            
            throw PhaseModelError(info: "", type: .OldSegmentCountIsNotOne)
            
        }
        
        
        
        
        
        
        print("New segment has \(newSegments[0].connections.count) connections")
    }
    
    /// Function to check the comparative position of 'toSegment' with respect to 'fromSegment'. For instance, if 'fromSegment;' is in coil position 2, and toSegment is in coil position 1, the function will return 'adjacentInner'. The 'toSegment' parameter must exit in the current model or an error is thrown. It is not necessary that the fromSegment exists in the model, but it must have the correct location (with repsect to the current model) set in it.
    func ComparativePosition(fromSegment:Segment, toSegment:Segment) throws -> Segment.ComparativePosition {
        
        guard self.segments.contains(toSegment) else {
            
            throw PhaseModelError(info: "", type: .SegmentNotInModel)
            
        }
        
        guard fromSegment.location != toSegment.location else {
            
            throw PhaseModelError(info: "There is already a Segment at that axial location.", type: .IllegalLocation)
        }
        
        let fromRadial = fromSegment.location.radial
        let toRadial = fromSegment.location.radial
        let radialDiff = fromRadial - toRadial
        
        let fromAxial = fromSegment.location.axial
        let toAxial = fromSegment.location.axial
        
        if radialDiff > 0 {
            
            if radialDiff == 1 {
                
                return .innerAdjacent
            }
            else {
                
                return .inner
            }
        }
        else if radialDiff < 0 {
            
            if radialDiff == -1 {
                
                return .outerAdjacent
            }
            else {
                
                return .outer
            }
        }
        else {
            
            let toIndex = self.segments.firstIndex(of: toSegment)!
            let prevIndex:Int? = toIndex > 0 && self.segments[toIndex - 1].location.radial == toRadial ? toIndex - 1 : nil
            let nextIndex:Int? = toIndex < self.segments.endIndex - 1 && self.segments[toIndex + 1].location.radial == toRadial ? toIndex + 1 : nil
            
            let axialDiff = fromAxial - toAxial
            
            if axialDiff > 0 {
                
                // 'toSegment' is below
                if let next = nextIndex {
                    
                    if self.segments[next].location.axial > fromAxial {
                        
                        return .adjacentBelow
                    }
                    else if self.segments[next].location.axial == fromAxial {
                        
                        throw PhaseModelError(info: "There is already a Segment at that axial location.", type: .IllegalLocation)
                    }
                }
                
                return .below
            }
            else if axialDiff < 0 {
                
                // toSegment is above
                if let prev = prevIndex {
                    
                    if self.segments[prev].location.axial < fromAxial {
                        
                        return .adjacentAbove
                    }
                    else if self.segments[prev].location.axial == fromAxial {
                        
                        throw PhaseModelError(info: "There is already a Segment at that axial location.", type: .IllegalLocation)
                    }
                }
                
                return .above
                
            }
            else {
                
                throw PhaseModelError(info: "There is already a Segment at that axial location.", type: .IllegalLocation)
            }
        }
    }
    
    
    /// Routine to check whether an array of Segments is contiguous. It is not necessary for the 'segments' array to be sorted.
    func SegmentsAreContiguous(segments:[Segment]) -> Bool {
        
        if segments.count == 0 {
            
            return false
        }
        
        if segments.count == 1 {
            
            return true
        }
        
        // sort the array the same way that the segmentStore property is sorted
        let sortedSegments = segments.sorted(by: { lhs, rhs in
            
            if lhs.radialPos != rhs.radialPos {
                
                return lhs.radialPos < rhs.radialPos
            }
            
            return lhs.axialPos < rhs.axialPos
        })
        
        // find the index of the first entry in the model
        if let firstIndex = self.segmentStore.firstIndex(of: sortedSegments[0]) {
            
            for i in 1..<sortedSegments.count {
                
                if firstIndex + i >= self.segmentStore.count {
                    
                    return false
                }
                
                if self.segmentStore[firstIndex + i] != sortedSegments[i] {
                    
                    return false
                }
            }
        }
        else {
            
            return false
        }
        
        // we've run the gauntlet, return true
        return true
    }
    
    func CalculateInductanceMatrix(useEVmodel:Bool = true) throws {
        
        guard self.segments.count > 0 else {
            
            throw PhaseModelError(info: "", type: .EmptyModel)
        }
        
        if useEVmodel {
            
            // We need to grab the main window pointer here, while we're still in the main loop
            let theMainWindow = NSApplication.shared.mainWindow
            
            if let progIndicator = rb2021_progressIndicatorWindow, let mainWindow = theMainWindow {
                
                progIndicator.UpdateIndicator(value: 0.0, minValue: 0.0, maxValue: Double(self.segments.count * 2), text: "Calculating current densities & vector potentials")
                
                mainWindow.beginSheet(progIndicator.window!, completionHandler: {responseCode in
                    DLog("Ended sheet")
                })
            }
            
            let mutIndQueue = DispatchQueue(label: "com.huberistech.rb2021_mutual_inductance_calculation")
            
            mutIndQueue.async {
                    
                    let evArray = EslamianVahidiSegment.Create_EV_Array(segments: self.segments, core: self.core)
                    
                    guard let indArray = try? EslamianVahidiSegment.InductanceMatrix(evSegments: evArray) else {
                        
                        PCH_ErrorAlert(message: "Error while creating Inductance Matrix!", info: "You are well and truly fucked!")
                        return
                    }
                
                    self.M = indArray
                
            
                if let progIndicator = rb2021_progressIndicatorWindow, let mainWindow = theMainWindow {
                    
                    DispatchQueue.main.sync { mainWindow.endSheet(progIndicator.window!) }
                }
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
    
    /// Check if there is a radial shield inside the given coil and if so, return it as a Segment
    func RadialShieldInside(coil:Int) throws -> Segment? {
        
        guard let _ = self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        let radialPos = coil == 0 ? Segment.negativeZeroPosition : -coil
        
        return self.SegmentAt(location: LocStruct(radial: radialPos, axial: 0))
    }
    
    /// Check if there a radial shield  outside the given coil and if so, return it as a Segment
    func RadialShieldOutside(coil:Int) throws -> Segment? {
        
        guard let _ = self.SegmentAt(location: LocStruct(radial: coil + 1, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil + 1)", type: .CoilDoesNotExist)
        }
        
        return self.SegmentAt(location: LocStruct(radial: -(coil + 1), axial: 0))
    }
    
    /// Get the Hilo under the given coil
    func HiloUnder(coil:Int) throws -> Double {
        
        guard let segment = self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        let coilInnerRadius = segment.r1
        
        if segment.radialPos == 0 {
            
            return coilInnerRadius - self.core.radius
        }
        else {
            
            guard let innerSegment = self.SegmentAt(location: LocStruct(radial: coil - 1, axial: 0)) else {
                
                throw PhaseModelError(info: "\(coil - 1)", type: .CoilDoesNotExist)
            }
            
            return coilInnerRadius - innerSegment.r2
        }
    }
    
    /// Return the spaces above and below the given segment. If the segment is not in the model, throw an error.
    func AxialSpacesAboutSegment(segment:Segment) throws -> (above: Double, below: Double) {
        
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
    
    /// Try to add a radial shield inside the given coil and return it as a Segment. If unsuccessful, the function throws an error.
    func AddRadialShieldInside(coil:Int, hiloToShield:Double) throws -> Segment {
        
        guard let segment = self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        // check if there is already a radial shield under the coil
        let radPos = coil == 0 ? Segment.negativeZeroPosition : -coil
        guard self.SegmentAt(location: LocStruct(radial: radPos, axial: 0)) == nil else {
            
            throw PhaseModelError(info: "Radial Shield", type: .ShieldingElementExists)
        }
        
        do {
            
            let requiredSpace = hiloToShield + 0.002
            let availableSpace = try self.HiloUnder(coil: coil)
            
            if requiredSpace >= availableSpace {
                
                throw PhaseModelError(info: "Radial Shield", type: .NoRoomForShieldingElement)
            }
            
            let highestSegmentIndex = try self.GetHighestSection(coil: coil)
            guard let highestSegment = self.SegmentAt(location: LocStruct(radial: coil, axial: highestSegmentIndex)) else {
                
                throw PhaseModelError(info: "", type: .SegmentNotInModel)
            }
            
            let height = highestSegment.z2 - segment.z1
            
            let radialShield = try Segment.RadialShield(adjacentSegment: segment, hiloToSegment: hiloToShield, elecHt: height)
            
            return radialShield
            
        }
        catch {
            
            throw error
        }
    }
    
    /// Try to add a static ring either above or below the adjacent Segment. If unsuccessful, this function throws an error.
    func AddStaticRing(adjacentSegment:Segment, above:Bool, staticRingThickness:Double? = nil, gapToStaticRing:Double? = nil) throws -> Segment {
        
        guard let _ = self.segmentStore.firstIndex(of: adjacentSegment) else {
            
            throw PhaseModelError(info: "", type: .SegmentNotInModel)
        }
        
        do {
            
            // check if there is already a static ring above/below the adjacent segment
            if above {
                
                if let _ = try StaticRingAbove(segment: adjacentSegment, recursiveCheck: true) {
                    
                    throw PhaseModelError(info: "Static Ring", type: .ShieldingElementExists)
                }
                
            }
            else {
                
                if let _ = try StaticRingBelow(segment: adjacentSegment, recursiveCheck: true) {
                    
                    throw PhaseModelError(info: "Static Ring", type: .ShieldingElementExists)
                }
            }
        
            let axialSpaces = try self.AxialSpacesAboutSegment(segment: adjacentSegment)
            let gapToRing = gapToStaticRing != nil ? gapToStaticRing! : try self.StandardAxialGap(coil: adjacentSegment.location.radial) / 2
            let srThickness = staticRingThickness != nil ? staticRingThickness! : Segment.stdStaticRingThickness
            let requiredSpace = gapToRing + srThickness
            
            if (above && requiredSpace >= axialSpaces.above) || (!above && requiredSpace >= axialSpaces.below) {
                
                throw PhaseModelError(info: "Static Ring", type: .NoRoomForShieldingElement)
            }
            
            // There is room for the static ring, so try creating it
            let newRing = try Segment.StaticRing(adjacentSegment: adjacentSegment, gapToSegment: gapToRing, staticRingIsAbove: above, staticRingThickness: srThickness)
            
            // if we get here, we know that the call was succesful
            return newRing
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
        
        // if this is the last segment in the whole model, just return
        guard segIndex + 1 < self.segmentStore.count else {
            
            return staticRingAbove
        }
        
        // there might still be a static ring above, but it's been defined as being below the next segment in the array (and there is not a gap there, which is defined as anything greater or equal to 25mm)
        if staticRingAbove == nil && recursiveCheck && self.segmentStore[segIndex + 1].radialPos == segment.radialPos && self.segmentStore[segIndex + 1].z1 - segment.z2 < 0.025 {
            
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
        
        // there might still be a static ring below, but it's been defined as being above the previous segment in the array (and there is not a gap there, which is defined as anything greater or equal to 25mm)
        if staticRingBelow == nil && recursiveCheck && self.segmentStore[segIndex - 1].radialPos == segment.radialPos && segment.z1 - self.segmentStore[segIndex - 1].z2 < 0.025 {
            
            staticRingBelow = try? StaticRingAbove(segment: self.segmentStore[segIndex - 1], recursiveCheck: false)
        }
        
        return staticRingBelow
    }
    
    /// Function to remove a radial shield
    func RemoveRadialShield(radialShield:Segment) throws {
        
        guard let rsIndex = self.segmentStore.firstIndex(of: radialShield) else {
            
            throw PhaseModelError(info: "", type: .SegmentNotInModel)
        }
        
        guard radialShield.isRadialShield else {
            
            throw PhaseModelError(info: "Radial Shie;d", type: .NotAShieldingElement)
        }
        
        self.segmentStore.remove(at: rsIndex)
    }
    
    /// Function to remove a static ring
    func RemoveStaticRing(staticRing:Segment) throws {
        
        guard let srIndex = self.segmentStore.firstIndex(of: staticRing) else {
            
            throw PhaseModelError(info: "", type: .SegmentNotInModel)
        }
        
        guard staticRing.isStaticRing else {
            
            throw PhaseModelError(info: "Static Ring", type: .NotAShieldingElement)
        }
        
        self.segmentStore.remove(at: srIndex)
    }
    
    /// Function to add a collection of Segments to the store. The array can be in any order - the routine will ensure that the Segments are inserted at the correct place in the store. If a Segment cannot be inserted, an error is thrown. The routine will reset the model to whatever it was before the call was attempted (which may or may not be a stable model).
    func AddSegments(newSegments:[Segment]) throws {
        
        do {
            
            for nextSegment in newSegments {
            
                try self.InsertSegment(newSegment: nextSegment)
            }
        }
        catch {
            
            self.RemoveSegments(badSegments: newSegments)
            
            throw error
        }
    }
    
    /// Function to remove a collection of Segments from the store. Any Segments that are not actually in the store are ignored
    func RemoveSegments(badSegments:[Segment]) {
        
        for nextSegment in badSegments {
            
            guard let nsegIndex = self.segmentStore.firstIndex(of: nextSegment) else {
                
                continue
            }
            
            self.segmentStore.remove(at: nsegIndex)
        }
    }
    
    
    /// Check if there is a Segment at the specified location and if so, return it (otherwise, return nil)
    func SegmentAt(location:LocStruct) -> Segment? {
        
        return self.segmentStore.first(where: {$0.location == location})
    }
    
    
    /// Get the axial index of the highest (max Z) section for the given coil
    func GetHighestSection(coil:Int) throws -> Int {
        
        guard let _ = self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        // I believe that this is in order but it should be tested
        let coilSections = self.segmentStore.filter({$0.radialPos == coil})
        
        return coilSections.last!.axialPos
    }
    
    
    /// Get the gap between the bottom-most section of a coil and the next adjacent section.  If the coil at the given radial position is not a disc coil, an error is thrown.
    func StandardAxialGap(coil:Int) throws -> Double {
        
        guard let bottomMostDisc = self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        if bottomMostDisc.wdgType != .disc && bottomMostDisc.wdgType != .helical {
            
            throw PhaseModelError(info: "", type: .NotADiscCoil)
        }
        
        guard let nextDisc = self.SegmentAt(location: LocStruct(radial: coil, axial: 1)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        let result = nextDisc.z1 - bottomMostDisc.z2
        
        if result < 0.0 {
            
            throw PhaseModelError(info: "It is negative", type: .IllegalAxialGap)
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

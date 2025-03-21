//
//  PhaseModel.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-13.
//

import Foundation
import AppKit
import Accelerate
import ComplexModule
import RealModule
import PchBasePackage
import PchMatrixPackage
import PchFiniteElementPackage

actor PhaseModel /*:Codable */ {
    
    /// The segments that make up the model. This array is kept sorted by the LocStruct of the segments (radial first, then axial).
    private var segmentStore:[Segment]
    
    /// read-only access to the segment store
    var segments:[Segment] {
        get {
            return segmentStore
        }
    }
    
    /// The set of nodes in the model
    private var nodeStore:[Node] = []
    
    /// read-only access to the node store
    var nodes:[Node] {
        get {
            return nodeStore
        }
    }
    
    /// The core for the model
    let core:Core
    
    /// An array of arrays where the first index is the segment number and the second index (i) is J[i] for the segment (used for DelVecchio only)
    // var J:[[Double]] = []
    
    /// An array of Eslamian Vahidi segments. Ultimately, there will probably be no reason to keep this around and it should be removed from the class.
    //var evSegments:[EslamianVahidiSegment] = []
    
    /// The A-matrix as defined in DelVecchio, with rows corresponding to nodes and columns corresponding to sections
    var A:PchMatrix? = nil
    
    /// The B-matrix as defined in DelvVecchio, with rows corresponding to sections and columns corresponding to nodes.
    /// This matrix is multiplied by the voltage vector to yield the voltage drop across each section. The matrix is made up of 1's and -1's to achieve this.
    var B:PchMatrix? = nil
    
    /// The inductance for the model in unfactored form. 
    var unfactoredM:PchMatrix? = nil
    
    /// The inductance matrix for the model. **NOTE: This matrix is in Cholesky-factorized form
    var M:PchMatrix? = nil
    
    /// Set the inductance matrices
    func SetInductanceMatrices(unfactoreM:PchMatrix? = nil, M:PchMatrix? = nil) {
        
        self.unfactoredM = unfactoreM
        self.M = M
    }
    
    /// The basic (unmodified) capacitance matrix for the model
    var C:PchMatrix? = nil
    
    /// The 'fixed' capacitance matrix (used by the actual simulation)
    var fixedC:PchMatrix? = nil
    
    func SetFixedC(newFixedC:PchMatrix) {
        
        self.fixedC = newFixedC
    }
    /// The window height to actually use
    var useWindowHeight:Double {
        
        return self.core.adjustedWindHt
    }
    
    /// The real window height of the core
    var realWindowHeight:Double {
        
        return self.core.realWindowHeight
    }
    
    // value needed for calculation of outermost coil shunt capacitances
    let tankDepth:Double
    
    /// Errors that can be thrown by some routines
    struct PhaseModelError:LocalizedError
    {
        /// The different error types that are available
        enum errorType
        {
            case UnknownError
            case UnimplementedInductanceMethod
            case EmptyModel
            case IllegalMatrix
            case CoilDoesNotExist
            case NotADiscCoil
            case IllegalAxialGap
            case SegmentExists
            case SegmentNotInModel
            case ShieldingElementExists
            case OnlyOneStaticRingAllowed
            case NoRoomForShieldingElement
            case NotAShieldingElement
            case ArgAIsNotAMultipleOfArgB
            case OldSegmentCountIsNotOne
            case UnequalBasicSectionsPerSet
            case ArgumentIsZeroCount
            case IllegalLocation
            case IllegalConnector
            case TooManyConnectors
            case CapacitanceNotCalculated
            case NodeHasNoSegments
            case SameCoilTwice
            case SegmentIsShieldingElement
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
                else if self.type == .TooManyConnectors {
                    
                    return "The segment at \(info) has too many connectors associated with it!"
                }
                else if self.type == .OnlyOneStaticRingAllowed {
                    
                    return "At this time, only one static ring is allowed to be adjacent to a disc (winding discs are not implemented). \(info)"
                }
                else if self.type == .CapacitanceNotCalculated {
                    
                    return "The capacitance for coil \(info) has not been calculated!"
                }
                else if self.type == .NodeHasNoSegments {
                    
                    return "The node \(info) has no Segments associated with it!"
                }
                else if self.type == .SameCoilTwice {
                    
                    return "The same coil has been used for both parameters (they must be different)."
                }
                else if self.type == .SegmentIsShieldingElement {
                    
                    return "The segment specified is a static ring or radial shield."
                }
                
                let extraInfo = info != "" ? " Added info: \(info)" : ""
                return "An unknown error occurred.\(extraInfo)"
            }
        }
    }
    
    /// Designated initializer.
    /// - Parameter segments: The segments that make up the basis for the model
    /// - Parameter core: The core (duh)
    init(segments:[Segment], core:Core, tankDepth:Double) {
        
        self.segmentStore = segments.sorted(by: { lhs, rhs in
            
            if lhs.radialPos != rhs.radialPos {
                
                return lhs.radialPos < rhs.radialPos
            }
            
            return lhs.axialPos < rhs.axialPos
        })
        
        self.core = core
        
        self.tankDepth = tankDepth
    }
    
    /// Get the array of segments excluding shielding elements
    func CoilSegments() -> [Segment] {
        
        var result = self.segmentStore
        
        result.removeAll(where: {$0.radialPos < 0 || $0.axialPos < 0})
        
        return result
    }
    
    /// The number of coils in the model
    func CoilCount() -> Int {
        
        guard let finalSegment = self.segmentStore.last(where: {$0.radialPos >= 0 || $0.axialPos >= 0}) else {
            
            DLog("No coils!")
            return -1
        }
        
        return finalSegment.radialPos + 1
    }
    
    /// Get the range of the segments that make up the given coil, as a closed range of the indices into the inductance matrix, with lowerbound equal to the lowest disc and upperbound equal to the highest
    func SegmentRange(coil:Int) async throws -> ClosedRange<Int> {
        
        guard let _ = await self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        // let coilSegments = CoilSegments()
        
        do {
            
            var lowBound = 0
            for i in 0..<coil {
                
                await lowBound += try GetHighestSection(coil: i) + 1
            }
            
            let highestSegment = try await GetHighestSection(coil: coil)
            let highBound = lowBound + highestSegment
            
            return ClosedRange(uncheckedBounds: (lowBound, highBound))
        }
        catch {
            
            throw error
        }
    }
    
    /// Return the index into the inductance matrix for the given Segment
    func SegmentIndex(segment:Segment) async throws -> Int {
        
        guard self.segments.contains(segment) else {
            
            throw PhaseModelError(info: "", type: .SegmentNotInModel)
        }
        
        guard !segment.isStaticRing && !segment.isRadialShield else {
            
            throw PhaseModelError(info: "Illegal Segment!", type: .SegmentIsShieldingElement)
        }
        
        var result = 0
        
        do {
            for i in 0..<segment.radialPos {
                
                await result += try GetHighestSection(coil: i)
                result += 1
            }
        }
        catch {
            
            throw error
        }
        
        result += segment.axialPos
        
        return result
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
    
    /// Return an array of non-axially-adjacent connections (and tapping gap connections added by the user - these will be adjacent, but for the purposes of the simulation they will not be)  that come to one of the segment's terminals. This is useful when "fixing" the C-array since the axial-adjacent connections are taken care of _implicitly_ in the array, while connections to other coils, non-adjacent discs, or impulse/ground need to be _explicity_ handled
    func NonAdjacentConnections(segment:Segment) async -> [Segment.Connection] {
        
        var result:[Segment.Connection] = []
        
        for nextConnection in await segment.connections {
            
            if let connSegID = nextConnection.segmentID {
                
                guard let connSeg = self.segmentStore.first(where: { $0.serialNumber == connSegID }) else {
                    
                    return result
                }
                // If the segments aren't adjacent or they are a tapping gap, add the connection
                // Note that the 'await'-able call has to go first in an 'or' statement (??)
                if await self.IsTappingGap(segment1: segment, segment2: connSeg) || !SegmentsAreAdjacent(segment1: segment, segment2: connSeg) {
                    
                    result.append(nextConnection)
                }
            }
        }
        
        return result
    }
    
    func IsTappingGap(segment1:Segment, segment2:Segment) async -> Bool {
        
        // the idea here is to check if there are "floating" connections between the two segments, and if so, this must be a tapping gap (used for offload taps)
        
        // take care of the case where these are not even adjacent, which is handled differently
        guard SegmentsAreAdjacent(segment1: segment1, segment2: segment2) else {
            
            return false
        }
        
        // sort the segments by their axial positions
        var segments = [segment1, segment2]
        segments.sort(by: {$0.axialPos < $1.axialPos})
        
        for nextConnection1 in await segments[0].connections {
            
            if !nextConnection1.connector.fromIsLower && nextConnection1.connector.toLocation == .floating {
                
                for nextConnection2 in await segments[1].connections {
                    
                    if !nextConnection2.connector.fromIsUpper && nextConnection2.connector.toLocation == .floating {
                        
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    /// The serial-number-using version of NodeAt() [see next function]
    func NodeAt(segmentID:Int, useFrom:Bool, connector:Connector) -> Node? {
        
        guard let segment = self.segments.first(where: {$0.serialNumber == segmentID}) else {
            
            return nil
        }
        
        return self.NodeAt(segment: segment, useFrom: useFrom, connector: connector)
    }
    
    /// A function to return the node that is connected to the given segment at the given location.
    /// - Parameter segment: The segment that connects to the node
    /// - Parameter useFrom: If true, use the 'from...' field of 'connector', otherwise use the 'to...' field
    /// - Parameter connector: The connector to check
    /// - Returns: If the node exists, the Node; otherwise nil
    func NodeAt(segment:Segment, useFrom:Bool, connector:Connector) -> Node? {
        
        
        let connIsUpper = useFrom ? connector.fromIsUpper : connector.toIsUpper
        let connIsLower = useFrom ? connector.fromIsLower : connector.toIsLower
        
        for nextNode in nodeStore {
            
            // coding gymnastics for floating connectors that are on the outside_center or inside_center (used for center-taping gaps)
            if !(connIsLower || connIsUpper) {
                
                if nextNode.belowSegment == segment && nextNode.aboveSegment == nil || nextNode.aboveSegment == segment && nextNode.belowSegment == nil {
                    
                    return nextNode
                }
            }
            
            if nextNode.aboveSegment == segment {
                
                if connIsLower {
                    
                    return nextNode
                }
            }
            else if nextNode.belowSegment == segment {
                
                if connIsUpper {
                    
                    return nextNode
                }
            }
        }
        
        return nil
    }
    
    func NodeAt_old(fromSegment:Segment, toSegment:Segment?, connection:Segment.Connection) -> Node? {
        
        for nextNode in nodes {
            
            if nextNode.aboveSegment != fromSegment && nextNode.belowSegment != fromSegment {
                
                continue
            }
            else if nextNode.aboveSegment == fromSegment {
                
                if !connection.connector.fromIsLower {
                    
                    continue
                }
                
                if let otherSegment = toSegment {
                    
                    if nextNode.belowSegment == otherSegment && connection.connector.toIsUpper {
                        
                        return nextNode
                    }
                }
            }
            else if nextNode.belowSegment == fromSegment {
                
                if !connection.connector.fromIsUpper {
                    
                    continue
                }
                
                if let otherSegment = toSegment {
                    
                    if nextNode.aboveSegment == otherSegment && connection.connector.toIsLower {
                        
                        return nextNode
                    }
                }
            }
            
            // at this point, if fromSegment and toSegment are axially adjacent and the connection parameter was such that the only possible node was the "shared" node, that node would already have been returned
            
            if let otherSegment = toSegment {
                
                
            }
            else {
                
                // This is a bit ugly. We will return the first node that connects to fromSegment and matches all the connector criteria.
                if nextNode.aboveSegment == fromSegment {
                    
                    if !connection.connector.fromIsUpper {
                        
                        return nextNode
                    }
                }
                else {
                    
                    if !connection.connector.fromIsLower {
                        
                        return nextNode
                    }
                }
            }
            
        }
        
        return nil
    }
    
    /// Function to determine if there is a shared node between two segments (as in when two adjacent discs are actually connected together)
    /// - Parameter segment1: The first segment to consider
    /// - Parameter segment2: The other segment to consider
    /// - returns: True if a shared node exists, otherwise false
    /// - Note: If segment1 and segment2 are not adjacent, this function returns false
    func SharedNodeExists(segment1:Segment, segment2:Segment) -> Bool {
        
        guard SegmentsAreAdjacent(segment1: segment1, segment2: segment2) else {
            
            return false
        }
        
        var segments = [segment1, segment2]
        segments.sort(by: {$0.axialPos < $1.axialPos})
        
        let aboveNodeLowerSegment = AdjacentNodes(to: segments[0]).above
        let belowNodeUpperSegment = AdjacentNodes(to: segments[1]).below
        
        return aboveNodeLowerSegment == belowNodeUpperSegment
    }
    
    /// Function to return the shared node between two axially-adjacent segments, if any
    /// - Parameter segment1: The first segment to consider
    /// - Parameter segment2: The other segment to consider
    /// - returns: An optional value equal to the shared node (if it exists), otherwise nil
    /// - Note: If segment1 and segment2 are not adjacent, this function returns nil
    func SharedNode(segment1:Segment, segment2:Segment) -> Node? {
        
        if SharedNodeExists(segment1: segment1, segment2: segment2) {
            
            var segments = [segment1, segment2]
            segments.sort(by: {$0.axialPos < $1.axialPos})
            
            let aboveNodeLowerSegment = AdjacentNodes(to: segments[0]).above
            return self.nodeStore[aboveNodeLowerSegment]
        }
        
        return nil
    }
    
    /// Function return the nodes directly associated with a segment . The nodes are returned as integer indices into the voltage matrix
    /// - Parameter to: A segment in the model (this must not be a shielding element, otherwise an error occurs)
    /// - Note: The segment passed to the routine must not be either a static ring or a radial shield. It is an error to pass a shielding element.
    func AdjacentNodes(to:Segment) -> (below:Int, above:Int) {
        
        guard !to.isStaticRing && !to.isRadialShield else {
            
            ALog("Shielding elements do not have NODES!")
            return (-1, -1)
        }
        
        guard let belowNode = nodes.first(where: { $0.aboveSegment == to }), let aboveNode = nodes.first(where: { $0.belowSegment == to }) else {
            
            DLog("No nodes match the segment!")
            return (-1, -1)
        }
        
        return (belowNode.number, aboveNode.number)
    }
    
    /// Function to return the axially adjacent Segments below and above the given Segment
    func AxiallyAdjacentSegments(to:Segment) async throws -> (below:Segment?, above:Segment?) {
        
        do {
            
            let segmentIndex = try await self.SegmentIndex(segment: to)
            let belowIndex = segmentIndex - 1
            let aboveIndex = segmentIndex == self.segments.count - 1 ? -1 : segmentIndex + 1
            
            let belowSegment:Segment? = belowIndex < 0 ? nil : self.segments[belowIndex]
            let aboveSegment:Segment? = aboveIndex < 0 ? nil : self.segments[aboveIndex]
            
            return (belowSegment, aboveSegment)
        }
        catch {
            
            throw error
        }
    }
    
    /// Calculate the A matrix, save it to Aand return it. NOTE: In practice, I doubt that it is actually worth creating this matrix and multiplying it by the I (current) vector. It is probably better to simply maintain a current-drop vector - TBD.
    /*
    func GetAmatrix() throws -> PchMatrix {
        
        guard !nodes.isEmpty && !segments.isEmpty else {
            
            throw PhaseModelError(info: "", type: .EmptyModel);
        }
        
        let newA = PchMatrix(matrixType: .general, numType: .Double, rows: UInt(nodes.count), columns: UInt(segments.count))
        
        for nextNode in nodes {
            
            if let belowSegment = nextNode.belowSegment {
                
                do {
                    
                    let column = try SegmentIndex(segment: belowSegment)
                    newA[nextNode.number, column] = 1.0
                }
                catch {
                    
                    throw error
                }
            }
            
            if let aboveSegment = nextNode.aboveSegment {
                
                do {
                    
                    let column = try SegmentIndex(segment: aboveSegment)
                    newA[nextNode.number, column] = -1.0
                }
                catch {
                    
                    throw error
                }
            }
        }
        
        self.A = newA
        return newA
    } */
    
    /// Calculate the B matrix, save it to B and return it. NOTE: In practice, I doubt that it is actually worth creating this matrix and multiplying it by the Voltage vector. It is probably better to simply maintain a voltage-drop vector - TBD.
    func GetBmatrix() async throws -> PchMatrix {
        
        guard !segments.isEmpty else {
            
            throw PhaseModelError(info: "", type: .EmptyModel);
        }
        
        let newB = PchMatrix(matrixType: .general, numType: .Double, rows: UInt(segments.count), columns: UInt(nodes.count));
        
        for nextNode in nodes {
            
            if let aboveSeg = nextNode.aboveSegment {
                
                do {
                    
                    let row = try await SegmentIndex(segment: aboveSeg)
                    await newB.SetDoubleValue(value: 1.0, row: row, col: nextNode.number)
                    // newB[row, nextNode.number] = 1.0
                }
                catch {
                    
                    throw error
                }
            }
            
            if let belowSegment = nextNode.belowSegment {
                
                do {
                    
                    let row = try await SegmentIndex(segment: belowSegment)
                    await newB.SetDoubleValue(value: -1.0, row: row, col: nextNode.number)
                    // newB[row, nextNode.number] = -1.0
                }
                catch {
                    
                    throw error
                }
            }
        }
        
        self.B = newB
        return newB
    }
    
    /// Function to return all nodes in the model that are _directly_ connected to one of impulse, ground, or floating via a Segment.connection to one of those locations.
    func NodesOfType(connType:Connector.Location) async -> [Node] {
        
        var result:[Node] = []
        
        for nextNode in nodes {
            
            if let aboveSegment = nextNode.aboveSegment, let belowSegment = nextNode.belowSegment {
                
                var addedNode = false
                // in this case, only ground and impulse are possible
                if connType == .impulse || connType == .ground {
                    
                    for nextConnection in await aboveSegment.connections {
                        
                        if nextConnection.connector.fromIsLower && nextConnection.connector.toLocation == connType {
                            
                            result.append(nextNode)
                            addedNode = true
                            break
                        }
                    }
                    
                    if !addedNode {
                        
                        for nextConnection in await belowSegment.connections {
                            
                            if nextConnection.connector.fromIsUpper && nextConnection.connector.toLocation == connType {
                                
                                result.append(nextNode)
                                break
                            }
                        }
                    }
                    
                }
            }
            else if let aboveSegment = nextNode.aboveSegment {
                
                // belowSegment is nil
                for nextConnection in await aboveSegment.connections {
                    
                    if !nextConnection.connector.fromIsUpper && nextConnection.connector.toLocation == connType {
                        
                        result.append(nextNode)
                        break
                    }
                }
            }
            else if let belowSegment = nextNode.belowSegment {
                
                // aboveSegment is nil
                for nextConnection in await belowSegment.connections {
                    
                    if !nextConnection.connector.fromIsLower && nextConnection.connector.toLocation == connType {
                        
                        result.append(nextNode)
                        break
                    }
                }
            }
        }
        
        return result
    }
    
    /// A routine to change the connectors in the model when newSegment(s) take(s) the place of oldSegment(s). It is assumed that the Segment arrays are contiguous and in order. The count of oldSegments must be a multiple of newSegments or the count of newSegmenst must be a multiple of oldSegments.  If both arguments only have a single Segment, it is assumed that the one in newSegment replaces the one in oldSegment. It is further assumed that the new Segments have _NOT_ been added to the model yet, but will be soon after calling this function. Any connector references to oldSegments that should be set to newSegments will be replaced in the model - however, the model itself (ie: the array of Segments in segmentStore) will not be changed.
    ///  - Note: If there is only a single oldSegment, only adjacent-segment connections are retained, and connections to non-Segments (like ground, etc) are trashed.
    func UpdateConnectors(oldSegments:[Segment], newSegments:[Segment]) async throws {
        
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
                
                await newSeg.SetConnections(connections: firstOldSeg.connections + lastOldSeg.connections)
                //newSeg.connections.append(contentsOf: lastOldSeg.connections)
                
                // there may be old-segment references in the newSeg.connections array, get rid of them
                for nextOldSegment in currentOldSegments {
                    
                    await newSeg.RemoveConnectionsWithID(nextOldSegment.serialNumber)
                    //newSeg.connections.removeAll(where: {$0.segment == nextOldSegment})
                }
            }
            
            for nextSegment in newSegments {
                
                for i in await 0..<nextSegment.connections.count {
                    
                    if let refSegID = await nextSegment.connections[i].segmentID {
                        
                        if segmentMap[refSegID] != nil {
                            
                            await nextSegment.SetSegmentIDforConnectionAt(i, newID: refSegID)
                        }
                    }
                }
            }
            
            /*
            for nextSegment in newSegments {
                
                for i in 0..<nextSegment.connections.count {
                    
                    if let refSeg = nextSegment.connections[i].segment {
                        
                        if let mappedSegment = segmentMap[refSeg.serialNumber] {
                            
                            nextSegment.connections[i].segment = mappedSegment
                        }
                    }
                }
            } */
            
            for nextSegment in self.segments {
                
                for i in await 0..<nextSegment.connections.count {
                    
                    if let refSegID = await nextSegment.connections[i].segmentID {
                        
                        if segmentMap[refSegID] != nil {
                            
                            await nextSegment.SetSegmentIDforConnectionAt(i, newID: refSegID)
                        }
                    }
                }
            }
            /*
            for nextSegment in self.segments {
                
                for i in 0..<nextSegment.connections.count {
                    
                    if let refSeg = nextSegment.connections[i].segment {
                        
                        if let mappedSegment = segmentMap[refSeg.serialNumber] {
                            
                            nextSegment.connections[i].segment = mappedSegment
                        }
                    }
                }
            } */
        }
        else if oldSegments.count == 1 {
            
            guard  newSegments.count % oldSegments[0].basicSections.count == 0 else {
                
                throw PhaseModelError(info: "", type: .UnequalBasicSectionsPerSet)
            }
            
            let firstNewSegment = newSegments.first!
            let lastNewSegment = newSegments.last!
            
            // now we worry about replacing the old segment connections
            var connectionsWithSegments = await oldSegments[0].connections
            connectionsWithSegments.removeAll(where: {$0.segmentID == nil})
            
            do {
                
                for nextConnection in connectionsWithSegments {
                    
                    guard let nextConnSegment = segmentStore.first(where: { $0.serialNumber == nextConnection.segmentID}) else {
                        
                        throw PhaseModelError(info: "", type: .SegmentNotInModel)
                    }
                    
                    let compPos = try await self.ComparativePosition(fromSegment: oldSegments[0], toSegment: nextConnSegment)
                    if compPos == .adjacentBelow || compPos == Segment.ComparativePosition.top {
                        
                        let prevSegment = nextConnSegment
                        for i in await 0..<prevSegment.connections.count {
                            
                            if let nextPrevConnSegID = await prevSegment.connections[i].segmentID {
                                
                                if nextPrevConnSegID == oldSegments[0].serialNumber {
                                    
                                    await prevSegment.SetSegmentIDforConnectionAt(i, newID: firstNewSegment.serialNumber)
                                    await firstNewSegment.AppendConnection(connection: nextConnection)
                                    // prevSegment.connections[i].segment = firstNewSegment
                                    // firstNewSegment.connections.append(nextConnection)
                                }
                            }
                        }
                    }
                    else if compPos == .adjacentAbove || compPos == Segment.ComparativePosition.bottom {
                        
                        guard let nextSegmentID = nextConnection.segmentID, let nextSegment = segments.first(where: { $0.serialNumber == nextSegmentID }) else {
                            
                            throw PhaseModelError(info: "", type: .SegmentNotInModel)
                        }
                        for i in await 0..<nextSegment.connections.count {
                            
                            if let nextNextConnSegID = await nextSegment.connections[i].segmentID {
                                
                                if nextNextConnSegID == oldSegments[0].serialNumber {
                                    
                                    await nextSegment.SetSegmentIDforConnectionAt(i, newID: lastNewSegment.serialNumber)
                                    await lastNewSegment.AppendConnection(connection: nextConnection)
                                    // nextSegment.connections[i].segment = lastNewSegment
                                    // lastNewSegment.connections.append(nextConnection)
                                }
                            }
                        }
                    }
                }
                
                var connectionCountGreaterThanOne:Bool = await firstNewSegment.connections.count > 1
                if await lastNewSegment.connections.count > 1 || connectionCountGreaterThanOne {
                    
                    ALog("Fuckin' shit!")
                }
                
                // At this point, there are a few possibilities:
                // firstNewSegment either has no connections or exactly one. If it has one, we can go on. Otherwise, it means that it needs a floating 'toLocation' (it is the lowest of the axial sections for the coil). The fromLocation depends on whether lastNewSegment has a fromLocation in it. If so (it may ALSO have no connections), the fromLocation for firstNewSegment can be calculated depending on the coil type and (in the case of a disc coil), whether there are an even or odd number of new segments being added to the model. Similarly, if firstNewSegmnent has a connection, then its lower fromLocation can be used to determine lastNewSegments' fromLocation connection.
                
                var newIncomingConnector:Connector? = await firstNewSegment.connections.count > 0 ? firstNewSegment.connections[0].connector : nil
                var newOutgoingConnector:Connector? = await lastNewSegment.connections.count > 0 ? lastNewSegment.connections[0].connector : nil
                
                // get all the basic sections in the newSegments array
                var newBasicSections:[BasicSection] = []
                for nextSegment in newSegments {
                    
                    newBasicSections.append(contentsOf: nextSegment.basicSections)
                }
                
                let wdgType = newSegments[0].basicSections[0].wdgData.type
                if newIncomingConnector == nil {
                    
                    if newOutgoingConnector == nil {
                        
                        if wdgType == .helical {
                            
                            newIncomingConnector = Connector(fromLocation: .center_lower, toLocation: .floating)
                        }
                        else if wdgType == .disc {
                            
                            let numDiscs = newBasicSections.count
                            if numDiscs % 2 == 0 {
                                
                                newIncomingConnector = Connector(fromLocation: .outside_lower, toLocation: .floating)
                            }
                            else {
                                
                                newIncomingConnector = Connector(fromLocation: .inside_lower, toLocation: .floating)
                            }
                        }
                        else {
                            
                            newIncomingConnector = Connector(fromLocation: .inside_lower, toLocation: .floating)
                        }
                    }
                    else { // use outGoingConnector to decide
                        
                        if wdgType == .helical {
                            
                            newIncomingConnector = Connector(fromLocation: .center_lower, toLocation: .floating)
                        }
                        else if wdgType == .disc {
                            
                            let numDiscs = newBasicSections.count
                            if numDiscs % 2 == 0 {
                                
                                newIncomingConnector = Connector(fromLocation: Connector.StandardToLocation(fromLocation: newOutgoingConnector!.fromLocation), toLocation: .floating)
                            }
                            else {
                                
                                newIncomingConnector = Connector(fromLocation: Connector.AlternatingLocation(lastLocation: newOutgoingConnector!.fromLocation), toLocation: .floating)
                            }
                        }
                        else {
                            
                            newIncomingConnector = Connector(fromLocation: .inside_lower, toLocation: .floating)
                        }
                    }
                }
                
                // at this point, newIncomingConnector is guaranteed to exist, so we move on to newOutgoingConnector
                if newOutgoingConnector == nil {
                    
                    if wdgType == .helical {
                        
                        newOutgoingConnector = Connector(fromLocation: .center_upper, toLocation: .floating)
                    }
                    else if wdgType == .disc {
                        
                        let numDiscs = newBasicSections.count
                        if numDiscs % 2 == 0 {
                            
                            newOutgoingConnector = Connector(fromLocation: Connector.StandardToLocation(fromLocation: newIncomingConnector!.fromLocation), toLocation: .floating)
                        }
                        else {
                            
                            newOutgoingConnector = Connector(fromLocation: Connector.AlternatingLocation(lastLocation: newIncomingConnector!.fromLocation), toLocation: .floating)
                        }
                    }
                    else {
                        
                        newOutgoingConnector = Connector(fromLocation: .outside_upper, toLocation: .floating)
                    }
                }
                
                // Here we now have the newIncomingConnector and newOutgoingConnector defined, we just need to add the connectors within the new Segments
                var incomingConnector = newIncomingConnector!
                var outgoingConnector = newIncomingConnector!
                var lastSegmentID = await firstNewSegment.connections.count == 0 ? nil : firstNewSegment.connections[0].segmentID
                var lastSegment = lastSegmentID == nil ? nil : segmentStore.first(where: { $0.serialNumber == lastSegmentID })
                
                for nextSegment in newSegments {
                    
                    if await (firstNewSegment.connections.count == 0 && nextSegment == firstNewSegment) || nextSegment != firstNewSegment {
                        
                        await nextSegment.AppendConnection(connection: Segment.Connection(segmentID: lastSegmentID, connector: incomingConnector))
                        // nextSegment.connections.append(Segment.Connection(segment: lastSegment, connector: incomingConnector))
                    }
                    
                    if nextSegment != firstNewSegment, let prevSegment = lastSegment {
                        
                        await prevSegment.AppendConnection(connection: Segment.Connection(segmentID: nextSegment.serialNumber, connector: outgoingConnector))
                        // prevSegment.connections.append(Segment.Connection(segment: nextSegment, connector: outgoingConnector))
                    }
                    
                    // set up the connector for the outgoing connection next time through the loop
                    let fromConnection = Connector.AlternatingLocation(lastLocation: incomingConnector.fromLocation)
                    let toConnection = Connector.StandardToLocation(fromLocation: fromConnection)
                    outgoingConnector = Connector(fromLocation: fromConnection, toLocation: toConnection)
                    incomingConnector = Connector(fromLocation: toConnection, toLocation: fromConnection)
                    
                    if await lastNewSegment.connections.count == 1 && nextSegment == lastNewSegment {
                        
                        await nextSegment.AppendConnection(connection: Segment.Connection(segmentID: nil, connector: outgoingConnector))
                        // nextSegment.connections.append(Segment.Connection(segment: nil, connector: outgoingConnector))
                    }
                    
                    lastSegment = nextSegment
                }
                
                // do a quick check - this should never happen and should be treated as a programming error
                for nextNewSegment in newSegments {
                    
                    if await nextNewSegment.connections.count > 2 {
                        
                        throw PhaseModelError(info: "\(await nextNewSegment.location)", type: .TooManyConnectors)
                    }
                }
            }
            catch {
                
                throw error
            }
            
        }
        else { // oldSegments.count < newSegments.count
            
            throw PhaseModelError(info: "", type: .OldSegmentCountIsNotOne)
            
        }
    }
    
    /// Function to check the comparative position of 'toSegment' with respect to 'fromSegment'. For instance, if 'fromSegment;' is in coil position 2, and toSegment is in coil position 1, the function will return 'adjacentInner'. The 'toSegment' parameter must exit in the current model or an error is thrown. It is not necessary that the fromSegment exists in the model, but it must have the correct location (with repsect to the current model) set in it.
    func ComparativePosition(fromSegment:Segment, toSegment:Segment) async throws -> Segment.ComparativePosition {
        
        guard self.segments.contains(toSegment) else {
            
            throw PhaseModelError(info: "", type: .SegmentNotInModel)
            
        }
        
        guard await fromSegment.location != toSegment.location else {
            
            throw PhaseModelError(info: "There is already a Segment at that axial location.", type: .IllegalLocation)
        }
        
        let fromRadial = await fromSegment.location.radial
        let toRadial = await toSegment.location.radial
        let radialDiff = fromRadial - toRadial
        
        let fromAxial = await fromSegment.location.axial
        let toAxial = await toSegment.location.axial
        
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
            let isBottom = await self.segments[toIndex - 1].location.radial < toRadial
            
            if toIndex == 0 || (toIndex > 0 && isBottom) {
                
                return .bottom
            }
            
            let isTop = await self.segments[toIndex + 1].location.radial > toRadial
            if toIndex == self.segments.endIndex - 1 || isTop {
                
                return .top
            }
            
            let prevIsTo:Bool = await self.segments[toIndex - 1].location.radial == toRadial
            let nextIsTo = await self.segments[toIndex + 1].location.radial == toRadial
            let prevIndex:Int? = toIndex > 0 && prevIsTo ? toIndex - 1 : nil
            let nextIndex:Int? = toIndex < self.segments.endIndex - 1 && nextIsTo ? toIndex + 1 : nil
            
            let axialDiff = fromAxial - toAxial
            
            if axialDiff > 0 {
                
                // 'toSegment' is below
                if let next = nextIndex {
                    
                    if await self.segments[next].location.axial > fromAxial {
                        
                        return .adjacentBelow
                    }
                    else if await self.segments[next].location.axial == fromAxial {
                        
                        throw PhaseModelError(info: "There is already a Segment at that axial location.", type: .IllegalLocation)
                    }
                }
                
                return .below
            }
            else if axialDiff < 0 {
                
                // toSegment is above
                if let prev = prevIndex {
                    
                    if await self.segments[prev].location.axial < fromAxial {
                        
                        return .adjacentAbove
                    }
                    else if await self.segments[prev].location.axial == fromAxial {
                        
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
    
    /// Essentially, this function creates (overwrites) the Nodes that are attached to the top and bottom of each segment in the current model. A Node may be shared, as in when a Segment.Connection exists between two Segments, _particularly_ the top of one Segment that is connected to the bottom of the next axial Segment.Note that if there is no connection between two adjacent segments, a floating node is created on each segment. All other Connections (ie: between different coils or non-contiguous Segments) will only be handled when refining the capacitance matrix prior to impulse simulation. The function returns an array of Ints that are the index (in the Nodes array) to  the LAST (uppermost) Node for each *coil*.
    func SetNodes() async throws -> [Int] {
        
        guard self.segments.count > 0 else {
            
            throw PhaseModelError(info: "", type: .EmptyModel)
        }
        
        // clear the Node array
        self.nodeStore = []
        var result:[Int] = []
        
        // split the Segment array into coils (without shielding elements)
        var currentCoil = -1
        var coils:[[Segment]] = []
        var nextCoil:[Segment] = []
        
        for nextSegment in self.segments {
            
            if nextSegment.radialPos != currentCoil {
                
                if (currentCoil >= 0) {
                    
                    coils.append(nextCoil)
                }
                
                currentCoil = nextSegment.radialPos
                nextCoil = []
            }
            
            // don't add static rings
            if nextSegment.axialPos >= 0 {
            
                nextCoil.append(nextSegment)
            }
        }
        
        coils.append(nextCoil)
        
        var nextNodeNum = 0
        for nextCoil in coils {
            
            var prevSegment:Segment? = nil
            
            for i in 0..<nextCoil.count {
                
                let thisSegment = nextCoil[i]
                
                /*
                if thisSegment.serialNumber >= 80 && thisSegment.serialNumber <= 82 {
                    
                    print("Stop!")
                } */
                
                let nodeZ = await prevSegment == nil ? thisSegment.z1 : (prevSegment!.z2 + thisSegment.z1) / 2.0
                let newNode = Node(number: nextNodeNum, aboveSegment: thisSegment, belowSegment: prevSegment, z: nodeZ)
                nextNodeNum += 1
                self.nodeStore.append(newNode)
                
                if (i < nextCoil.count - 1) {
                    
                    let nextAxialSegment = nextCoil[i + 1]
                    
                    if await thisSegment.connections.first(where: {$0.segmentID == nextAxialSegment.serialNumber}) == nil {
                        
                        let newNode = await Node(number: nextNodeNum, aboveSegment: nil, belowSegment: thisSegment, z: thisSegment.z2)
                        nextNodeNum += 1
                        self.nodeStore.append(newNode)
                        prevSegment = nil
                    }
                    else {
                        
                        prevSegment = thisSegment
                    }
                }
                else { // topmost segment of the coil
                    
                    let topNode = await Node(number: nextNodeNum, aboveSegment: nil, belowSegment: thisSegment, z: thisSegment.z2)
                    result.append(nextNodeNum)
                    nextNodeNum += 1
                    self.nodeStore.append(topNode)
                }
            }
        }
        
        return result
    }
    
    
    func CalculateCapacitanceMatrix() async throws {
        
        guard self.segments.count > 0 else {
            
            throw PhaseModelError(info: "", type: .EmptyModel)
        }
        
        do {
            
            let coilSegments = self.CoilSegments()
            // start with the series capacitances
            for i in 0..<coilSegments.count {
                
                let nextSegment = coilSegments[i]
                
                // this shouldn't happen
                if nextSegment.radialPos < 0 || nextSegment.axialPos < 0 {
                    
                    continue
                }
                
                let isBottomSegment:Bool = await nextSegment.location.axial == 0
                let topSegmentIndex = try await GetHighestSection(coil: nextSegment.location.radial)
                let isTopSegment:Bool = await nextSegment.location.axial == topSegmentIndex
                
                let endDisc:(lowest:Bool, highest:Bool)? = (isBottomSegment || isTopSegment) ? (isBottomSegment, isTopSegment) : nil
                
                let staticRingUnder = try await StaticRingBelow(segment: nextSegment, recursiveCheck: false)
                let staticRingOver = try await StaticRingAbove(segment: nextSegment, recursiveCheck: false)
                
                /*
                if staticRingOver != nil {
                    
                    print("Stop here")
                } */
                
                if staticRingOver != nil && staticRingUnder != nil {
                    
                    let extraInfo = topSegmentIndex == 0 ? "(If this is a disc or helical coil, consider splitting it into at least 2 Segments.)" : ""
                    throw PhaseModelError(info: extraInfo, type: .OnlyOneStaticRingAllowed)
                }
                
                var adjStaticRing:(above:Bool, below:Bool)? = (false, false)
                if staticRingOver != nil {
                    
                    adjStaticRing = (above:true, below:false)
                }
                else if staticRingUnder != nil {
                    
                    adjStaticRing = (above:false, below:true)
                }
                else {
                    
                    adjStaticRing = nil
                }
                
                var axialGaps:(above:Double, below:Double)? = nil
                var radialGaps:(inside:Double, outside:Double)? = nil
                
                var wdgIsDiscOrHelix = await nextSegment.wdgType == .disc
                wdgIsDiscOrHelix = await nextSegment.wdgType == .helical || wdgIsDiscOrHelix
                if wdgIsDiscOrHelix {
                    
                    axialGaps = try await self.AxialSpacesAboutSegment(segment: nextSegment)
                }
                else {
                    
                    radialGaps = try await self.RadialSpacesAboutSegment(segment: nextSegment)
                }
                
                let serCap = try await nextSegment.SeriesCapacitance(axialGaps: axialGaps, radialGaps: radialGaps, endDisc: endDisc, adjStaticRing: adjStaticRing)
                
                await nextSegment.SetSeriesCapacitance(serCap: serCap)
                // nextSegment.seriesCapacitance = serCap
            }
            
            // Now we take care of the shunt capacitances
            
            // First, we update the Nodes array. This sets up the nodes on each Segment, and returns an array of the topmost nodes (as an Int index into the self.nodeStore array) for the coils.
            let coilTopNodes = try await SetNodes()
            
            // let floatingNodes = self.NodesOfType(connType: .floating)
            
            // Init some local vars
            var innerFirstNode = 0
            var outerFirstNode = 0
            var innerCoilHt = 0.0
            var referenceZero = await self.nodeStore[0].aboveSegment!.z1
            
            // For each coil ('i' is the index of the "outer" coil)
            for i in 0..<coilTopNodes.count {
                
                // we need to find the first (ie: lowest) and last (highest) node for the outermost coil. Note that for coil '0' (the innermost coil), the core is considered to be the 'inner' coil
                outerFirstNode = i == 0 ? 0 : coilTopNodes[i - 1] + 1
                let outerLastNode = coilTopNodes[i]
                
                // get the overall height of the outer coil
                let outerCoilHt = await self.nodeStore[outerLastNode].belowSegment!.z2 - self.nodeStore[outerFirstNode].aboveSegment!.z1
                // fix the reference '0' for the coil pair (set it to the lesser of the two)
                referenceZero = await min(referenceZero, self.nodeStore[outerFirstNode].aboveSegment!.z1)
                
                ZAssert(outerCoilHt > 0.0, message: "Got negative height!")
                
                // Get the shunt capacitance between the 'i-th' coil and the i-1 coil
                let totalCapacitance = try await CoilInnerShuntCapacitance(coil: i)
                
                ZAssert(totalCapacitance > 0.0, message: "Got negative total capacitance")
                
                // choose the higher of the two heights as the reference to use
                let referenceHt = max(innerCoilHt, outerCoilHt)
                
                // come up with a rate of change for the capacitance
                let faradsPerMeter = totalCapacitance / referenceHt
                
                struct nodeCap {
                    
                    let nodeIndex:Int
                    let z:Double
                    let cap:Double
                }
                
                let currentCoil = self.nodeStore[outerFirstNode].aboveSegment!.radialPos
                let hasShieldInside = try await self.RadialShieldInside(coil: currentCoil) != nil
                var innerNodeCaps:[nodeCap] = []
                
                // What we do next depends if this is the innermost coil, or if there is a ground shield inside the coil
                if i == 0 || hasShieldInside {
                    
                    // take care of the special case where it's the first coil (ie: the 'inner coil' is actually the core)
                    innerNodeCaps = [nodeCap(nodeIndex: -1, z: 0.0, cap: totalCapacitance / 2.0), nodeCap(nodeIndex: -1, z: referenceHt, cap: totalCapacitance / 2.0)]
                }
                else {
                    
                    let innerLastNode = coilTopNodes[i - 1]
                    innerCoilHt = self.nodeStore[innerLastNode].z - self.nodeStore[innerFirstNode].z
                    
                    for j in innerFirstNode...innerLastNode {
                        
                        let lastCcum = j == innerFirstNode ? 0.0 : (self.nodeStore[j - 1].z - referenceZero) * faradsPerMeter
                        let nextCcum = j == innerLastNode ? totalCapacitance : (self.nodeStore[j + 1].z - referenceZero) * faradsPerMeter
                        
                        let nextNodeCap = nodeCap(nodeIndex: j, z: self.nodeStore[j].z, cap: (nextCcum - lastCcum) / 2.0)
                        innerNodeCaps.append(nextNodeCap)
                    }
                }
                
                // At this point, the (inner -> outer) shunt capacitances are calculated; now calculate the (outer -> inner) capacitances
                
                var outerNodeCaps:[nodeCap] = []
                
                for j in outerFirstNode...outerLastNode {
                    
                    let lastCcum = j == outerFirstNode ? 0.0 : (self.nodeStore[j - 1].z - referenceZero) * faradsPerMeter
                    let nextCcum = j == outerLastNode ? totalCapacitance : (self.nodeStore[j + 1].z - referenceZero) * faradsPerMeter
                    
                    let nextNodeCap = nodeCap(nodeIndex: j, z: self.nodeStore[j].z, cap: (nextCcum - lastCcum) / 2.0)
                    outerNodeCaps.append(nextNodeCap)
                }
                
                // At this point, the two sets of node capacitances are set up. Take care of the trivial cases first, where the shunt capacitances from the innermost coil are to the core or a radial shield (a ground plane).
                if i == 0 || hasShieldInside {
                    
                    for nextNodeCap in outerNodeCaps {
                        
                        self.nodeStore[nextNodeCap.nodeIndex].shuntCapacitances.append(Node.shuntCap(toNode: -1, capacitance: nextNodeCap.cap))
                    }
                }
                else {
                    
                    // Apply the Super Duper Shunt Capacitance Algorithm™ by PCH
                    
                    struct capLink {
                        
                        let innerNode:Int
                        let outerNode:Int
                        let aveCap:Double
                    }
                    
                    // set the indices into the various arrays
                    let inner = 0
                    let outer = 1
                    
                    // initialize arrays & variables
                    let nodeCaps = [innerNodeCaps, outerNodeCaps]
                    var currentNodeIndex = [0, 0]
                    var cumCap = [innerNodeCaps[0].cap, outerNodeCaps[0].cap]
                    // set the reference coil as the one whose first node has the lower capacitance (ie: the most nodes - I think)
                    var refCoil = nodeCaps[inner][0].cap <= nodeCaps[outer][0].cap ? inner : outer
                    var otherCoil = refCoil == inner ? outer : inner
                    var capLinks:[capLink] = []
                    var prevAverageC = 0.0
                    
                    while currentNodeIndex[inner] < nodeCaps[inner].count && currentNodeIndex[outer] < nodeCaps[outer].count {
                    
                        // This is where weird things like large axial gaps in tapping windings are (should) be taken care of
                        let thisAverageZ = (nodeCaps[inner][currentNodeIndex[inner]].z + nodeCaps[outer][currentNodeIndex[outer]].z) / 2.0
                        let thisAverageC = (thisAverageZ - referenceZero) / referenceHt * totalCapacitance
                        
                        let innerNode = nodeCaps[inner][currentNodeIndex[inner]].nodeIndex
                        let outerNode = nodeCaps[outer][currentNodeIndex[outer]].nodeIndex
                        
                        // capLinks.append(capLink(innerNode: nodeCaps[inner][currentNodeIndex[inner]].nodeIndex, outerNode: nodeCaps[outer][currentNodeIndex[outer]].nodeIndex, aveCap: averageC))
                         
                        let refValue = nodeCaps[refCoil][currentNodeIndex[refCoil]].cap / 2.0
                        
                        if abs(cumCap[inner] - cumCap[outer]) > refValue {
                                
                            currentNodeIndex[refCoil] += 1
                            
                            if currentNodeIndex[refCoil] >= nodeCaps[refCoil].count {
                                
                                break
                            }
                            
                            cumCap[refCoil] += nodeCaps[refCoil][currentNodeIndex[refCoil]].cap
                        }
                        else {
                            
                            currentNodeIndex[refCoil] += 1
                            currentNodeIndex[otherCoil] += 1
                            
                            if currentNodeIndex[inner] >= nodeCaps[inner].count && currentNodeIndex[outer] >= nodeCaps[outer].count {
                                
                                break
                            }
                            
                            if currentNodeIndex[refCoil] < nodeCaps[refCoil].count {
                                
                                cumCap[refCoil] += nodeCaps[refCoil][currentNodeIndex[refCoil]].cap
                            }
                            else {
                                
                                currentNodeIndex[refCoil] = nodeCaps[refCoil].count - 1
                            }
                            
                            if currentNodeIndex[otherCoil] < nodeCaps[otherCoil].count {
                                
                                cumCap[otherCoil] += nodeCaps[otherCoil][currentNodeIndex[otherCoil]].cap
                            }
                            else {
                                
                                currentNodeIndex[otherCoil] = nodeCaps[otherCoil].count - 1
                            }
                        }
                        
                        let nextAverageZ = (nodeCaps[inner][currentNodeIndex[inner]].z + nodeCaps[outer][currentNodeIndex[outer]].z) / 2.0
                        let nextAverageC = (nextAverageZ - referenceZero) / referenceHt * totalCapacitance
                        
                        let averageC = (nextAverageC - prevAverageC) / 2
                        
                        prevAverageC = thisAverageC
                        
                        capLinks.append(capLink(innerNode: innerNode, outerNode: outerNode, aveCap: averageC))
                        
                        refCoil = nodeCaps[inner][currentNodeIndex[inner]].cap <= nodeCaps[outer][currentNodeIndex[outer]].cap ? inner : outer
                        otherCoil = refCoil == inner ? outer : inner
                    }
                    
                    // add the final shunt capacitance
                    capLinks.append(capLink(innerNode: nodeCaps[inner].last!.nodeIndex, outerNode: nodeCaps[outer].last!.nodeIndex, aveCap: (totalCapacitance - prevAverageC) / 2))
                    
                    // convert the capLinks to shunt capacitances
                    for j in 0..<capLinks.count {
                        
                        // let lowIndex = max(0, j - 1)
                        // let hiIndex = min(capLinks.count - 1, j + 1)
                        // let shuntCap = (capLinks[hiIndex].aveCap - capLinks[lowIndex].aveCap) / 2.0
                        
                        let shuntCap = capLinks[j].aveCap
                        self.nodeStore[capLinks[j].innerNode].shuntCapacitances.append(Node.shuntCap(toNode: capLinks[j].outerNode, capacitance: shuntCap))
                        self.nodeStore[capLinks[j].outerNode].shuntCapacitances.append(Node.shuntCap(toNode: capLinks[j].innerNode, capacitance: shuntCap))
                    }
                }
                
                // We now need to check if there is a radial shield OUTSIDE the coil
                if let radialShieldOutside = try await self.RadialShieldOutside(coil: currentCoil) {
                    
                    let rsCoil = radialShieldOutside.radialPos
                    let rsCapacitance = try await self.CoilInnerShuntCapacitance(coil: rsCoil)
                    
                    let coilLastNode = outerLastNode
                    let coilFirstNode = outerFirstNode
                    
                    let rsFaradsPerMeter = rsCapacitance / referenceHt
                    
                    var rsNodeCaps:[nodeCap] = []
                    for j in coilFirstNode...coilLastNode {
                        
                        let lastCcum = j == coilFirstNode ? 0.0 : (self.nodeStore[j - 1].z - referenceZero) * rsFaradsPerMeter
                        let nextCcum = j == coilLastNode ? rsCapacitance : (self.nodeStore[j + 1].z - referenceZero) * rsFaradsPerMeter
                        
                        let nextNodeCap = nodeCap(nodeIndex: j, z: self.nodeStore[j].z, cap: (nextCcum - lastCcum) / 2.0)
                        rsNodeCaps.append(nextNodeCap)
                    }
                    
                    for nextNodeCap in rsNodeCaps {
                        
                        self.nodeStore[nextNodeCap.nodeIndex].shuntCapacitances.append(Node.shuntCap(toNode: -1, capacitance: nextNodeCap.cap))
                    }
                }
                
                // set some variables for the next time through the loop
                innerCoilHt = outerCoilHt
                innerFirstNode = outerFirstNode
                
            }
            
            // Add the shunt capacitances to ground for the outermost coil
            let outerCapacitance = try await OuterShuntCapacitance()
            let referenceHt = self.nodeStore[coilTopNodes.last!].z - self.nodeStore[innerFirstNode].z
            referenceZero = self.nodeStore[innerFirstNode].z
            let faradsPerMeter = outerCapacitance / referenceHt
            
            for j in innerFirstNode...coilTopNodes.last! {
                
                let lastCcum = j == innerFirstNode ? 0.0 : (self.nodeStore[j - 1].z - referenceZero) * faradsPerMeter
                let nextCcum = j == coilTopNodes.last! ? outerCapacitance : (self.nodeStore[j + 1].z - referenceZero) * faradsPerMeter
                
                self.nodeStore[j].shuntCapacitances.append(Node.shuntCap(toNode: -1, capacitance: (nextCcum - lastCcum) / 2.0))
            }
            
            // At this point, all of the series and shunt capacitances have been calculated, so we can create the C-matrix. Note that at this point, the matrix has not taken into consideration any cross connections, nodal connections to ground, etc.
            
            let C = PchMatrix(matrixType: .general, numType: .Double, rows: UInt(self.nodeStore.count), columns: UInt(self.nodeStore.count))
            
            for nextNode in self.nodes {
                
                let Cj = await nextNode.belowSegment != nil ? nextNode.belowSegment!.seriesCapacitance : 0.0
                let Cj1 = await nextNode.aboveSegment != nil ? nextNode.aboveSegment!.seriesCapacitance : 0.0
                
                guard Cj > 0.0 || Cj1 > 0.0 else {
                    
                    throw PhaseModelError(info: "\(nextNode.number)", type: .NodeHasNoSegments)
                }
                
                var sumK = 0.0
                for nextShuntCap in nextNode.shuntCapacitances {
                    
                    // ground nodes are not included in the capacitance matrix, but everything else is
                    if nextShuntCap.toNode >= 0 {
                    
                        // in case there's alrady something in that cell
                        var existingCap = 0.0
                        if let cap:Double = await C[nextNode.number, nextShuntCap.toNode] {
                            
                            existingCap = cap
                        }
                        
                        // C[nextNode.number, nextShuntCap.toNode] = existingCap - nextShuntCap.capacitance
                        await C.SetDoubleValue(value: existingCap - nextShuntCap.capacitance, row: nextNode.number, col: nextShuntCap.toNode)
                    }
                    
                    sumK += nextShuntCap.capacitance
                }
                
                // C[nextNode.number, nextNode.number] = Cj + Cj1 + sumK
                await C.SetDoubleValue(value: Cj + Cj1 + sumK, row: nextNode.number, col: nextNode.number)
                
                if Cj != 0.0 {
                    
                    // C[nextNode.number, nextNode.number - 1] = -Cj
                    await C.SetDoubleValue(value: -Cj, row: nextNode.number, col: nextNode.number - 1)
                }
                
                if Cj1 != 0.0 {
                    
                    // C[nextNode.number, nextNode.number + 1] = -Cj1
                    await C.SetDoubleValue(value: -Cj1, row: nextNode.number, col: nextNode.number + 1)
                }
            }
            
            self.C = C
        }
        catch {
            
            throw error
        }
    }
    
    // Calculate the capacitance to the tank and to the other coils of the outermost coil (per Kulkarne 7.15)
    func OuterShuntCapacitance() async throws -> Double {
        
        guard let lastCoilSeg = self.CoilSegments().last else {
            
            throw PhaseModelError(info: "Outermost coil", type: .CoilDoesNotExist)
        }
        
        do {
            
            let sTank = self.tankDepth / 2
            let tSolidTank = 0.25 * 0.0254
            let tOilTank = await sTank - lastCoilSeg.r2 - tSolidTank
            let H = try await EffectiveHeight(coil: lastCoilSeg.radialPos)
            let R = await (lastCoilSeg.r1 + lastCoilSeg.r2) / 2
            
            let firstTermTank = 2 * π * ε0 * H / acosh(sTank / R)
            let secondTermTank = (tOilTank + tSolidTank) / ((tOilTank / εOil) + (tSolidTank / εBoard))
            
            let Ctank = firstTermTank * secondTermTank
            
            let sCoils:Double = self.core.legCenters / 2
            let tSolidCoils = 2 * tSolidTank
            let tOilCoils:Double = await self.core.legCenters - (lastCoilSeg.r2 * 2) - tSolidCoils
            
            let firstTermCoils = 2 * π * ε0 * H / acosh(sCoils / R)
            let secondTermCoil = (tOilCoils + tSolidCoils) / ((tOilCoils / εOil) + (tSolidCoils / εBoard))
            
            let Ccoils = firstTermCoils * secondTermCoil
            
            return Ctank + Ccoils
        }
        catch {
            
            throw error
        }
        
    }
    
    func CoilInnerShuntCapacitance(coil:Int) async throws -> Double {
        
        guard let bottomCoilSeg = await self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        let bs = bottomCoilSeg.basicSections[0];
        
        do {
            
            // start with the inner radius
            var prevIR:Double = 0.0
            if coil == 0 {
                
                // check if there's a shield OVER the core (can't imagine why this would be needed, but...)
                if let coreShield = await self.SegmentAt(location: LocStruct(radial: Segment.negativeZeroPosition, axial: 0)) {
                    
                    prevIR = await coreShield.r2
                }
                else {
                    
                    prevIR = self.core.radius
                }
            }
            else if let innerShield = await self.SegmentAt(location: LocStruct(radial: -coil, axial: 0)) {
                
                prevIR = await innerShield.r2
            }
            else {
                
                guard let prevCoilSeg = await self.SegmentAt(location: LocStruct(radial: coil - 1, axial: 0)) else {
                    
                    throw PhaseModelError(info: "\(coil-1)", type: .CoilDoesNotExist)
                }
                
                prevIR = await prevCoilSeg.r2
            }
            
            let hilo = try await HiloUnder(coil: coil)
            let rGap = prevIR + hilo / 2.0
            
            // TODO: This should probably be dependent on whether 'coil' is actually a radial shield
            let Ns = Double(bs.wdgData.discData.numAxialColumns)
            // assume 3/4" sticks
            let ws = 0.75 * 0.0254
            let fs = Ns * ws / (2 * π * rGap)
            let H = try await CapacitiveHeightInner(coil: coil)
            // assume standard radial spacers & tube thicknesses
            let Npress = round(hilo / 0.0084 - 0.5)
            let tPress = 0.08 * 0.0254 * Npress
            let tStick = hilo - tPress
            
            let firstTerm = fs / ((tPress / εBoard) + (tStick / εBoard))
            let secondTerm = (1 - fs) / ((tPress / εBoard) + (tStick / εOil))
            
            let Cinner = ε0 * 2 * π * rGap * H * (firstTerm + secondTerm)
            
            return Cinner
        }
        catch {
            
            throw error
        }
    }
    
    // Calculate the height that will be used for the shunt capacitance calculation to the coil/shield/core that is radially "inside" to the given coil.
    func CapacitiveHeightInner(coil:Int) async throws -> Double {
        
        guard let _ = await self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        do {
            
            let effCapHeight = try await EffectiveHeight(coil: coil)
            let hasRadialShieldInside = try await RadialShieldInside(coil: coil) != nil
            
            if (coil == 0 || hasRadialShieldInside) {
                
                return effCapHeight
            }
            
            let innerCoilEffCapHeight = try await EffectiveHeight(coil: coil - 1)
            
            return (effCapHeight + innerCoilEffCapHeight) / 2
        }
        catch {
            
            throw error
        }
    }
    
    // The "effective height" of a coil is simply its electrical height minus any axial gaps that are larger than 75mm (yes, that is aribtrary).
    func EffectiveHeight(coil:Int) async throws -> Double {
        
        let MAX_GAP = 0.075
        
        guard let _ = await self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        let coilSections = self.CoilSegments().filter({$0.radialPos == coil})
        let coilBottom = await coilSections[0].z1
        let coilTop = await coilSections.last!.z2
        let coilHeight = coilTop - coilBottom
        
        var sumAxialGaps = 0.0
        for i in 0..<coilSections.count - 1 {
            
            let nextGap = await coilSections[i+1].z1 - coilSections[i].z2
            if nextGap > MAX_GAP {
                
                sumAxialGaps += nextGap
            }
        }
        
        return coilHeight - sumAxialGaps
    }
    
    /// This is (currently) a simple (ie: useless) calculation of series capacitance (simple because it does not consider things like interconnections, line in the middle, etc.). It gives the same result as the Excel-design sheet.
    func CoilSeriesCapacitance(coil:Int) async throws -> Double {
        
        guard let _ = await self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        guard let _ = self.C else {
            
            throw PhaseModelError(info: "\(coil)", type: .CapacitanceNotCalculated)
        }
        
        
        var result = 0.0
        
        for i in 0..<self.segments.count {
            
            let nextSegment = self.segments[i]
            
            if nextSegment.radialPos == coil && nextSegment.axialPos >= 0 {
                
                // print("\(nextSegment.seriesCapacitance)")
                await result += 1.0 / nextSegment.seriesCapacitance
            }
        }
        
        return 1 / result
        
    }
    
    
    /// Insert a new Segment into the correct spot in the model to keep the segmentStore array sorted. If there is an existing Segment with the same LocStruct as the new one, this function throws an error.
    func InsertSegment(newSegment:Segment) async throws {
        
        // use binary search method to insert (probably unnecessary, but what the hell)
        var lo = 0
        var hi = self.segmentStore.count - 1
        while lo <= hi {
            
            let mid = (lo + hi) / 2
            if await self.segmentStore[mid].location < newSegment.location {
                
                lo = mid + 1
            }
            else if await newSegment.location < self.segmentStore[mid].location {
                
                hi = mid - 1
            }
            else {
                
                // The location already exists, throw an error
                throw PhaseModelError(info: "\(await newSegment.location)", type: .SegmentExists)
            }
        }
        
        self.segmentStore.insert(newSegment, at: lo)
    }
    
    /// Check if there is a radial shield inside the given coil and if so, return it as a Segment
    func RadialShieldInside(coil:Int) async throws -> Segment? {
        
        guard let _ = await self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        let radialPos = coil == 0 ? Segment.negativeZeroPosition : -coil
        
        return await self.SegmentAt(location: LocStruct(radial: radialPos, axial: 0))
    }
    
    /// Check if there a radial shield  outside the given coil and if so, return it as a Segment
    func RadialShieldOutside(coil:Int) async throws -> Segment? {
        
        guard let _ = await self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil + 1)", type: .CoilDoesNotExist)
        }
        
        return await self.SegmentAt(location: LocStruct(radial: -(coil + 1), axial: 0))
    }
    
    /// Get the Hilo under the given coil (or shield)
    func HiloUnder(coil:Int) async throws -> Double {
        
        guard let segment = await self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        let coilInnerRadius = await segment.r1
        
        if coil < 0 {
            
            guard let innerSegment = await self.SegmentAt(location: LocStruct(radial: (-coil) - 1, axial: 0)) else {
                
                throw PhaseModelError(info: "\(coil - 1)", type: .CoilDoesNotExist)
            }
            
            return await coilInnerRadius - innerSegment.r2
        }
        else if segment.radialPos == 0 {
            
            if let coreShield = await SegmentAt(location: LocStruct(radial: Segment.negativeZeroPosition, axial: 0)) {
                
                return await coilInnerRadius - coreShield.r2
            }
            
            return coilInnerRadius - self.core.radius
        }
        // check for a radial shield inside the coil
        else if let innerShield = await self.SegmentAt(location: LocStruct(radial: -coil, axial: 0)) {
            
            return await coilInnerRadius - innerShield.r2
        }
        else {
            
            guard let innerSegment = await self.SegmentAt(location: LocStruct(radial: coil - 1, axial: 0)) else {
                
                throw PhaseModelError(info: "\(coil - 1)", type: .CoilDoesNotExist)
            }
            
            return await coilInnerRadius - innerSegment.r2
        }
    }
    
    /// Return the radial spaces inside and outside the given segment. If the segment is not in the model, throw an error.
    func RadialSpacesAboutSegment(segment:Segment) async throws -> (inside:Double, outside:Double) {
        
        guard let _ = self.segmentStore.firstIndex(of: segment) else {
            
            throw PhaseModelError(info: "", type: .SegmentNotInModel)
        }
        
        do {
            
            let insideResult:Double = try await self.HiloUnder(coil: segment.location.radial)
            var outsideResult:Double = -1.0
            
            if let nextCoilSegment = await self.SegmentAt(location: LocStruct(radial: segment.radialPos + 1, axial: 0)) {
                
                outsideResult = try await self.HiloUnder(coil: nextCoilSegment.radialPos)
            }
            
            return (insideResult, outsideResult)
        }
        catch {
            
            throw error
        }
    }
    
    /// Return the spaces above and below the given segment. If the segment is not in the model, throw an error.
    func AxialSpacesAboutSegment(segment:Segment) async throws -> (above: Double, below: Double) {
        
        guard let segIndex = self.segmentStore.firstIndex(of: segment) else {
            
            throw PhaseModelError(info: "", type: .SegmentNotInModel)
        }
        
        var aboveResult:Double = -1.0
        var belowResult:Double = -1.0
        
        do {
            
            if let staticRingAbove = try await self.StaticRingAbove(segment: segment, recursiveCheck: true) {
                
                aboveResult = await staticRingAbove.z1 - segment.z2
            }
            
            if let staticRingBelow = try await self.StaticRingBelow(segment: segment, recursiveCheck: true) {
                
                belowResult = await segment.z1 - staticRingBelow.z2
            }
            
            if aboveResult < 0.0 {
                
                let highest = try await self.GetHighestSection(coil: segment.radialPos)
                if segment.axialPos == highest {
                    
                    aboveResult = await segment.realWindowHeight - segment.z2
                }
                else {
                    
                    aboveResult = await self.segmentStore[segIndex + 1].z1 - segment.z2
                }
            }
            
            if belowResult < 0.0 {
                
                if segment.axialPos == 0 {
                    
                    belowResult = await segment.z1
                }
                else {
                    
                    belowResult = await segment.z1 - self.segmentStore[segIndex - 1].z2
                }
            }
            
            return (aboveResult, belowResult)
        }
        catch {
            
            throw error
        }
    }
    
    /// Try to add a radial shield inside the given coil and return it as a Segment. If unsuccessful, the function throws an error.
    func AddRadialShieldInside(coil:Int, hiloToShield:Double) async throws -> Segment {
        
        guard let segment = await self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        // check if there is already a radial shield under the coil
        let radPos = coil == 0 ? Segment.negativeZeroPosition : -coil
        guard await self.SegmentAt(location: LocStruct(radial: radPos, axial: 0)) == nil else {
            
            throw PhaseModelError(info: "Radial Shield", type: .ShieldingElementExists)
        }
        
        do {
            
            let requiredSpace = hiloToShield + 0.002
            let availableSpace = try await self.HiloUnder(coil: coil)
            
            if requiredSpace >= availableSpace {
                
                throw PhaseModelError(info: "Radial Shield", type: .NoRoomForShieldingElement)
            }
            
            let highestSegmentIndex = try await self.GetHighestSection(coil: coil)
            guard let highestSegment = await self.SegmentAt(location: LocStruct(radial: coil, axial: highestSegmentIndex)) else {
                
                throw PhaseModelError(info: "", type: .SegmentNotInModel)
            }
            
            let height = await highestSegment.z2 - segment.z1
            
            let radialShield = try await Segment.RadialShield(adjacentSegment: segment, hiloToSegment: hiloToShield, elecHt: height)
            
            return radialShield
            
        }
        catch {
            
            throw error
        }
    }
    
    /// Try to add a static ring either above or below the adjacent Segment. If unsuccessful, this function throws an error. Note that this rountien does not actually add the static ring to the model's segmentStore
    func AddStaticRing(adjacentSegment:Segment, above:Bool, staticRingThickness:Double? = nil, gapToStaticRing:Double? = nil) async throws -> Segment {
        
        guard let _ = self.segmentStore.firstIndex(of: adjacentSegment) else {
            
            throw PhaseModelError(info: "", type: .SegmentNotInModel)
        }
        
        do {
            
            // check if there is already a static ring above/below the adjacent segment
            if above {
                
                if let _ = try await StaticRingAbove(segment: adjacentSegment, recursiveCheck: true) {
                    
                    throw PhaseModelError(info: "Static Ring", type: .ShieldingElementExists)
                }
                
            }
            else {
                
                if let _ = try await StaticRingBelow(segment: adjacentSegment, recursiveCheck: true) {
                    
                    throw PhaseModelError(info: "Static Ring", type: .ShieldingElementExists)
                }
            }
        
            let axialSpaces = try await self.AxialSpacesAboutSegment(segment: adjacentSegment)
            let gapToRing = await gapToStaticRing != nil ? gapToStaticRing! : try self.StandardAxialGap(coil: adjacentSegment.location.radial) / 2
            let srThickness = staticRingThickness != nil ? staticRingThickness! : Segment.stdStaticRingThickness
            let requiredSpace = gapToRing + srThickness
            
            if (above && requiredSpace >= axialSpaces.above) || (!above && requiredSpace >= axialSpaces.below) {
                
                throw PhaseModelError(info: "Static Ring", type: .NoRoomForShieldingElement)
            }
            
            // There is room for the static ring, so try creating it
            let newRing = try await Segment.StaticRing(adjacentSegment: adjacentSegment, gapToSegment: gapToRing, staticRingIsAbove: above, staticRingThickness: srThickness)
            
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
    func StaticRingAbove(segment:Segment, recursiveCheck:Bool) async throws -> Segment? {
        
        guard let segIndex = self.segmentStore.firstIndex(of: segment) else {
            
            throw PhaseModelError(info: "", type: .SegmentNotInModel)
        }
        
        var staticRingAbove:Segment? = nil
        
        // check the easy thing first, looking for a direct reference to a static ring
        let srAxial = segment.axialPos == 0 ? Segment.negativeZeroPosition : -segment.axialPos
        let srLocation = LocStruct(radial: segment.radialPos, axial: srAxial)
        if let srSegment = await self.SegmentAt(location: srLocation) {
            
            if await srSegment.z1 > segment.z1 {
                
                staticRingAbove = srSegment
            }
        }
        
        // if this is the last segment in the whole model, just return
        guard segIndex + 1 < self.segmentStore.count else {
            
            return staticRingAbove
        }
        
        // there might still be a static ring above, but it's been defined as being below the next segment in the array (and there is not a gap there, which is defined as anything greater or equal to 25mm)
        var srIsBelowNext = self.segmentStore[segIndex + 1].radialPos == segment.radialPos
        srIsBelowNext = await self.segmentStore[segIndex + 1].z1 - segment.z2 < 0.025 && srIsBelowNext
        if staticRingAbove == nil && recursiveCheck && srIsBelowNext {
            
            staticRingAbove = try? await StaticRingBelow(segment: self.segmentStore[segIndex + 1], recursiveCheck: false)
        }
        
        return staticRingAbove
    }
    
    /// Check if there is a static ring  below the given segment, and if so, return the segment - otherwise return nil. If the segment is not in the model, this function throws an error.
    /// - Parameter segment: The segment that we want to check
    /// - Parameter recursiveCheck: A Boolean to indicate whether we should check above the next segment as well (needed to avoid infinite loops)
    func StaticRingBelow(segment:Segment, recursiveCheck:Bool) async throws -> Segment? {
        
        guard let segIndex = self.segmentStore.firstIndex(of: segment) else {
            
            throw PhaseModelError(info: "", type: .SegmentNotInModel)
        }
        
        var staticRingBelow:Segment? = nil
        
        // check the easy thing first, looking for a direct reference to a static ring
        let srAxial = segment.axialPos == 0 ? Segment.negativeZeroPosition : -segment.axialPos
        let srLocation = LocStruct(radial: segment.radialPos, axial: srAxial)
        if let srSegment = await self.SegmentAt(location: srLocation) {
            
            if await srSegment.z1 < segment.z1 {
                
                staticRingBelow = srSegment
            }
        }
        
        // if this is the bottom-most segment of a coil, just return
        guard segment.axialPos > 0 else {
            
            return staticRingBelow
        }
        
        // there might still be a static ring below, but it's been defined as being above the previous segment in the array (and there is not a gap there, which is defined as anything greater or equal to 25mm)
        var srIsAbovePrev = self.segmentStore[segIndex - 1].radialPos == segment.radialPos
        srIsAbovePrev = await segment.z1 - self.segmentStore[segIndex - 1].z2 < 0.025 && srIsAbovePrev
        if staticRingBelow == nil && recursiveCheck && srIsAbovePrev {
            
            staticRingBelow = try? await StaticRingAbove(segment: self.segmentStore[segIndex - 1], recursiveCheck: false)
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
    func AddSegments(newSegments:[Segment]) async throws {
        
        do {
            
            for nextSegment in newSegments {
            
                try await self.InsertSegment(newSegment: nextSegment)
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
    func SegmentAt(location:LocStruct) async -> Segment? {
        
        let coilSegs = self.CoilSegments()
        for nextSegment in coilSegs {
            
            let nextLoc = await nextSegment.location
            if nextLoc == location {
                
                return nextSegment
            }
        }
        
        return nil
    }
    
    /// Get the axial index of the highest (max Z) section for the given coil
    /// - note: This returns the axial position equal to: highestDiscNumber - lowestDiscNumber for the coil in question
    func GetHighestSection(coil:Int) async throws -> Int {
        
        guard let _ = await self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        // I believe that this is in order but it should be tested
        let coilSections = self.segmentStore.filter({$0.radialPos == coil && !$0.isStaticRing && !$0.isRadialShield})
        
        return coilSections.last!.axialPos
    }
    
    
    /// Get the gap between the bottom-most section of a coil and the next adjacent section.  If the coil at the given radial position is not a disc coil, an error is thrown.
    func StandardAxialGap(coil:Int) async throws -> Double {
        
        guard let bottomMostDisc = await self.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        var wdgTypeIsDiscOrHelix = await bottomMostDisc.wdgType == .disc
        wdgTypeIsDiscOrHelix = await bottomMostDisc.wdgType == .helical || wdgTypeIsDiscOrHelix
        if !wdgTypeIsDiscOrHelix {
            
            throw PhaseModelError(info: "", type: .NotADiscCoil)
        }
        
        guard let nextDisc = await self.SegmentAt(location: LocStruct(radial: coil, axial: 1)) else {
            
            throw PhaseModelError(info: "\(coil)", type: .CoilDoesNotExist)
        }
        
        let result = await nextDisc.z1 - bottomMostDisc.z2
        
        if result < 0.0 {
            
            throw PhaseModelError(info: "It is negative", type: .IllegalAxialGap)
        }
        
        return result
    }
    
    /*
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
    } */
    
    /*
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
    } */
}

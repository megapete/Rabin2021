//
//  Segment.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-07.
//

// This file defines the most basic segment that is used for calculations of inductance and capacitance for the model. A Segment is made up of one or more BasicSections.

import Foundation
import PchBasePackage

/// A Segment is, at its most basic, a collection of BasicSections. The collection MUST be from the same Winding and it must represent an axially contiguous (adjacent) collection of coils.The collection may only hold a single BasicSection, or anywhere up to all of the BasicSections that make up a coil (for disc coils, only if there are no central or DV gaps in the coil). It is the unit that is actually modeled (and displayed). Static rings and radial shields are special Segments - creation routines (class functions) are provided for each.
class Segment: Codable, Equatable, Hashable {
    
    /// flag used during debugging to identify a Segment for a breakpoint
    var debugFlag = false
    
    /// Enum to define the comparative position(s) of 2 or more Segments
    enum ComparativePosition {
        
        case inner
        case outer
        
        case innerAdjacent
        case outerAdjacent
        
        case above
        case below
        
        case adjacentAbove
        case adjacentBelow
        
        case bottom
        case top
    }
    
    /// Function required to make Segment be Equatable. Basically, we use the serial number to decide if two Segments are equal. This allows us to use Segment as a struct instead of a class, but it means that we must be very careful about setting those serial numbers.
    static func == (lhs: Segment, rhs: Segment) -> Bool {
        
        return lhs.serialNumber == rhs.serialNumber
    }
    
    func hash(into hasher: inout Hasher) {
        
        hasher.combine(self.serialnumberStore)
    }
    
    /// Global storage for the next serial number to assign
    private static var nextSerialNumberStore:Int = 0
    
    /// Return the next available serial number for the Segment class, then advance the counter to the next number.
    static var nextSerialNumber:Int {
        get {
            
            let nextNum = Segment.nextSerialNumberStore
            Segment.nextSerialNumberStore += 1
            return nextNum
        }
    }
    
    /// A class constant for the thickness of a standard static ring
    static let stdStaticRingThickness = 0.625 * meterPerInch
    
    /// This segment's serial number
    private var serialnumberStore:Int
    
    /// Segment serial number (needed to make the "==" operator code simpler.
    var serialNumber:Int {
        get {
            return serialnumberStore
        }
    }
    
    /// The first (index = 0) entry  has the lowest Z and the last entry has the highest.
    let basicSections:[BasicSection]
        
    /// A Boolean to indicate whether the segment is interleaved
    var interleaved:Bool
    
    /// A  constant used to identify the location of radial shields and static rings whose associated Segment is in position 0
    static let negativeZeroPosition = -2048
    
    /// A Boolean to indicate whether the segment is actually a static ring
    let isStaticRing:Bool
    
    /// A Boolean to indicate whether the segment is actually a radial shield
    let isRadialShield:Bool
    
    /// The type of the coil that owns this segment
    var wdgType:BasicSectionWindingData.WdgType {
        
        return self.basicSections[0].wdgData.type
    }
    
    /// The series current through a single turn in the segment
    let I:Double
    
    /// The radial position of the segment (0 = closest to core)
    var radialPos:Int {
        get {
            return self.basicSections[0].location.radial
        }
    }
    
    /// The axial position of the Segment. In the case where a Segment is made up of more than one BasicSection, the lowest BasicSection's axial position is used.
    var axialPos:Int {
        
        get {
            return self.basicSections[0].location.axial
        }
    }
    
    var strandRadial:Double {
        
        get {
            
            return self.basicSections[0].wdgData.turn.strandRadial
        }
    }
    
    var strandAxial:Double {
        
        get {
            
            return self.basicSections[0].wdgData.turn.strandAxial
        }
    }
    
    var location:LocStruct {
        get {
            return LocStruct(radial: self.radialPos, axial: self.axialPos)
        }
    }
    
    /// The _actual_ window height for the core
    let realWindowHeight:Double
    
    /// The window height that is used for DelVecchio inductance modeling
    let useWindowHeight:Double
    
    /// The rectangle that the segment occupies in the core window, with the origin at (LegCenter, BottomYoke)
    var rect:NSRect
    
    /// Simple struct for connections. These work as follows: if the 'segment' property is nil, the connector property should have a 'fromLocation' at the actual location on self, and a 'toConnector' of one of the special connectors (floating, impulse, or ground). If, on the other hand, 'segment' is non-nil, then the fromLocation is still at the actual location on self, and toLocation is the actual location on 'segment'.
    struct Connection:Codable, Equatable, Hashable {
        
        static func == (lhs: Segment.Connection, rhs: Segment.Connection) -> Bool {
            
            guard lhs.connector.fromLocation == rhs.connector.fromLocation && lhs.connector.toLocation == rhs.connector.toLocation else {
                
                return false
            }
            
            if let lSegment = lhs.segment {
                
                guard let rSegment = rhs.segment else {
                    
                    return false
                }
                
                return lSegment == rSegment
            }
            else if rhs.segment != nil {
                
                return false
            }
            
            return true
        }
        
        func hash(into hasher: inout Hasher) {
            
            hasher.combine(self.segment)
            hasher.combine(self.connector)
        }
        
        var segment:Segment?
        var connector:Connector
        
        struct EquivalentConnection:Codable, Equatable, Hashable {
            
            let parent:Segment
            let connection:Connection
        }
        
        var equivalentConnections:Set<EquivalentConnection> = []
    }
    
    /// The connections to the Segment
    var connections:[Connection] = []
    
    /// The inner radius of the segment (from the core center)
    var r1:Double {
        get {
            return self.rect.origin.x
        }
    }
    
    /// The outer radius of the segment (from the core center)
    var r2:Double {
        get {
            return Double(self.rect.origin.x + self.rect.size.width)
        }
    }
    
    /// The bottom-most axial dimension of the segment (using the REAL window height)
    var z1:Double {
        get {
            return Double(self.rect.origin.y)
        }
    }
    
    /// The top-most axial dimension of the segment (using the REAL window height)
    var z2:Double {
        get {
            return Double(self.rect.origin.y + self.rect.size.height)
        }
    }
    
    /// The axial center of the segment (using the real window height)
    var zMean:Double {
        
        return (self.z1 + self.z2) / 2
    }
    
    /// The window height that is used in the Fourier series (corresponds to the 'L' variable in  the formulas in DelVecchio
    var L:Double {
        get {
            return max(self.realWindowHeight, self.useWindowHeight)
        }
    }
    
    /// The number to add to z1 and z2 to get the axial dimensions in the "Fourrier series" window height ('L')
    var zWindHtAdder:Double {
        get {
            let result = (self.L - self.realWindowHeight) / 2.0
            
            return result
        }
    }
    
    /// The area of the segment
    var area:Double {
        get {
            return Double(self.rect.width * self.rect.height)
        }
    }
    
    /// The number of turns in the Segment
    var N:Double {
        get {
            var result = 0.0
            
            for nextSection in self.basicSections {
                
                result += nextSection.N
            }
            
            return result
        }
    }
    
    /// The current density of the section
    /*
    var ActualJ:Double {
        get {
            return self.N * self.I / self.area
        }
    }
    */
    
    /// The resistance of the segment at the given temperature (in C)
    func resistance(at temp:Double = 20.0) -> Double {
        
        let tempFactor = (234.5 + temp) / (234.5 + 20)
        let lmt = (self.r1 + self.r2) * π
        
        guard let bSect = self.basicSections.first else {
            
            return 0
        }
        
        let result = self.N * lmt * bSect.wdgData.turn.resistancePerMeter * tempFactor
        
        return result
    }
    
    func turnEffectiveRadius() -> Double {
        
        guard let bSect = self.basicSections.first else {
            
            return 0
        }
        
        return bSect.wdgData.turn.effectiveRadius
    }
    
    var eddyLossRadialPU:Double = 0.0
    var eddyLossAxialPU:Double = 0.0
    
    
    /// The series capacitance of the segment when it is considered within a coil (this property is set elsewhere)
    var seriesCapacitance:Double = 0.0
    
    /// A struct to define mutual inductance to other Segments (note: the self-inductance can be defined using this struc with the 'toSegment' poroperty set to 'nil')
    struct MutualInductance:Codable {
        
        let toSegment:Segment?
        let inductance:Double
    }
    
    var inductances:[MutualInductance] = []
    
    /// Constructor for a Segment. The array of BasicSections that is passed in is checked to make sure that all sections are part of the same coil, and that they are adjacent and in order from lowest Z to highest Z.
    /// - Note: This initiializer may fail and throw an error.
    /// - Parameter basicSections: An array of BasicSections. The sections must be part of the same Winding, be adjacent, and in order from lowest Z to highest Z.
    /// - Parameter interleaved: Boolean for indication of whether the Segment is interleaved or not (default: false)
    /// - Parameter isStaticRing: Boolean to indicate that the Segment is actaully a static ring (default: false)
    /// - Parameter isRadialShield: Boolean to indicate that the Segment is actually a radial sheild (default: false)
    /// - Parameter realWindowHeight: The actual window height of the core
    /// - Parameter useWindowHeight: The window height that should be used (important for some Delvecchio calculations)
    init(basicSections:[BasicSection], interleaved:Bool = false, isStaticRing:Bool = false, isRadialShield:Bool = false, realWindowHeight:Double, useWindowHeight:Double) throws
    {
        guard let first = basicSections.first, let last = basicSections.last else {
            
            throw SegmentError(info: "", type: .EmptyModel)
        }
        
        let winding = first.location.radial
        var axialIndex = first.location.axial
        var zCurrent = first.z1
        self.I = first.I
        self.realWindowHeight = realWindowHeight
        self.useWindowHeight = useWindowHeight
        
        for i in 1..<basicSections.count {
            
            guard basicSections[i].location.axial == axialIndex + 1, basicSections[i].z1 > zCurrent, basicSections[i].location.radial == winding else {
                
                
                throw SegmentError(info: "\(basicSections[i].location)", type: .IllegalSection)
            }
            
            axialIndex = basicSections[i].location.axial
            zCurrent = basicSections[i].z1
        }
        
        // if we get here, we can save the array and set the properties
        self.basicSections = basicSections
        self.interleaved = interleaved
        
        self.rect = NSRect(x: first.r1, y: first.z1, width: first.width, height: last.z2 - first.z1)
        
        // if it's a static ring or radial shield, set the serial number to a dummy number, otherwise set it to the next available serial number
        self.serialnumberStore = isStaticRing || isRadialShield ? -1 : Segment.nextSerialNumber
        self.isStaticRing = isStaticRing
        self.isRadialShield = isRadialShield
    }
    
    /// Errors for the Segment class
    struct SegmentError:LocalizedError {
        
        /// The different error types that are available
        enum errorType {
            
            case UnknownError
            case EmptyModel
            case IllegalSection
            case StaticRing
            case RadialShield
            case UnimplementedWdgType
            case AxialAndRadialGapsAreNil
            case AxialAndRadialGapsAreNonNil
            case IllegalWindingType
            case IllegalInterleavedType
        }
        
        /// Specialized information that can be added to the descritpion String (can be the empty string)
        let info:String
        /// The error type
        let type:errorType
        
        /// The error string to return with the error
        var errorDescription: String? {
            
            get {
                
                if self.type == .EmptyModel {
                    
                    return "There are no BasicSections in the array!"
                }
                else if self.type == .IllegalSection {
                    
                    return "There is an illegal BasicSection (at location \(info)) in the array. All sections must be part of the same coil, must be adjacent, and in order from lowest Z to highest Z."
                }
                else if self.type == .StaticRing {
                    
                    return "The segment at location \(info) is a static ring!"
                }
                else if self.type == .RadialShield {
                    
                    return "The segment at location \(info) is a radial shield!"
                }
                else if self.type == .UnimplementedWdgType {
                    
                    return "Unimplemented winding type!"
                }
                else if self.type == .AxialAndRadialGapsAreNil {
                    
                    return "Either Axial or Radial adjacent gaps must be defined!"
                }
                else if self.type == .IllegalWindingType {
                    
                    return "The winding type does not match the adjacent gaps that are defined!"
                }
                else if self.type == .IllegalInterleavedType {
                    
                    return "Only disc windings can be interleaved!"
                }
                
                return "An unknown error occurred."
            }
        }
    }
    
    /// Return all the destination segments (and locations) for the given location on this Segment
    func ConnectionDestinations(fromLocation:Connector.Location) -> [(segment:Segment?, location:Connector.Location)] {
        
        var result:[(segment:Segment?, location:Connector.Location)] = []
        
        for nextConnection in self.connections {
            
            if nextConnection.connector.fromLocation == fromLocation {
                
                result.append((nextConnection.segment, nextConnection.connector.toLocation))
            }
        }
        
        return result
    }
    
    /// Add the Set of Connections as 'equivalent connections' to the given Connection. If the 'to' parameter is in the 'equ' array, it is ignored. If 'to' does not exist, the function does nothing.
    func AddEquivalentConnections(to:Connection, equ:Set<Connection.EquivalentConnection>) {
        
        guard let connIndex = self.connections.firstIndex(where: { $0 == to }) else {
            
            return
        }
        
        self.connections[connIndex].equivalentConnections.formUnion(equ)
        self.connections[connIndex].equivalentConnections.remove(Connection.EquivalentConnection(parent: self, connection: to))
    }
    
    /// Remove the given connection and all of it's iterations (from connected segments, etc), except for segments in the maskSegments array.. If the connection is to ground or impulse, the connection is converted to a floating connection.
    /// - Returns: A Set of all the Segments that were affected by the operation
    func RemoveConnection(connection:Segment.Connection) -> Set<Segment> {
        
        var result:Set<Segment> = []
        
        guard let connIndex = self.connections.firstIndex(where: { $0 == connection }) else {
            
            return []
        }
        
        for nextEquivalent in self.connections[connIndex].equivalentConnections {
            
            let removeCheck = nextEquivalent.parent.DoRemoveConnection(connection: nextEquivalent.connection)
            
            if removeCheck {
                
                result.insert(nextEquivalent.parent)
            }
        }
        
        if self.DoRemoveConnection(connection: connection) {
            
            result.insert(self)
        }
        
        return result
    }
    
    /// A private function that actually removes a connection from this Segment. Calling routines should call the RemoveConnection() function to make sure all related connections are also removed. If the connection that is passed to the routine does not exist, the routine does nothing. If the connecion is to ground or impulse, it is basically converted to floating. If the connection is floating, the routine does nothing.
    /// - Returns: A Boolean, indicating whether anything was actually removed/changed
    private func DoRemoveConnection(connection:Segment.Connection) -> Bool {
        
        let toLocation = connection.connector.toLocation
        
        if toLocation == .floating {
            
            return false
        }
        
        let oldCount = self.connections.count
        self.connections.removeAll(where: { $0 == connection })
        
        if toLocation == .impulse || toLocation == .ground {
            
            let newConnection = Segment.Connection(segment: connection.segment, connector: Connector(fromLocation: connection.connector.fromLocation, toLocation: .floating))
            self.connections.append(newConnection)
            
            return true
        }
        
        return self.connections.count < oldCount
    }
    
    
    /// Add a connector to the segment at the given fromLocation. The toLocation parameter depends on the toSegment parameter:
    /// If toSegment is not nil, then toLocation refers to the location on the toSegment. This routine will also add the inverse connector to the toSegment
    /// If toSegment is nil, then the behaviour of the routine is as follows:
    /// If toLocation is .ground or .impulse and self.connection has a connection with a fromLocation the same as the parameter, and a toLocation equal to .floating, that connector is changed to the new connector definition.
    /// If toLocation is .ground, or .impulse, or .floating, and self.connection does not have a corresponding .floating connector, then the new connector is added to self.connections.
    /// - Returns: If toSegment is non-nil, the function returns tuple of the one or two equivalent connections that were created; otherwise it returns both nil
    func AddConnector(fromLocation:Connector.Location, toLocation:Connector.Location, toSegment:Segment?) -> (from:Segment.Connection?, to:Segment.Connection?) {
        
        if let otherSegment = toSegment {
            
            // don't create a connector to self
            if otherSegment == self {
                
                return (nil, nil)
            }
            
            let newSelfConnection = Connection(segment: otherSegment, connector: Connector(fromLocation: fromLocation, toLocation: toLocation))
            self.connections.append(newSelfConnection)
            let newOtherConnection = Connection(segment: self, connector: Connector(fromLocation: toLocation, toLocation: fromLocation))
            otherSegment.connections.append(newOtherConnection)
            
            self.AddEquivalentConnections(to: newSelfConnection, equ: [Connection.EquivalentConnection(parent: otherSegment, connection: newOtherConnection)])
            otherSegment.AddEquivalentConnections(to: newOtherConnection, equ: [Connection.EquivalentConnection(parent: self, connection: newSelfConnection)])
            
            return (newSelfConnection, newOtherConnection)
        }
        else if let existingFloatingIndex = self.connections.firstIndex(where: {$0.connector.fromLocation == fromLocation && $0.connector.toLocation == .floating}) {
            
            self.connections.remove(at: existingFloatingIndex)
            let newSelfConnection = Connection(segment: nil, connector: Connector(fromLocation: fromLocation, toLocation: toLocation))
            self.connections.append(newSelfConnection)
            return (newSelfConnection, nil)
        }
        else if (toLocation == .ground || toLocation == .impulse) && (self.connections.first(where: {$0.connector.toLocation == .ground}) != nil || self.connections.first(where: {$0.connector.toLocation == .impulse}) != nil) {
            
            // already grounded or impulsed, ignore and return
            return (nil, nil)
        }
        else {
            
            // add a new termination at a non-floating location
            let newSelfConnection = Connection(segment: nil, connector: Connector(fromLocation: fromLocation, toLocation: toLocation))
            self.connections.append(newSelfConnection)
            return (newSelfConnection, nil)
        }
    }
    
    /// The series capacitance of the Segment. For Segments that are made up of more than one (or two, for interleaved windings) axial BasicSections, the routine calls itself for each BasicSection.
    func SeriesCapacitance(axialGaps:(above:Double, below:Double)?, radialGaps:(inside:Double, outside:Double)?, endDisc:(lowest:Bool, highest:Bool)?, adjStaticRing:(above:Bool, below:Bool)?) throws -> Double {
        
        guard axialGaps != nil || radialGaps != nil else {
            
            throw SegmentError(info: "", type: .AxialAndRadialGapsAreNil)
        }
        
        guard axialGaps == nil || radialGaps == nil else {
            
            throw SegmentError(info: "", type: .AxialAndRadialGapsAreNonNil)
        }
        
        guard axialGaps != nil && (self.wdgType == .disc || self.wdgType == .helical) else {
            
            throw SegmentError(info: "", type: .IllegalWindingType)
        }
        
        do {
        
            if self.wdgType == .disc || self.wdgType == .helical {
                
                let numBasicSections = self.interleaved ? self.basicSections.count / 2 : self.basicSections.count
                let bsStride = self.interleaved ? 2 : 1
                
                var result = 0.0
                
                if numBasicSections > 1 {
                    
                    for i in 0..<numBasicSections {
                        
                        let thisBasicSection = self.basicSections[i]
                        
                        if (i == 0) {
                            
                            let nextBasicSection = self.basicSections[i + bsStride]
                            
                            let axGaps = (above:nextBasicSection.z1 - thisBasicSection.z2, below:axialGaps!.below)
                            let endD:(lowest:Bool, highest:Bool)? = endDisc != nil ? (endDisc!.lowest, false) : nil
                            let staticRing:(above:Bool, below:Bool)? = adjStaticRing != nil ? (false, adjStaticRing!.below) : nil
                            
                            let bs:[BasicSection] = self.interleaved ? Array(self.basicSections[i...i+1]) : [self.basicSections[i]]
                            
                            let tmpSeg = try Segment(basicSections: bs, interleaved: self.interleaved, isStaticRing: false, isRadialShield: false, realWindowHeight: self.realWindowHeight, useWindowHeight: self.useWindowHeight)
                            
                            let serCap = try tmpSeg.SeriesCapacitance(axialGaps: axGaps, radialGaps: nil, endDisc: endD, adjStaticRing: staticRing)
                            
                            result += 1 / serCap
                        }
                        else if (i == numBasicSections - 1) {
                            
                            let prevBasicSection = self.basicSections[i - 1]
                            
                            let axGaps = (above:axialGaps!.above, below:thisBasicSection.z1 - prevBasicSection.z2)
                            let endD:(lowest:Bool, highest:Bool)? = endDisc != nil ? (false, endDisc!.highest) : nil
                            let staticRing:(above:Bool, below:Bool)? = adjStaticRing != nil ? (adjStaticRing!.above, false) : nil
                            
                            let bs:[BasicSection] = self.interleaved ? Array(self.basicSections[0...i+1]) : [self.basicSections[i]]
                            
                            let tmpSeg = try Segment(basicSections: bs, interleaved: self.interleaved, isStaticRing: false, isRadialShield: false, realWindowHeight: self.realWindowHeight, useWindowHeight: self.useWindowHeight)
                            
                            let serCap = try tmpSeg.SeriesCapacitance(axialGaps: axGaps, radialGaps: nil, endDisc: endD, adjStaticRing: staticRing)
                            
                            result += 1 / serCap
                        }
                        else {
                            
                            let prevBasicSection = self.basicSections[i - 1]
                            let nextBasicSection = self.basicSections[i + bsStride]
                            
                            let axGaps = (above:nextBasicSection.z1 - thisBasicSection.z2, below:thisBasicSection.z1 - prevBasicSection.z2)
                            
                            let bs:[BasicSection] = self.interleaved ? Array(self.basicSections[0...i+1]) : [self.basicSections[i]]
                            
                            let tmpSeg = try Segment(basicSections: bs, interleaved: self.interleaved, isStaticRing: false, isRadialShield: false, realWindowHeight: self.realWindowHeight, useWindowHeight: self.useWindowHeight)
                            
                            let serCap = try tmpSeg.SeriesCapacitance(axialGaps: axGaps, radialGaps: nil, endDisc: nil, adjStaticRing: nil)
                            
                            result += 1 / serCap
                        }
                        
                    }
                    
                    return 1 / result
                }
            }
            
            var Cs = try self.BasicSectionSeriesCapacitance()
            if self.interleaved {
                
                Cs /= 2
            }
            
            if self.wdgType == .sheet {
                
                return Cs
            }
            else if self.wdgType == .helical {
                
                // for helical coils, we ignore things like static rings and whether it's an end-turn
                let aboveGap = axialGaps!.above
                let belowGap = axialGaps!.below
                
                let gapToUse = max(aboveGap, belowGap)
                let Cdd = Segment.DiscToDiscSeriesCapacitance(belowGap: gapToUse, aboveGap: gapToUse, basicSection: self.basicSections[0])
                
                return Cs + 4 / 3 * max(Cdd.below, Cdd.above)
            }
            else if self.wdgType == .disc {
                
                let aboveGap = axialGaps!.above
                let belowGap = axialGaps!.below
                
                let bs = self.basicSections[0]
                
                let Cdd = Segment.DiscToDiscSeriesCapacitance(belowGap: belowGap, aboveGap: aboveGap, basicSection: bs)
                
                if let endDiscLoc = endDisc, endDiscLoc != (false, false) {
                    
                    if let staticRing = adjStaticRing, staticRing != (false, false) {
                        
                        let useCdd = staticRing.below ? Cdd.above : Cdd.below
                        let Ca = staticRing.below ? Cdd.below : Cdd.above
                        
                        let Csum = Ca + 2 * useCdd
                        let Ya = Ca / Csum
                        let Yb = 2 * useCdd / Csum
                        
                        let alpha = sqrt(Csum / Cs)
                        
                        let firstTerm = (Ya * Ya + Yb * Yb) * alpha / tanh(alpha)
                        let secondTerm = 2 * Ya * Yb * alpha / sinh(alpha)
                        let thirdTerm = Ya * Yb * alpha * alpha
                        
                        let Cgeneral = Cs * (firstTerm + secondTerm + thirdTerm)
                        
                        return Cgeneral
                    }
                    else {
                    
                        let useCdd = endDiscLoc.lowest ? Cdd.above : Cdd.below
                        
                        let alpha = sqrt(2 * useCdd / Cs)
                        
                        return Cs * alpha / tanh(alpha)
                    }
                }
                else {
                    
                    var Ya:Double = 0.0
                    var Yb:Double = 0.0
                    var alpha:Double =  0.0
                    
                    if let staticRing = adjStaticRing {
                    
                        let useCdd = staticRing.below ? Cdd.above : Cdd.below
                        let Ca = staticRing.below ? Cdd.below : Cdd.above
                        
                        let Csum = Ca + 2 * useCdd
                        Ya = Ca / Csum
                        Yb = 2 * useCdd / Csum
                        
                        alpha = sqrt(Csum / Cs)
                    }
                    else {
                        
                        let sumCdd = Cdd.above + Cdd.below
                        Ya = Cdd.below / sumCdd
                        Yb = Cdd.above / sumCdd
                        
                        alpha = sqrt(2 * sumCdd / Cs)
                        
                    }
                    
                    let firstTerm = (Ya * Ya + Yb * Yb) * alpha / tanh(alpha)
                    let secondTerm = 2 * Ya * Yb * alpha / sinh(alpha)
                    let thirdTerm = Ya * Yb * alpha * alpha
                    
                    let Cgeneral = Cs * (firstTerm + secondTerm + thirdTerm)
                    
                    return Cgeneral
                }
            }
            /* else if self.wdgType == .layer {
                
            } */
            else {
                
                throw SegmentError(info: "", type: .UnimplementedWdgType)
            }
        }
        catch {
            
            throw error
        }
        
        // throw SegmentError(info: "", type: .UnknownError)
    }
    
    
    /// Return the Cdd values per DelVecchio equation 12.52 (3rd edition) for the gap above an below the given BasicSection.
    static func DiscToDiscSeriesCapacitance(belowGap:Double, aboveGap:Double, basicSection:BasicSection) -> (below:Double, above:Double) {
        
        let fks = Double(basicSection.wdgData.discData.numAxialColumns) * basicSection.wdgData.discData.axialColumnWidth / (π * (basicSection.r1 + basicSection.r2))
        let tp = /* 2.0 * */ basicSection.wdgData.turn.turnInsulation
        
        var Cdd_below = ε0 * π * (basicSection.r2 * basicSection.r2 - basicSection.r1 * basicSection.r1)
        var Cdd_above = Cdd_below
        // calculate Cdd for the gap below the segment
        if belowGap > 0.0 {
            
            let firstTerm = fks / ((tp / εPaper) + (belowGap / εBoard))
            let secondTerm = (1 - fks) / ((tp / εPaper) + (belowGap / εOil))
            Cdd_below *= (firstTerm + secondTerm)
        }
        else {
            
            Cdd_below = 0.0
        }
        
        // calculate Cdd for the gap above the segment
        if aboveGap > 0.0 {
            
            let firstTerm = fks / ((tp / εPaper) + (aboveGap / εBoard))
            let secondTerm = (1 - fks) / ((tp / εPaper) + (aboveGap / εOil))
            Cdd_above *= (firstTerm + secondTerm)
        }
        else {
            
            Cdd_above = 0.0
        }
        
        return (Cdd_below, Cdd_above)
    }
    
    /// The series capacitance of a single BasicSection, as caused by the turns of the disc (for continuous-disc windings), double-disc (for interleaved segments) or a single layer (for layer windings). For interleaved windings, note that the value returned is the "effective" capacitance of a single disc, which is double the capacitance of the double-disc. It is up to the calling routine to treat the capacitance correctly. The methods come from (respectively) DelVecchio, Veverka, Huber (ie: me)
    func BasicSectionSeriesCapacitance() throws -> Double {
        
        guard !self.isStaticRing else {
            
            throw SegmentError(info: "\(self.location)", type: .StaticRing)
        }
        
        guard !self.isRadialShield else {
            
            throw SegmentError(info: "\(self.location)", type: .RadialShield)
        }
        
        if self.wdgType == .helical {
            
            return 0.0
        }
        
        do {
            
            let Ctt = try self.CapacitanceTurnToTurn()
            let N = self.basicSections[0].N
            
            if self.wdgType == .disc && self.interleaved {
                
                // Veverka method (equation 6.4). This should probably be made more precise using the logic given in DelVecchio where they say that the turn-turn capacitances do not see the full disc voltage (it's actually one turn less voltage per disc). Note that as mentioned in the comment for the function, this is actually double the amount of the double-disc.
                let Cs = Ctt * (N - 1) // divide by 2 to get the double-disc series capacitance value
                
                return Cs
            }
            else if self.wdgType == .disc || self.wdgType == .sheet {
                
                // Del Vecchio method
                let Cs = Ctt * (N - 1) / (N * N)
                
                return Cs
            }
            else if self.wdgType == .layer {
                
                // Huber method. Basically, this uses the Del Vecchio method for discs, but turns it on its side, so that the series capacitance goes in the axial direction and the disc-disc capacitance becomes the layer-layer capacitance. 
                let turnsPerLayer = N / Double(self.basicSections[0].wdgData.layers.numLayers)
                let Cs = Ctt * (turnsPerLayer - 1) / (turnsPerLayer * turnsPerLayer)
                
                return Cs
            }
        }
        catch {
            
            throw error
        }
        
        throw SegmentError(info: "", type: .UnimplementedWdgType)
    }
    
    /// The turn-turn capacitance of the mean turn of a single basic section of this Segment,
    func CapacitanceTurnToTurn() throws -> Double {
        
        guard !self.isStaticRing else {
            
            throw SegmentError(info: "\(self.location)", type: .StaticRing)
        }
        
        guard !self.isRadialShield else {
            
            throw SegmentError(info: "\(self.location)", type: .RadialShield)
        }
        
        if self.wdgType == .helical {
            
            return 0.0
        }
        
        // For disc & sheet coils, this corresponds to Ctt in the DelVeccio book. For layer windings, it is the turn-turn capacitance in the axial direction (my own invention).
        
        if self.wdgType == .disc || self.wdgType == .layer {
            
            let tau = /* 2.0 * */ self.basicSections[0].wdgData.turn.turnInsulation
            
            // the calculation of the turn thickness of layer windings does not account for ducts in the winding
            let h = self.wdgType == .disc ? self.basicSections[0].height - tau : self.basicSections[0].width / Double(self.basicSections[0].wdgData.layers.numLayers)
            
            var Ctt:Double = ε0 * εPaper
            Ctt *= π * (self.r1 + self.r2)
            Ctt *= (h + 2 * tau) / tau
            
            return Ctt
        }
        else if self.wdgType == .sheet {
            
            let bs = self.basicSections[0]
            let copperAxial = bs.N * bs.wdgData.turn.radialDimn
            let tau = (bs.width - copperAxial) / (bs.N - 1)
            let h = bs.height
            
            var Ctt:Double = ε0 * εPaper
            Ctt *= π * (self.r1 + self.r2)
            Ctt *= (h + 2 * tau) / tau
            
            return Ctt
        }
        
        throw SegmentError(info: "", type: .UnimplementedWdgType)
    }
    
    /// Class function to create a radial shield. The Segment has its 'isRadialShield' property set to true. The radial location of the shield is equal to the _negative_ of the 'adjacentSegment' argument unless the adjacent segment is in coil '0', in which case the radial location of the shield is Segment.negativeZeroPosition. The adjacent segment must be the FIRST (lowest) Segment in the NEXT coil position from the core.  That is, the radial shield will be placed in the hilo UNDER the adjacent Segment. The thickness of the shield is fixed at 2mm. The radial shield should be set to have  the full electrical height of the coil to which adjacentSegment belongs.
    /// - Parameter adjacentSegment: The segment that is immediately outside the radial shield..
    /// - Parameter hiloToSegment: The radial gap between the shield and the adjacent Segment.
    /// - Parameter elecHt: The height of the radial shield
    static func RadialShield(adjacentSegment:Segment, hiloToSegment:Double, elecHt:Double) throws -> Segment {
        
        // Create the special BasicSection for a radial shield
        let radialPos = adjacentSegment.radialPos == 0 ? Segment.negativeZeroPosition : -adjacentSegment.radialPos
        let rsLocation = LocStruct(radial: radialPos, axial: 0)
        let rsThickness = 0.002 // 2mm standard thickness
        let originX = adjacentSegment.rect.origin.x - hiloToSegment - rsThickness
        let originY = adjacentSegment.rect.origin.y
        let rsRect = NSRect(x: originX, y: originY, width: rsThickness, height: elecHt)
        // create a dummy BSdata struct
        let rsWdgData = BasicSectionWindingData(type: .disc, discData: BasicSectionWindingData.DiscData(numAxialColumns: 10, axialColumnWidth: 0.038), layers: BasicSectionWindingData.LayerData(numLayers: 1, interLayerInsulation: 0, ducts: BasicSectionWindingData.LayerData.DuctData(numDucts: 0, ductDimn: 0)), turn: BasicSectionWindingData.TurnData(radialDimn: rsThickness, axialDimn: elecHt, turnInsulation: 0, resistancePerMeter: 0, strandRadial: 0, strandAxial: 0))
        let rsSection = BasicSection(location: rsLocation, N: 0, I: 0, wdgData: rsWdgData, rect: rsRect)
        
        do {
            
            let newSegment = try Segment(basicSections: [rsSection], interleaved: false, isStaticRing: false, isRadialShield: true, realWindowHeight: adjacentSegment.realWindowHeight, useWindowHeight: adjacentSegment.useWindowHeight)
            
            return newSegment
        }
        catch {
            
            throw error
        }
    }
    
    /// Class function to create a static ring. The Segment is marked as a static ring using its 'isStaticRing' property. The radial location of the static ring is equal to the radial location of the 'adjacentSegment' argument. The axial location is equal to the _negative_ of the adjacentSegment argument, unless the adjacent segment is at axial location 0, in which case the static ring's axial location is equal to Segment.negativeZeroPosition
    /// - Parameter adjacentSegment: The segment that is immediately adjacent to the static ring.
    /// - Parameter gapToSegment: The axial gap (shrunk) between the adjacent segment and the static ring
    /// - Parameter staticRingIsAbove: Boolean to indicate whether the static ring is above (true) or below (false) the adjacentSegment
    /// - Parameter staticRingThickness: An optional static ring thickness (axial height). If nil, then the "standard" thickness of 5/8" is used.
    static func StaticRing(adjacentSegment:Segment, gapToSegment:Double, staticRingIsAbove:Bool, staticRingThickness:Double? = nil) throws -> Segment {
        
        // Create a special BasicSection as follows
        // The location is the same as the adjacent segment EXCEPT the axial position is the NEGATIVE of the adjacent segment
        let axialPos = adjacentSegment.axialPos == 0 ? Segment.negativeZeroPosition : -adjacentSegment.axialPos
        let srLocation = LocStruct(radial: adjacentSegment.radialPos, axial: axialPos)
        // The rect has the same x-origin and width as the adjacent segment but is offset by the gaptoSegment and the standard static-ring axial dimension
        let srThickness = staticRingThickness == nil ? stdStaticRingThickness : staticRingThickness!
        let offsetY = staticRingIsAbove ? adjacentSegment.rect.height + gapToSegment : -(gapToSegment + srThickness)
        var srRect = adjacentSegment.rect
        srRect.origin.y += offsetY
        srRect.size.height = srThickness
        // we need to create a dummy cable definition for the static ring
        let srWdgData = BasicSectionWindingData(type: .disc, discData: BasicSectionWindingData.DiscData(numAxialColumns: 10, axialColumnWidth: 0.038), layers: BasicSectionWindingData.LayerData(numLayers: 1, interLayerInsulation: 0, ducts: BasicSectionWindingData.LayerData.DuctData(numDucts: 0, ductDimn: 0)), turn: BasicSectionWindingData.TurnData(radialDimn: 0, axialDimn: 0, turnInsulation: 0.125 * meterPerInch, resistancePerMeter: 0, strandRadial: 0, strandAxial: 0))
        let srSection = BasicSection(location: srLocation, N: 0.0, I: 0.0, wdgData: srWdgData,  rect: srRect)
        
        do {
            
            let newSegment = try Segment(basicSections: [srSection], interleaved: false, isStaticRing: true, realWindowHeight: adjacentSegment.realWindowHeight, useWindowHeight: adjacentSegment.useWindowHeight)
                        
            return newSegment
        }
        catch {
            
            throw error
        }
    }
    
    /// Reset the value of the next Segment serial number to be assigned to 0. NOTE:  Any Segments that may have been created by the user prior to calling this function SHOULD BE DESTROYED to avoid problems when testing for equality between Segments (the equality test reiles on the the serial number).
    static func resetSerialNumber()
    {
        Segment.nextSerialNumberStore = 0
    }
    
    /*
    /// Create the Fourier series representation of the current density for the segment. Note that the "useWindowHeight" property of the segment is used to create the series. This is used by DelVecchio.
    func CreateFourierJ() -> [Double]
    {
        var result:[Double] = []
        
        for i in 0...PCH_RABIN2021_IterationCount {
            
            result.append(self.J(n: i))
        }
        
        return result
    } */
    
    /*
    /// Private function to create the n-th entry into the Fourier series representation of the current density, using the max of the real and 'use'  window height as the 'L' variable.
    private func J(n:Int) -> Double
    {
        let L = self.L
        
        if n == 0 {
            
            let result = self.ActualJ * (self.z2 - self.z1) / L
            return result
        }
        
        let z1 = self.z1 + self.zWindHtAdder
        let z2 = self.z2 + self.zWindHtAdder
        
        let nn = Double(n)
        let result:Double = 2.0 * self.ActualJ / (nn * π) * (sin(nn * π * z2 / L) - sin(nn * π * z1 / L))
        
        return result
    } */
}

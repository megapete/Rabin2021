//
//  Segment.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-07.
//

// This file defines the most basic segment that is used for calculations of inductance and capacitance for the model. A Segment is made up of one or more BasicSections.

import Foundation

/// A Segment is, at its most basic, a collection of BasicSections. The collection MUST be from the same Winding and it must represent an axially contiguous (adjacent) collection of coils.The collection may only hold a single BasicSection, or anywhere up to all of the BasicSections that make up a coil (for disc coils, only if there are no central or DV gaps in the coil). It is the unit that is actually modeled (and displayed). Static rings and radial shields are special Segments - creation routines (class functions) are provided for each.
class Segment: Codable, Equatable {
    
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
    struct Connection:Codable, Equatable {
        
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
        
        var segment:Segment?
        var connector:Connector
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
    var ActualJ:Double {
        get {
            return self.N * self.I / self.area
        }
    }
    
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
    
    // Functions required by the paper "New Methods for Computation of the Inductance Matrix of Transformer Windings for Very Fast Transients Studies" by M. Eslamian and B. Vahidi.
    
    /// A synonym for z1
    func y1() -> Double {
        
        return self.z1
    }
    
    /// A synonym for z2
    func y2() -> Double {
        
        return self.z2
    }
    
    /// The radial dimension from the core _surface_ (diameter) to the inner edge of the segment
    func x1(coreRadius:Double) -> Double {
        
        return self.r1 - coreRadius
    }
    
    /// The radial dimension from the core _surface_ (diameter) to the outer edge of the segment
    func x2(coreRadius:Double) -> Double {
        
        return self.r2 - coreRadius
    }
    
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
            
            case EmptyModel
            case IllegalSection
            case StaticRing
            case RadialShield
            case UnimplementedWdgType
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
    
    /// Remove the given connection and its reverse (if it exists). It is the calling routine's responsibility to check (and remove as necessary) any other connections that woiuld effectively keep the bad connector in place. Note that "floating" connections are not removed. If thec connection is to ground or impulse, the connection is converted to a floating connection.
    func RemoveConnection(connection:Segment.Connection) {
        
        if connection.connector.toLocation == .floating {
            
            return
        }
        
        guard let connectionIndex = self.connections.firstIndex(where: { $0 == connection }) else {
            
            return
        }
        
        if let otherSegment = connection.segment {
            
            let otherConnection = Segment.Connection(segment: self, connector: Connector(fromLocation: connection.connector.toLocation, toLocation: connection.connector.fromLocation))
            if let otherConnectionIndex = otherSegment.connections.firstIndex(where: { $0 == otherConnection }) {
                
                otherSegment.connections.remove(at: otherConnectionIndex)
            }
        }
        
        self.connections.remove(at: connectionIndex)
        
        if connection.connector.toLocation == .ground || connection.connector.toLocation == .impulse {
            
            let floatingConnection = Connection(segment: nil, connector: Connector(fromLocation: connection.connector.fromLocation, toLocation: .floating))
            self.connections.append(floatingConnection)
        }
        
    }
    
    /// Add a connector to the segment at the given fromLocation. The toLocation parameter depends on the toSegment parameter:
    /// If toSegment is not nil, then toLocation refers to the location on the toSegment. This routine will also add the inverse connector to the toSegment
    /// If toSegment is nil, then the behaviour of the routine is as follows:
    /// If toLocation is .ground or .impulse and self.connection has a connection with a fromLocation the same as the parameter, and a toLocation equal to .floating, that connector is changed to the new connector definition.
    /// If toLocation is .ground, or .impulse, or .floating, and self.connection does not have a corresponding .floating connector, then the new connector is added to self.connections.
    func AddConnector(fromLocation:Connector.Location, toLocation:Connector.Location, toSegment:Segment?) {
        
        if let otherSegment = toSegment {
            
            // don't create a connector to self
            if otherSegment == self {
                
                return
            }
            
            let newSelfConnection = Connection(segment: otherSegment, connector: Connector(fromLocation: fromLocation, toLocation: toLocation))
            self.connections.append(newSelfConnection)
            let newOtherConnection = Connection(segment: self, connector: Connector(fromLocation: toLocation, toLocation: fromLocation))
            otherSegment.connections.append(newOtherConnection)
        }
        else if let existingFloatingIndex = self.connections.firstIndex(where: {$0.connector.fromLocation == fromLocation && $0.connector.toLocation == .floating}) {
            
            self.connections.remove(at: existingFloatingIndex)
            self.connections.append(Connection(segment: nil, connector: Connector(fromLocation: fromLocation, toLocation: toLocation)))
        }
        else if (toLocation == .ground || toLocation == .impulse) && (self.connections.first(where: {$0.connector.toLocation == .ground}) != nil || self.connections.first(where: {$0.connector.toLocation == .impulse}) != nil) {
            
            // already grounded or impulsed, ignore and return
            return
        }
        else {
            
            self.connections.append(Connection(segment: nil, connector: Connector(fromLocation: fromLocation, toLocation: toLocation)))
        }
    }
    
    /// The series capacitance of the segment caused by the turns of the disc (for continuous-disc windings), double-disc (for interleaved segments) or a single layer (for layer windings). The methods come from (respectively) DelVecchio, Viverka, Huber (ie: me)
    func SeriesCapacitance() throws -> Double {
        
        guard !self.isStaticRing else {
            
            throw SegmentError(info: "\(self.location)", type: .StaticRing)
        }
        
        guard !self.isRadialShield else {
            
            throw SegmentError(info: "\(self.location)", type: .RadialShield)
        }
        
        if self.wdgType == .helical || self.wdgType == .sheet {
            
            return 0.0
        }
        
        do {
            
            let Ctt = try self.CapacitanceTurnToTurn()
            
            if self.wdgType == .disc && self.interleaved {
                
                // Viverka method
                let Cs = Ctt * (self.N - 1) / 2
                
                return Cs
            }
            else if self.wdgType == .disc {
                
                // Del Vecchio method
                let Cs = Ctt * (self.N - 1) / (self.N * self.N)
                
                return Cs
            }
            else if self.wdgType == .layer {
                
                // Huber method. Basically, this uses the Del Vecchio method for discs, but turns it on its side, so that the series capacitance goes in the axial direction and the disc-disc capacitance becomes the layer-layer capacitance. 
                let turnsPerLayer = self.N / Double(self.basicSections[0].wdgData.layers.numLayers)
                let Cs = Ctt * (turnsPerLayer - 1) / (turnsPerLayer * turnsPerLayer)
                
                return Cs
            }
        }
        catch {
            
            throw error
        }
        
        throw SegmentError(info: "", type: .UnimplementedWdgType)
    }
    
    func CapacitanceTurnToTurn() throws -> Double {
        
        guard !self.isStaticRing else {
            
            throw SegmentError(info: "\(self.location)", type: .StaticRing)
        }
        
        guard !self.isRadialShield else {
            
            throw SegmentError(info: "\(self.location)", type: .RadialShield)
        }
        
        if self.wdgType == .helical || self.wdgType == .sheet {
            
            return 0.0
        }
        
        // For disc coils, this corresponds to Ctt in the DelVeccio book. For layer windings, it is the turn-turn capacitance in the axial direction (my own invention).
        
        let tau = 2.0 * self.basicSections[0].wdgData.turn.turnInsulation
        
        if self.wdgType == .disc || self.wdgType == .layer {
            
            // the calculation of the turn thickness of laye windings does not account for ducts in the winding
            let h = self.wdgType == .disc ? self.basicSections[0].height - tau : self.basicSections[0].width / Double(self.basicSections[0].wdgData.layers.numLayers)
            
            var Ctt:Double = ε0 * εPaper
            Ctt *= π * (self.r1 + self.r2)
            Ctt *= (h + 2 * tau) / tau
            
            return Ctt
        }
        
        throw SegmentError(info: "", type: .UnimplementedWdgType)
    }
    
    /// Class function to create a radial shield. The Segment has its 'isRadialShield' property set to true. The radial location of the shield is equal to the _negative_ of the 'adjacentSegment' argument unless the adjacent segment is in coil '0', in which case the radial location of the shield is Int.min. The adjacent segment must be the FIRST (lowest) Segment in the NEXT coil position from the core.  That is, the radial shield will be placed in the hilo UNDER the adjacent Segment. The thickness of the shield is fixed at 2mm. The radial shield should be set to have  the full electrical height of the coil to which adjacentSegment belongs.
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
        let rsWdgData = BasicSectionWindingData(type: .disc, layers: BasicSectionWindingData.LayerData(numLayers: 1, interLayerInsulation: 0, ducts: BasicSectionWindingData.LayerData.DuctData(numDucts: 0, ductDimn: 0)), turn: BasicSectionWindingData.TurnData(radialDimn: rsThickness, axialDimn: elecHt, turnInsulation: 0, resistancePerMeter: 0))
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
        let srWdgData = BasicSectionWindingData(type: .disc, layers: BasicSectionWindingData.LayerData(numLayers: 1, interLayerInsulation: 0, ducts: BasicSectionWindingData.LayerData.DuctData(numDucts: 0, ductDimn: 0)), turn: BasicSectionWindingData.TurnData(radialDimn: 0, axialDimn: 0, turnInsulation: 0.125 * meterPerInch, resistancePerMeter: 0))
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
    
    /// Create the Fourier series representation of the current density for the segment. Note that the "useWindowHeight" property of the segment is used to create the series. This is used by DelVecchio.
    func CreateFourierJ() -> [Double]
    {
        var result:[Double] = []
        
        for i in 0...PCH_RABIN2021_IterationCount {
            
            result.append(self.J(n: i))
        }
        
        return result
    }
    
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
    }
}

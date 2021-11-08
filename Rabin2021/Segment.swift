//
//  Segment.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-07.
//

import Foundation

/// A segment is a collection of BasicSections. The collection MUST be from the same Winding and it must represent an axially contiguous (adjacent) collection of coils.The collection may only hold a single BasicSection, or anywhere up to all of the BasicSections that make up a coil (only if there are no central or DV gaps in the coil). It is the unit that is actually modeled (and displayed).

struct Segment: Codable, Equatable {
    
    static func == (lhs: Segment, rhs: Segment) -> Bool {
        
        return lhs.serialNumber == rhs.serialNumber
    }
    
    private static var nextSerialNumberStore:Int = 0
    
    /// Return the next available serial number for the Segment class.
    static var nextSerialNumber:Int {
        get {
            
            let nextNum = Segment.nextSerialNumberStore
            Segment.nextSerialNumberStore += 1
            return nextNum
        }
    }
    
    /// Segment serial number (needed for the mirrorSegment property and to make the "==" operator code simpler
    let serialNumber:Int
    
    /// The first (index = 0) entry  has the lowest Z and the last entry has the highest.
    private var basicSectionStore:[BasicSection] = []
        
    /// A Boolean to indicate whether the segment is interleaved
    var interleaved:Bool
    
    /// The series current through a single turn in the segment
    let I:Double
    
    /// The radial position of the segment (0 = closest to core)
    var radialPos:Int {
        get {
            guard self.basicSectionStore.count > 0 else {
                return -1
            }
            
            return self.basicSectionStore[0].location.radial
        }
    }
    
    /// The _actual_ window height for the core
    let realWindowHeight:Double
    
    /// The window height that is used for the model
    let useWindowHeight:Double
    
    /// The rectangle that the segment occupies in the core window, with the origin at (LegCenter, BottomYoke)
    var rect:NSRect
    
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
    
    /// The number of tuns in the Segment
    var N:Double {
        get {
            var result = 0.0
            
            for nextSection in self.basicSectionStore {
                
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
    /// - Note: This initiializer may fail.
    /// - Parameter basicSections: An array of BasicSections. The sections must be part of the same Winding, be adjacent, and in order from lowest Z to highest Z.
    /// - Parameter interleaved: Boolean for indication of whether the Segment is interleaved or not (default: false)
    /// - Parameter realWindowHeight: The actual window height of the core
    /// - Parameter useWindowHeight: The window height that should be used (important for some Delvecchio calculations)
    init?(basicSections:[BasicSection], interleaved:Bool = false, realWindowHeight:Double, useWindowHeight:Double)
    {
        guard let first = basicSections.first, let last = basicSections.last else {
            
            DLog("Array is empty")
            return nil
        }
        
        let winding = first.location.radial
        var axialIndex = first.location.axial
        var zCurrent = first.z1
        self.I = first.I
        self.realWindowHeight = realWindowHeight
        self.useWindowHeight = useWindowHeight
        
        for i in 1..<basicSections.count {
            
            guard basicSections[i].location.axial == axialIndex + 1, basicSections[i].z1 > zCurrent, basicSections[i].location.radial == winding else {
                
                DLog("Illegal entry in array")
                return nil
            }
            
            axialIndex = basicSections[i].location.axial
            zCurrent = basicSections[i].z1
        }
        
        // if we get here, we can save the array and set the properties
        self.basicSectionStore = basicSections
        self.interleaved = interleaved
        
        self.rect = NSRect(x: first.r1, y: first.z1, width: first.width, height: last.z2 - first.z1)
        self.serialNumber = Segment.nextSerialNumber
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

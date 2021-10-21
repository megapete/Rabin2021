//
//  Segment.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-07.
//

import Foundation

/// A segment is a collection of BasicSections. The collection MUST be from the same Winding and it must represent a contiguous (adjacent) collection of coils.The collection may only hold a single BasicSection, or anywhere up to all of the BasicSections that make up a coil (only if there are no central or DV gaps in the coil). It is the unit that is actually modeled (and displayed).
/// 
struct Segment: Codable, Equatable {
    
    static func == (lhs: Segment, rhs: Segment) -> Bool {
        
        return lhs.serialNumber == rhs.serialNumber
    }
    
    private static var nextSerialNumberStore:Int = 0
    
    static var nextSerialNumber:Int {
        get {
            
            let nextNum = Segment.nextSerialNumberStore
            Segment.nextSerialNumberStore += 1
            return nextNum
        }
    }
    
    /// Segment serial number (needed for the mirrorSegment property and to make the "==" operator code simpler
    let serialNumber:Int
    
    /// The first (index = 0) entry  has the lowest Z and the last enrty has the highest.
    private var basicSectionStore:[BasicSection] = []
        
    /// A Boolean to indicate whether the segment is interlaved
    var interleaved:Bool
    
    /// The series current through the segment
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
    
    /// The rectangle that the segment occupies in the core window
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
    
    var area:Double {
        get {
            return Double(self.rect.width * self.rect.height)
        }
    }
    
    var N:Double {
        get {
            var result = 0.0
            
            for nextSection in self.basicSectionStore {
                
                result += nextSection.N
            }
            
            return result
        }
    }
    
    var ActualJ:Double {
        get {
            return self.N * self.I / self.area
        }
    }
    
    // Alternative variable names as defined in the paper "New Methods for Computation of the Inductance Matrix of Transformer Windings for Very Fast Transients Studies" by M. Eslamian and B. Vahidi. For now, we just use the single-Fourier series method inside the core window.
    
    var H:Double {
        get {
            return self.L
        }
    }
    
    var y1:Double {
        get {
            return self.z1
        }
    }
    
    var y2:Double {
        get {
            return self.z2
        }
    }
    
    var x1:Double {
        get {
            return self.r1
        }
    }
    
    var x2:Double {
        get {
            return self.r2
        }
    }
    
    /// Constructor for a Segment. The array of BasicSections that is passed in is checked to make sure that all sections are part of the same coil, and that they are adjacent and in order from lowest Z to highest Z.
    /// - Parameter basicSections: An array of BasicSections. The sections must be part of the same Winding, be adjacent, and in order from lowest Z to highest Z.
    /// - Parameter interleaved: Boolean for indication of whether the Segment is interleaved or not (default: false)
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
    
    static func resetSerialNumber()
    {
        Segment.nextSerialNumberStore = 0
    }
    
    /// Create the Fourier series representation of the current density for the segment. Note that the "useWindowHeight" property of the segment is used to create the series.
    func CreateFourierJ() -> [Double]
    {
        var result:[Double] = []
        
        for i in 0...PCH_RABIN2021_IterationCount {
            
            result.append(self.J(n: i))
        }
        
        return result
    }
    
    /// Private function to create the n-th entry into the Fourier series representation of the current deinsity, using the max of the real and 'use'  window height as the 'L' variable.
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

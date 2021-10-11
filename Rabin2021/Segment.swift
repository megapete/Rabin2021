//
//  Segment.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-07.
//

import Foundation

/// A segment is a collection of BasicSections. The collection MUST be from the same Winding and it must represent a contiguous (adjacent) collection of coils.The collection may only hold a single BasicSection, or anywhere up to all of the BasicSections that make up a coil (only if there are no central or DV gaps in the coil). It is the unit that is actually modeled (and displayed).
/// 
struct Segment: Equatable {
    
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
        
    var interleaved:Bool
    
    var radialPos:Int {
        get {
            guard self.basicSectionStore.count > 0 else {
                return -1
            }
            
            return self.basicSectionStore[0].location.radial
        }
    }
    
    var rect:NSRect
    
    var r1:Double {
        get {
            return self.rect.origin.x
        }
    }
    
    var r2:Double {
        get {
            return Double(self.rect.origin.x + self.rect.size.width)
        }
    }
    
    var z1:Double {
        get {
            return Double(self.rect.origin.y)
        }
    }
    
    var z2:Double {
        get {
            return Double(self.rect.origin.y + self.rect.size.height)
        }
    }
    
    /// Constructor for a Segment. The array of BasicSections that is passed in is checked to make sure that all sections are part of the same coil, and that they are adjacent and in order from lowest Z to highest Z.
    /// - Parameter basicSections: An array of BasicSections. The sections must be part of the same Winding, be adjacent, and in order from lowest Z to highest Z.
    /// - Parameter interleaved: Boolean for indication of whether the Segment is interleaved or not (default: false)
    init?(basicSections:[BasicSection], interleaved:Bool = false)
    {
        guard let first = basicSections.first, let last = basicSections.last else {
            
            DLog("Array is empty")
            return nil
        }
        
        let winding = first.location.radial
        var axialIndex = first.location.axial
        var zCurrent = first.z1
        
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
}

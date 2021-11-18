//
//  BasicSection.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-06.
//

import Cocoa

/// A LocStruct holds the physical location of a coil section in the window.
struct LocStruct:Codable, CustomStringConvertible, Comparable {
    
    static func < (lhs: LocStruct, rhs: LocStruct) -> Bool {
        
        if lhs.radial != rhs.radial {
            
            return lhs.radial < rhs.radial
        }
        else {
            
            return lhs.axial < rhs.axial
        }
    }
    
    
    var description: String {
        
        return "(R:\(self.radial), A:\(self.axial))"
    }
    
    /// The radial location, where 0 is closest to the core leg.
    let radial:Int
    /// The axial location, where 0 is closest to the bottom yoke.
    let axial:Int
}

/// This struct defines  the most basic definitiion of a coil section. There are no "electrical" functions defined for the struct. It is basically just used to describe the physical and electrical characteristics of a coil section (either a single disc or a single layer). 
struct BasicSection:Codable {
    
    /// The location of the section
    let location:LocStruct
    
    /// The number of turns in the section
    let N:Double
    /// The series current through a single turn in the section
    let I:Double
    
    /// The coil type
    let wdgType:PCH_ExcelDesignFile.Winding.WindingType
    
    /// The rectangle that holds the section, assuming that the origin is at (x=coreCenter, y=topOfBottomYoke)
    private var rect:NSRect
    
    /// Deisgnated initializer
    /// - Parameter location: A LocStruct that is the location of the BasicSection in the phase
    /// - Parameter wdgType: The PCH_ExcelDesignFile.Winding.WindingType of the owning winding
    /// - Parameter N: The number of turns in the section
    /// - Parameter I: The series current in a single turn of the section
    /// - Parameter rect: The rectangle that the section occupies. The origin is at (LegCenter, BottomYoke)
    init(location:LocStruct, N:Double, I:Double, wdgType:PCH_ExcelDesignFile.Winding.WindingType, rect:NSRect)
    {
        self.location = location
        self.N = N
        self.I = I
        self.rect = rect
        self.wdgType = wdgType
    }
    
    /// The area of the section
    var area:Double {
        get {
            return Double(self.rect.width * self.rect.height)
        }
    }
    
    /// The radial dimension from the core leg center to the left-most edge of the section
    var r1:Double {
        get {
            return Double(self.rect.origin.x)
        }
        set {
            self.rect.origin.x = CGFloat(newValue)
        }
    }
    
    /// The radial dimension from the core leg center to the right-most edge of the section
    var r2:Double {
        get {
            return Double(self.rect.origin.x + self.rect.size.width)
        }
        set {
            self.rect.size.width = CGFloat(newValue) - self.rect.origin.x
        }
    }
    
    /// The axial dimension from the core bottom yoke to the bottom-most edge of the section
    var z1:Double {
        get {
            return Double(self.rect.origin.y)
        }
        set {
            self.rect.origin.y = CGFloat(newValue)
        }
    }
    
    /// The axial dimension from the core bottom yoke to the top-most edge of the section
    var z2:Double {
        get {
            return Double(self.rect.origin.y + self.rect.size.height)
        }
        set {
            self.rect.size.height = CGFloat(newValue) - self.rect.origin.y
        }
    }
    
    /// The height of the section
    var height:Double {
        get {
            return Double(self.rect.size.height)
        }
    }
    
    /// The radial build (width) of the section
    var width:Double {
        get {
            return Double(self.rect.size.width)
        }
    }
    
    
}

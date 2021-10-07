//
//  BasicSection.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-06.
//

import Cocoa

/// This struct defines  the most basic definitiion of a coil section. There are no "electrical" functions defined for the struct. It is basically just used to describe the physical and electrical characteristics of a coil section (either a single disc or a single layer).
struct BasicSection:Codable {
    
    struct LocStruct:Codable {
        let radial:Int // 0 is closest to core
        let axial:Int // 0 is closest to bottom yoke
    }
    
    /// The location of the section
    let location:LocStruct
    
    /// The number of turns in the section
    let N:Double
    /// The series current in the section
    let I:Double
    
    private var rect:NSRect
    
    /// The area of the section
    var area:Double {
        get {
            return Double(self.rect.width * self.rect.height)
        }
    }
    
    var r1:Double {
        get {
            return Double(self.rect.origin.x)
        }
        set {
            self.rect.origin.x = CGFloat(newValue)
        }
    }
    
    var r2:Double {
        get {
            return Double(self.rect.origin.x + self.rect.size.width)
        }
        set {
            self.rect.size.width = CGFloat(newValue) - self.rect.origin.x
        }
    }
    
    var z1:Double {
        get {
            return Double(self.rect.origin.y)
        }
        set {
            self.rect.origin.y = CGFloat(newValue)
        }
    }
    
    var z2:Double {
        get {
            return Double(self.rect.origin.y + self.rect.size.height)
        }
        set {
            self.rect.size.height = CGFloat(newValue) - self.rect.origin.y
        }
    }
    
    var height:Double {
        get {
            return Double(self.rect.size.height)
        }
    }
    
    var width:Double {
        get {
            return Double(self.rect.size.width)
        }
    }
    
    let aboveInsulation:Double
    let belowInsulation:Double
}

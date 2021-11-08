//
//  Core.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-07.
//

import Foundation

/// A simple core class, used for inductance calculations
class Core:Codable
{
    /// The diameter of the core
    let diameter:Double
    
    /// The actual window height of the core
    let realWindowHeight:Double
    
    /// The dimension between leg centers on the core
    let legCenters:Double
    
    /// The multiplier used to adjust the  windowheight (used for certain DelVecchio calculations)
    var windHtMultiplier:Double
    
    /// The adjusted window height  (used for certain DelVecchio calculations)
    var adjustedWindHt:Double {
        
        get {
            return self.realWindowHeight * self.windHtMultiplier
        }
    }
    
    /// The core radius
    var radius:Double {
        get {
            return self.diameter / 2.0
        }
    }
    
    /// The window width (from diameter to diameter)
    var windowWidth:Double {
        get {
            return self.legCenters - self.diameter
        }
    }
    
    ///  Designated initializer
    ///  - Parameter diameter: The diameter of the core
    ///  - Parameter realWindowHeight: The actual window height of the core
    ///  - Parameter windHtMultiplier: The multiplier to adjust the window height for certain DelVecchio calculations (default = 3)
    ///  - Parameter legCenters: The dimension between leg centers of the core
    init(diameter:Double, realWindowHeight:Double, windHtMultiplier:Double = 3.0, legCenters:Double) {
        self.diameter = diameter
        self.realWindowHeight = realWindowHeight
        self.windHtMultiplier = windHtMultiplier
        self.legCenters = legCenters
    }
    
    
}

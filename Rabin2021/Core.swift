//
//  Core.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-07.
//

import Foundation

class Core:Codable
{
    let diameter:Double
    let realWindowHeight:Double
    let legCenters:Double
    
    var windHtMultiplier:Double
    
    var adjustedWindHt:Double {
        
        get {
            return self.realWindowHeight * self.windHtMultiplier
        }
    }
    
    var radius:Double {
        get {
            return self.diameter / 2.0
        }
    }
    
    var windowWidth:Double {
        get {
            return self.legCenters - self.diameter
        }
    }
    
    init(diameter:Double, realWindowHeight:Double, windHtMultiplier:Double = 3.0, legCenters:Double) {
        self.diameter = diameter
        self.realWindowHeight = realWindowHeight
        self.windHtMultiplier = windHtMultiplier
        self.legCenters = legCenters
    }
    
    
}

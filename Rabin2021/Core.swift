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
    
    var windHtMultiplier:Double
    
    var adjustedWindHt:Double {
        
        get {
            return realWindowHeight * windHtMultiplier
        }
    }
    
    var radius:Double {
        get {
            return self.diameter / 2.0
        }
    }
    
    init(diameter:Double, realWindowHeight:Double, windHtMultiplier:Double = 3.0) {
        self.diameter = diameter
        self.realWindowHeight = realWindowHeight
        self.windHtMultiplier = windHtMultiplier
    }
    
    
}

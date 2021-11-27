//
//  Connector.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2021-11-27.
//

import Foundation


struct Connector:Codable {
    
    enum Location:Codable {
        
        case outside_upper
        case center_upper
        case inside_upper
        
        case outside_lower
        case center_lower
        case inside_lower
        
        // special locations (that are not really locations but more accurately, 'terminations')
        case floating
        case ground
        case shot
    }
    
    let fromLocation:Location
    let toLocation:Location
    
}

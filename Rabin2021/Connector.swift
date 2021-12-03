//
//  Connector.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2021-11-27.
//

import Foundation

// A connector is usually the little line that connects two adjacent axial coil segments. To see how this is actually used, see the comment for Segment.Connection

struct Connector:Codable {
    
    enum Location:Codable {
        
        case outside_upper
        case center_upper
        case inside_upper
        
        case outside_center
        case inside_center
        
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
    
    static func AlternatingLocation(lastLocation:Connector.Location) -> Connector.Location {
        
        if lastLocation == .outside_upper {
            
            return .inside_lower
        }
        else if lastLocation == .inside_lower {
            
            return .outside_upper
        }
        else if lastLocation == .center_lower {
            
            return .center_upper
        }
        else if lastLocation == .center_upper {
            
            return .center_lower
        }
        else if lastLocation == .inside_upper {
            
            return .outside_lower
        }
        else if lastLocation == .outside_lower {
            
            return .inside_upper
        }
        else if lastLocation == .outside_center {
            
            return .inside_center
        }
        else if lastLocation == .inside_center {
            
            return .outside_center
        }
        
        // must be one of the "special" locations, just return the same value
        return lastLocation
    }
    
    // This function should only be used for helical or disc coils
    static func StandardToLocation(fromLocation:Connector.Location) -> Connector.Location {
        
        if fromLocation == .center_upper {
            
            return .center_lower
        }
        else if fromLocation == .center_lower {
            
            return .center_upper
        }
        else if fromLocation == .inside_upper {
            
            return .inside_lower
        }
        else if fromLocation == .inside_lower {
            
            return .inside_upper
        }
        else if fromLocation == .outside_upper {
            
            return .outside_lower
        }
        else if fromLocation == .outside_lower {
            
            return .outside_upper
        }
        
        return fromLocation
    }
    
}

//
//  ShuntCapacitance.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2022-03-11.
//

import Foundation

struct ShuntCapacitance:Codable, Equatable {
    
    let fromSegment:Segment
    let fromNode:Connector.Location
    
    let toSegment:Segment
    let toNode:Connector.Location
    
    var capacitance:Double = 0.0
}

//
//  Node.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2022-03-15.
//

import Foundation

struct Node:Codable {
    
    // The identifying number for the Node. This is also used as the index into the capaciance matrix, so it is 0-based
    let number:Int
    
    let aboveSegment:Segment?
    // var aboveConnector:Connector
    
    let belowSegment:Segment?
    // var belowConnector:Connector
    
    // note: shunt capacitances to ground must have toNode set to -1
    struct shuntCap:Codable {
        
        let toNode:Int
        let capacitance:Double
    }
    
    var shuntCapacitances:[shuntCap] = []
}

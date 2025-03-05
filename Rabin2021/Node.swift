//
//  Node.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2022-03-15.
//

import Foundation

struct Node:Codable, Hashable, Sendable {
    
    static func == (lhs: Node, rhs: Node) -> Bool {
        
        return lhs.number == rhs.number
    }
    
    func hash(into hasher: inout Hasher) {
        
        hasher.combine(number)
    }
    
    /// The identifying number for the Node. This is also used as the index into the capaciance matrix, so it is 0-based
    let number:Int
    
    /// The Segment immediately above that is actually connected to the Node (this will be nil for the highest Node of a coil)
    let aboveSegment:Segment?
    
    /// The Segment immediately below that is actually connected to the Node (this will be nil for the lowest Node of a coil)
    let belowSegment:Segment?
    
    /// The z-dimension of the Node
    let z:Double
    
    // note: shunt capacitances to ground must have toNode set to -1
    struct shuntCap:Codable {
        
        let toNode:Int
        let capacitance:Double
    }
    
    var shuntCapacitances:[shuntCap] = []
}

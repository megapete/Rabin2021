//
//  PhaseModel.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-13.
//

import Foundation

class PhaseModel:Codable {
    
    var segments:[Segment]
    
    init(segments:[Segment]) {
        
        self.segments = segments
    }
}

//
//  CoilSection.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-07.
//

import Foundation

/// A coil section is a collection of BasicSections. The collection may only hold a single BasicSection, or all of the BasicSections that make up a coil (only if there are no central or DV gaps in the coil).
class CoilSection:Codable {
    
    private var basicSectionStore:[BasicSection] = []
    
    let location:LocStruct
    
    var interleaved:Bool
}

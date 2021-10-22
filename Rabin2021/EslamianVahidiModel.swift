//
//  EslamianVahidiModel.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-22.
//

// This is an attempt to encapsulate the methods and formulas presented in the technical paper "New Methods for Computation of the Inductance Matrix of Transformer Windings for Very Fast Transients Studies" by M. Eslamian and B. Vahidi. To begin, only the Double-Fourier Series method Inside the Core Window is implemented. If that works well, I may try and implement the Outside the Core Window calculation as well.

// Use of this struct requires that the "Segment" class from Rabin2021 be included in the project.

import Foundation

struct EslamianVahidi {
    
    let segment:Segment
    let core:Core
    
    func J(m:Int, n:Int) -> Double {
        
        let mm = Double(m)
        let nn = Double(n)
        
        let L = self.core.windowWidth
        let H = self.core.realWindowHeight
        
        let firstTerm = 4.0 * self.segment.ActualJ / (mm * nn * π * π)
        let secondTerm = cos(mm * π * self.segment.x1(coreRadius: self.core.radius) / L) - cos(mm * π * self.segment.x2(coreRadius: self.core.radius) / L)
        let thirdTerm = cos(nn * π * self.segment.y1() / H) - cos(nn * π * self.segment.y2() / H)
        
        return firstTerm * secondTerm * thirdTerm
    }
    
    func A(m:Int, n:Int) -> Double {
        
        let mm = Double(m)
        let nn = Double(n)
        
        let L = self.core.windowWidth
        let H = self.core.realWindowHeight
        
        let numerator = µ0 * self.J(m: m, n: n)
        let denominator = (mm * π / L) * (mm * π / L) + (nn * π / H) * (nn * π / H)
        
        return numerator / denominator
    }
    
    // self inductance
    func L() -> Double {
        
        return M(otherSegment: self)
    }
    
    // mutual inductance
    func M(otherSegment:EslamianVahidi) -> Double {
        
        let iterations = 300
        
        let L = self.core.windowWidth
        let H = self.core.realWindowHeight
        
        let I1 = self.segment.I
        let I2 = otherSegment.segment.I
        
        var sum = 0.0
        for m in 1...iterations {
            for n in 1...iterations {
                
                sum += self.J(m: m, n: n) * otherSegment.A(m: m, n: n)
            }
        }
        
        return L * H / (4 * I1 * I2) * sum
    }
    
}

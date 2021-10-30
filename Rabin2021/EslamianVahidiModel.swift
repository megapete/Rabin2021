//
//  EslamianVahidiModel.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-22.
//

// This is an attempt to encapsulate the methods and formulas presented in the technical paper "New Methods for Computation of the Inductance Matrix of Transformer Windings for Very Fast Transients Studies" by M. Eslamian and B. Vahidi. To begin, only the Double-Fourier Series method Inside the Core Window is implemented. If that works well, I may try and implement the Outside the Core Window calculation as well.

// Use of this struct requires that the "Segment" class from Rabin2021 be included in the project.

import Foundation

class EslamianVahidi {
    
    static let iterations = 200
    
    let segment:Segment
    let core:Core
    
    var J_DoubleFourier:[[Double]] = Array(repeating: Array(repeating: 0.0, count: EslamianVahidi.iterations), count: EslamianVahidi.iterations)
    var A_InWindow:[[Double]] = Array(repeating: Array(repeating: 0.0, count: EslamianVahidi.iterations), count: EslamianVahidi.iterations)
    
    
    init(segment:Segment, core:Core) {
        
        self.segment = segment
        self.core = core
        
        print("Calculating all Jmn and Amn for segment: \(segment.serialNumber)")
        for m in 0..<EslamianVahidi.iterations {
            for n in 0..<EslamianVahidi.iterations {
                
                self.J_DoubleFourier[m][n] = self.J_DoubleFourier(m: m + 1, n: n + 1)
                self.A_InWindow[m][n] = self.A_pu_InWindow(m: m + 1, n: n + 1)
            }
        }
        print("Done!")
        
    }
    
    func J_DoubleFourier(m:Int, n:Int) -> Double {
        
        let mm = Double(m)
        let nn = Double(n)
        
        let L = self.core.windowWidth
        let H = self.core.realWindowHeight
        
        let firstTerm = 4.0 * self.segment.ActualJ / (mm * nn * π * π)
        let secondTerm = cos(mm * π * self.segment.x1(coreRadius: self.core.radius) / L) - cos(mm * π * self.segment.x2(coreRadius: self.core.radius) / L)
        let thirdTerm = cos(nn * π * self.segment.y1() / H) - cos(nn * π * self.segment.y2() / H)
        
        return firstTerm * secondTerm * thirdTerm
    }
    
    func A_pu_InWindow(m:Int, n:Int) -> Double {
        
        let mm = Double(m)
        let nn = Double(n)
        
        let L = self.core.windowWidth
        let H = self.core.realWindowHeight
        
        let numerator = µ0 * self.J_DoubleFourier(m: m, n: n)
        let denominator = (mm * π / L) * (mm * π / L) + (nn * π / H) * (nn * π / H)
        
        return numerator / denominator
    }
     
    // self inductance (in the window, per-unit-length)
    func L_pu_InWindow() -> Double {
        
        return M_pu_InWindow(otherSegment: self)
    }
    
    // mutual inductance (in the window, per-unit-length)
    func M_pu_InWindow(otherSegment:EslamianVahidi) -> Double {
        
        let L = self.core.windowWidth
        let H = self.core.realWindowHeight
        
        let I1 = self.segment.I
        let I2 = otherSegment.segment.I
                
        var sum = 0.0
        for m in 0..<EslamianVahidi.iterations {
            
            for n in 0..<EslamianVahidi.iterations {
    
                sum += self.J_DoubleFourier[m][n] * otherSegment.A_InWindow[m][n]
            }
        }
        
        return L * H / (4 * I1 * I2) * sum
    }
    
}

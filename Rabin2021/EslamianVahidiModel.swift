//
//  EslamianVahidiModel.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-22.
//

// This is an attempt to encapsulate the methods and formulas presented in the technical paper "New Methods for Computation of the Inductance Matrix of Transformer Windings for Very Fast Transients Studies" by M. Eslamian and B. Vahidi. To begin, only the Double-Fourier Series method Inside the Core Window is implemented. If that works well, I may try and implement the Outside the Core Window calculation as well.

// Use of this struct requires that the "Segment" class from Rabin2021 be included in the project.

import Foundation
import Accelerate

class EslamianVahidi {
    
    static let iterations = 200
    
    let segment:Segment
    let core:Core
    
    let yCenter:Double
    
    var J_DoubleFourier:[[Double]] = Array(repeating: Array(repeating: 0.0, count: EslamianVahidi.iterations), count: EslamianVahidi.iterations)
    var A_InWindow:[[Double]] = Array(repeating: Array(repeating: 0.0, count: EslamianVahidi.iterations), count: EslamianVahidi.iterations)
    
    
    init(segment:Segment, core:Core) {
        
        self.segment = segment
        self.core = core
        self.yCenter = (segment.y1() + segment.y2()) / 2.0
        
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
    
    func M_pu_OutsideWindow(otherSegment:EslamianVahidi) -> Double {
        
        let J1 = self.segment.ActualJ
        let I1 = self.segment.I
        let I2 = otherSegment.segment.I
        
        let coreRadius = self.core.radius
        
        let c = (otherSegment.segment.x1(coreRadius: coreRadius) + otherSegment.segment.x2(coreRadius: coreRadius)) / 2.0
        
        let uStart = self.segment.x1(coreRadius: coreRadius)
        let uEnd = self.segment.x2(coreRadius: coreRadius)
        
        
        let absTol = 1.0E-10
        let relTol = 1.0E-9
        
        let outerQuadrature1 = Quadrature(integrator: .qng, absoluteTolerance: absTol, relativeTolerance: relTol)
        let innerQuadrature1 = Quadrature(integrator: .qng, absoluteTolerance: absTol, relativeTolerance: relTol)
        
        let A_plus_2 = outerQuadrature1.integrate(over: (uStart-c)...(uEnd-c)) { u in
            
            let yOffset = self.yCenter - otherSegment.yCenter
            
            let yStart = self.segment.y1() + yOffset
            let yEnd = self.segment.y2() + yOffset
            
            
            let a = otherSegment.segment.rect.width / 2.0
            let b = otherSegment.segment.rect.height / 2.0
            
            let innerA = innerQuadrature1.integrate(over: yStart...yEnd) { v in
                
                let term1 = (b - v) * (a - u) * log((b - v) * (b - v) + (a - u) * (a - u))
                let term2 = (b - v) * (a + u) * log((b - v) * (b - v) + (a + u) * (a + u))
                let term3 = (b + v) * (a - u) * log((b + v) * (b + v) + (a - u) * (a - u))
                let term4 = (b + v) * (a + u) * log((b + v) * (b + v) + (a + u) * (a + u))
                
                let term5 = (b - v) * (b - v) * (atan((a - u) / (b - v)) + atan((a + u) / (b - v)))
                let term6 = (b + v) * (b + v) * (atan((a - u) / (b + v)) + atan((a + u) / (b + v)))
                let term7 = (a - u) * (a - u) * (atan((b - v) / (a - u)) + atan((b + v) / (a - u)))
                let term8 = (a + u) * (a + u) * (atan((b - v) / (a + u)) + atan((b + v) / (a + u)))
                
                let term9 = 12.0 * a * b
                
                return -µ0 * otherSegment.segment.I / (16.0 * π * a * b) * (term1 + term2 + term3 + term4 + term5 + term6 + term7 + term8 - term9)
            }
            
            switch innerA {
                
            case .success((let result, _)):
                return result
                
            case .failure(let error):
                ALog("Error calling integration routine. The error is: \(error)")
                return 0.0
            }
        }
        
        var funcResult = 0.0
        
        switch A_plus_2 {
            
        case .success((let result, _)):
            funcResult = result
            
        case .failure(let error):
            ALog("Error calling integration routine. The error is: \(error)")
            return 0.0
        }
        
        let outerQuadrature2 = Quadrature(integrator: .qng, absoluteTolerance: absTol, relativeTolerance: relTol)
        let innerQuadrature2 = Quadrature(integrator: .qng, absoluteTolerance: absTol, relativeTolerance: relTol)
        
        let A_minus_2 = outerQuadrature2.integrate(over: (uStart+c)...(uEnd+c)) { u in
            
            let yStart = self.segment.y1()
            let yEnd = self.segment.y2()
            
            let a = otherSegment.segment.rect.width / 2.0
            let b = otherSegment.segment.rect.height / 2.0
            
            let innerA = innerQuadrature2.integrate(over: yStart...yEnd) { v in
                
                let term1 = (b - v) * (a - u) * log((b - v) * (b - v) + (a - u) * (a - u))
                let term2 = (b - v) * (a + u) * log((b - v) * (b - v) + (a + u) * (a + u))
                let term3 = (b + v) * (a - u) * log((b + v) * (b + v) + (a - u) * (a - u))
                let term4 = (b + v) * (a + u) * log((b + v) * (b + v) + (a + u) * (a + u))
                
                let term5 = (b - v) * (b - v) * (atan((a - u) / (b - v)) + atan((a + u) / (b - v)))
                let term6 = (b + v) * (b + v) * (atan((a - u) / (b + v)) + atan((a + u) / (b + v)))
                let term7 = (a - u) * (a - u) * (atan((b - v) / (a - u)) + atan((b + v) / (a - u)))
                let term8 = (a + u) * (a + u) * (atan((b - v) / (a + u)) + atan((b + v) / (a + u)))
                
                let term9 = 12.0 * a * b
                
                return -µ0 * otherSegment.segment.I / (16.0 * π * a * b) * (term1 + term2 + term3 + term4 + term5 + term6 + term7 + term8 - term9)
            }
            
            switch innerA {
                
            case .success((let result, _)):
                return result
                
            case .failure(let error):
                ALog("Error calling integration routine. The error is: \(error)")
                return 0.0
            }
        }
        
        switch A_minus_2 {
            
        case .success((let result, _)):
            funcResult += result
            
        case .failure(let error):
            ALog("Error calling integration routine. The error is: \(error)")
            return 0.0
        }
        
        return J1 / (I1 * I2) * funcResult
        
    }
    
}

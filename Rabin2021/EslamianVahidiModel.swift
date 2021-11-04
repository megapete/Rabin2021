//
//  EslamianVahidiModel.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-22.
//

// This is an attempt to encapsulate the methods and formulas presented in the technical paper "New Methods for Computation of the Inductance Matrix of Transformer Windings for Very Fast Transients Studies" by M. Eslamian and B. Vahidi. To begin, only the Double-Fourier Series method Inside the Core Window is implemented. The Outside the Core Window method is also implemented. Both methods have been compared to the results in the paper. The Outside the Core Window calculations match exactly, while the Inside the Core Window reesults are very close (I think they probably used the Single-Fourier Series method).

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
        
        let firstTerm:Double = 4.0 * self.segment.ActualJ / (mm * nn * π * π)
        let secondTerm:Double = cos(mm * π * self.segment.x1(coreRadius: self.core.radius) / L) - cos(mm * π * self.segment.x2(coreRadius: self.core.radius) / L)
        let thirdTerm:Double = cos(nn * π * self.segment.y1() / H) - cos(nn * π * self.segment.y2() / H)
        
        return firstTerm * secondTerm * thirdTerm
    }
    
    func A_pu_InWindow(m:Int, n:Int) -> Double {
        
        let mm = Double(m)
        let nn = Double(n)
        
        let L = self.core.windowWidth
        let H = self.core.realWindowHeight
        
        let numerator:Double = µ0 * self.J_DoubleFourier(m: m, n: n)
        let denominator:Double = (mm * π / L) * (mm * π / L) + (nn * π / H) * (nn * π / H)
        
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
        
        let J1:Double = self.segment.ActualJ
        let I1:Double = self.segment.I
        let I2:Double = otherSegment.segment.I
        
        let coreRadius:Double = self.core.radius
        
        let c:Double = (otherSegment.segment.x1(coreRadius: coreRadius) + otherSegment.segment.x2(coreRadius: coreRadius)) / 2.0
        
        let uStart:Double = self.segment.x1(coreRadius: coreRadius)
        let uEnd:Double = self.segment.x2(coreRadius: coreRadius)
        
        
        let absTol = 1.0E-10
        let relTol = 1.0E-9
        
        let outerQuadrature1 = Quadrature(integrator: .qng, absoluteTolerance: absTol, relativeTolerance: relTol)
        let innerQuadrature1 = Quadrature(integrator: .qng, absoluteTolerance: absTol, relativeTolerance: relTol)
        
        let A_plus_2 = outerQuadrature1.integrate(over: (uStart-c)...(uEnd-c)) { u in
            
            let yOffset:Double = self.yCenter - otherSegment.yCenter
            let yHeight:Double = self.segment.rect.height
            let yStart:Double = yOffset - yHeight / 2.0
            let yEnd:Double = yStart + yHeight
            
            let a:Double = otherSegment.segment.rect.width / 2.0
            let b:Double = otherSegment.segment.rect.height / 2.0
            
            let innerA = innerQuadrature1.integrate(over: yStart...yEnd) { v in
                
                let b_minus_v_squared:Double = (b - v) * (b - v)
                let b_plus_v_squared:Double = (b + v) * (b + v)
                let a_minus_u_squared:Double = (a - u) * (a - u)
                let a_plus_u_squared:Double = (a + u) * (a + u)
                
                let term1:Double = (b - v) * (a - u) * log(b_minus_v_squared + a_minus_u_squared)
                let term2:Double = (b - v) * (a + u) * log(b_minus_v_squared + a_plus_u_squared)
                let term3:Double = (b + v) * (a - u) * log(b_plus_v_squared + a_minus_u_squared)
                let term4:Double = (b + v) * (a + u) * log(b_plus_v_squared + a_plus_u_squared)
                
                let term5:Double = (b - v) * (b - v) * (atan((a - u) / (b - v)) + atan((a + u) / (b - v)))
                let term6:Double = (b + v) * (b + v) * (atan((a - u) / (b + v)) + atan((a + u) / (b + v)))
                let term7:Double = (a - u) * (a - u) * (atan((b - v) / (a - u)) + atan((b + v) / (a - u)))
                let term8:Double = (a + u) * (a + u) * (atan((b - v) / (a + u)) + atan((b + v) / (a + u)))
                
                let term9:Double = 12.0 * a * b
                
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
            print("A+ = \(result)")
            funcResult = result
            
        case .failure(let error):
            ALog("Error calling integration routine. The error is: \(error)")
            return 0.0
        }
        
        let outerQuadrature2 = Quadrature(integrator: .qng, absoluteTolerance: absTol, relativeTolerance: relTol)
        let innerQuadrature2 = Quadrature(integrator: .qng, absoluteTolerance: absTol, relativeTolerance: relTol)
        
        let A_minus_2 = outerQuadrature2.integrate(over: (uStart+c)...(uEnd+c)) { u in
            
            let yOffset:Double = self.yCenter - otherSegment.yCenter
            let yHeight:Double = self.segment.rect.height
            let yStart:Double = yOffset - yHeight / 2.0
            let yEnd:Double = yStart + yHeight
            
            let a = otherSegment.segment.rect.width / 2.0
            let b = otherSegment.segment.rect.height / 2.0
            
            let innerA = innerQuadrature2.integrate(over: yStart...yEnd) { v in
                
                let b_minus_v_squared:Double = (b - v) * (b - v)
                let b_plus_v_squared:Double = (b + v) * (b + v)
                let a_minus_u_squared:Double = (a - u) * (a - u)
                let a_plus_u_squared:Double = (a + u) * (a + u)
                
                let term1:Double = (b - v) * (a - u) * log(b_minus_v_squared + a_minus_u_squared)
                let term2:Double = (b - v) * (a + u) * log(b_minus_v_squared + a_plus_u_squared)
                let term3:Double = (b + v) * (a - u) * log(b_plus_v_squared + a_minus_u_squared)
                let term4:Double = (b + v) * (a + u) * log(b_plus_v_squared + a_plus_u_squared)
                
                let term5:Double = (b - v) * (b - v) * (atan((a - u) / (b - v)) + atan((a + u) / (b - v)))
                let term6:Double = (b + v) * (b + v) * (atan((a - u) / (b + v)) + atan((a + u) / (b + v)))
                let term7:Double = (a - u) * (a - u) * (atan((b - v) / (a - u)) + atan((b + v) / (a - u)))
                let term8:Double = (a + u) * (a + u) * (atan((b - v) / (a + u)) + atan((b + v) / (a + u)))
                
                let term9:Double = 12.0 * a * b
                
                // don't forget that the current of the 'image' is equal to -I, so the negative cancels out the minus sign before µ0
                return µ0 * otherSegment.segment.I / (16.0 * π * a * b) * (term1 + term2 + term3 + term4 + term5 + term6 + term7 + term8 - term9)
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
            print("A- = \(result)")
            funcResult += result
            
        case .failure(let error):
            ALog("Error calling integration routine. The error is: \(error)")
            return 0.0
        }
        
        return J1 / (I1 * I2) * funcResult
        
    }
    
}

//
//  WaveFormDisplayView.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-02-13.
//

import Cocoa
import PchBasePackage

class WaveFormDisplayView: NSView {

    // Fraction of an inch to use for the margins
    private let margin:CGFloat = 0.1 // ie: 1/10"
    // Screen resolution in dots per inch (default is for Retina screen)
    var screenRes:NSSize = NSSize(width: 144, height: 144)
    
    let axisColor = NSColor.darkGray
    
    private var scaleMultiplier:NSPoint = NSPoint()
    
    private var scale:CGFloat = 1.0
    
    private var extrema:NSRect = NSRect()
    
    private var dataStore:[[NSPoint]] = []
    
    func UpdateScaleAndZoomWindow() {
        
        // Convert the current extrema and axes' positions into the bounds for our view and zoom to show everything. The extrema rectangle will be inset by the value (in inches) defined by 'self.margin'.
        
        let extremaRect = extrema.isEmpty ? NSRect(x: 0, y: 0, width: 1000, height: 800) : extrema
        
        // let usableFrame = self.frame.insetBy(dx: screenRes.width / margin, dy: screenRes.height / margin)
        
        var newBoundsRect = extremaRect
        
        //newBoundsRect.size.width += extremaRect.origin.x
        //newBoundsRect.origin.x = 0.0
        
        // scale is always based on the x (time) axis
        scale = extremaRect.width / self.frame.width
        scaleMultiplier = NSPoint(x: 1.0, y: self.frame.height * scale / extremaRect.height)
        newBoundsRect.origin.y *= scaleMultiplier.y
        newBoundsRect.size.height *= scaleMultiplier.y
        
        
        // figure out the margin values using our scale
        let scaledMarginX = screenRes.width * margin * scale
        let scaledMarginY = screenRes.height * margin * scale
        
        self.bounds = newBoundsRect.insetBy(dx: -scaledMarginX, dy: -scaledMarginY)
        
        DLog("\(self.bounds)")
        
        self.needsDisplay = true
    }
    
    func AddDataSeries(newData:[NSPoint]) {
        
        self.dataStore.append(newData)
        
        self.extrema = self.extrema.union(WaveFormDisplayView.GetExtremaFromData(data: newData))
    }
    
    func RemoveAllDataSeries() {
        
        self.dataStore = []
        self.extrema = NSRect()
        
        self.bounds = NSRect(x: -screenRes.width / margin, y: -screenRes.height / margin, width: self.frame.width, height: self.frame.height)
        self.UpdateScaleAndZoomWindow()
    }
    
    static func GetExtremaFromData(data:[NSPoint]) -> NSRect {
        
        var xMin:CGFloat = CGFloat.greatestFiniteMagnitude
        var xMax:CGFloat = -xMin
        var yMin = xMin
        var yMax = xMax
        
        for nextPoint in data {
            
            xMin = min(nextPoint.x, xMin)
            xMax = max(nextPoint.x, xMax)
            yMin = min(nextPoint.y, yMin)
            yMax = max(nextPoint.y, yMax)
        }
        
        return NSRect(x: xMin, y: yMin, width: xMax - xMin, height: yMax - yMin)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        
        super.draw(dirtyRect)

        // Drawing code here.
        // Draw the axes
        let Axes = NSBezierPath()
        let xAxisGap = screenRes.width * margin * scale / 2
        let yAxisGap = screenRes.height * margin * scale / 2
        Axes.lineWidth = scale
        Axes.move(to: NSPoint(x: bounds.origin.x + xAxisGap , y: 0))
        Axes.line(to: NSPoint(x: bounds.origin.x + bounds.width - xAxisGap, y: 0))
        Axes.move(to: NSPoint(x: 0, y: bounds.origin.y - yAxisGap))
        Axes.line(to: NSPoint(x: 0, y: bounds.origin.y + bounds.height - yAxisGap))
        axisColor.setStroke()
        Axes.stroke()
        
        if dataStore.isEmpty {
            
            return
        }
        
        NSBezierPath.defaultLineWidth = scale
        var waveForms:[NSBezierPath] = []
        
        var moveCount = 0
        var didFirst = false
        for nextTimeStep in dataStore {
            
            for nextPointIndex in 0..<nextTimeStep.count {
                
                var drawPoint = nextTimeStep[nextPointIndex]
                drawPoint.y *= scaleMultiplier.y
                
                if !didFirst {
                    
                    moveCount += 1
                    waveForms.append(NSBezierPath())
                    waveForms[nextPointIndex].move(to: drawPoint)
                }
                else {
                    
                    DLog("Num elements in waveform \(nextPointIndex) before: \(waveForms[nextPointIndex].elementCount)")
                    waveForms[nextPointIndex].line(to: drawPoint)
                }
                
                DLog("Num elements in waveform \(nextPointIndex) after: \(waveForms[nextPointIndex].elementCount)")
            }
            
            didFirst = true
        }
        
        DLog("Number of elements in first path: \(waveForms[0].elementCount)")
        
        var colorHue:CGFloat = 0.0
        for nextPath in waveForms {
            
            let lineColor = NSColor(calibratedHue: colorHue, saturation: 1.0, brightness: 1.0, alpha: 1.0)
            lineColor.set()
            
            nextPath.stroke()
            
            colorHue += 1.0 / 12.0
            if colorHue >= 1.0 {
                
                colorHue = 0.0
            }
        }
    }
    
}

//
//  CoilResultsDisplayView.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-02-29.
//

import Cocoa
import PchBasePackage

class CoilResultsDisplayView: NSView {
    
    // Fraction of an inch to use for the margins
    private let margin:CGFloat = 0.1 // ie: 1/10"
    // Screen resolution in dots per inch (default is for Retina screen)
    var screenRes:NSSize = NSSize(width: 144, height: 144)
    
    let axisColor = NSColor.darkGray
    let lineColor = NSColor.red
    
    var scaleMultiplier:NSPoint = NSPoint()
    
    private var scale:CGFloat = 1.0
    
    private var extrema:NSRect = NSRect()
    
    // The data line currently being displayed
    var currentData:NSBezierPath = NSBezierPath()
    // private var dataStore:[[NSPoint]] = []
    
    func UpdateScaleAndZoomWindow(extremaRect:NSRect) {
        
        // Convert the current extrema and axes' positions into the bounds for our view and zoom to show everything. The extrema rectangle will be inset by the value (in inches) defined by 'self.margin'.
        
        var newBoundsRect = extremaRect
        
        // scale is always based on the x (coil-height, preferably in millimeters) axis
        scale = extremaRect.width / self.frame.width
        scaleMultiplier = NSPoint(x: 1.0, y: self.frame.height * scale / extremaRect.height)
        newBoundsRect.origin.y *= scaleMultiplier.y
        newBoundsRect.size.height *= scaleMultiplier.y
        
        
        // figure out the margin values using our scale
        let scaledMarginX = screenRes.width * margin * scale
        let scaledMarginY = screenRes.height * margin * scale
        
        self.bounds = newBoundsRect.insetBy(dx: -scaledMarginX, dy: -scaledMarginY)
        
        self.needsDisplay = true
    }
    
    /*
    func AddDataSeries(newData:[NSPoint]) {
        
        self.dataStore.append(newData)
        
        self.extrema = self.extrema.union(CoilResultsDisplayView.GetExtremaFromData(data: newData))
    }
    
    func RemoveAllDataSeries() {
        
        self.dataStore = []
        self.extrema = NSRect()
        
        self.bounds = NSRect(x: -screenRes.width / margin, y: -screenRes.height / margin, width: self.frame.width, height: self.frame.height)
        self.UpdateScaleAndZoomWindow()
    }
    */
    
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

        let oldLineWidth = NSBezierPath.defaultLineWidth
        NSBezierPath.defaultLineWidth = 1.0
        
        // we only show the x-axis (but the code is left here to draw the y-axis if we ever decide to do so)
        let Axes = NSBezierPath()
        let xAxisGap = screenRes.width * margin * scale / 2
        // let yAxisGap = screenRes.height * margin * scale / 2
        Axes.lineWidth = scale
        Axes.move(to: NSPoint(x: bounds.origin.x + xAxisGap , y: 0))
        Axes.line(to: NSPoint(x: bounds.origin.x + bounds.width - xAxisGap, y: 0))
        // Axes.move(to: NSPoint(x: 0, y: bounds.origin.y - yAxisGap))
        // Axes.line(to: NSPoint(x: 0, y: bounds.origin.y + bounds.height - yAxisGap))
        axisColor.setStroke()
        Axes.stroke()
        
        if currentData.isEmpty {
            
            return
        }
        
        /*
        print("Bounds: \(self.bounds)")
        for i in 0..<currentData.elementCount {
            
            let pointArray = NSPointArray.allocate(capacity: 3)
            let getElement = currentData.element(at: i, associatedPoints: pointArray)
            print("Point: \(pointArray[0])")
        } */
        
        lineColor.setStroke()
        currentData.stroke()
        
        NSBezierPath.defaultLineWidth = oldLineWidth
    }
    
}

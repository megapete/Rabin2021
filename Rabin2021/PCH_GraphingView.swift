//
//  PCH_GraphingView.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-15.
//

import Cocoa
import PchBasePackage

class PCH_GraphingView: NSView {
    
    weak var owner:PCH_GraphingWindow? = nil
    
    var xAxisIsVisible = false
    var yAxisIsVisible = false
    
    override var acceptsFirstResponder: Bool
    {
        return true
    }
    
    struct DataPath {
        
        let color:NSColor
        let path:NSBezierPath
        
        init(color:NSColor, points:[NSPoint]) {
            
            self.color = color
            
            let path = NSBezierPath()
            
            var didFirst = false
            for nextPoint in points {
                
                if didFirst {
                    
                    path.line(to: nextPoint)
                }
                else {
                    
                    path.move(to: nextPoint)
                    didFirst = true
                }
            }
            
            self.path = path
        }
    }
    
    var dataPaths:[DataPath] = []

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
        if xAxisIsVisible {
            
            NSColor.gray.setStroke()
            let axis = NSBezierPath()
            axis.move(to: NSPoint(x: self.bounds.origin.x, y: 0.0))
            axis.line(to: NSPoint(x: self.bounds.origin.x + self.bounds.width, y: 0.0))
            axis.stroke()
        }
        
        if yAxisIsVisible {
            
            NSColor.gray.setStroke()
            let axis = NSBezierPath()
            axis.move(to: NSPoint(x: 0.0, y: self.bounds.origin.y))
            axis.line(to: NSPoint(x: 0.0, y: self.bounds.origin.y + self.bounds.height))
            axis.stroke()
        }
        
        for nextPath in self.dataPaths {
            
            nextPath.color.setStroke()
            nextPath.path.stroke()
        }
    }
    
    /// Show or hide the axes, depending on the value of the show parameter
    /// - Parameter show: true if you want to show the axes, false otherwise
    func showAxes(show:Bool) {
        
        self.xAxisIsVisible = show
        self.yAxisIsVisible = show
        
        self.needsDisplay = true
    }
    
    override func mouseMoved(with event: NSEvent) {
        
        guard let wndCtrl = self.owner else {
            
            DLog("Owner not set")
            return
        }
        
        let currentPoint = self.convert(event.locationInWindow, from: nil)
        
        if !self.isMousePoint(currentPoint, in: self.bounds) {
            
            return
        }
        
        wndCtrl.xLocField.doubleValue = currentPoint.x
        wndCtrl.yLocField.doubleValue = currentPoint.y
    }
    
}

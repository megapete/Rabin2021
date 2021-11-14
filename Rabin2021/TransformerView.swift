//
//  TransformerView.swift
//  AndersenFE_2020
//
//  Created by Peter Huber on 2020-07-29.
//  Copyright © 2020 Peter Huber. All rights reserved.
//

// The original file for this class comes from AndersenFE_2020. It has been adapted to this program.

import Cocoa

let dimensionMultiplier = 1000.0

fileprivate extension NSPoint {
    
    /// Convert the dimensions in an NSPoint to some other unit
    static func *(left:NSPoint, right:CGFloat) -> NSPoint {
        
        let newPoint = NSPoint(x: left.x * right, y: left.y * right)
        return newPoint
    }
    
    static func *=( left:inout NSPoint, right:CGFloat) {
        
        left = left * right
    }
    
    static func +(left:NSPoint, right:NSSize) -> NSPoint {
        
        let newPoint = NSPoint(x: left.x + right.width, y: left.y + right.height)
        return newPoint
    }
    
    static func +=(left:inout NSPoint, right:NSSize) {
        
        left = left + right
    }
}

fileprivate extension NSRect {
    
    /// Convert all the dimensions in an NSRect to some other unit
    static func *(left:NSRect, right:CGFloat) -> NSRect {
        
        let newOrigin = left.origin * right
        let newSize = NSSize(width: left.size.width * right, height: left.size.height * right)
        
        let newRect = NSRect(origin: newOrigin, size: newSize)
        
        return newRect
    }
    
    static func *=(left:inout NSRect, right:CGFloat) {
        
        left = left * right
    }
}

struct SegmentPath {
    
    let segment:Segment
    
    var toolTipTag:NSView.ToolTipTag = 0
    
    var path:NSBezierPath? {
        get {
            return NSBezierPath(rect: self.segment.rect * dimensionMultiplier)
        }
    }
    
    var rect:NSRect {
        get {
            return self.segment.rect * dimensionMultiplier
        }
    }
        
    let segmentColor:NSColor
    static var bkGroundColor:NSColor = .white
    
    var isActive:Bool {
        get {
            return true
        }
    }
    
    // Test whether this segment contains 'point'
    func contains(point:NSPoint) -> Bool
    {
        guard let segPath = self.path else
        {
            return false
        }
        
        return segPath.contains(point)
    }
    
    // constant for showing that a segment is not active
    let nonActiveAlpha:CGFloat = 0.25
    
    func show()
    {
        if isActive
        {
            self.clear()
        }
        else
        {
            self.fill(alpha: nonActiveAlpha)
        }
    }
    
    // Some functions that make it so we can use SegmentPaths in a similar way as NSBezierPaths
    func stroke()
    {
        guard let path = self.path else
        {
            return
        }
        
        if self.isActive
        {
            self.segmentColor.set()
            path.stroke()
        }
    }
    
    func fill(alpha:CGFloat)
    {
        guard let path = self.path else
        {
            return
        }
        
        self.segmentColor.withAlphaComponent(alpha).set()
        path.fill()
        self.segmentColor.set()
        path.stroke()
    }
    
    // fill the path with the background color
    func clear()
    {
        guard let path = self.path else
        {
            return
        }
        
        SegmentPath.bkGroundColor.set()
        path.fill()
        self.segmentColor.set()
        path.stroke()
    }
}

class TransformerView: NSView, NSViewToolTipOwner, NSMenuItemValidation {
    
    // I suppose that I could get fancy and create a TransformerViewDelegate protocol but since the calls are so specific, I'm unable to justify the extra complexity, so I'll just save a weak reference to the AppController here
    weak var appController:AppController? = nil
    
    enum Mode {
        
        case selectSegment
        case zoomRect
    }
    
    private var modeStore:Mode = .selectSegment
    
    var mode:Mode {
        
        get {
            
            return self.modeStore
        }
        
        set {
            
            if newValue == .selectSegment
            {
                NSCursor.arrow.set()
            }
            else if newValue == .zoomRect
            {
                NSCursor.crosshair.set()
            }
            
            self.modeStore = newValue
        }
    }
    
    var segments:[SegmentPath] = []
    var boundary:NSRect = NSRect(x: 0, y: 0, width: 0, height: 0)
    let boundaryColor:NSColor = .gray
    
    var zoomRect:NSRect? = nil
    let zoomRectLineDash:[CGFloat] = [15.0, 8.0]
    
    var currentSegment:SegmentPath? = nil
    
    var fluxlines:[NSBezierPath] = []
    
    @IBOutlet weak var contextualMenu:NSMenu!
    @IBOutlet weak var reverseCurrentDirectionMenuItem:NSMenuItem!
    @IBOutlet weak var toggleActivationMenuItem:NSMenuItem!
    @IBOutlet weak var activateAllWdgTurnsMenuItem:NSMenuItem!
    @IBOutlet weak var deactivateAllWdgTurnsMenuItem:NSMenuItem!
    @IBOutlet weak var moveWdgRadiallyMenuItem:NSMenuItem!
    @IBOutlet weak var moveWdgAxiallyMenuItem:NSMenuItem!
    @IBOutlet weak var splitSegmentMenuItem:NSMenuItem!
    
    // MARK: Draw function override
    override func draw(_ dirtyRect: NSRect) {
        // super.draw(dirtyRect)

        print("Dirty rect: \(dirtyRect)")
        let oldLineWidth = NSBezierPath.defaultLineWidth
        
        /* This is my "simple" way to get a one-pixel (ish) line thickness
        NSBezierPath.defaultLineWidth = self.bounds.width / self.frame.width
        print("New line width: \(self.bounds.width / self.frame.width)")
        */
        // Set the line width to 1mm
        NSBezierPath.defaultLineWidth = 1.0
        let scrollView = self.superview!.superview! as! NSScrollView
        print("Magnification: \(scrollView.magnification)")
        
        // Drawing code here.
        
        if self.needsToDraw(self.boundary) {
            
            print("Drawing boundary")
            let boundaryPath = NSBezierPath(rect: boundary)
            self.boundaryColor.set()
            boundaryPath.stroke()
        }
        
        for nextSegment in self.segments
        {
            nextSegment.show()
        }
        
        if let currSeg = self.currentSegment
        {
            self.ShowHandles(segment: currSeg)
        }
        
        if !fluxlines.isEmpty
        {
            NSColor.black.set()
            
            for nextPath in fluxlines
            {
                nextPath.stroke()
            }
        }
        
        if self.mode == .zoomRect
        {
            if let rect = self.zoomRect
            {
                // print(rect)
                NSColor.gray.set()
                let zoomPath = NSBezierPath(rect: rect)
                zoomPath.setLineDash(self.zoomRectLineDash, count: 2, phase: 0.0)
                zoomPath.stroke()
            }
        }
        
        NSBezierPath.defaultLineWidth = oldLineWidth
    }
    
    override var acceptsFirstResponder: Bool
    {
        return true
    }
    
    // MARK: Current segment functions
    
    func ShowHandles(segment:SegmentPath)
    {
        let handleSide = NSBezierPath.defaultLineWidth * 5.0
        let handleBaseRect = NSRect(x: 0.0, y: 0.0, width: handleSide, height: handleSide)
        let handleFillColor = NSColor.white
        let handleStrokeColor = NSColor.darkGray
        
        var corners:[NSPoint] = [segment.rect.origin]
        corners.append(NSPoint(x: segment.rect.origin.x + segment.rect.size.width, y: segment.rect.origin.y))
        corners.append(NSPoint(x: segment.rect.origin.x + segment.rect.size.width, y: segment.rect.origin.y + segment.rect.size.height))
        corners.append(NSPoint(x: segment.rect.origin.x, y: segment.rect.origin.y + segment.rect.size.height))
        
        for nextPoint in corners
        {
            let handleRect = NSRect(origin: NSPoint(x: nextPoint.x - handleSide / 2.0, y: nextPoint.y - handleSide / 2.0), size: handleBaseRect.size)
            
            let handlePath = NSBezierPath(rect: handleRect)
            
            handleFillColor.set()
            handlePath.fill()
            handleStrokeColor.setStroke()
            handlePath.stroke()
        }
    }
    
    // MARK: Tooltips to display over segments
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String
    {
        var result = "Tooltip!"
        
        
        
        return result
    }
    
    // MARK: Contextual Menu Handlers

    @IBAction func handleReverseCurrent(_ sender: Any) {
        
        guard let appCtrl = self.appController, let currSeg = self.currentSegment else
        {
            return
        }
        
        /*
        let winding = currSeg.segment.inLayer!.parentTerminal.winding!
        
        appCtrl.doReverseCurrentDirection(winding: winding)
         */
    }
    
    @IBAction func handleMoveWdgRadially(_ sender: Any) {
        
        guard let appCtrl = self.appController, self.currentSegment != nil else
        {
            return
        }
        
        // appCtrl.handleMoveWindingRadially(self)
    }
    
    @IBAction func handleMoveWdgAxially(_ sender: Any) {
        
        guard let appCtrl = self.appController, self.currentSegment != nil else
        {
            return
        }
        
        // appCtrl.handleMoveWindingAxially(self)
    }
    
    @IBAction func handleToggleActivation(_ sender: Any) {
        
        guard let appCtrl = self.appController, let currSeg = self.currentSegment else
        {
            return
        }
        
        // appCtrl.doToggleSegmentActivation(segment: currSeg.segment)
    }
    
    @IBAction func handleActivateAllWindingTurns(_ sender: Any) {
        
        guard let appCtrl = self.appController, let currSeg = self.currentSegment else
        {
            return
        }
        
        // appCtrl.doSetActivation(winding: currSeg.segment.inLayer!.parentTerminal.winding!, activate: true)
    }
    
    @IBAction func handleDeactivateAllWindingTurns(_ sender: Any) {
        
        guard let appCtrl = self.appController, let currSeg = self.currentSegment else
        {
            return
        }
        
        // appCtrl.doSetActivation(winding: currSeg.segment.inLayer!.parentTerminal.winding!, activate: false)
    }
    
    
    @IBAction func handleSplitSegment(_ sender: Any) {
        
        guard let appCtrl = self.appController, self.currentSegment != nil else
        {
            return
        }
        
        // appCtrl.handleSplitSegment(self)
    }
    
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        
        guard let appCtrl = self.appController /*, let txfo = appCtrl.currentTxfo */ else
        {
            return false
        }
        /*
        if menuItem == self.reverseCurrentDirectionMenuItem
        {
            guard let currSeg = self.currentSegment else
            {
                return false
            }
            
            let terminal = currSeg.segment.inLayer!.parentTerminal
            let termNum = terminal.andersenNumber
            
            if let refTerm = txfo.niRefTerm
            {
                if refTerm != termNum
                {
                    // DLog("Fraction: \(txfo.FractionOfTerminal(terminal: terminal, andersenNum: termNum))")
                    if txfo.FractionOfTerminal(terminal: terminal, andersenNum: termNum) >= 0.5
                    {
                        // DLog("Returning false because this would cause a reversal of a non-ref terminal")
                        return false
                    }
                }
            }
            
            return currSeg.segment.inLayer!.parentTerminal.winding!.CurrentCarryingTurns() != 0.0
        }
        else if menuItem == self.toggleActivationMenuItem
        {
            guard let segPath = self.currentSegment else
            {
                return false
            }
            
            if segPath.isActive
            {
                let winding = segPath.segment.inLayer!.parentTerminal.winding!
                let totalTerminalTurns = txfo.CurrentCarryingTurns(terminal: winding.terminal.andersenNumber)
                let wdgTurns = winding.CurrentCarryingTurns()
                let segTurns = segPath.segment.activeTurns
                
                if wdgTurns == segTurns && fabs(totalTerminalTurns - wdgTurns) < 0.5
                {
                    return false
                }
            }
        }
        else if menuItem == self.activateAllWdgTurnsMenuItem || menuItem == self.moveWdgAxiallyMenuItem || menuItem == self.moveWdgRadiallyMenuItem || menuItem == self.splitSegmentMenuItem
        {
            return self.currentSegment != nil
        }
        else if menuItem == self.deactivateAllWdgTurnsMenuItem
        {
            guard let segPath = self.currentSegment else
            {
                return false
            }
            
            let winding = segPath.segment.inLayer!.parentTerminal.winding!
            let totalTerminalTurns = txfo.CurrentCarryingTurns(terminal: winding.terminal.andersenNumber)
            let wdgTurns = winding.CurrentCarryingTurns()
            
            if fabs(totalTerminalTurns - wdgTurns) < 0.5
            {
                return false
            }
        }
         */
        
        return true
    }
    
    func UpdateToggleActivationMenu(deactivate:Bool)
    {
        if deactivate
        {
            self.toggleActivationMenuItem.title = "Deactivate segment"
        }
        else
        {
            self.toggleActivationMenuItem.title = "Activate segment"
        }
        
        guard let appCtrl = self.appController else
        {
            return
        }
        
        // appCtrl.UpdateToggleActivationMenu(deactivate: deactivate)
    }
    
    // MARK: Mouse Events
    override func mouseDown(with event: NSEvent) {
        
        if self.mode == .zoomRect
        {
            self.mouseDownWithZoomRect(event: event)
            return
        }
        else if self.mode == .selectSegment
        {
            self.mouseDownWithSelectSegment(event: event)
            return
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        
        if self.mode == .zoomRect
        {
            self.mouseDraggedWithZoomRect(event: event)
            return
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        
        if self.mode == .zoomRect
        {
            let endPoint = self.convert(event.locationInWindow, from: nil)
            let newSize = NSSize(width: endPoint.x - self.zoomRect!.origin.x, height: endPoint.y - self.zoomRect!.origin.y)
            self.zoomRect!.size = newSize
            self.handleZoomRect(zRect: self.zoomRect!)
        }
        else {
            return
        }
        
        self.mode = .selectSegment
        self.needsDisplay = true
    }
    
    
    
    func mouseDraggedWithZoomRect(event:NSEvent)
    {
        let endPoint = self.convert(event.locationInWindow, from: nil)
        let newSize = NSSize(width: endPoint.x - self.zoomRect!.origin.x, height: endPoint.y - self.zoomRect!.origin.y)
        self.zoomRect!.size = newSize
        self.needsDisplay = true
    }
    
    func mouseDownWithSelectSegment(event:NSEvent)
    {
        let clickPoint = self.convert(event.locationInWindow, from: nil)
        print("Point:\(clickPoint)")
        let clipBounds = self.convert(self.superview!.bounds, from: self.superview!)
        print("Clip view: Bounds: \(clipBounds)")
        
        self.currentSegment = nil
        
        for nextSegment in self.segments
        {
            if nextSegment.contains(point: clickPoint)
            {
                self.currentSegment = nextSegment
                // self.appController!.UpdateToggleActivationMenu(deactivate: nextSegment.isActive)
                break
            }
        }
        
        if self.currentSegment == nil {
            return
        }
        
        // check if it was actually a double-click
        if event.clickCount == 2
        {
            if let segmentPath = self.currentSegment
            {
                // self.appController!.doToggleSegmentActivation(segment: segmentPath.segment)
            }
        }
        
        self.needsDisplay = true
    }
    
    func mouseDownWithZoomRect(event:NSEvent)
    {
        let eventLocation = event.locationInWindow
        let localLocation = self.convert(eventLocation, from: nil)
        
        self.zoomRect = NSRect(origin: localLocation, size: NSSize())
        self.needsDisplay = true
    }
    
    // MARK: Contextual Menu handling
    
    override func rightMouseDown(with event: NSEvent) {
        
        // reset the mode
        self.mode = .selectSegment
        let eventLocation = event.locationInWindow
        let clickPoint = self.convert(eventLocation, from: nil)
        
        for nextPath in self.segments
        {
            if nextPath.contains(point: clickPoint)
            {
                self.currentSegment = nextPath
                // self.UpdateToggleActivationMenu(deactivate: nextPath.segment.IsActive())
                self.needsDisplay = true
                NSMenu.popUpContextMenu(self.contextualMenu, with: event, for: self)
                return
            }
        }
    }
    
    // MARK: Zoom Functions
    // transformer display zoom functions
    func handleZoomAll(coreRadius:CGFloat, windowHt:CGFloat, tankWallR:CGFloat)
    {
        guard let parentView = self.superview else
        {
            return
        }
        
        self.frame = parentView.bounds
        // aspectRatio is defined as width/height
        // it is assumed that the window height (z) is ALWAYS the dominant dimension compared to the "half tank-width" in the r-direction
        let aspectRatio = parentView.bounds.width / parentView.bounds.height
        let boundsW = windowHt * aspectRatio
        
        let newRect = NSRect(x: coreRadius, y: 0.0, width: boundsW, height: windowHt) * dimensionMultiplier
        // DLog("NewRect: \(newRect)")
        
        self.bounds = newRect
        
        // DLog("Bounds: \(self.bounds)")
        self.boundary = self.bounds
        
        self.boundary.size.width = (tankWallR - coreRadius) * dimensionMultiplier
        // DLog("Boundary: \(self.boundary)")
        print("Clip view: Bounds:\(self.superview!.bounds)\nFrame:\(self.superview!.frame)")
        
        self.needsDisplay = true
    }
    
    // the zoom in/out ratio (maybe consider making this user-settable)
    var zoomRatio:CGFloat = 0.75
    func handleZoomOut()
    {
        self.frame.size.width *= zoomRatio
        self.frame.size.height *= zoomRatio
        self.frame.origin = NSPoint()
        self.bounds.size.width /= zoomRatio
        self.bounds.size.height /= zoomRatio
        
        self.needsDisplay = true
    }
    
    func handleZoomIn()
    {
        /*
        print("Before Zoom In: Bounds:\(self.bounds)\nFrame:\(self.frame)")
        self.bounds.size.width *= zoomRatio
        self.bounds.size.height *= zoomRatio
        
        self.frame.size.width /= zoomRatio
        self.frame.size.height /= zoomRatio
        
        
        print("After Zoom In: Bounds:\(self.bounds)\nFrame:\(self.frame)")
        print("Clip view: Bounds:\(self.superview!.bounds)\nFrame:\(self.superview!.frame)")
        */
        
        guard let clipView = self.superview as? NSClipView, let scrollView = clipView.superview as? NSScrollView else {
            
            DLog("Couldn't get clip view and/or scroll view")
            return
        }
        
        let contentCenter = NSPoint(x: clipView.bounds.origin.x + clipView.bounds.width / 2.0, y: clipView.bounds.origin.y + clipView.bounds.height / 2.0)
        scrollView.setMagnification(scrollView.magnification / zoomRatio, centeredAt: contentCenter)
        // zoomRatio *= zoomRatio
        
        // self.needsDisplay = true
    }
    
    func handleZoomRect(zRect:NSRect)
    {
        // reset the zoomRect
        self.zoomRect = NSRect()
        
        print("Old frame: \(self.frame); Old bounds: \(self.bounds)")
        // zRect is in the same units as self.bounds
        print("New rect: \(zRect)")
        // Get the width/height ratio of self.bounds
        let reqWidthHeightRatio = self.bounds.width / self.bounds.height
        // Fix the zRect
        let newBoundsRect = ForceAspectRatioAndNormalize(srcRect: zRect, widthOverHeightRatio: reqWidthHeightRatio)
        print("Fixed zoom rect: \(newBoundsRect)")
        let zoomFactor = newBoundsRect.width / self.bounds.width
        self.frame.size.width /= zoomFactor
        self.frame.size.height /= zoomFactor
        self.bounds = newBoundsRect
        
        print("New frame: \(self.frame); New Bounds: \(self.bounds)")
        
        self.needsDisplay = true
        
    }
    

    
}

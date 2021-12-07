//
//  TransformerView.swift
//  AndersenFE_2020
//
//  Created by Peter Huber on 2020-07-29.
//  Copyright © 2020 Peter Huber. All rights reserved.
//

// The original file for this class comes from AndersenFE_2020. It has been adapted to this program.

import Cocoa

fileprivate let dimensionMultiplier = 1000.0

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
    
    func Rotate(theta:CGFloat) -> NSPoint {
        
        let newX = self.x * cos(theta) - self.y * sin(theta)
        let newY = self.x * sin(theta) + self.y * cos(theta)
        
        return NSPoint(x: newX, y: newY)
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
    
    func BottomLeft() -> NSPoint {
        
        return self.origin
    }
    
    func TopRight() -> NSPoint {
        
        return self.origin + self.size
    }
    
    func TopLeft() -> NSPoint {
        
        return self.origin + NSSize(width: 0.0, height: self.size.height)
    }
    
    func BottomRight() -> NSPoint {
        
        return self.origin + NSSize(width: self.size.width, height: 0.0)
    }
    
    func BottomCenter() -> NSPoint {
        
        return self.origin + NSSize(width: self.size.width / 2.0, height: 0.0)
    }
    
    func TopCenter() -> NSPoint {
        
        return self.origin + NSSize(width: self.size.width / 2.0, height: self.size.height)
    }
    
    func LeftCenter() -> NSPoint {
        
        return self.origin + NSSize(width: 0.0, height: self.size.height / 2.0)
    }
    
    func RightCenter() -> NSPoint {
        
        return self.origin + NSSize(width: self.size.width, height: self.size.height / 2.0)
    }
}

struct Circle {
    
    let center:NSPoint
    let radius:CGFloat
    
    var path:NSBezierPath {
        
        let encRect = NSRect(x: center.x - radius, y: center.y - radius, width: 2.0 * radius, height: 2.0 * radius)
        return NSBezierPath(roundedRect: encRect * dimensionMultiplier, xRadius: self.radius * dimensionMultiplier, yRadius: self.radius * dimensionMultiplier)
    }
}

struct SegmentPath:Equatable {
    
    static var txfoView:TransformerView? = nil
    
    let segment:Segment
    
    var toolTipTag:NSView.ToolTipTag = 0
    
    var path:NSBezierPath? {
        get {
        
            if segment.isStaticRing {
                
                let radius = self.segment.rect.height / 2.0
                return NSBezierPath(roundedRect: self.segment.rect * dimensionMultiplier, xRadius: radius * dimensionMultiplier, yRadius: radius * dimensionMultiplier)
            }
            
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
    
    // show all connectors for this SegmentPath EXCEPT any that end at a Segment in 'maskSegments'. This allows us to avoid redrawing paths
    func showConnectors(maskSegments:[Segment]) {
        
        let model = SegmentPath.txfoView!.appController!.currentModel!
        SegmentPath.txfoView!.floatingLocations = []
        
        for nextConnection in self.segment.connections {
            
            if let otherSegment = nextConnection.segment {
                
                if maskSegments.contains(otherSegment) {
                    
                    continue
                }
            }
            
            let connectorPath = NSBezierPath()
            
            var fromPoint = NSPoint()
            let segRect = self.segment.rect
            
            switch nextConnection.connector.fromLocation {
            
            case .outside_upper:
                fromPoint = segRect.TopRight()
            
            case .center_upper:
                fromPoint = segRect.TopCenter()
            
            case .inside_upper:
                fromPoint = segRect.TopLeft()
            
            case .outside_center:
                fromPoint = segRect.RightCenter()
            
            case .inside_center:
                fromPoint = segRect.LeftCenter()
            
            case .outside_lower:
                fromPoint = segRect.BottomRight()
            
            case .center_lower:
                fromPoint = segRect.BottomCenter()
            
            case .inside_lower:
                fromPoint = segRect.BottomLeft()
            
            default:
                fromPoint = NSPoint()
            }
            
            // now for the end point of the path
            var toPoint = NSPoint()
            
            if let otherSeg = nextConnection.segment {
                
                // check if same coil
                if otherSeg.location.radial == self.segment.location.radial {
                    
                    // check if adjacent section
                    if model.SegmentsAreAdjacent(segment1: self.segment, segment2: otherSeg) {
                        
                        let segRect = otherSeg.rect
                        switch nextConnection.connector.toLocation {
                            
                        case .outside_upper:
                            toPoint = segRect.TopRight()
                        
                        case .center_upper:
                            toPoint = segRect.TopCenter()
                        
                        case .inside_upper:
                            toPoint = segRect.TopLeft()
                        
                        case .outside_center:
                            toPoint = segRect.RightCenter()
                        
                        case .inside_center:
                            toPoint = segRect.LeftCenter()
                        
                        case .outside_lower:
                            toPoint = segRect.BottomRight()
                        
                        case .center_lower:
                            toPoint = segRect.BottomCenter()
                        
                        case .inside_lower:
                            toPoint = segRect.BottomLeft()
                        
                        default:
                            
                            toPoint = NSPoint()
                        }
                        
                        connectorPath.move(to: fromPoint * dimensionMultiplier)
                        connectorPath.line(to: toPoint * dimensionMultiplier)
                    }
                    else {
                        // non-adjacent section, complicated!
                    }
                }
                else {
                    // other coil, complicated!
                }
            }
            else {
                
                // must be a termination
                let fromLoc = nextConnection.connector.fromLocation
                var specialDirection = SpecialConnector.direction.down
                if fromLoc == .center_lower || fromLoc == .inside_lower || fromLoc == .outside_lower {
                    
                    toPoint = fromPoint + NSSize(width: 0.0, height: -0.025)
                }
                else if fromLoc == .center_upper || fromLoc == .inside_upper || fromLoc == .outside_upper {
                    
                    toPoint = fromPoint + NSSize(width: 0.0, height: 0.025)
                    specialDirection = .up
                }
                else if fromLoc == .outside_center {
                    
                    toPoint = fromPoint + NSSize(width: 0.25, height: 0.0)
                    specialDirection = .right
                }
                
                connectorPath.move(to: fromPoint * dimensionMultiplier)
                connectorPath.line(to: toPoint * dimensionMultiplier)
                
                let toLoc = nextConnection.connector.toLocation
                if toLoc == .ground {
                    
                    let gndConnector = SpecialConnector.GroundConnection(connectionPoint: toPoint * dimensionMultiplier, owner: SegmentPath.txfoView!, connectorDirection: specialDirection)
                    
                    gndConnector.color.set()
                    gndConnector.path.stroke()
                }
                else if toLoc == .floating {
                    
                    let tolerance = TransformerView.connectorDistanceTolerance
                    
                }
            }
            
            self.segmentColor.set()
            connectorPath.stroke()
        }
    }
}

/// Definition and drawing routines for Ground, Impulse, and connections between non-adjacent coil segments. Note that dimensions passed in to routines in the struct are expected to be in the model's coordiantes.
struct SpecialConnector {
    
    enum type {
        
        case ground
        case impulse
        case general
    }
    
    enum direction {
        
        case variable
        case up
        case down
        case left
        case right
    }
    
    static let GroundCursor:NSCursor = SpecialConnector.LoadGroundCursor()
    
    static func LoadGroundCursor() -> NSCursor {
        
        if let groundImage = NSImage(named: "Ground") {
            
            let groundCursor = NSCursor(image: groundImage, hotSpot: NSPoint(x: 8, y: 1))
            
            return groundCursor
        }
    
        return NSCursor.arrow
    }
    
    static let connectorCircleRadius = 3.0
    
    let color:NSColor
    
    let connectorType:SpecialConnector.type
    
    let connectorDirection:SpecialConnector.direction
    
    let path:NSBezierPath
    
    static func GroundConnection(connectionPoint:NSPoint, owner:TransformerView, connectorDirection:SpecialConnector.direction) -> SpecialConnector {
        
        // set theta according to the direction that was passed into the routine - this value will be used to calculate the rotation matrix
        var theta = 0.0
        if connectorDirection == .up {
            theta = π / 2.0
        }
        else if connectorDirection == .left {
            theta = π
        }
        else if connectorDirection == .down {
            theta = 1.5 * π
        }
        
        // set up the grounding arrow as if it is pointing to the right (theta = 0)
        let leadEndPoint = owner.convert(NSPoint(x: 10.0, y: 0.0), from: owner.scrollView)
        let toFirstLine = owner.convert(NSPoint(x: 0.0, y: -8.5), from: owner.scrollView)
        let toEndFirstLine = owner.convert(NSPoint(x: 0.0, y: 17.0), from: owner.scrollView)
        
        let path = Circle(center: connectionPoint, radius: SpecialConnector.connectorCircleRadius).path
        path.move(to: connectionPoint)
        
        // apply the rotation matrix to the points on the grounding symbol before adding it to the path
        path.relativeLine(to: leadEndPoint.Rotate(theta: theta))
        path.relativeMove(to: toFirstLine.Rotate(theta: theta))
        path.relativeLine(to: toEndFirstLine.Rotate(theta: theta))
        
        return SpecialConnector(color:.green, connectorType: .ground, connectorDirection: connectorDirection, path: path)
    }
}

class TransformerView: NSView, NSViewToolTipOwner, NSMenuItemValidation {
    
    // I suppose that I could get fancy and create a TransformerViewDelegate protocol but since the calls are so specific, I'm unable to justify the extra complexity, so I'll just save a weak reference to the AppController here
    weak var appController:AppController? = nil
    
    static let connectorDistanceTolerance = 0.003 // meters
    
    enum Mode {
        
        case selectSegment
        case selectRect
        case zoomRect
        case addGround
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
            else if newValue == .zoomRect || newValue == .selectRect
            {
                NSCursor.crosshair.set()
            }
            else if newValue == .addGround {
                
                print("setting cursor to ground")
                SpecialConnector.GroundCursor.set()
            }
            
            self.modeStore = newValue
        }
    }
    
    var segments:[SegmentPath] = []
    
    var specialConnectors:[SpecialConnector] = []
    var floatingLocations:[NSRect] = []
    
    var boundary:NSRect = NSRect(x: 0, y: 0, width: 0, height: 0)
    let boundaryColor:NSColor = .gray
    
    var zoomRect:NSRect? = nil
    let zoomRectLineDash = NSSize(width: 15.0, height: 8.0)
    
    var selectRect:NSRect? = nil
    let selectRectLineDash = NSSize(width: 10.0, height: 5.0)
    
    let defaultLineWidth = 1.0
    
    var currentSegments:[SegmentPath] = []
    var currentSegmentIndices:[Int] {
        
        get {
            
            var result:[Int] = []
            
            for i in 0..<self.segments.count {
                
                if self.currentSegments.contains(self.segments[i]) {
                    
                    result.append(i)
                }
            }
            
            return result
        }
    }
    
    var currentSegmentsContainMoreThanOneWinding:Bool {
        
        get {
            
            if self.currentSegments.count > 1 {
                
                let radialPosToCheck = self.currentSegments[0].segment.radialPos
                
                for nextSegment in self.currentSegments {
                    
                    if nextSegment.segment.radialPos != radialPosToCheck {
                        
                        return true
                    }
                }
            }
            
            return false
        }
    }
    
    var rightClickSelection:SegmentPath? = nil
    
    // contextual (right-click) menus
    @IBOutlet weak var contextualMenu:NSMenu!
    @IBOutlet weak var addStaticRingAboveMenuItem:NSMenuItem!
    @IBOutlet weak var addStaticRingBelowMenuItem:NSMenuItem!
    @IBOutlet weak var removeStaticRingMenuItem:NSMenuItem!
    @IBOutlet weak var addRadialShieldMenuItem:NSMenuItem!
    @IBOutlet weak var removeRadialShieldMenuItem:NSMenuItem!
    
    // The scrollview that this view is in
    @IBOutlet weak var scrollView:NSScrollView!
    
    override func awakeFromNib() {
        
        SegmentPath.txfoView = self
    }
    
    // MARK: Draw function override
    override func draw(_ dirtyRect: NSRect) {
        // super.draw(dirtyRect)

        let oldLineWidth = NSBezierPath.defaultLineWidth
        
        // Set the line width to 1mm (as defined by the original ZoomAll)
        // NSBezierPath.defaultLineWidth = 1.0 / scrollView.magnification
        
        let fixedLineWidthSize = self.convert(NSSize(width: self.defaultLineWidth, height: self.defaultLineWidth), from: self.scrollView)
        NSBezierPath.defaultLineWidth = fixedLineWidthSize.width
        // Drawing code here.
        
        if self.needsToDraw(self.boundary) {
            
            // print("Drawing boundary")
            let boundaryPath = NSBezierPath(rect: boundary)
            self.boundaryColor.set()
            boundaryPath.stroke()
        }
        
        var maskSegments:[Segment] = []
        for nextSegment in self.segments
        {
            nextSegment.show()
            nextSegment.showConnectors(maskSegments: maskSegments)
            
            maskSegments.append(nextSegment.segment)
        }
        
        for nextSegment in self.currentSegments
        {
            self.ShowHandles(segment: nextSegment)
        }
        
        if self.mode == .zoomRect
        {
            if let rect = self.zoomRect
            {
                // print(rect)
                NSColor.gray.set()
                let zoomPath = NSBezierPath(rect: rect)
                let lineDashSize = self.convert(self.zoomRectLineDash, from: self.scrollView)
                zoomPath.setLineDash([lineDashSize.width, lineDashSize.height], count: 2, phase: 0.0)
                zoomPath.stroke()
            }
        }
        else if self.mode == .selectRect {
            
            if let rect = self.selectRect {
                
                NSColor.gray.set()
                let selectPath = NSBezierPath(rect: rect)
                let lineDashSize = self.convert(self.selectRectLineDash, from: self.scrollView)
                selectPath.setLineDash([lineDashSize.width, lineDashSize.height], count: 2, phase: 0.0)
                selectPath.stroke()
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

    @IBAction func handleAddRadialShield(_ sender: Any) {
        
        guard let appCtrl = self.appController, let segment = self.rightClickSelection else {
            
            return
        }
        
        appCtrl.doAddRadialShield(segmentPath: segment)
    }
    
    @IBAction func handleRemoveRadialShield(_ sender: Any) {
        
        guard let appCtrl = self.appController, let segment = self.rightClickSelection else {
            
            return
        }
        
        appCtrl.doRemoveRadialShield(segmentPath: segment)
    }
    
    @IBAction func handleAddStaticRingAbove(_ sender: Any) {
        
        guard let appCtrl = self.appController, let segment = self.rightClickSelection else {
            
            return
        }
        
        appCtrl.doAddStaticRingOver(segmentPath: segment)
    }
    
    @IBAction func handleAddStaticRingBelow(_ sender: Any) {
        
        guard let appCtrl = self.appController, let segment = self.rightClickSelection else {
            
            return
        }
        
        appCtrl.doAddStaticRingBelow(segmentPath: segment)
    }
    
    @IBAction func handleRemoveStaticRing(_ sender: Any) {
        
        guard let appCtrl = self.appController, let segment = self.rightClickSelection else {
            
            return
        }
        
        appCtrl.doRemoveStaticRing(segmentPath: segment)
    }
    
    @IBAction func handleMoveWdgRadially(_ sender: Any) {
        
        guard let appCtrl = self.appController else
        {
            return
        }
        
        // appCtrl.handleMoveWindingRadially(self)
    }
    
    @IBAction func handleMoveWdgAxially(_ sender: Any) {
        
        guard let appCtrl = self.appController else
        {
            return
        }
        
        // appCtrl.handleMoveWindingAxially(self)
    }
    
    @IBAction func handleToggleActivation(_ sender: Any) {
        
        guard let appCtrl = self.appController else
        {
            return
        }
        
        // appCtrl.doToggleSegmentActivation(segment: currSeg.segment)
    }
    
    @IBAction func handleActivateAllWindingTurns(_ sender: Any) {
        
        guard let appCtrl = self.appController else
        {
            return
        }
        
        // appCtrl.doSetActivation(winding: currSeg.segment.inLayer!.parentTerminal.winding!, activate: true)
    }
    
    @IBAction func handleDeactivateAllWindingTurns(_ sender: Any) {
        
        guard let appCtrl = self.appController else
        {
            return
        }
        
        // appCtrl.doSetActivation(winding: currSeg.segment.inLayer!.parentTerminal.winding!, activate: false)
    }
    
    
    @IBAction func handleSplitSegment(_ sender: Any) {
        
        guard let appCtrl = self.appController else
        {
            return
        }
        
        // appCtrl.handleSplitSegment(self)
    }
    
    // MARK: Menu validation
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        
        guard let appCtrl = self.appController, appCtrl.currentModel != nil else
        {
            return false
        }
        
        if menuItem == addStaticRingAboveMenuItem || menuItem == addStaticRingBelowMenuItem || menuItem == addRadialShieldMenuItem {
            
            return self.currentSegments.count == 1 && !self.currentSegments[0].segment.isStaticRing && !self.currentSegments[0].segment.isRadialShield
        }
        
        if menuItem == removeStaticRingMenuItem {
            
            return self.currentSegments.count == 1 && self.currentSegments[0].segment.isStaticRing
        }
        
        if menuItem == removeRadialShieldMenuItem {
            
            return self.currentSegments.count == 1 && self.currentSegments[0].segment.isRadialShield
        }
        
        return true
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
        else if self.mode == .addGround {
            
            self.mouseDownWithAddGround(event: event)
            return
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        
        if self.mode == .zoomRect
        {
            self.mouseDraggedWithZoomRect(event: event)
            return
        }
        
        // testing has revealed that fast clicking can sometimes make the program think there should be a selection rectangle when there actually is not, so we check for it before proceeding
        guard self.selectRect != nil else {
            
            return
        }
        
        // must be dragging with selection rectangle
        let endPoint = self.convert(event.locationInWindow, from: nil)
        let newSize = NSSize(width: endPoint.x - selectRect!.origin.x, height: endPoint.y - selectRect!.origin.y)
        self.selectRect!.size = newSize
        self.needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        
        if self.mode == .zoomRect
        {
            let endPoint = self.convert(event.locationInWindow, from: nil)
            let newSize = NSSize(width: endPoint.x - self.zoomRect!.origin.x, height: endPoint.y - self.zoomRect!.origin.y)
            self.zoomRect!.size = newSize
            self.handleZoomRect(zRect: self.zoomRect!)
        }
        else if self.mode == .selectRect {
            
            let endPoint = self.convert(event.locationInWindow, from: nil)
            let newSize = NSSize(width: endPoint.x - self.selectRect!.origin.x, height: endPoint.y - self.selectRect!.origin.y)
            self.selectRect!.size = newSize
            
            self.selectRect = NormalizeRect(srcRect: self.selectRect!)
            
            self.currentSegments = []
            
            for nextSegment in self.segments {
                
                if NSContainsRect(self.selectRect!, nextSegment.rect) {
                    
                    if self.currentSegments.firstIndex(of: nextSegment) == nil {
                    
                        self.currentSegments.append(nextSegment)
                    }
                }
            }
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
    
    func mouseDownWithAddGround(event:NSEvent) {
        
        let clickPoint = self.convert(event.locationInWindow, from: nil)
    }
    
    func mouseDownWithSelectSegment(event:NSEvent)
    {
        let clickPoint = self.convert(event.locationInWindow, from: nil)
        // print("Point:\(clickPoint)")
        // let clipBounds = self.convert(self.superview!.bounds, from: self.superview!)
        // print("Clip view: Bounds: \(clipBounds)")
        
        if !event.modifierFlags.contains(.shift) {
        
            self.currentSegments = []
        }
        
        for nextSegment in self.segments
        {
            if nextSegment.contains(point: clickPoint)
            {
                if let selectedSegmentIndex = self.currentSegments.firstIndex(of: nextSegment) {
                    
                    self.currentSegments.remove(at: selectedSegmentIndex)
                }
                else {
                
                    self.currentSegments.append(nextSegment)
                }
                
                break
            }
        }
        
        if self.currentSegments == [] {
            
            let eventLocation = event.locationInWindow
            let localLocation = self.convert(eventLocation, from: nil)
            self.mode = .selectRect
            self.selectRect = NSRect(origin: localLocation, size: NSSize())
            self.needsDisplay = true
        }
        
        // check if it was actually a double-click
        if event.clickCount == 2
        {
            DLog("Do nothing")
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
                self.rightClickSelection = nextPath
                if self.currentSegments.firstIndex(of: nextPath) == nil {
                
                    self.currentSegments = [nextPath]
                }
                self.needsDisplay = true
                NSMenu.popUpContextMenu(self.contextualMenu, with: event, for: self)
                
                break
            }
        }
        
        self.rightClickSelection = nil
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
        // print("Clip view: Bounds:\(self.superview!.bounds)\nFrame:\(self.superview!.frame)")
        
        self.needsDisplay = true
    }
    
    // the zoom in/out ratio (maybe consider making this user-settable)
    var zoomRatio:CGFloat = 0.75
    
    func handleZoomOut()
    {
        let contentCenter = NSPoint(x: self.scrollView.contentView.bounds.origin.x + self.scrollView.contentView.bounds.width / 2.0, y: self.scrollView.contentView.bounds.origin.y + self.scrollView.contentView.bounds.height / 2.0)
        self.scrollView.setMagnification(scrollView.magnification * zoomRatio, centeredAt: contentCenter)
    }
    
    func handleZoomIn()
    {
        
        let contentCenter = NSPoint(x: self.scrollView.contentView.bounds.origin.x + self.scrollView.contentView.bounds.width / 2.0, y: self.scrollView.contentView.bounds.origin.y + self.scrollView.contentView.bounds.height / 2.0)
        self.scrollView.setMagnification(scrollView.magnification / zoomRatio, centeredAt: contentCenter)
        
        // self.needsDisplay = true
    }
    
    func handleZoomRect(zRect:NSRect)
    {
        // reset the zoomRect
        self.zoomRect = NSRect()
        
        // print("Old frame: \(self.frame); Old bounds: \(self.bounds)")
        // zRect is in the same units as self.bounds
        // print("New rect: \(zRect)")
        // Get the width/height ratio of self.bounds
        let reqWidthHeightRatio = self.bounds.width / self.bounds.height
        // Fix the zRect
        let newBoundsRect = ForceAspectRatioAndNormalize(srcRect: zRect, widthOverHeightRatio: reqWidthHeightRatio)
        // print("Fixed zoom rect: \(newBoundsRect)")
        let zoomFactor = newBoundsRect.width / self.bounds.width
        
        let clipView = self.scrollView.contentView
        let contentCenter = NSPoint(x: newBoundsRect.origin.x + newBoundsRect.width / 2, y: newBoundsRect.origin.y + newBoundsRect.height / 2)
        
        self.scrollView.setMagnification(scrollView.magnification / zoomFactor, centeredAt: clipView.convert(contentCenter, from: self))

        // self.needsDisplay = true
        
    }
    

    
}

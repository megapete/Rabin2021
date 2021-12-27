//
//  TransformerView.swift
//  AndersenFE_2020
//
//  Created by Peter Huber on 2020-07-29.
//  Copyright © 2020 Peter Huber. All rights reserved.
//

// The original file for this class comes from AndersenFE_2020. It has been adapted to this program.

import Cocoa

// Through trial and error, I have discovered that NSView does not like small (<1) dimensions. Since the main units used in transformer design are in meters, I multiply all dimensions that are drawn by 1000 so that the NSView is using numbers that it likes more.
fileprivate let dimensionMultiplier = 1000.0

/// These extensions to NSImage come from the Internet. I only use them for custom cursors and didn't want to bother figuring this stuff out by myself. However, I have commented the code so that I can understand what its doing.
fileprivate extension NSImage {
    
    // PCH: Create a new NSImage by resizing 'self'
    func resized(to newSize: NSSize) -> NSImage? {
        
        // PCH: Create a bitmap image representation. We will draw into this bitmap.
        if let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(newSize.width), pixelsHigh: Int(newSize.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) {
            bitmapRep.size = newSize
            // PCH: Save the current NSGraphicsContext
            NSGraphicsContext.saveGraphicsState()
            // PCH: Set the current NSGraphicsContexto to our bitmap. Subsequent drawing calls will draw into the bitmap
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
            // PCH: Draw self (an NSImage) into the bitmap. Note that the width and height parameters are the new size - our image will be scaled to fit into those dimensions
            draw(in: NSRect(x: 0, y: 0, width: newSize.width, height: newSize.height), from: .zero, operation: .copy, fraction: 1.0)
            // PCH: Restore the NSGraphicsContext to whatever it was before we did our drawing
            NSGraphicsContext.restoreGraphicsState()
            
            // PCH: At this point, we have a bitmap image with our resized drawing in it, but we need to convert it to an NSimage by using the 'addRepresentation' call.
            let resizedImage = NSImage(size: newSize)
            resizedImage.addRepresentation(bitmapRep)
            return resizedImage
        }
        
        return nil
    }
    
    // PCH: Create a new NSImage by rotating 'self'
    func rotated(by degrees: CGFloat) -> NSImage {
        
        // PCH: Get the sin and cos of the angle (convert to radians first)
        let sinDegrees = abs(sin(degrees * CGFloat.pi / 180.0))
        let cosDegrees = abs(cos(degrees * CGFloat.pi / 180.0))
        
        // PCH: The rectangle that the image will fit into will change based on the rotation angle - calculate the size of the rectangle
        let newSize = CGSize(width: size.height * sinDegrees + size.width * cosDegrees,
                             height: size.width * sinDegrees + size.height * cosDegrees)
        
        // PCH: Create the new rectangle so that it will be centered on the new size
        let imageBounds = NSRect(x: (newSize.width - size.width) / 2,
                                 y: (newSize.height - size.height) / 2,
                                 width: size.width, height: size.height)
        
        // PCH: Create an affine transform (this is an advanced graphics topic). From the Xcode documentatiion: "A transformation specifies how points in one coordinate system are transformed to points in another coordinate system. An affine transformation is a special type of transformation that preserves parallel lines in a path but does not necessarily preserve lengths or angles."
        let otherTransform = NSAffineTransform()
        // PCH: Move to the center of the transform
        otherTransform.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
        // PCH: Rotate the transform
        otherTransform.rotate(byDegrees: degrees)
        // PCH: Move back to where we started
        otherTransform.translateX(by: -newSize.width / 2, yBy: -newSize.height / 2)
        
        // PCH: Create a new, empty NSImage
        let rotatedImage = NSImage(size: newSize)
        // PCH: Lock the focus of drawing routines to the new NSImage
        rotatedImage.lockFocus()
        // PCH: Multiply the NSImage's transformation matrix by the affine transform's matrix (this is an advanced graphics topic)
        otherTransform.concat()
        // PCH: Draw the new image
        draw(in: imageBounds, from: CGRect.zero, operation: NSCompositingOperation.copy, fraction: 1.0)
        // PCH: Reset the focus
        rotatedImage.unlockFocus()
        
        return rotatedImage
    }
}

/// Convenient extensions to NSPoint
fileprivate extension NSPoint {
    
    /// Convert the dimensions in an NSPoint to some other unit
    static func *(left:NSPoint, right:CGFloat) -> NSPoint {
        
        let newPoint = NSPoint(x: left.x * right, y: left.y * right)
        return newPoint
    }
    
    static func *=( left:inout NSPoint, right:CGFloat) {
        
        left = left * right
    }
    
    /// Add an NSSize to and NSPoint
    static func +(left:NSPoint, right:NSSize) -> NSPoint {
        
        let newPoint = NSPoint(x: left.x + right.width, y: left.y + right.height)
        return newPoint
    }
    
    static func +=(left:inout NSPoint, right:NSSize) {
        
        left = left + right
    }
    
    /// Subtract an NSSize from an NSPoint
    static func -(left:NSPoint, right:NSSize) -> NSPoint {
        
        let newPoint = NSPoint(x: left.x - right.width, y: left.y - right.height)
        return newPoint
    }
    
    static func -=(left:inout NSPoint, right:NSSize) {
        
        left = left - right
    }
    
    /// Subtract an NSPoint from and NSPoint
    static func -(left:NSPoint, right:NSPoint) -> NSPoint {
        
        let newPoint = NSPoint(x: left.x - right.x, y: left.y - right.y)
        return newPoint
    }
    
    static func -=(left:inout NSPoint, right:NSPoint) {
        
        left = left - right
    }
    
    /// Add an NSPoint to an NSPoint
    static func +(left:NSPoint, right:NSPoint) -> NSPoint {
        
        let newPoint = NSPoint(x: left.x + right.x, y: left.y + right.y)
        return newPoint
    }
    
    /// Rotate an NSPoint about the origin (theta is in radians)
    func Rotate(theta:CGFloat) -> NSPoint {
        
        let newX = self.x * cos(theta) - self.y * sin(theta)
        let newY = self.x * sin(theta) + self.y * cos(theta)
        
        return NSPoint(x: newX, y: newY)
    }
    
    /// Calculate the straight-line distance between two NSPoints
    func Distance(otherPoint:NSPoint) -> CGFloat {
        
        let a = self.x - otherPoint.x
        let b = self.y - otherPoint.y
        
        return sqrt(a * a + b * b)
    }
}

/// Convenient extensions to NSRect
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
    
    /// Return the point at the bottom-left of the NSRect
    func BottomLeft() -> NSPoint {
        
        return self.origin
    }
    
    /// Return the point at the top-right of the NSRect
    func TopRight() -> NSPoint {
        
        return self.origin + self.size
    }
    
    /// Return the point at the top-left of the NSRect
    func TopLeft() -> NSPoint {
        
        return self.origin + NSSize(width: 0.0, height: self.size.height)
    }
    
    /// Return the point at the bottom-right of the NSRect
    func BottomRight() -> NSPoint {
        
        return self.origin + NSSize(width: self.size.width, height: 0.0)
    }
    
    /// Return the point at the bottom-center of the NSRect
    func BottomCenter() -> NSPoint {
        
        return self.origin + NSSize(width: self.size.width / 2.0, height: 0.0)
    }
    
    /// Return the point at the top-center of the NSRect
    func TopCenter() -> NSPoint {
        
        return self.origin + NSSize(width: self.size.width / 2.0, height: self.size.height)
    }
    
    /// Return the point at the left-center of the NSRect
    func LeftCenter() -> NSPoint {
        
        return self.origin + NSSize(width: 0.0, height: self.size.height / 2.0)
    }
    
    /// Return the point at the right-center of the NSRect
    func RightCenter() -> NSPoint {
        
        return self.origin + NSSize(width: self.size.width, height: self.size.height / 2.0)
    }
}

/// A struct for representing the segment paths that are displayed by the TransformeView class. Some of this comes from my AndersenFE-2020 program so there are a few things that aren't actually used. Eventually, I will remove unused code.
struct SegmentPath:Equatable {
    
    // This is kind of an ugly way to get "global" access to the TransformerView. Since my program only has one TransformerView available at a time, this works, but it would probably be better to declare it as an instance variable (in case I ever allow more than one TransformerView).
    static var txfoView:TransformerView? = nil
    
    // The Segment that is displayed by this instance
    let segment:Segment
    
    // A holder for future ToolTips for the Segment (not sure what to show yet)
    var toolTipTag:NSView.ToolTipTag = 0
    
    // The actual path that is drawn for the Segment. Note that for a Static Ring, the path is converted from a rectangle to a RoundedRectangle
    var path:NSBezierPath? {
        get {
        
            if segment.isStaticRing {
                
                let radius = self.segment.rect.height / 2.0
                return NSBezierPath(roundedRect: self.rect, xRadius: radius * dimensionMultiplier, yRadius: radius * dimensionMultiplier)
            }
            
            return NSBezierPath(rect: self.rect)
        }
    }
    
    // The rectangle that the Segment occupies (multiplied by the dimensionMultiplier global
    var rect:NSRect {
        get {
            return self.segment.rect * dimensionMultiplier
        }
    }
        
    // The color of the Segment
    let segmentColor:NSColor
    
    // The background for the a Segment
    static var bkGroundColor:NSColor = .white
    
    // Unused indicator to show that the Segment is active
    var isActive:Bool {
        get {
            return true
        }
    }
    
    /// Test whether this segment contains 'point'
    func contains(point:NSPoint) -> Bool
    {
        guard let segPath = self.path else
        {
            return false
        }
        
        return segPath.contains(point)
    }
    
    /// constant for showing that a segment is not active (unused)
    let nonActiveAlpha:CGFloat = 0.25
    
    /// Call this function to actually show the Segment. If the Segment is active, then call clear()
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
    
    /// The stroke() function so that  we can use SegmentPaths in a similar way as NSBezierPaths
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
    
    /// The fill() function so that  we can use SegmentPaths in a similar way as NSBezierPaths
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
    
    /// fill the path with the background color and stroke the path with the segmentColor
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
    
    /// Set up the paths for all connectors for this SegmentPath EXCEPT any that end at a Segment in 'maskSegments'. This allows us to avoid redrawing paths. This function is automaticlaly called when the "segments" property of TransformerView is changed. However, it must be called manually when adding (or removing) a connection. The 'viewConnectors' property of the TransformerView is changed by this routine. See the Connector struct and the Segment.Connection struct for more details on how those structures work.
    func SetUpConnectors(maskSegments:[Segment]) {
                
        let model = SegmentPath.txfoView!.appController!.currentModel!
        let txfoView = SegmentPath.txfoView!
        
        for nextConnection in self.segment.connections {
            
            if let otherSegment = nextConnection.segment {
                                
                if maskSegments.contains(otherSegment) || otherSegment == self.segment {
                    
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
                
                // check if same coil
                if otherSeg.location.radial == self.segment.location.radial {
                    
                    // check if adjacent section
                    if model.SegmentsAreAdjacent(segment1: self.segment, segment2: otherSeg) {
                        
                        connectorPath.move(to: fromPoint * dimensionMultiplier)
                        connectorPath.line(to: toPoint * dimensionMultiplier)
                        
                        txfoView.viewConnectors.append(ViewConnector(segments: (self.segment, otherSeg), pathColor: self.segmentColor, connectorType: .adjacent, connectorDirection: .up, connector: nextConnection.connector, path: connectorPath))
                    }
                    else {
                        // non-adjacent section, same coil
                        print("Got a non-adjacent connection from Segment#\(self.segment.serialNumber) to Segment#\(otherSeg.serialNumber)")
                        
                        if nextConnection.connector.fromIsOutside {
                            
                            if nextConnection.connector.toIsOutside {
                                
                                connectorPath.move(to: fromPoint * dimensionMultiplier)
                                connectorPath.line(to: (fromPoint + NSSize(width: 0.010, height: 0)) * dimensionMultiplier)
                                connectorPath.line(to: (toPoint + NSSize(width: 0.010, height: 0)) * dimensionMultiplier)
                                connectorPath.line(to: toPoint * dimensionMultiplier)
                            }
                            else {
                                
                                guard let highestSegmentIndex = try? model.GetHighestSection(coil: self.segment.radialPos) else {
                                    
                                    return
                                }
                                
                                let highestSegment = model.SegmentAt(location: LocStruct(radial: self.segment.radialPos, axial: highestSegmentIndex))!
                                let lowestSegment = model.SegmentAt(location: LocStruct(radial: self.segment.radialPos, axial: 0))!
                                
                                connectorPath.move(to: fromPoint * dimensionMultiplier)
                                connectorPath.line(to: (fromPoint + NSSize(width: 0.010, height: 0)) * dimensionMultiplier)
                                
                                let startHtFraction = (self.segment.zMean - lowestSegment.z1) / (highestSegment.z2 - lowestSegment.z1)
                                if startHtFraction < 0.5 {
                                    
                                    // go down
                                    connectorPath.line(to: NSPoint(x: fromPoint.x + 0.010, y: lowestSegment.z1 - 0.025 - 0.03) * dimensionMultiplier)
                                    connectorPath.line(to: NSPoint(x: toPoint.x - 0.010, y: lowestSegment.z1 - 0.025 - 0.03) * dimensionMultiplier)
                                    connectorPath.line(to: (toPoint + NSSize(width: -0.010, height: 0)) * dimensionMultiplier)
                                    connectorPath.line(to: toPoint * dimensionMultiplier)
                                }
                                else {
                                    
                                    // go up
                                    connectorPath.line(to: NSPoint(x: fromPoint.x + 0.010, y: highestSegment.z2 + 0.025 + 0.03) * dimensionMultiplier)
                                    connectorPath.line(to: NSPoint(x: toPoint.x - 0.010, y: highestSegment.z2 + 0.025 + 0.03) * dimensionMultiplier)
                                    connectorPath.line(to: (toPoint + NSSize(width: -0.010, height: 0)) * dimensionMultiplier)
                                    connectorPath.line(to: toPoint * dimensionMultiplier)
                                }
                            }
                        }
                        else { // fromConnector is inside
                            
                            if nextConnection.connector.toIsOutside {
                                
                                guard let highestSegmentIndex = try? model.GetHighestSection(coil: self.segment.radialPos) else {
                                    
                                    return
                                }
                                
                                let highestSegment = model.SegmentAt(location: LocStruct(radial: self.segment.radialPos, axial: highestSegmentIndex))!
                                let lowestSegment = model.SegmentAt(location: LocStruct(radial: self.segment.radialPos, axial: 0))!
                                
                                connectorPath.move(to: fromPoint * dimensionMultiplier)
                                connectorPath.line(to: (fromPoint + NSSize(width: -0.010, height: 0)) * dimensionMultiplier)
                                
                                let startHtFraction = (self.segment.zMean - lowestSegment.z1) / (highestSegment.z2 - lowestSegment.z1)
                                if startHtFraction < 0.5 {
                                    
                                    // go down
                                    connectorPath.line(to: NSPoint(x: fromPoint.x - 0.010, y: lowestSegment.z1 - 0.025 - 0.03) * dimensionMultiplier)
                                    connectorPath.line(to: NSPoint(x: toPoint.x + 0.010, y: lowestSegment.z1 - 0.025 - 0.03) * dimensionMultiplier)
                                    connectorPath.line(to: (toPoint + NSSize(width: 0.010, height: 0)) * dimensionMultiplier)
                                    connectorPath.line(to: toPoint * dimensionMultiplier)
                                }
                                else {
                                    
                                    // go up
                                    connectorPath.line(to: NSPoint(x: fromPoint.x - 0.010, y: highestSegment.z2 + 0.025 + 0.03) * dimensionMultiplier)
                                    connectorPath.line(to: NSPoint(x: toPoint.x + 0.010, y: highestSegment.z2 + 0.025 + 0.03) * dimensionMultiplier)
                                    connectorPath.line(to: (toPoint + NSSize(width: 0.010, height: 0)) * dimensionMultiplier)
                                    connectorPath.line(to: toPoint * dimensionMultiplier)
                                }
                            }
                            else {
                                
                                connectorPath.move(to: fromPoint * dimensionMultiplier)
                                connectorPath.line(to: (fromPoint + NSSize(width: -0.010, height: 0)) * dimensionMultiplier)
                                connectorPath.line(to: (toPoint + NSSize(width: -0.010, height: 0)) * dimensionMultiplier)
                                connectorPath.line(to: toPoint * dimensionMultiplier)
                            }
                        }
                        
                        txfoView.viewConnectors.append(ViewConnector(segments: (self.segment, otherSeg), pathColor: self.segmentColor, connectorType: .adjacent, connectorDirection: .variable, connector: nextConnection.connector, path: connectorPath))
                    }
                }
                else {
                    
                    // it's to another coil
                    let fromAndToInSameHilo = (otherSeg.radialPos - self.segment.radialPos == 1 && nextConnection.connector.fromIsOutside && !nextConnection.connector.toIsOutside) || (otherSeg.radialPos - self.segment.radialPos == -1 && !nextConnection.connector.fromIsOutside && nextConnection.connector.toIsOutside)
                    
                    guard let highestSegmentIndex = try? model.GetHighestSection(coil: self.segment.radialPos) else {
                        
                        return
                    }
                    
                    let highestSegment = model.SegmentAt(location: LocStruct(radial: self.segment.radialPos, axial: highestSegmentIndex))!
                    let lowestSegment = model.SegmentAt(location: LocStruct(radial: self.segment.radialPos, axial: 0))!
                    let startHtFraction = (self.segment.zMean - lowestSegment.z1) / (highestSegment.z2 - lowestSegment.z1)
                    
                    connectorPath.move(to: fromPoint * dimensionMultiplier)
                    
                    var currentX = fromPoint.x + 0.010
                    var currentY = fromPoint.y
                    if nextConnection.connector.fromIsOutside {
                        
                        connectorPath.line(to: (fromPoint + NSSize(width: 0.010, height: 0)) * dimensionMultiplier)
                    }
                    else { // from connector is inside
                        
                        connectorPath.line(to: (fromPoint + NSSize(width: -0.010, height: 0)) * dimensionMultiplier)
                        currentX = fromPoint.x - 0.010
                    }
                        
                    if !fromAndToInSameHilo {
                        
                        if startHtFraction < 0.5 {
                            
                            // go down
                            currentY = lowestSegment.z1 - 0.025 - 0.03
                            connectorPath.line(to: NSPoint(x: currentX, y: currentY) * dimensionMultiplier)
                        }
                        else {
                            
                            // go up
                            currentY = highestSegment.z2 + 0.025 + 0.03
                            connectorPath.line(to: NSPoint(x: currentX, y: currentY) * dimensionMultiplier)
                            
                        }
                    }
                    
                    var channelConnPoint = NSPoint()
                    if nextConnection.connector.toIsOutside {
                        
                        channelConnPoint = toPoint + NSSize(width: 0.010, height: 0.0)
                    }
                    else {
                        
                        channelConnPoint = toPoint + NSSize(width: -0.010, height: 0.0)
                    }
                    
                    connectorPath.line(to: NSPoint(x: channelConnPoint.x, y: currentY) * dimensionMultiplier)
                    connectorPath.line(to: channelConnPoint * dimensionMultiplier)
                    connectorPath.line(to: toPoint * dimensionMultiplier)
                    
                    txfoView.viewConnectors.append(ViewConnector(segments: (self.segment, otherSeg), pathColor: self.segmentColor, connectorType: .general, connectorDirection: .variable, connector: nextConnection.connector, path: connectorPath))
                }
            }
            else {
                
                // must be a 'termination' (ground, impulse, or floating)
                let fromLoc = nextConnection.connector.fromLocation
                var specialDirection = ViewConnector.direction.down
                if fromLoc == .center_lower || fromLoc == .inside_lower || fromLoc == .outside_lower {
                    
                    toPoint = fromPoint + NSSize(width: 0.0, height: -0.025)
                }
                else if fromLoc == .center_upper || fromLoc == .inside_upper || fromLoc == .outside_upper {
                    
                    toPoint = fromPoint + NSSize(width: 0.0, height: 0.025)
                    specialDirection = .up
                }
                else if fromLoc == .outside_center {
                    
                    toPoint = fromPoint + NSSize(width: 0.025, height: 0.0)
                    specialDirection = .right
                }
                
                connectorPath.move(to: fromPoint * dimensionMultiplier)
                connectorPath.line(to: toPoint * dimensionMultiplier)
                
                let toLoc = nextConnection.connector.toLocation
                if toLoc == .ground {
                    
                    let gndConnector = ViewConnector.GroundConnection(connectionPoint: toPoint * dimensionMultiplier, segments: (self.segment, nil), connector: nextConnection.connector, owner: SegmentPath.txfoView!, connectorDirection: specialDirection)
                    
                    txfoView.viewConnectors.append(gndConnector)
                }
                else if toLoc == .impulse {
                    
                    let impConnector = ViewConnector.ImpulseConnection(connectionPoint: toPoint * dimensionMultiplier, segments: (self.segment, nil), connector: nextConnection.connector, owner: SegmentPath.txfoView!, connectorDirection: .right)
                    
                    txfoView.viewConnectors.append(impConnector)
                }
                
                txfoView.viewConnectors.append(ViewConnector(segments: (self.segment, nil), pathColor: self.segmentColor, connectorType: .general, connectorDirection: specialDirection, connector: nextConnection.connector, path: connectorPath))
            }
        }
        
        
    }
}

/// Definition and drawing routines for Ground, Impulse, and connections between non-adjacent coil segments. Note that dimensions passed in to routines in the struct are expected to be in the model's coordiantes (including the 'dimensionMultiplier' global variable). The fancy cursors are also defined here.
struct ViewConnector {
    
    /// The different types of connectors
    enum type {
        
        case ground
        case impulse
        case general
        case adjacent
    }
    
    /// The direction of the connector (the reasoning for this enum is evolving - it will probably be  changed in some future version of the program)
    enum direction {
        
        case variable
        case up
        case down
        case left
        case right
    }
    
    /// The Segments associated with the connector. There is always a 'from' Segment and there may be a 'to' Segment
    var segments:(from:Segment, to:Segment?)
    
    /// The global Ground cursor and its creation routine
    static let GroundCursor:NSCursor = ViewConnector.LoadGroundCursor()
    
    static func LoadGroundCursor() -> NSCursor {
        
        if let groundImage = NSImage(named: "Ground") {
            
            let imageSize = groundImage.size
            print("ground image size: \(imageSize)")
            let groundCursor = NSCursor(image: groundImage, hotSpot: NSPoint(x: 8, y: 1))
            
            return groundCursor
        }
    
        // couldn't load the cursor image, just show the arrow
        return NSCursor.arrow
    }
    
    /// The global Impulse cursor and its creation routine
    static let ImpulseCursor:NSCursor = ViewConnector.LoadImpulseCursor()
    
    static let impulseImagePoint = NSPoint(x: 9, y: 22)
   
    static func LoadImpulseCursor() -> NSCursor {
        
        if let impulseImage = NSImage(named: "Impulse") {
            
            let impulseCursor = NSCursor(image: impulseImage, hotSpot: ViewConnector.impulseImagePoint)
            
            return impulseCursor
        }
    
        // couldn't load the cursor image, just show the arrow
        return NSCursor.arrow
    }
    
    /// The global Add Connection cursor and its creation routine
    static let AddConnectionCursor:NSCursor = ViewConnector.LoadAddConnectorCursor()
    
    static func LoadAddConnectorCursor() -> NSCursor {
        
        if let addCursor = NSImage(named: "AddConnector") {
            
            let addConnCursor = NSCursor(image: addCursor, hotSpot: NSPoint(x: 7, y: 9))
            
            return addConnCursor
        }
        
        return NSCursor.arrow
    }
    
    /// The global pliers cursor and its creation routine
    static let PliersCursor:NSCursor = ViewConnector.LoadPliersCursor()
    
    static func LoadPliersCursor() -> NSCursor {
        
        if let pliersImage = NSImage(named: "Pliers") {
            
            if let scaledPliers = pliersImage.resized(to: NSSize(width: 16, height: 24)) {
            
                // The image of the pliers is pointing straight up, so rotate it 45 degrees so it looks better
                let rotatedPliers = scaledPliers.rotated(by: 45.0)
                let pliersCursor = NSCursor(image: rotatedPliers, hotSpot: NSPoint(x: 6, y: 8))
                
                return pliersCursor
            }
        }
        
        // couldn't load the cursor image, just show the arrow
        return NSCursor.arrow
    }
    
    /// The circle that shows we're "connected"
    static let connectorCircleRadius = 1.5
    
    /// The color of the connector (only used if the 'path' property is not nil)
    let pathColor:NSColor
    
    /// The type
    let connectorType:ViewConnector.type
    
    /// The direction
    let connectorDirection:ViewConnector.direction
    
    /// The connector itself
    let connector:Connector
    
    // A ViewConnector can have only a path, or a path and an image
    /// The drawn path
    var path:NSBezierPath
    
    /// Or the image to display
    var image:NSImage? = nil
    
    /// The destination rectangle (in model coordinates) of the image
    var imageRect:NSRect = NSRect()
    
    /// The end points of the path
    var endPoints:(p1:NSPoint, p2:NSPoint) {
        
        var result = (NSPoint(), NSPoint())
        
        let path = self.path
        
        let numElements = path.elementCount
        
        if numElements > 1 {
            
            var pointArray:[NSPoint] = Array(repeating: NSPoint(), count: 3)
            var _ = path.element(at: 0, associatedPoints: &pointArray)
            let point1 = pointArray[0]
            path.element(at: 1, associatedPoints: &pointArray)
            let point2 = pointArray[0]
            
            result = (point1, point2)
        }
        
        return result
    }
    
    /// Return the end point of this SegmentPath that is closest to the given point (in TransformerView dimensions)
    func ClosestEndPoint(toPoint:NSPoint) -> NSPoint {
        
        let points = self.endPoints
        
        if toPoint.Distance(otherPoint: points.p1) <= toPoint.Distance(otherPoint: points.p2) {
            
            return points.p1
        }
        
        return points.p2
    }
    
    /// The "hit zone" for the connector. This can be polled by the NSBezierPath function 'contains' to see if a mouse click in in this hit zone.
    var hitZone:NSBezierPath {
        get {
            
            let result = NSBezierPath()
            
            let inset = TransformerView.connectorDistanceTolerance * dimensionMultiplier
            
            let numElements = path.elementCount
            
            if numElements > 1 {
                
                var pointArray:[NSPoint] = Array(repeating: NSPoint(), count: 3)
                var _ = path.element(at: 0, associatedPoints: &pointArray)
                var point1 = pointArray[0]
                
                for i in 1..<numElements {
            
                    _ = path.element(at: i, associatedPoints: &pointArray)
                    let point2 = pointArray[0]
                    
                    // Convert the line into a rectangle for hit-testing. I came up with this all by myself.
                    let nextZoneRect = NSInsetRect(NormalizeRect(srcRect: NSRect(x: point1.x, y: point1.y, width: point2.x - point1.x, height: point2.y - point1.y)), -inset, -inset)
                    
                    result.append(NSBezierPath(rect: nextZoneRect))
                    
                    if (i < numElements - 1) {
                        
                        point1 = point2
                    }
                }
            }
            
            return result
        }
    }
    
    /// Function to draw an Impulse connection image at the given NSPoint and in the given direction.
    /// - Parameter connectionPoint: The point (in TransformerView coordinates) where the connector will be drawn. This should be an EndPoint of a ViewConnector.
    /// - Parameter segments: Needed for the call to ViewConnector(). The 'to' member should always be 'nil'
    /// - Parameter connector: The Connector that this will replace
    /// - Parameter owner: The TransformerView that is to display this connector
    /// - Parameter connectorDirection: The direction that the new connector should point in
    /// - Returns: A ViewConnector
    static func ImpulseConnection(connectionPoint:NSPoint, segments:(from:Segment, to:Segment?), connector:Connector, owner:TransformerView, connectorDirection:ViewConnector.direction) -> ViewConnector {
        
        // Get the scale from the scrollView
        let scaleSize = owner.convert(NSSize(width: 1.0, height: 1.0), from: owner.scrollView)
        
        // set up the lead so that it is pointing to the right
        let leadEndPoint = NSPoint(x: 10.0 * scaleSize.width, y: 0.0)
        
        let circleRadius = ViewConnector.connectorCircleRadius * scaleSize.width
        let circleRectOrigin = connectionPoint + NSSize(width: -circleRadius, height: -circleRadius)
        let circleRect = NSRect(origin: circleRectOrigin, size: NSSize(width: circleRadius * 2, height: circleRadius * 2))
        let path = NSBezierPath(roundedRect: circleRect, xRadius: circleRadius, yRadius: circleRadius)
        
        // print("Connection: \(connectionPoint), leadEnd: \(leadEndPoint), Connection + leadEnd: \(connectionPoint + leadEndPoint)")
        
        path.move(to: connectionPoint)
        path.relativeLine(to: leadEndPoint)
        
        let impulseImage = NSImage(named: "Impulse")
        
        var imageRect = NSRect()
        if let image = impulseImage {
            
            let anchor = NSPoint(x: impulseImagePoint.x, y: image.size.height - impulseImagePoint.y) * scaleSize.width
            imageRect = NSRect(x: (connectionPoint + leadEndPoint).x - anchor.x, y: (connectionPoint + leadEndPoint).y - anchor.y, width: image.size.width * scaleSize.width, height: image.size.height * scaleSize.height)
        }
        
        return ViewConnector(segments:segments, pathColor: .red, connectorType: .impulse, connectorDirection: connectorDirection, connector: connector, path: path, image: impulseImage, imageRect: imageRect)
    }
    
    /// Function to draw a ground connection image at the given NSPoint and in the given direction.
    /// - Parameter connectionPoint: The point (in TransformerView coordinates) where the connector will be drawn. This should be an EndPoint of a ViewConnector.
    /// - Parameter segments: Needed for the call to ViewConnector(). The 'to' member should always be 'nil'
    /// - Parameter connector: The Connector that this will replace
    /// - Parameter owner: The TransformerView that is to display this connector
    /// - Parameter connectorDirection: The direction that the new connector should point in
    /// - Returns: A ViewConnector
    static func GroundConnection(connectionPoint:NSPoint, segments:(from:Segment, to:Segment?), connector:Connector, owner:TransformerView, connectorDirection:ViewConnector.direction) -> ViewConnector {
        
        // set theta according to the direction that was passed into the routine - this value will be used to calculate the rotation matrix
        var theta = 0.0
        if connectorDirection == .up {
            theta = 0.5 * π
        }
        else if connectorDirection == .left {
            theta = π
        }
        else if connectorDirection == .down {
            theta = 1.5 * π
        }
        
        // Get the scale from the scrollView
        let scaleSize = owner.convert(NSSize(width: 1.0, height: 1.0), from: owner.scrollView)
        // set up the grounding arrow as if it is pointing to the right (theta = 0)
        let leadEndPoint = NSPoint(x: 10.0 * scaleSize.width, y: 0.0)
        let toFirstLine = NSPoint(x: 0.0, y: -8.5 * scaleSize.height)
        let toEndFirstLine = NSPoint(x: 0.0, y: 17.0 * scaleSize.height)
        
        let circleRadius = ViewConnector.connectorCircleRadius * scaleSize.width
        let circleRectOrigin = connectionPoint + NSSize(width: -circleRadius, height: -circleRadius)
        let circleRect = NSRect(origin: circleRectOrigin, size: NSSize(width: circleRadius * 2, height: circleRadius * 2))
        let path = NSBezierPath(roundedRect: circleRect, xRadius: circleRadius, yRadius: circleRadius)
        
        //let path = Circle(center: connectionPoint, radius: ViewConnector.connectorCircleRadius * scaleSize.width).path
        path.move(to: connectionPoint)
        
        // apply the rotation matrix to the points on the grounding symbol before adding it to the path
        path.relativeLine(to: leadEndPoint.Rotate(theta: theta))
        path.relativeMove(to: toFirstLine.Rotate(theta: theta))
        path.relativeLine(to: toEndFirstLine.Rotate(theta: theta))
        
        let heightOffset = 2.0 * scaleSize.height
        let widthOffset = 2.0 * scaleSize.width
        var lastHeight = toEndFirstLine.y
        for _ in 0..<3 {
            
            path.relativeMove(to: NSPoint(x: widthOffset, y: -lastHeight + heightOffset).Rotate(theta: theta))
            lastHeight -= 2 * heightOffset
            path.relativeLine(to: NSPoint(x: 0.0, y: lastHeight).Rotate(theta: theta))
            
        }
        
        return ViewConnector(segments:segments, pathColor:.green, connectorType: .ground, connectorDirection: connectorDirection, connector: connector, path: path)
    }
}


/// The class that actually displays all the Segments the current model, along with all Connectors. There are also routines to update the mouse cursor depending on the current mode of the TransformerView, as well as mouseDown routines that do different things depending on the mode. See each function for a biref description of what it does. This class derives from NSView and conforms to the NSViewToolTipOwner and NSMenuItemValidation protocols.
class TransformerView: NSView, NSViewToolTipOwner, NSMenuItemValidation {
    
    /// I suppose that I could get fancy and create a TransformerViewDelegate protocol but since the calls are so specific, I'm unable to justify the extra complexity, so I'll just save a weak reference to the AppController here. The AppController will need to stuff a pointer to itself in here, probably best done in awakeFromNib()
    weak var appController:AppController? = nil
    
    /// The distance (in meters) that is used to highlight the connectors (used for certain modes)
    static let connectorDistanceTolerance = 0.003 // meters
    
    /// The different modes that are available
    enum Mode {
        
        /// Select a segment
        case selectSegment
        /// Use a rectangle to select one or more segments
        case selectRect
        /// Use a rectangle to zoom in on a certain section of the TransformerView
        case zoomRect
        /// Add a ground connector
        case addGround
        /// Add an impulse connector
        case addImpulse
        /// Add a connector between any two existing connectors
        case addConnection
        /// Remove a connector
        case removeConnector
    }
    
    /// The actual storage for the TransformerView's mode
    private var modeStore:Mode = .selectSegment
    
    /// A computed property for the mode of the TransformerView. The getter just returns the current mode, but the setter does things like update the mode indicator field at the bottom of the window and change the cursor (if necessary)
    var mode:Mode {
        
        get {
            
            return self.modeStore
        }
        
        set {
            
            if newValue == .selectSegment
            {
                if let appCtrl = self.appController {
                    
                    appCtrl.modeIndicatorTextField.stringValue = "Mode: Select"
                }
                
                NSCursor.arrow.set()
            }
            else if newValue == .zoomRect || newValue == .selectRect
            {
                if let appCtrl = self.appController {
                    
                    if newValue == .zoomRect {
                    
                        appCtrl.modeIndicatorTextField.stringValue = "Mode: Zoom Rect"
                    }
                    else {
                        
                        appCtrl.modeIndicatorTextField.stringValue = "Mode: Select Rect"
                    }
                }
                
                NSCursor.crosshair.set()
            }
            else if newValue == .addGround {
                
                if let appCtrl = self.appController {
                    
                    appCtrl.modeIndicatorTextField.stringValue = "Mode: Add Ground"
                }
                
                ViewConnector.GroundCursor.set()
            }
            else if newValue == .addImpulse {
                
                if let appCtrl = self.appController {
                    
                    appCtrl.modeIndicatorTextField.stringValue = "Mode: Add Impulse"
                }
                
                ViewConnector.ImpulseCursor.set()
            }
            else if newValue == .removeConnector {
                
                if let appCtrl = self.appController {
                    
                    appCtrl.modeIndicatorTextField.stringValue = "Mode: Remove Connector"
                }
                
                ViewConnector.PliersCursor.set()
            }
            else if newValue == .addConnection {
                
                if let appCtrl = self.appController {
                    
                    appCtrl.modeIndicatorTextField.stringValue = "Mode: Add Connector"
                }
                
                ViewConnector.AddConnectionCursor.set()
            }
            
            self.modeStore = newValue
        }
    }
    
    /// An array of all the Segment paths in the model.
    /// - Warning: If it is necessary to add a large number of SegmentPaths (when initializing the model, for example), it is better to create a separate array in the calling routine and append it (or assign it, for initialization) to this property. The reason for this is that any change to the segments array will cause a recalculation of all the ViewConnectors, which tends to slow things down...a lot.
    var segments:[SegmentPath] = [] {
        
        didSet {
            
            var maskSegments:[Segment] = []
            self.viewConnectors = []
            for nextSegment in segments {
                
                nextSegment.SetUpConnectors(maskSegments: maskSegments)
                maskSegments.append(nextSegment.segment)
            }
        }
    }
    
    /// An array of the ViewConnectors currently being displayed by the TransformerView
    var viewConnectors:[ViewConnector] = []
    /// The bezier path of the currently-highlighted connector path (if any)
    var highlightedConnectorPath:NSBezierPath? = nil
    /// A constant for the color of the highighted connector path
    let highlightColor:NSColor = .lightGray.withAlphaComponent(0.5)
    
    /// The boundary of the core window
    var boundary:NSRect = NSRect(x: 0, y: 0, width: 0, height: 0)
    /// The color to stroke the edges of the core window
    let boundaryColor:NSColor = .gray
    
    /// In zoom mode, this variable holds the current zoom rectangle
    var zoomRect:NSRect? = nil
    /// A constant for the line dash used when displaying the zoom rectangle
    let zoomRectLineDash = NSSize(width: 15.0, height: 8.0)
    
    /// In selectRect mode, this variable holds the current selection rectangle
    var selectRect:NSRect? = nil
    /// A constant for the line dash used when displaying the selecttion rectangle
    let selectRectLineDash = NSSize(width: 10.0, height: 5.0)
    
    /// In addConnection mode, this holds the ViewConnector where the connection started
    var addConnectionStartConnector:ViewConnector? = nil
    /// In addConnection mode, this holds the NSPoint where the connection started
    var addConnectionStartPoint:NSPoint = NSPoint()
    /// In addConnection mode, this holds the current connection path
    let addConnectionPath = NSBezierPath()
    
    /// The default line width for the TransformerView
    let defaultLineWidth = 1.0
    
    /// An array of the currently-selected SegmentPaths
    var currentSegments:[SegmentPath] = []
    
    /// An array of Int that holds the indices of the currently-selected SegmentPaths (the indices are into the segments array)
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
    
    /// A Boolean that returns true if the collection of currently-selected SegmentPaths includes Segments from more than one coil (winding).
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
    
    /// A variable that holds the currently-selected SegmentPath that was actually selected with a right-click
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
        
    // Override awakeFromNib() to do some initialization
    override func awakeFromNib() {
        
        // stuff ourself into the SegmentPath.txfoView global
        SegmentPath.txfoView = self
        
        // mark our window as 'wanting' mouse-moved events
        self.window!.acceptsMouseMovedEvents = true
        
        // call our function createTrackingArea() so that we can check if the mouse is in our window for cursor-changing
        self.createTrackingArea()
    }
    
    // We want to get first-responder messages, so we need to override the property and return true
    override var acceptsFirstResponder: Bool
    {
        return true
    }
    
    // We need to create a tracking area so that the cursor is updated when it leaves our view (we don't want to have select menus, for instance, using the "ground" cursor).
    func createTrackingArea() {
        
        let newTrackingArea = NSTrackingArea(rect: self.bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        
        self.addTrackingArea(newTrackingArea)
    }
    
    // Override the updateTrackingAreas() function, which is called by the system whenever something about the view changes (scrolling, resizing, etc)
    override func updateTrackingAreas() {
        
        for nextTrackingArea in self.trackingAreas {
        
            self.removeTrackingArea(nextTrackingArea)
        }
        
        self.createTrackingArea()
        
        super.updateTrackingAreas()
    }
    
    // Whenever the user exits the view, we reset the cursor to the arrow
    override func mouseExited(with event: NSEvent) {
        
        NSCursor.arrow.set()
    }
    
    // Whenever we re-enter the view, we set the cursor depending on the mode of the view
    override func mouseEntered(with event: NSEvent) {
        
        let mode = self.mode
        
        if mode == .selectSegment {
            
            NSCursor.arrow.set()
        }
        else if mode == .zoomRect || mode == .selectRect {
            
            NSCursor.crosshair.set()
        }
        else if mode == .addGround {
            
            ViewConnector.GroundCursor.set()
        }
        else if mode == .addImpulse {
            
            ViewConnector.ImpulseCursor.set()
        }
        else if mode == .removeConnector {
            
            ViewConnector.PliersCursor.set()
        }
        else if mode == .addConnection {
            
            ViewConnector.AddConnectionCursor.set()
        }
        else {
            
            NSCursor.arrow.set()
        }
    }
    
    
    // MARK: Draw function override
    override func draw(_ dirtyRect: NSRect) {
        
        // save the old line width
        let oldLineWidth = NSBezierPath.defaultLineWidth
        
        // calculate the new line width based on the size of the scrollView. We use the convenient 'convert' function from NSView to do this
        let fixedLineWidthSize = self.convert(NSSize(width: self.defaultLineWidth, height: self.defaultLineWidth), from: self.scrollView)
        NSBezierPath.defaultLineWidth = fixedLineWidthSize.width
        
        // In the interest of speed, we do not simply set "needsDisplay" to true for every single update that is required (that will cause a complete redraw of the entire view rectangle, which takes time). Instead, most of the routines will call setNeedsDisplay(invalidRect:NSRect) with a rectangle (in TransformerView coordinates) that needs to be redrawn. The system collects these rectangles and then passes it through to the draw routine. We could either check ourselves if we need to redraw certain elements, or use the NSView routine "needsToDraw" and oly redraw if that routine returns 'true'. This is the kind of advanced programming that is needed if you are drawing a LOT of different elements at a somewhat high speed (for instance, the zoom and select rectangles).
        
        if self.needsToDraw(self.boundary) {
            
            // print("Drawing boundary")
            let boundaryPath = NSBezierPath(rect: boundary)
            self.boundaryColor.set()
            boundaryPath.stroke()
        }
        
        for nextSegment in self.segments
        {
            if self.needsToDraw(nextSegment.rect) {
                
                nextSegment.show()
            }
        }
        
        for nextViewConnector in self.viewConnectors {
            
            if self.needsToDraw(nextViewConnector.hitZone.bounds) {
            
                nextViewConnector.pathColor.set()
                nextViewConnector.path.stroke()
            
            }
            
            if let image = nextViewConnector.image, self.needsToDraw(nextViewConnector.imageRect) {
                
                // draw the image
                image.draw(in: nextViewConnector.imageRect, from: NSRect(origin: NSPoint(), size: image.size), operation: .sourceOver, fraction: 1)
            }
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
        else if self.mode == .addConnection {
            
            if let highlightPath = self.highlightedConnectorPath {
                
                self.highlightColor.set()
                highlightPath.stroke()
                highlightPath.fill()
            }
            
            if let startConnector = self.addConnectionStartConnector {
                
                startConnector.pathColor.set()
                self.addConnectionPath.stroke()
            }
        }
        else if self.mode == .addGround || self.mode == .addImpulse || self.mode == .removeConnector {
            
            if let highlightPath = self.highlightedConnectorPath {
                
                self.highlightColor.set()
                highlightPath.stroke()
                highlightPath.fill()
            }
        }
        
        NSBezierPath.defaultLineWidth = oldLineWidth
    }
    
    
    // MARK: Current segment functions
    
    /// Show the little square 'handles' on the corners of the given SegmentPath
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
    
    // We track mouse-moved events so that we can highlight the connector paths if the mode is one of addConnectio, addImpulse, addground, or removeConnector. We also update the R/Z indicator at the bottom of teh window (but only if the mouse is in the TransformerView).
    override func mouseMoved(with event: NSEvent) {
        
        guard let appCtrl = self.appController, appCtrl.currentModel != nil else {
            
            return
        }
        
        let mouseLoc = self.convert(event.locationInWindow, from: nil)
        
        if !self.isMousePoint(mouseLoc, in: self.bounds) {
            
            return
        }
        
        appCtrl.updateCoordinates(rValue: mouseLoc.x, zValue: mouseLoc.y)
        
        if self.mode == .addConnection || self.mode == .addImpulse || self.mode == .addGround || self.mode == .removeConnector {
            
            if let oldHightlightPath = self.highlightedConnectorPath {
                
                self.highlightedConnectorPath = nil
                self.setNeedsDisplay(oldHightlightPath.bounds)
            }
            
            for nextViewConnector in self.viewConnectors {
                
                let hitZone = nextViewConnector.hitZone
                if hitZone.contains(mouseLoc) {
                
                    self.highlightedConnectorPath = hitZone
                    self.setNeedsDisplay(hitZone.bounds)
                    break
                }
            }
        }
    }
    
    // We forward the various mouse-down events based on the current mode
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
        else if self.mode == .addImpulse {
            
            self.mouseDownWithAddImpulse(event: event)
            return
        }
        else if self.mode == .addConnection {
            
            self.mouseDownWithAddConnection(event: event)
            return
        }
        else if self.mode == .removeConnector {
            
            self.mouseDownWithRemoveConnector(event: event)
            return
        }
    }
    
    // Depending on the current mode, dragging the mouse means different things. We handle selection-rectangle updating in this routine but transfer to otehr routines for zooming and for adding a connection.
    override func mouseDragged(with event: NSEvent) {
        
        if self.mode == .zoomRect
        {
            self.mouseDraggedWithZoomRect(event: event)
            return
        }
        else if self.mode == .addConnection {
            
            self.mouseDraggedWithAddConnection(event: event)
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
    
    // Depending on the mode, we may be interested when the user releases the mouse button.
    override func mouseUp(with event: NSEvent) {
        
        // The user has finished dragging his zoom rectangle, get the end point and do the zoom
        if self.mode == .zoomRect
        {
            let endPoint = self.convert(event.locationInWindow, from: nil)
            let newSize = NSSize(width: endPoint.x - self.zoomRect!.origin.x, height: endPoint.y - self.zoomRect!.origin.y)
            self.zoomRect!.size = newSize
            self.handleZoomRect(zRect: self.zoomRect!)
        }
        // The user has finished dragging his selection rectangle, so get the end point and add all segments in the rectangle to the currentSegments array
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
        // The user has finished adding a connection. If teh end-point is a valid connection point, add the new conenctor to the model.
        else if self.mode == .addConnection, let startConnector = self.addConnectionStartConnector {
            
            let endPoint = self.convert(event.locationInWindow, from: nil)
            
            for nextViewConnector in self.viewConnectors {
                
                if nextViewConnector.hitZone.contains(endPoint) {
                    
                    var startConnections = startConnector.segments.from.ConnectionDestinations(fromLocation: startConnector.connector.fromLocation)
                    startConnections.removeAll(where: { $0.segment == nil })
                    startConnections.insert((startConnector.segments.from, startConnector.connector.fromLocation), at: 0)
                    
                    var endConnections = nextViewConnector.segments.from.ConnectionDestinations(fromLocation: nextViewConnector.connector.fromLocation)
                    endConnections.removeAll(where: { $0.segment == nil })
                    endConnections.insert((nextViewConnector.segments.from, nextViewConnector.connector.fromLocation), at: 0)
                    
                    for nextStartConnection in startConnections {
                        
                        for nextEndConnection in endConnections {
                            
                            nextStartConnection.segment!.AddConnector(fromLocation: nextStartConnection.location, toLocation: nextEndConnection.location, toSegment: nextEndConnection.segment)
                        }
                    }
                    
                    guard let startSegmentPath = self.segments.first(where: {$0.segment == startConnector.segments.from}) else {
                        
                        // this should never happen
                        DLog("Problem!")
                        break
                    }
                    
                    // add all the non-touched segments to the maskSegment array so that the SetUpConnectors call goes quickly
                    var maskSegments:[Segment] = []
                    for nextSegmentPath in self.segments {
                        
                        if nextSegmentPath.segment != nextViewConnector.segments.from {
                            
                            maskSegments.append(nextSegmentPath.segment)
                        }
                    }
                    
                    startSegmentPath.SetUpConnectors(maskSegments: maskSegments)
                    
                    break
                }
            }
            
            self.highlightedConnectorPath = nil
            self.addConnectionStartConnector = nil
            self.addConnectionPath.removeAllPoints()
        }
        
        self.mode = .selectSegment
        self.needsDisplay = true
    }
    
    // The mouse is being dragged while in addConnection mode. Update the connection path and check if the mouse location is currently in the hitZone of a connector - if it is, set the highlight
    func mouseDraggedWithAddConnection(event:NSEvent) {
        
        let endPoint = self.convert(event.locationInWindow, from: nil)
        self.addConnectionPath.removeAllPoints()
        self.addConnectionPath.move(to: self.addConnectionStartPoint)
        self.addConnectionPath.line(to: endPoint)
        
        self.highlightedConnectorPath = nil
        
        for nextViewConnector in self.viewConnectors {
            
            let hitZone = nextViewConnector.hitZone
            if hitZone.contains(endPoint) {
            
                self.highlightedConnectorPath = hitZone
                break
            }
        }
        
        self.needsDisplay = true
    }
    
    // The mouse is being dragged while in zoomRect mode. Update the zoom rectangle
    func mouseDraggedWithZoomRect(event:NSEvent)
    {
        let endPoint = self.convert(event.locationInWindow, from: nil)
        let newSize = NSSize(width: endPoint.x - self.zoomRect!.origin.x, height: endPoint.y - self.zoomRect!.origin.y)
        self.zoomRect!.size = newSize
        self.needsDisplay = true
    }
    
    // The mouse was clicked while in removeConnector mode. Remove the connection and call SetUpConnectors to update the connectors that are displayed.
    func mouseDownWithRemoveConnector(event:NSEvent) {
        
        let clickPoint = self.convert(event.locationInWindow, from: nil)
                
        for (fromIndex, nextViewConnector) in self.viewConnectors.enumerated() {
            
            if nextViewConnector.hitZone.contains(clickPoint) {
                
                nextViewConnector.segments.from.RemoveConnection(connection: Segment.Connection(segment: nextViewConnector.segments.to, connector: nextViewConnector.connector))
                
                // add all the non-touched segments to the maskSegment array so that the SetUpConnectors call goes quickly
                var maskSegments:[Segment] = []
                for nextSegmentPath in self.segments {
                    
                    if nextSegmentPath.segment != nextViewConnector.segments.from && nextSegmentPath.segment != nextViewConnector.segments.to {
                        
                        maskSegments.append(nextSegmentPath.segment)
                    }
                }
                
                guard let segmentPath = self.segments.first(where: {$0.segment == nextViewConnector.segments.from}) else {
                    
                    // this shouldn't happen
                    DLog("Problem!")
                    break
                }
                
                self.viewConnectors.remove(at: fromIndex)
                
                // we just altered the self.viewConnectors array, so we need to search for the other segment (if any)
                if let toSegment = nextViewConnector.segments.to {
                    
                    if let toIndex = self.viewConnectors.firstIndex(where: { $0.segments.from == toSegment}) {
                        
                        self.viewConnectors.remove(at: toIndex)
                        
                        if let toPath = self.segments.first(where: { $0.segment == toSegment}) {
                            
                            toPath.SetUpConnectors(maskSegments: maskSegments)
                        }
                    }
                }
                
                segmentPath.SetUpConnectors(maskSegments: maskSegments)
                self.needsDisplay = true
                break
            }
        }
        
        
    }
    
    // The mouse was clicked while in addImpulse mode. Check if the clicked point is a valid location and if so, add the impulse connection and show it
    func mouseDownWithAddImpulse(event:NSEvent) {
        
        let clickPoint = self.convert(event.locationInWindow, from: nil)
        
        // print("Mouse down with impulse at point: \(clickPoint)")
        
        for nextViewConnector in self.viewConnectors {
            
            if nextViewConnector.hitZone.contains(clickPoint) {
                
                nextViewConnector.segments.from.AddConnector(fromLocation: nextViewConnector.connector.fromLocation, toLocation: .impulse, toSegment: nil)
                
                for nextConnection in nextViewConnector.segments.from.ConnectionDestinations(fromLocation: nextViewConnector.connector.fromLocation) {
                    
                    if let nextSegment = nextConnection.segment {
                        
                        nextSegment.AddConnector(fromLocation: nextConnection.location, toLocation: .impulse, toSegment: nil)
                    }
                }
                
                var maskSegments:[Segment] = []
                for nextSegmentPath in self.segments {
                    
                    if nextSegmentPath.segment != nextViewConnector.segments.from {
                        
                        maskSegments.append(nextSegmentPath.segment)
                    }
                }
                
                guard let segmentPath = self.segments.first(where: {$0.segment == nextViewConnector.segments.from}) else {
                    
                    DLog("Problem!")
                    break
                }
                
                segmentPath.SetUpConnectors(maskSegments: maskSegments)
                
                break
            }
        }
        
        self.highlightedConnectorPath = nil
        self.needsDisplay = true
    }
    
    // The mouse was clicked while in addGround mode. Check if the clicked point is a valid location and if so, add the ground connection and show it
    func mouseDownWithAddGround(event:NSEvent) {
        
        let clickPoint = self.convert(event.locationInWindow, from: nil)
        
        for nextViewConnector in self.viewConnectors {
            
            if nextViewConnector.hitZone.contains(clickPoint) {
                
                if nextViewConnector.hitZone.contains(clickPoint) {
                    
                    nextViewConnector.segments.from.AddConnector(fromLocation: nextViewConnector.connector.fromLocation, toLocation: .ground, toSegment: nil)
                    
                    for nextConnection in nextViewConnector.segments.from.ConnectionDestinations(fromLocation: nextViewConnector.connector.fromLocation) {
                        
                        if let nextSegment = nextConnection.segment {
                            
                            nextSegment.AddConnector(fromLocation: nextConnection.location, toLocation: .ground, toSegment: nil)
                        }
                    }
                    
                    var maskSegments:[Segment] = []
                    for nextSegmentPath in self.segments {
                        
                        if nextSegmentPath.segment != nextViewConnector.segments.from {
                            
                            maskSegments.append(nextSegmentPath.segment)
                        }
                    }
                    
                    guard let segmentPath = self.segments.first(where: {$0.segment == nextViewConnector.segments.from}) else {
                        
                        DLog("Problem!")
                        break
                    }
                    
                    segmentPath.SetUpConnectors(maskSegments: maskSegments)
                    
                    break
                }
            }
        }
        
        self.highlightedConnectorPath = nil
        self.needsDisplay = true
    }
    
    // The user clicked down on the mouse while in addConnector mode. If the click is at a valid location, set the addConnectionStartConnector and addConnectionStartPoint so that we can track the new connector
    func mouseDownWithAddConnection(event:NSEvent) {
        
        let clickPoint = self.convert(event.locationInWindow, from: nil)
        
        // print("Click location: \(clickPoint)")
        for nextViewConnector in self.viewConnectors {
            
            if nextViewConnector.hitZone.contains(clickPoint) {
                
                // print("Got connector")
                self.addConnectionStartConnector = nextViewConnector
                self.addConnectionStartPoint = nextViewConnector.ClosestEndPoint(toPoint: clickPoint)
                
                return
            }
        }
    }
    
    // The user clicked the mouse while in selectSegment mode. Check if the click was in a segment and if so, highlight it. If the user was holding down the shift key while clicking, add the segment to the set of current segments, otherwise erase the set of current segments and add the new one to it. If the segment is already selected, de-select it (remove it from the set of current segments).
    func mouseDownWithSelectSegment(event:NSEvent)
    {
        let clickPoint = self.convert(event.locationInWindow, from: nil)
        
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
            // self.needsDisplay = true
        }
        
        // check if it was actually a double-click
        if event.clickCount == 2
        {
            DLog("Do nothing")
        }
        
        self.needsDisplay = true
    }
    
    // The user clicked the mouse while in zoomRect mode. Start tracking the zoom rectangle
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

    // Zoom the view so that we see the entire model (ie: zoom to the core window)
    func handleZoomAll(coreRadius:CGFloat, windowHt:CGFloat, tankWallR:CGFloat)
    {
        guard let parentView = self.superview else
        {
            return
        }
        
        // find the center point of the view, then set the magnification of the scrollView to 1, centered on that point
        let contentCenter = NSPoint(x: self.scrollView.contentView.bounds.origin.x + self.scrollView.contentView.bounds.width / 2.0, y: self.scrollView.contentView.bounds.origin.y + self.scrollView.contentView.bounds.height / 2.0)
        self.scrollView.setMagnification(1.0, centeredAt: contentCenter)
        
        // set our frame to the clipView's bounds
        self.frame = parentView.bounds
        
        // aspectRatio is defined as width/height
        // it is assumed that the window height (z) is ALWAYS the dominant dimension compared to the "half tank-width" in the r-direction
        let aspectRatio = parentView.bounds.width / parentView.bounds.height
        let boundsW = windowHt * aspectRatio
        
        // Set the display rectangle to be equal to the core window - don't forget to multiply everything by dimensionMultiplier so that it shows up correctly
        let newRect = NSRect(x: coreRadius, y: 0.0, width: boundsW, height: windowHt) * dimensionMultiplier
        
        // and set the new bounds rectangle
        self.bounds = newRect
        
        self.boundary = self.bounds
        
        self.boundary.size.width = (tankWallR - coreRadius) * dimensionMultiplier
        
        self.needsDisplay = true
    }
    
    // the zoom in/out ratio (maybe consider making this user-settable)
    var zoomRatio:CGFloat = 0.75
    
    func handleZoomOut()
    {
        // Define the center of the new view and multiply the current scrollView magnification by the zoomRatio global to get the new view rectangle
        let contentCenter = NSPoint(x: self.scrollView.contentView.bounds.origin.x + self.scrollView.contentView.bounds.width / 2.0, y: self.scrollView.contentView.bounds.origin.y + self.scrollView.contentView.bounds.height / 2.0)
        self.scrollView.setMagnification(scrollView.magnification * zoomRatio, centeredAt: contentCenter)
        self.needsDisplay = true
    }
    
    func handleZoomIn()
    {
        // Define the center of the new view and divide the current scrollView magnification by the zoomRatio global to get the new view rectangle
        let contentCenter = NSPoint(x: self.scrollView.contentView.bounds.origin.x + self.scrollView.contentView.bounds.width / 2.0, y: self.scrollView.contentView.bounds.origin.y + self.scrollView.contentView.bounds.height / 2.0)
        self.scrollView.setMagnification(scrollView.magnification / zoomRatio, centeredAt: contentCenter)
        self.needsDisplay = true
    }
    
    func handleZoomRect(zRect:NSRect)
    {
        // reset the zoomRect
        self.zoomRect = NSRect()
        
        // Get the width/height ratio of self.bounds
        let reqWidthHeightRatio = self.bounds.width / self.bounds.height
        // Fix the zoomRect using my ForceAspectRatioAndNormalize routine (found in GlobalDefs)
        let newBoundsRect = ForceAspectRatioAndNormalize(srcRect: zRect, widthOverHeightRatio: reqWidthHeightRatio)
        // calculate the required zoom factor
        let zoomFactor = newBoundsRect.width / self.bounds.width
        
        // find the new center
        let clipView = self.scrollView.contentView
        let contentCenter = NSPoint(x: newBoundsRect.origin.x + newBoundsRect.width / 2, y: newBoundsRect.origin.y + newBoundsRect.height / 2)
        
        // set the magnification (it is guaranteed to be a "zoom in") and center it at the new center point
        self.scrollView.setMagnification(scrollView.magnification / zoomFactor, centeredAt: clipView.convert(contentCenter, from: self))
        self.needsDisplay = true
    }
}

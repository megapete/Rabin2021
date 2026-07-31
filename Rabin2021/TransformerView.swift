//
//  TransformerView.swift
//  AndersenFE_2020
//
//  Created by Peter Huber on 2020-07-29.
//  Copyright © 2020 Peter Huber. All rights reserved.
//

// The original file for this class comes from AndersenFE_2020. It has been adapted to this program.

import Cocoa
import Carbon.HIToolbox
import PchBasePackage

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


/// A struct for representing the segment paths that are displayed by the TransformeView class. Some of this comes from my AndersenFE-2020 program so there are a few things that aren't actually used. Eventually, I will remove unused code.
@MainActor
struct SegmentPath:Equatable, Sendable  {
    
    // This is kind of an ugly way to get "global" access to the TransformerView. Since my program only has one TransformerView available at a time, this works, but it would probably be better to declare it as an instance variable (in case I ever allow more than one TransformerView).
    static var txfoView:TransformerView? = nil
    
    // The Segment that is displayed by this instance
    let segment:Segment
    
    // Local copy of the Segment's rectangle (to avoid 'await' calls when drawing)
    let segRect:NSRect
    // Local copy of the Segment's isStaticRing ivar (to avoid 'await' calls when drawing)
    let segIsStaticRing:Bool
    
    // A holder for future ToolTips for the Segment (not sure what to show yet)
    var toolTipTag:NSView.ToolTipTag = 0
    
    // The actual path that is drawn for the Segment. Note that for a Static Ring, the path is converted from a rectangle to a RoundedRectangle
    func GetPath() -> NSBezierPath {
        
        if segIsStaticRing {
            
            let radius = self.segRect.height / 2.0
            return NSBezierPath(roundedRect: self.GetRect(), xRadius: radius * dimensionMultiplier, yRadius: radius * dimensionMultiplier)
        }
        
        return NSBezierPath(rect: self.GetRect())
    }
    
    // The rectangle that the Segment occupies (multiplied by the dimensionMultiplier global
    func GetRect() -> NSRect {
        
        return self.segRect * dimensionMultiplier
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
        let segPath = self.GetPath()
        
        return segPath.contains(point)
    }
    
    /// constant for showing that a segment is not active (unused)
    let nonActiveAlpha:CGFloat = 0.25
    
    /// Call this function to actually show the Segment. If the Segment is active, then call clear()
    func show() {
        
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
        let path = self.GetPath()
        
        if self.isActive
        {
            self.segmentColor.set()
            path.stroke()
        }
    }
    
    /// The fill() function so that  we can use SegmentPaths in a similar way as NSBezierPaths
    func fill(alpha:CGFloat)
    {
        let path = self.GetPath()
        
        self.segmentColor.withAlphaComponent(alpha).set()
        path.fill()
        self.segmentColor.set()
        path.stroke()
    }
    
    /// fill the path with the background color and stroke the path with the segmentColor
    func clear()
    {
        let path = self.GetPath()
        
        SegmentPath.bkGroundColor.set()
        path.fill()
        self.segmentColor.set()
        path.stroke()
    }
    
    /// Set up the paths for all connectors for this SegmentPath EXCEPT any that end at a Segment in 'maskSegments'. This allows us to avoid redrawing paths. This function is automatically called when the "segments" property of TransformerView is changed. However, it must be called manually when adding (or removing) a connection. The 'viewConnectors' property of the TransformerView is changed by this routine. See the Connector struct and the Segment.Connection struct for more details on how those structures work.
    func SetUpConnectors(allSegments:[Segment], maskSegments:[Int]) async {
                
        let model = SegmentPath.txfoView!.appController!.currentModel!
        let txfoView = SegmentPath.txfoView!

        // The current view scale (as used to size the ground / impulse symbols), so lead stubs stay a consistent size on screen.
        let scaleSize = txfoView.convert(NSSize(width: 1.0, height: 1.0), from: txfoView.scrollView)

        // Geometry-derived routing offsets (Phase 3), so the routing scales with the physical size of the model.
        let stub = txfoView.connectorStubOffset
        let laneGap = txfoView.connectorLaneGap
        let crossMargin = txfoView.connectorCrossoverClearance

        let selfConnections = await self.segment.connections

        for nextConnection in selfConnections {
            
            if let otherSegmentID = nextConnection.segmentID {
                                
                if maskSegments.contains(otherSegmentID) || otherSegmentID == self.segment.serialNumber {
                    
                    continue
                }
            }
            
            let connectorPath = NSBezierPath()
            
            var fromPoint = NSPoint()
            let segRect = await self.segment.rect
            
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
            
            if let otherSegID = nextConnection.segmentID, let otherSeg = allSegments.first(where: { $0.serialNumber == otherSegID }) {
                
                let segRect = await otherSeg.rect
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

                // Coil ends and tapping gaps carry a floating "lead" stub. If this connection starts and/or ends at
                // such a point, attach it to the tip of the existing lead rather than drawing a new stub beside it.
                if let leadVector = ConnectorLeadVector(for: nextConnection.connector.fromLocation, scaleSize: scaleSize),
                   selfConnections.contains(where: { $0.connector.fromLocation == nextConnection.connector.fromLocation && $0.connector.toLocation == .floating }) {

                    fromPoint = fromPoint + leadVector
                }

                let otherConnections = await otherSeg.connections
                if let leadVector = ConnectorLeadVector(for: nextConnection.connector.toLocation, scaleSize: scaleSize),
                   otherConnections.contains(where: { $0.connector.fromLocation == nextConnection.connector.toLocation && $0.connector.toLocation == .floating }) {

                    toPoint = toPoint + leadVector
                }

                // check if same coil
                if await otherSeg.location.radial == self.segment.location.radial {
                    
                    // check if adjacent section
                    if await model.SegmentsAreAdjacent(segment1: self.segment, segment2: otherSeg) {
                        
                        connectorPath.move(to: fromPoint * dimensionMultiplier)
                        connectorPath.line(to: toPoint * dimensionMultiplier)

                        txfoView.viewConnectors.append(ViewConnector(segments: (self.segment, otherSeg), pathColor: self.segmentColor, connectorType: .adjacent, connectorDirection: .up, connector: nextConnection.connector, path: connectorPath))
                    }
                    else {
                        // non-adjacent section, same coil
                        print("Got a non-adjacent connection from Segment#\(self.segment.serialNumber) to Segment#\(otherSeg.serialNumber)")

                        let currentIdentity = ViewConnectorIdentity(fromSerialNumber: self.segment.serialNumber, toSerialNumber: otherSeg.serialNumber, fromLocation: nextConnection.connector.fromLocation, toLocation: nextConnection.connector.toLocation)
                        var channelUses:[ConnectorChannelUse] = []
                        var lane = 0

                        let fromIsRadialCenter = nextConnection.connector.fromLocation == .center_upper || nextConnection.connector.fromLocation == .center_lower
                        let toIsRadialCenter = nextConnection.connector.toLocation == .center_upper || nextConnection.connector.toLocation == .center_lower

                        if fromIsRadialCenter && toIsRadialCenter {

                            // Both ends are at the radial centre of the coil (typically its top and bottom terminals). A
                            // vertical run alongside would pass through the coil body, so wrap around the outside of the coil.
                            guard let highestSegmentIndex = try? await model.GetHighestSection(coil: self.segment.radialPos) else {

                                return
                            }

                            let highestSegment = await model.SegmentAt(location: LocStruct(radial: self.segment.radialPos, axial: highestSegmentIndex))!
                            let lowestSegment = await model.SegmentAt(location: LocStruct(radial: self.segment.radialPos, axial: 0))!
                            let coilTop = await highestSegment.z2
                            let coilBottom = await lowestSegment.z1

                            // upper terminals exit up over the top, lower terminals exit down under the bottom
                            let fromExitY = nextConnection.connector.fromIsUpper ? coilTop + crossMargin : coilBottom - crossMargin
                            let toExitY = nextConnection.connector.toIsUpper ? coilTop + crossMargin : coilBottom - crossMargin

                            let outsideX = segRect.maxX + stub
                            channelUses = [ConnectorChannelUse(channel: .vertical(baseX: outsideX), span: ConnectorSpan(fromExitY, toExitY))]
                            lane = ViewConnector.assignLane(uses: channelUses, existing: txfoView.viewConnectors, excluding: currentIdentity)
                            let runX = outsideX + Double(lane) * laneGap

                            connectorPath.move(to: fromPoint * dimensionMultiplier)
                            connectorPath.line(to: NSPoint(x: fromPoint.x, y: fromExitY) * dimensionMultiplier)
                            connectorPath.line(to: NSPoint(x: runX, y: fromExitY) * dimensionMultiplier)
                            connectorPath.line(to: NSPoint(x: runX, y: toExitY) * dimensionMultiplier)
                            connectorPath.line(to: NSPoint(x: toPoint.x, y: toExitY) * dimensionMultiplier)
                            connectorPath.line(to: toPoint * dimensionMultiplier)
                        }
                        else if nextConnection.connector.fromIsOutside {
                            
                            if nextConnection.connector.toIsOutside {

                                channelUses = [ConnectorChannelUse(channel: .vertical(baseX: fromPoint.x + stub), span: ConnectorSpan(fromPoint.y, toPoint.y))]
                                lane = ViewConnector.assignLane(uses: channelUses, existing: txfoView.viewConnectors, excluding: currentIdentity)
                                let runX = stub + Double(lane) * laneGap

                                connectorPath.move(to: fromPoint * dimensionMultiplier)
                                connectorPath.line(to: (fromPoint + NSSize(width: runX, height: 0)) * dimensionMultiplier)
                                connectorPath.line(to: (toPoint + NSSize(width: runX, height: 0)) * dimensionMultiplier)
                                connectorPath.line(to: toPoint * dimensionMultiplier)
                            }
                            else {
                                
                                guard let highestSegmentIndex = try? await model.GetHighestSection(coil: self.segment.radialPos) else {
                                    
                                    return
                                }
                                
                                let highestSegment = await model.SegmentAt(location: LocStruct(radial: self.segment.radialPos, axial: highestSegmentIndex))!
                                let lowestSegment = await model.SegmentAt(location: LocStruct(radial: self.segment.radialPos, axial: 0))!
                                
                                connectorPath.move(to: fromPoint * dimensionMultiplier)
                                connectorPath.line(to: (fromPoint + NSSize(width: stub, height: 0)) * dimensionMultiplier)

                                let crossover = ConnectorCrossover(fromZ: fromPoint.y, toZ: toPoint.y, extentBottom: await lowestSegment.z1, extentTop: await highestSegment.z2, margin: crossMargin)
                                let baseChannelY = crossover.baseChannelY
                                let laneSign = crossover.goUp ? 1.0 : -1.0
                                channelUses = [ConnectorChannelUse(channel: .horizontal(baseY: baseChannelY), span: ConnectorSpan(fromPoint.x + stub, toPoint.x - stub))]
                                lane = ViewConnector.assignLane(uses: channelUses, existing: txfoView.viewConnectors, excluding: currentIdentity)
                                let channelY = baseChannelY + laneSign * Double(lane) * laneGap

                                connectorPath.line(to: NSPoint(x: fromPoint.x + stub, y: channelY) * dimensionMultiplier)
                                connectorPath.line(to: NSPoint(x: toPoint.x - stub, y: channelY) * dimensionMultiplier)
                                connectorPath.line(to: (toPoint + NSSize(width: -stub, height: 0)) * dimensionMultiplier)
                                connectorPath.line(to: toPoint * dimensionMultiplier)
                            }
                        }
                        else { // fromConnector is inside
                            
                            if nextConnection.connector.toIsOutside {
                                
                                guard let highestSegmentIndex = try? await model.GetHighestSection(coil: self.segment.radialPos) else {
                                    
                                    return
                                }
                                
                                let highestSegment = await model.SegmentAt(location: LocStruct(radial: self.segment.radialPos, axial: highestSegmentIndex))!
                                let lowestSegment = await model.SegmentAt(location: LocStruct(radial: self.segment.radialPos, axial: 0))!
                                
                                connectorPath.move(to: fromPoint * dimensionMultiplier)
                                connectorPath.line(to: (fromPoint + NSSize(width: -stub, height: 0)) * dimensionMultiplier)

                                let crossover = ConnectorCrossover(fromZ: fromPoint.y, toZ: toPoint.y, extentBottom: await lowestSegment.z1, extentTop: await highestSegment.z2, margin: crossMargin)
                                let baseChannelY = crossover.baseChannelY
                                let laneSign = crossover.goUp ? 1.0 : -1.0
                                channelUses = [ConnectorChannelUse(channel: .horizontal(baseY: baseChannelY), span: ConnectorSpan(fromPoint.x - stub, toPoint.x + stub))]
                                lane = ViewConnector.assignLane(uses: channelUses, existing: txfoView.viewConnectors, excluding: currentIdentity)
                                let channelY = baseChannelY + laneSign * Double(lane) * laneGap

                                connectorPath.line(to: NSPoint(x: fromPoint.x - stub, y: channelY) * dimensionMultiplier)
                                connectorPath.line(to: NSPoint(x: toPoint.x + stub, y: channelY) * dimensionMultiplier)
                                connectorPath.line(to: (toPoint + NSSize(width: stub, height: 0)) * dimensionMultiplier)
                                connectorPath.line(to: toPoint * dimensionMultiplier)
                            }
                            else {

                                channelUses = [ConnectorChannelUse(channel: .vertical(baseX: fromPoint.x - stub), span: ConnectorSpan(fromPoint.y, toPoint.y))]
                                lane = ViewConnector.assignLane(uses: channelUses, existing: txfoView.viewConnectors, excluding: currentIdentity)
                                let runX = -(stub + Double(lane) * laneGap)

                                connectorPath.move(to: fromPoint * dimensionMultiplier)
                                connectorPath.line(to: (fromPoint + NSSize(width: runX, height: 0)) * dimensionMultiplier)
                                connectorPath.line(to: (toPoint + NSSize(width: runX, height: 0)) * dimensionMultiplier)
                                connectorPath.line(to: toPoint * dimensionMultiplier)
                            }
                        }

                        var nonAdjacentConnector = ViewConnector(segments: (self.segment, otherSeg), pathColor: self.segmentColor, connectorType: .adjacent, connectorDirection: .variable, connector: nextConnection.connector, path: connectorPath)
                        nonAdjacentConnector.channelUses = channelUses
                        nonAdjacentConnector.lane = lane
                        txfoView.viewConnectors.append(nonAdjacentConnector)
                    }
                }
                else {
                    
                    // it's to another coil
                    let fromAndToInSameHilo = (otherSeg.radialPos - self.segment.radialPos == 1 && nextConnection.connector.fromIsOutside && !nextConnection.connector.toIsOutside) || (otherSeg.radialPos - self.segment.radialPos == -1 && !nextConnection.connector.fromIsOutside && nextConnection.connector.toIsOutside)
                    
                    guard let highestSegmentIndex = try? await model.GetHighestSection(coil: self.segment.radialPos) else {
                        
                        return
                    }
                    
                    let highestSegment = await model.SegmentAt(location: LocStruct(radial: self.segment.radialPos, axial: highestSegmentIndex))!
                    let lowestSegment = await model.SegmentAt(location: LocStruct(radial: self.segment.radialPos, axial: 0))!

                    connectorPath.move(to: fromPoint * dimensionMultiplier)
                    
                    var currentX = fromPoint.x + stub
                    var currentY = fromPoint.y
                    if nextConnection.connector.fromIsOutside {
                        
                        connectorPath.line(to: (fromPoint + NSSize(width: stub, height: 0)) * dimensionMultiplier)
                    }
                    else { // from connector is inside
                        
                        connectorPath.line(to: (fromPoint + NSSize(width: -stub, height: 0)) * dimensionMultiplier)
                        currentX = fromPoint.x - stub
                    }
                        
                    let channelConnPoint = nextConnection.connector.toIsOutside ? toPoint + NSSize(width: stub, height: 0.0) : toPoint + NSSize(width: -stub, height: 0.0)

                    let currentIdentity = ViewConnectorIdentity(fromSerialNumber: self.segment.serialNumber, toSerialNumber: otherSeg.serialNumber, fromLocation: nextConnection.connector.fromLocation, toLocation: nextConnection.connector.toLocation)
                    var channelUses:[ConnectorChannelUse] = []
                    var lane = 0

                    if !fromAndToInSameHilo {

                        // Find the axial extent spanning every coil between the source and destination so that the
                        // cross-over channel clears them all instead of cutting through an intervening (or taller) coil.
                        let minPos = min(self.segment.radialPos, otherSeg.radialPos)
                        let maxPos = max(self.segment.radialPos, otherSeg.radialPos)
                        var spanTop = await highestSegment.z2
                        var spanBottom = await lowestSegment.z1
                        for coil in minPos...maxPos {

                            guard let hiIdx = try? await model.GetHighestSection(coil: coil),
                                  let hiSeg = await model.SegmentAt(location: LocStruct(radial: coil, axial: hiIdx)),
                                  let loSeg = await model.SegmentAt(location: LocStruct(radial: coil, axial: 0)) else { continue }

                            spanTop = max(spanTop, await hiSeg.z2)
                            spanBottom = min(spanBottom, await loSeg.z1)
                        }

                        let crossover = ConnectorCrossover(fromZ: fromPoint.y, toZ: toPoint.y, extentBottom: spanBottom, extentTop: spanTop, margin: crossMargin)
                        let baseChannelY = crossover.baseChannelY
                        let laneSign = crossover.goUp ? 1.0 : -1.0
                        channelUses = [ConnectorChannelUse(channel: .horizontal(baseY: baseChannelY), span: ConnectorSpan(currentX, channelConnPoint.x))]
                        lane = ViewConnector.assignLane(uses: channelUses, existing: txfoView.viewConnectors, excluding: currentIdentity)
                        currentY = baseChannelY + laneSign * Double(lane) * laneGap
                        connectorPath.line(to: NSPoint(x: currentX, y: currentY) * dimensionMultiplier)
                    }

                    connectorPath.line(to: NSPoint(x: channelConnPoint.x, y: currentY) * dimensionMultiplier)
                    connectorPath.line(to: channelConnPoint * dimensionMultiplier)
                    connectorPath.line(to: toPoint * dimensionMultiplier)

                    var coilToCoilConnector = ViewConnector(segments: (self.segment, otherSeg), pathColor: self.segmentColor, connectorType: .general, connectorDirection: .variable, connector: nextConnection.connector, path: connectorPath)
                    coilToCoilConnector.channelUses = channelUses
                    coilToCoilConnector.lane = lane
                    txfoView.viewConnectors.append(coilToCoilConnector)
                }
            }
            else {
                
                // must be a 'termination' (ground, impulse, or floating). This draws the "lead" stub for a coil end or
                // tapping gap; connectors to this point attach to the tip of this lead (see the routed branches above).
                let fromLoc = nextConnection.connector.fromLocation
                let leadVector = ConnectorLeadVector(for: fromLoc, scaleSize: scaleSize) ?? NSPoint()
                toPoint = fromPoint + NSSize(width: leadVector.x, height: leadVector.y)

                var specialDirection = ViewConnector.direction.down
                if fromLoc == .center_upper || fromLoc == .inside_upper || fromLoc == .outside_upper {

                    specialDirection = .up
                }
                else if fromLoc == .outside_center {

                    specialDirection = .right
                }
                else if fromLoc == .inside_center {

                    specialDirection = .left
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
// @MainActor
struct ViewConnector : Equatable {
    
    static func == (lhs: ViewConnector, rhs: ViewConnector) -> Bool {
        
        return lhs.segments.from == rhs.segments.from && lhs.segments.to == rhs.segments.to
    }
    
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

    // MARK: Phase 1 routing metadata (used to spread overlapping connectors into parallel lanes)

    /// The routing channels this connector occupies, if it is lane-managed (empty ⇒ not lane-managed).
    var channelUses:[ConnectorChannelUse] = []
    /// The parallel-lane index assigned to this connector within its shared channels.
    var lane:Int = 0

    /// The identity of the logical connection this ViewConnector belongs to (duplicates share an identity).
    var identity:ViewConnectorIdentity {

        return ViewConnectorIdentity(fromSerialNumber: segments.from.serialNumber, toSerialNumber: segments.to?.serialNumber, fromLocation: connector.fromLocation, toLocation: connector.toLocation)
    }

    /// Assign the lowest lane index not used by any already-placed connector that shares a channel with an
    /// overlapping span. Connectors that belong to the connection being (re)drawn are excluded, and duplicate
    /// copies of any other connection are counted only once, so the result is stable across redraws.
    static func assignLane(uses:[ConnectorChannelUse], existing:[ViewConnector], excluding identity:ViewConnectorIdentity) -> Int {

        guard !uses.isEmpty else { return 0 }

        var seenIdentities:Set<ViewConnectorIdentity> = []
        var usedLanes:Set<Int> = []

        for existingConnector in existing {

            let existingIdentity = existingConnector.identity
            if existingIdentity == identity { continue }
            if !seenIdentities.insert(existingIdentity).inserted { continue }

            let conflicts = existingConnector.channelUses.contains { existingUse in
                uses.contains { newUse in existingUse.channel == newUse.channel && existingUse.span.overlaps(newUse.span) }
            }

            if conflicts { usedLanes.insert(existingConnector.lane) }
        }

        var lane = 0
        while usedLanes.contains(lane) { lane += 1 }
        return lane
    }

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
            
            let inset = TransformerViewConstants.connectorDistanceTolerance * dimensionMultiplier
            
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
    @MainActor static func ImpulseConnection(connectionPoint:NSPoint, segments:(from:Segment, to:Segment?), connector:Connector, owner:TransformerView, connectorDirection:ViewConnector.direction) -> ViewConnector {
        
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
    @MainActor static func GroundConnection(connectionPoint:NSPoint, segments:(from:Segment, to:Segment?), connector:Connector, owner:TransformerView, connectorDirection:ViewConnector.direction) -> ViewConnector {
        
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

/// Constants associated with TransformerView that are placed here to get them out of the MainActor
struct TransformerViewConstants {

    /// The distance (in meters) that is used to highlight the connectors (used for certain modes)
    static let connectorDistanceTolerance = 0.003 // meters
}

// MARK: - Connector lane routing (Phase 1: overlap avoidance)

// The routing offsets below are the fallback defaults; TransformerView.UpdateConnectorMetrics() overrides them with
// values derived from the model geometry (Phase 3) so they scale with the physical size of the model.

/// Default spacing (in model meters) between parallel connector lanes that share a routing channel.
let connectorLaneSpacing = 0.004
/// Default radial offset (in model meters) that a connector steps out of a coil into the adjacent gap.
let connectorStubDefault = 0.010
/// Default axial clearance (in model meters) between the winding extent and the horizontal cross-over channel.
let connectorCrossoverMargin = 0.055

// Fractions used to derive the routing offsets from the model geometry (see UpdateConnectorMetrics). Chosen so that a
// typical mid-size winding reproduces roughly the previous fixed offsets.
/// Fraction of the tightest radial gap used for the step-out stub.
let connectorStubGapFraction = 0.33
/// Fraction of the tightest radial gap used for the spacing between parallel lanes.
let connectorLaneGapFraction = 0.15
/// Fraction of the winding height used for the axial cross-over clearance.
let connectorCrossoverHeightFraction = 0.035
/// The on-screen length (in view points at magnification 1) of the lead stub drawn for a coil-end or tapping-gap
/// (floating / ground / impulse) termination. It is scaled by the current view scale so it stays a consistent size on
/// screen (like the ground / impulse symbols), and is half of the previous fixed length.
let connectorLeadScreenLength = 12.5
/// Coordinate quantum (in model meters) used to decide whether two connector runs share a channel.
private let connectorChannelQuantum = 0.002

/// Identifies a routing channel (a shared straight run) that connectors can occupy, so that several
/// connectors using the same channel can be spread out into parallel lanes instead of overlapping.
struct ConnectorChannel:Hashable {

    enum Orientation { case vertical, horizontal }

    let orientation:Orientation
    /// The quantized base coordinate of the run (the x-value for a vertical run, the y-value for a horizontal run).
    let coordinateKey:Int

    static func vertical(baseX:Double) -> ConnectorChannel {

        return ConnectorChannel(orientation: .vertical, coordinateKey: Int((baseX / connectorChannelQuantum).rounded()))
    }

    static func horizontal(baseY:Double) -> ConnectorChannel {

        return ConnectorChannel(orientation: .horizontal, coordinateKey: Int((baseY / connectorChannelQuantum).rounded()))
    }
}

/// A connector's occupancy of a channel over a given span (the extent along the run direction), in model meters.
struct ConnectorChannelUse {

    let channel:ConnectorChannel
    let span:ClosedRange<Double>
}

/// Identifies a logical connection so that duplicate ViewConnectors (e.g. a ground symbol plus its lead, or a
/// connector that is re-drawn on an incremental update) are counted only once during lane assignment.
struct ViewConnectorIdentity:Hashable {

    let fromSerialNumber:Int
    let toSerialNumber:Int?
    let fromLocation:Connector.Location
    let toLocation:Connector.Location
}

/// A closed range built from the two given values in either order.
func ConnectorSpan(_ a:Double, _ b:Double) -> ClosedRange<Double> {

    return Swift.min(a, b)...Swift.max(a, b)
}

/// The lead (stub) vector, in model coordinates, that a floating coil-end / tapping-gap termination draws from its
/// take-off location (matching the geometry drawn in the termination branch of SetUpConnectors). The length is derived
/// from the current view scale (`scaleSize`, as used by the ground / impulse symbols) so the lead is a consistent size
/// on screen, then divided by dimensionMultiplier to bring it back into model coordinates. A connector to a location
/// that has such a lead attaches to the tip (take-off point + this vector) instead of drawing its own stub. Returns nil
/// for locations that do not have a lead.
func ConnectorLeadVector(for location:Connector.Location, scaleSize:NSSize) -> NSPoint? {

    let dx = connectorLeadScreenLength * scaleSize.width / dimensionMultiplier
    let dy = connectorLeadScreenLength * scaleSize.height / dimensionMultiplier

    switch location {

    case .center_lower, .inside_lower, .outside_lower:
        return NSPoint(x: 0.0, y: -dy)

    case .center_upper, .inside_upper, .outside_upper:
        return NSPoint(x: 0.0, y: dy)

    case .outside_center:
        return NSPoint(x: dx, y: 0.0)

    case .inside_center:
        return NSPoint(x: -dx, y: 0.0)

    default:
        return nil
    }
}

/// Decide whether a connector should route over the top or under the bottom of the given axial extent, choosing
/// whichever gives the shorter total vertical travel for the two endpoints. Returns the direction and the base
/// cross-over channel Y (the height of the horizontal run, before any lane offset), in model coordinates.
func ConnectorCrossover(fromZ:Double, toZ:Double, extentBottom:Double, extentTop:Double, margin:Double) -> (goUp:Bool, baseChannelY:Double) {

    let costUp = (extentTop - fromZ) + (extentTop - toZ)
    let costDown = (fromZ - extentBottom) + (toZ - extentBottom)
    let goUp = costUp <= costDown

    return (goUp, goUp ? extentTop + margin : extentBottom - margin)
}

/// The class that actually displays all the Segments the current model, along with all Connectors. There are also routines to update the mouse cursor depending on the current mode of the TransformerView, as well as mouseDown routines that do different things depending on the mode. See each function for a biref description of what it does. This class derives from NSView and conforms to the NSViewToolTipOwner and NSMenuItemValidation protocols.
@MainActor
class TransformerView: NSView, NSViewToolTipOwner, NSMenuItemValidation {
    
    /// I suppose that I could get fancy and create a TransformerViewDelegate protocol but since the calls are so specific, I'm unable to justify the extra complexity, so I'll just save a weak reference to the AppController here. The AppController will need to stuff a pointer to itself in here, probably best done in awakeFromNib()
    weak var appController:AppController? = nil
    
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

            self.RebuildConnectors()
        }
    }

    /// True while a connector rebuild is in progress, and whether another rebuild was requested while one was running.
    /// These coalesce bursts of rebuild requests (e.g. rapid zooming) into a single serialized re-run.
    private var connectorsRebuildRunning = false
    private var connectorsRebuildPending = false

    // MARK: Connector routing offsets (Phase 3: derived from the model geometry so they scale with model size)

    /// The radial offset a connector steps out of a coil into the adjacent gap.
    var connectorStubOffset = connectorStubDefault
    /// The spacing between parallel connector lanes in a shared channel.
    var connectorLaneGap = connectorLaneSpacing
    /// The axial clearance between the winding extent and a horizontal cross-over channel.
    var connectorCrossoverClearance = connectorCrossoverMargin

    /// Recompute the connector routing offsets from the model geometry (tightest radial gap and winding height) so that
    /// they scale with the physical size of the model. Falls back to the previous fixed defaults for degenerate geometry.
    func UpdateConnectorMetrics() async {

        let allSegments = segments.map { $0.segment }
        guard !allSegments.isEmpty else { return }

        // Gather each coil's radial extent (inside/outside edge) and the overall axial extent of the winding.
        var coilInside:[Int:Double] = [:]
        var coilOutside:[Int:Double] = [:]
        var windingTop = -Double.greatestFiniteMagnitude
        var windingBottom = Double.greatestFiniteMagnitude

        for segment in allSegments {

            let rect = await segment.rect
            let pos = segment.radialPos
            coilInside[pos] = min(coilInside[pos] ?? Double.greatestFiniteMagnitude, rect.minX)
            coilOutside[pos] = max(coilOutside[pos] ?? -Double.greatestFiniteMagnitude, rect.maxX)
            windingTop = max(windingTop, rect.maxY)
            windingBottom = min(windingBottom, rect.minY)
        }

        // Smallest radial build across the coils (fallback radial unit when there is only one coil).
        var minBuild = Double.greatestFiniteMagnitude
        for pos in coilInside.keys {

            if let inside = coilInside[pos], let outside = coilOutside[pos] {

                minBuild = min(minBuild, outside - inside)
            }
        }

        // Smallest positive hilo gap between radially-adjacent coils (preferred radial unit, since stubs sit in the gap).
        let sortedPositions = coilInside.keys.sorted()
        var minGap = Double.greatestFiniteMagnitude
        if sortedPositions.count > 1 {

            for i in 0 ..< (sortedPositions.count - 1) {

                if let curOutside = coilOutside[sortedPositions[i]], let nextInside = coilInside[sortedPositions[i + 1]] {

                    let gap = nextInside - curOutside
                    if gap > 0 { minGap = min(minGap, gap) }
                }
            }
        }

        let radialUnit = minGap.isFinite ? minGap : (minBuild.isFinite ? minBuild : 0.0)
        let windingHeight = windingTop - windingBottom

        if radialUnit > 0 {

            self.connectorStubOffset = radialUnit * connectorStubGapFraction
            self.connectorLaneGap = radialUnit * connectorLaneGapFraction
        }

        if windingHeight > 0 {

            self.connectorCrossoverClearance = windingHeight * connectorCrossoverHeightFraction
        }
    }

    /// Rebuild every connector's ViewConnector from scratch. Call this whenever the model changes, or whenever the
    /// view scale changes (so that scale-dependent geometry — the coil-end / gap lead stubs — re-fits to the new zoom).
    func RebuildConnectors() {

        if connectorsRebuildRunning {

            connectorsRebuildPending = true
            return
        }

        connectorsRebuildRunning = true

        Task {

            // Refresh the geometry-derived routing offsets before rebuilding (the model may have changed).
            await self.UpdateConnectorMetrics()

            repeat {

                connectorsRebuildPending = false

                let allSegments = segments.map { $0.segment }
                var maskSegments:[Int] = []
                self.viewConnectors = []
                for nextSegment in segments {

                    await nextSegment.SetUpConnectors(allSegments: allSegments, maskSegments: maskSegments)
                    maskSegments.append(nextSegment.segment.serialNumber)
                }

                self.needsDisplay = true

            } while connectorsRebuildPending

            connectorsRebuildRunning = false
        }
    }
    
    var allSegments:[Segment] {
        
        get {
            
            let result = segments.map({ $0.segment })
            return result
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

        // Rebuild the connectors when a trackpad pinch-zoom ends so that the scale-dependent lead stubs re-fit to the new zoom.
        NotificationCenter.default.addObserver(self, selector: #selector(handleLiveMagnifyDidEnd(_:)), name: NSScrollView.didEndLiveMagnifyNotification, object: self.scrollView)
    }

    // Called when a trackpad pinch-zoom on the scrollView finishes.
    @objc func handleLiveMagnifyDidEnd(_ notification: Notification) {

        self.RebuildConnectors()
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
        
        // In the interest of speed, we do not simply set "needsDisplay" to true for every single update that is required (that will cause a complete redraw of the entire view rectangle, which takes time). Instead, most of the routines will call setNeedsDisplay(invalidRect:NSRect) with a rectangle (in TransformerView coordinates) that needs to be redrawn. The system collects these rectangles and then passes it through to the draw routine. We could either check ourselves if we need to redraw certain elements, or use the NSView routine "needsToDraw" and only redraw if that routine returns 'true'. This is the kind of advanced programming that is needed if you are drawing a LOT of different elements at a somewhat high speed (for instance, the zoom and select rectangles).
        
        if self.needsToDraw(self.boundary) {
            
            // print("Drawing boundary")
            let boundaryPath = NSBezierPath(rect: boundary)
            self.boundaryColor.set()
            boundaryPath.stroke()
        }
        
        for nextSegment in self.segments
        {
            if self.needsToDraw(nextSegment.GetRect()) {
                
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
        
        let segRect = segment.GetRect()
        var corners:[NSPoint] = [segRect.origin]
        corners.append(NSPoint(x: segRect.origin.x + segRect.size.width, y: segRect.origin.y))
        corners.append(NSPoint(x: segRect.origin.x + segRect.size.width, y: segRect.origin.y + segRect.size.height))
        corners.append(NSPoint(x: segRect.origin.x, y: segRect.origin.y + segRect.size.height))
        
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

    // MARK: Key Events
    override func keyDown(with event: NSEvent) {
        
        if event.keyCode == kVK_Escape {
            
            self.mode = .selectSegment
            return
        }
        
        super.keyDown(with: event)
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
            self.mode = .selectSegment
            self.needsDisplay = true
        }
        // The user has finished dragging his selection rectangle, so get the end point and add all segments in the rectangle to the currentSegments array
        else if self.mode == .selectRect {
            
            let endPoint = self.convert(event.locationInWindow, from: nil)
            let newSize = NSSize(width: endPoint.x - self.selectRect!.origin.x, height: endPoint.y - self.selectRect!.origin.y)
            self.selectRect!.size = newSize
            
            self.selectRect = NormalizeRect(srcRect: self.selectRect!)
            
            self.currentSegments = []
            
            
            
            for nextSegment in self.segments {
                
                if NSContainsRect(self.selectRect!, nextSegment.GetRect()) {
                    
                    if self.currentSegments.firstIndex(of: nextSegment) == nil {
                        
                        self.currentSegments.append(nextSegment)
                    }
                }
            }
            
            self.mode = .selectSegment
            self.needsDisplay = true
        }
        // The user has finished adding a connection. If the end-point is a valid connection point, add the new conenctor to the model.
        else if self.mode == .addConnection, let startConnector = self.addConnectionStartConnector {
            
            let endPoint = self.convert(event.locationInWindow, from: nil)
            let segmentArray = self.allSegments
            
            Task {
                
                for nextViewConnector in self.viewConnectors {
                    
                    if nextViewConnector.hitZone.contains(endPoint) {
                        
                        if nextViewConnector == startConnector {
                            
                            return
                        }
                        
                        var startConnections = await startConnector.segments.from.ConnectionDestinations(fromLocation: startConnector.connector.fromLocation)
                        startConnections.removeAll(where: { $0.segmentID == nil })
                        startConnections.insert((startConnector.segments.from.serialNumber, startConnector.connector.fromLocation), at: 0)
                        
                        var endConnections = await nextViewConnector.segments.from.ConnectionDestinations(fromLocation: nextViewConnector.connector.fromLocation)
                        endConnections.removeAll(where: { $0.segmentID == nil })
                        endConnections.insert((nextViewConnector.segments.from.serialNumber, nextViewConnector.connector.fromLocation), at: 0)
                        
                        var equivalentConnections:Set<Segment.Connection.EquivalentConnection> = []
                        
                        for nextStartConnection in startConnections {
                            
                            for nextEndConnection in endConnections {
                                
                                guard let nextStartSegment = segmentArray.first(where: {$0.serialNumber == nextStartConnection.segmentID}) else {
                                    
                                    ALog("This should not happen!")
                                    return
                                }
                                let newConnections = await nextStartSegment.AddConnector(segments: segmentArray, fromLocation: nextStartConnection.location, toLocation: nextEndConnection.location, toSegmentID: nextEndConnection.segmentID)
                                // let newConnections = nextStartConnection.segment!.AddConnector(fromLocation: nextStartConnection.location, toLocation: nextEndConnection.location, toSegment: nextEndConnection.segmentID)
                                
                                guard let newSrcConnection = newConnections.from, let newDestConnection = newConnections.to else {
                                    
                                    ALog("FUCK!")
                                    return
                                }
                                
                                equivalentConnections.insert(Segment.Connection.EquivalentConnection(parent: nextStartConnection.segmentID!, connection: newSrcConnection))
                                equivalentConnections.insert(Segment.Connection.EquivalentConnection(parent: nextEndConnection.segmentID!, connection: newDestConnection))
                            }
                        }
                        
                        for nextConnection in equivalentConnections {
                            
                            guard let nextConnParent = segmentArray.first(where: {$0.serialNumber == nextConnection.parent}) else {
                                
                                ALog("No, no!")
                                return
                            }
                            await nextConnParent.AddEquivalentConnections(to: nextConnection.connection, equ: equivalentConnections)
                        }
                        
                        guard let startSegmentPath = self.segments.first(where: {$0.segment == startConnector.segments.from}) else {
                            
                            // this should never happen
                            DLog("Problem!")
                            break
                        }
                        
                        // add all the non-touched segments to the maskSegment array so that the SetUpConnectors call goes quickly
                        var maskSegments:[Int] = []
                        for nextSegmentPath in self.segments {
                            
                            if nextSegmentPath.segment != nextViewConnector.segments.from {
                                
                                maskSegments.append(nextSegmentPath.segment.serialNumber)
                            }
                        }
                        
                        await startSegmentPath.SetUpConnectors(allSegments: segmentArray, maskSegments: maskSegments)
                        
                        break
                    }
                }
                
                self.highlightedConnectorPath = nil
                self.addConnectionStartConnector = nil
                self.addConnectionPath.removeAllPoints()
                
                self.mode = .selectSegment
                self.needsDisplay = true
            }
        }
        
        // self.mode = .selectSegment
        // self.needsDisplay = true
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
        let segmentArray = self.allSegments
                
        Task {
            
            for nextViewConnector in self.viewConnectors {
                
                if nextViewConnector.hitZone.contains(clickPoint) {
                    
                    guard let appCtrl = self.appController, let model = appCtrl.currentModel else {
                        
                        return
                    }
                    
                    // var removeMask:[Segment] = []
                    let affectedSegments = await nextViewConnector.segments.from.RemoveConnection(segments: self.allSegments, connection: Segment.Connection(segmentID: nextViewConnector.segments.to?.serialNumber, connector: nextViewConnector.connector))
                    
                    // we will be removing ALL the ViewConnectors that are associated with the affected Segments. Since we show the ViewConnectors in a way that keeps "moving forward" (up), we need to also keep the previous segments (as long as they are on the same coil) out of thh maskSegments array
                    var adjacentSegments:[Segment] = []
                    for nextAffectedSegment in affectedSegments {
                        
                        guard let affSegment = segmentArray.first(where: {$0.serialNumber == nextAffectedSegment}) else {
                            
                            ALog("Can't happen!")
                            return
                        }
                        if let adjSegs = try? await model.AxiallyAdjacentSegments(to: affSegment) {
                            
                            if let belowAdj = adjSegs.below {
                                
                                adjacentSegments.append(belowAdj)
                            }
                            
                            if let aboveAdj = adjSegs.above {
                                
                                adjacentSegments.append(aboveAdj)
                            }
                        }
                    }
                    
                    // add all the non-touched segments to the maskSegment array so that the SetUpConnectors call goes quickly
                    var maskSegments:[Int] = []
                    for nextSegmentPath in self.segments {
                        
                        if !affectedSegments.contains(nextSegmentPath.segment.serialNumber) && !adjacentSegments.contains(nextSegmentPath.segment) {
                            
                            maskSegments.append(nextSegmentPath.segment.serialNumber)
                        }
                    }
                    
                    
                    
                    self.viewConnectors.removeAll(where: { affectedSegments.contains($0.segments.from.serialNumber) || ($0.segments.to != nil && affectedSegments.contains($0.segments.to!.serialNumber)) })
                    
                    for nextChangedSegment in affectedSegments {
                        
                        if let changedIndex = self.segments.firstIndex(where: { $0.segment.serialNumber == nextChangedSegment }) {
                            
                            await self.segments[changedIndex].SetUpConnectors(allSegments: segmentArray, maskSegments: maskSegments)
                            // maskSegments.append(nextChangedSegment)
                        }
                    }
                    
                    // segmentPath.SetUpConnectors(maskSegments: maskSegments)
                    
                    self.needsDisplay = true
                    
                    do {
                        
                        let _ = try await model.SetNodes()
                    }
                    catch {
                        
                        let alert = NSAlert(error: error)
                        let _ = alert.runModal()
                        return
                    }
                    
                    break
                }
            }
        }
        
    }
    
    // The mouse was clicked while in addImpulse mode. Check if the clicked point is a valid location and if so, add the impulse connection and show it
    func mouseDownWithAddImpulse(event:NSEvent) {
        
        let clickPoint = self.convert(event.locationInWindow, from: nil)
        
        let segmentArray = self.allSegments
        
        Task {
            
            for nextViewConnector in self.viewConnectors {
                
                if nextViewConnector.hitZone.contains(clickPoint) {
                    
                    await nextViewConnector.segments.from.AddConnector(segments: segmentArray, fromLocation: nextViewConnector.connector.fromLocation, toLocation: .impulse, toSegmentID: nil)
                    
                    for nextConnection in await nextViewConnector.segments.from.ConnectionDestinations(fromLocation: nextViewConnector.connector.fromLocation) {
                        
                        if let nextSegmentID = nextConnection.segmentID {
                            
                            guard let nextSegment = segmentArray.first(where: {$0.serialNumber == nextSegmentID}) else {
                                ALog("No!")
                                return
                            }
                            await nextSegment.AddConnector(segments: segmentArray, fromLocation: nextConnection.location, toLocation: .impulse, toSegmentID: nil)
                        }
                    }
                    
                    var maskSegments:[Int] = []
                    for nextSegmentPath in self.segments {
                        
                        if nextSegmentPath.segment != nextViewConnector.segments.from {
                            
                            maskSegments.append(nextSegmentPath.segment.serialNumber)
                        }
                    }
                    
                    guard let segmentPath = self.segments.first(where: {$0.segment == nextViewConnector.segments.from}) else {
                        
                        DLog("Problem!")
                        break
                    }
                    
                    await segmentPath.SetUpConnectors(allSegments: segmentArray, maskSegments: maskSegments)
                    
                    break
                }
            }
            
            self.highlightedConnectorPath = nil
            self.needsDisplay = true
        }
    }
    
    // The mouse was clicked while in addGround mode. Check if the clicked point is a valid location and if so, add the ground connection and show it
    func mouseDownWithAddGround(event:NSEvent) {
        
        let clickPoint = self.convert(event.locationInWindow, from: nil)
        
        let segmentArray = self.allSegments
        
        Task {
            
            for nextViewConnector in self.viewConnectors {
                
                if nextViewConnector.hitZone.contains(clickPoint) {
                    
                    if nextViewConnector.hitZone.contains(clickPoint) {
                        
                        await nextViewConnector.segments.from.AddConnector(segments: segmentArray, fromLocation: nextViewConnector.connector.fromLocation, toLocation: .ground, toSegmentID: nil)
                        
                        for nextConnection in await nextViewConnector.segments.from.ConnectionDestinations(fromLocation: nextViewConnector.connector.fromLocation) {
                            
                            if let nextSegmentID = nextConnection.segmentID {
                                
                                guard let nextSegment = segmentArray.first(where: {$0.serialNumber == nextSegmentID}) else {
                                    
                                    ALog("More impossiblilities!")
                                    return
                                }
                                
                                await nextSegment.AddConnector(segments: segmentArray, fromLocation: nextConnection.location, toLocation: .ground, toSegmentID: nil)
                            }
                        }
                        
                        var maskSegments:[Int] = []
                        for nextSegmentPath in self.segments {
                            
                            if nextSegmentPath.segment != nextViewConnector.segments.from {
                                
                                maskSegments.append(nextSegmentPath.segment.serialNumber)
                            }
                        }
                        
                        guard let segmentPath = self.segments.first(where: {$0.segment == nextViewConnector.segments.from}) else {
                            
                            DLog("Problem!")
                            break
                        }
                        
                        await segmentPath.SetUpConnectors(allSegments: segmentArray, maskSegments: maskSegments)
                        
                        break
                    }
                }
            }
            
            self.highlightedConnectorPath = nil
            self.needsDisplay = true
        }
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

        // re-fit the scale-dependent lead stubs to the new zoom
        self.RebuildConnectors()
    }

    // the zoom in/out ratio (maybe consider making this user-settable)
    var zoomRatio:CGFloat = 0.75

    func handleZoomOut()
    {
        // Define the center of the new view and multiply the current scrollView magnification by the zoomRatio global to get the new view rectangle
        let contentCenter = NSPoint(x: self.scrollView.contentView.bounds.origin.x + self.scrollView.contentView.bounds.width / 2.0, y: self.scrollView.contentView.bounds.origin.y + self.scrollView.contentView.bounds.height / 2.0)
        self.scrollView.setMagnification(scrollView.magnification * zoomRatio, centeredAt: contentCenter)
        self.needsDisplay = true

        // re-fit the scale-dependent lead stubs to the new zoom
        self.RebuildConnectors()
    }

    func handleZoomIn()
    {
        // Define the center of the new view and divide the current scrollView magnification by the zoomRatio global to get the new view rectangle
        let contentCenter = NSPoint(x: self.scrollView.contentView.bounds.origin.x + self.scrollView.contentView.bounds.width / 2.0, y: self.scrollView.contentView.bounds.origin.y + self.scrollView.contentView.bounds.height / 2.0)
        self.scrollView.setMagnification(scrollView.magnification / zoomRatio, centeredAt: contentCenter)
        self.needsDisplay = true

        // re-fit the scale-dependent lead stubs to the new zoom
        self.RebuildConnectors()
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

        // re-fit the scale-dependent lead stubs to the new zoom
        self.RebuildConnectors()
    }
}

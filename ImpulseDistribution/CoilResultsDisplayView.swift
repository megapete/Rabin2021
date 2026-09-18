//
//  CoilResultsDisplayView.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-02-29.
//

import Cocoa
import PchBasePackage

class CoilResultsDisplayView: NSView {

    // The margins, in typographic points, which is the unit an NSView's frame is measured in. The left margin is
    // whatever the y-axis labels need (see UpdateScaleAndZoomWindow(extremaRect:)), so the value here is only a floor.
    private let minimumMarginLeft:CGFloat = 12.0
    private let marginRight:CGFloat = 14.0
    private let marginTop:CGFloat = 16.0

    /// The bottom margin grows to fit the x-axis end labels when there are any, the same way the left margin grows to fit the y-axis
    /// tick labels. Left at its floor they would be drawn below the bounds and clipped away.
    private var marginBottom:CGFloat {

        return xEndLabels == nil ? 16.0 : max(16.0, AxisScale.XEndLabelHeight + 4.0)
    }

    /// Names for the two ends of the x axis, or nil to leave the axis unlabelled (which is what the animated coil-results display
    /// does - it is read against the y axis, and its x axis is a position whose ends need no naming).
    ///
    /// The stress profiles used to be the other user of this view and are now `StressProfileView`, whose x axis carries real
    /// millimetre ticks. This one keeps end labels rather than gaining them: `InitialDistributionWindow` runs its x axis
    /// top-to-bottom, so "Top"/"Bottom" is the thing that stops it being read backwards.
    ///
    /// Only the ends are marked, never the values between them: see ``AxisScale/DrawXEndLabels(leftLabel:rightLabel:axisY:plotLeft:plotRight:pointSize:color:)``.
    var xEndLabels:(left:String, right:String)? = nil {

        didSet {

            // The bottom margin depends on this, and the bounds depend on the margin.
            guard !extrema.isEmpty else {

                self.needsDisplay = true
                return
            }

            UpdateScaleAndZoomWindow(extremaRect: extrema)
        }
    }

    let axisColor = NSColor.darkGray
    let lineColor = NSColor.red
    let extremumColor = NSColor.systemYellow

    private var scaleMultiplier:NSPoint = NSPoint()

    /// View coordinates per typographic point: the ratio the view's bounds bear to its frame. The bounds are set so
    /// that this is the same in both directions, which is what lets text be drawn at a fixed size on screen.
    private var scale:CGFloat = 1.0

    /// The data rectangle, in the data's own units: x is the coil height in mm, y is volts or amps.
    private var extrema:NSRect = NSRect()

    /// The data's y values (volts or amps) are multiplied by this on their way into view coordinates. It only exists
    /// to keep the numbers CoreGraphics has to deal with in the "low integer" range whatever the units of the
    /// simulation happen to be; it is always a power of ten, so the tick values stay exactly representable.
    private var yValueMultiplier:CGFloat = 1.0

    private var yTicks:[AxisTick] = []

    /// What the y values of the data represent. This sets the major-tick interval and the way the tick labels are
    /// formatted, so it has to be set before ``UpdateScaleAndZoomWindow(extremaRect:)`` is called.
    var yQuantity:AxisQuantity = .unitless
    /// The crest voltage of the impulse being simulated, in volts. Sets the major-tick interval of a voltage axis.
    var peakTestVoltage:Double = 0.0

    /// The data line currently being displayed, in the data's own units (x in mm, y in volts or amps). Storing it
    /// this way rather than as a ready-made path means a window resize redraws it correctly instead of stretching it.
    var currentData:[NSPoint] = [] {

        didSet {

            self.needsDisplay = true
        }
    }

    /// Convert a value in the data's own units into a view y coordinate
    private func ViewY(_ value:Double) -> CGFloat {

        return value * yValueMultiplier * scaleMultiplier.y
    }

    func UpdateScaleAndZoomWindow(extremaRect:NSRect) {

        // Convert the current extrema and axes' positions into the bounds for our view and zoom to show everything.
        // The extrema rectangle is inset by the margins declared above, which are in points and so are converted to
        // view coordinates by multiplying by 'scale'.

        var extremaRect = extremaRect

        // A run in which nothing moved would collapse one of the scale factors and, with it, the bounds-to-frame ratio
        // that everything else here assumes is the same in both directions. Give the degenerate axis a unit span.
        if extremaRect.width <= 0 {

            extremaRect.origin.x -= 0.5
            extremaRect.size.width = 1.0
        }

        if extremaRect.height <= 0 {

            extremaRect.origin.y -= 0.5
            extremaRect.size.height = 1.0
        }

        self.extrema = extremaRect

        yValueMultiplier = pow(10.0, floor(log10(1000.0 / extremaRect.height)))

        // First pass. The left margin depends on the tick labels, the tick labels depend on how far apart two of them
        // have to be to stay legible, and that depends on the scale - so work out a provisional scale with the margin
        // at its floor, generate the ticks from it, and only then settle the margin and the final scale.
        var metrics = ScaleMetrics(extremaRect: extremaRect, marginLeft: minimumMarginLeft)
        let realUnitsPerPoint = metrics.scale / (yValueMultiplier * metrics.yScale)

        yTicks = AxisScale.Ticks(minimum: extremaRect.minY, maximum: extremaRect.maxY, quantity: yQuantity, peakTestVoltage: peakTestVoltage, minimumSeparation: AxisScale.labelLineHeight * realUnitsPerPoint)

        let marginLeft = max(minimumMarginLeft, AxisScale.YAxisWidth(ticks: yTicks) + 4.0)
        metrics = ScaleMetrics(extremaRect: extremaRect, marginLeft: marginLeft)

        scale = metrics.scale
        scaleMultiplier = NSPoint(x: 1.0, y: metrics.yScale)

        var newBoundsRect = NSRect(x: extremaRect.minX, y: ViewY(extremaRect.minY), width: extremaRect.width, height: ViewY(extremaRect.maxY) - ViewY(extremaRect.minY))

        newBoundsRect.origin.x -= marginLeft * scale
        newBoundsRect.size.width += (marginLeft + marginRight) * scale
        newBoundsRect.origin.y -= marginBottom * scale
        newBoundsRect.size.height += (marginBottom + marginTop) * scale

        self.bounds = newBoundsRect

        DLog("Bounds: \(self.bounds)")

        self.needsDisplay = true
    }

    /// The two scaling factors for a given left margin. 'scale' is set by the x (coil-height) axis and is the
    /// view-coordinate size of one point; 'yScale' then stretches the (already multiplied) y values independently so
    /// that the data fills the plot height.
    private func ScaleMetrics(extremaRect:NSRect, marginLeft:CGFloat) -> (scale:CGFloat, yScale:CGFloat) {

        let plotWidth = max(1.0, self.frame.width - marginLeft - marginRight)
        let plotHeight = max(1.0, self.frame.height - marginBottom - marginTop)

        let newScale = extremaRect.width > 0 ? extremaRect.width / plotWidth : 1.0
        let newYScale = extremaRect.height > 0 ? plotHeight * newScale / (extremaRect.height * yValueMultiplier) : 1.0

        return (newScale, newYScale)
    }

    override func setFrameSize(_ newSize: NSSize) {

        super.setFrameSize(newSize)

        // The bounds are derived from the frame, so a resized window has to be rescaled or everything in it - the tick
        // labels especially - gets stretched.
        guard !extrema.isEmpty else {

            return
        }

        UpdateScaleAndZoomWindow(extremaRect: extrema)
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

        let oldLineWidth = NSBezierPath.defaultLineWidth
        NSBezierPath.defaultLineWidth = scale

        // The y-axis sits at the left-hand edge of the data (the bottom of the coil); the x-axis is the zero line.
        let plotLeft = extrema.isEmpty ? bounds.minX + minimumMarginLeft * scale : extrema.minX
        let plotRight = bounds.maxX - marginRight * scale

        let Axes = NSBezierPath()
        Axes.lineWidth = scale
        Axes.move(to: NSPoint(x: plotLeft, y: 0))
        Axes.line(to: NSPoint(x: plotRight, y: 0))
        axisColor.setStroke()
        Axes.stroke()

        let tickPositions = yTicks.map({ ViewY($0.value) })
        let axisBottom = min(ViewY(extrema.minY), tickPositions.min() ?? 0.0)
        let axisTop = max(ViewY(extrema.maxY), tickPositions.max() ?? 0.0)

        AxisScale.DrawYAxis(ticks: yTicks, axisX: plotLeft, axisBottom: axisBottom, axisTop: axisTop, plotRight: plotRight, pointSize: scale, axisColor: axisColor, extremumColor: extremumColor, viewY: ViewY)

        // The end labels hang from the BOTTOM OF THE DATA RECTANGLE, not from the zero line the x axis is drawn on. The two are the
        // same place for a plot whose values are all positive, but a negative-polarity impulse puts zero at the top of its data and
        // would then have the labels drawn down across the curve. The bottom edge is also the only place the bottom margin is
        // reserved, so it is the only place they are guaranteed not to be clipped.
        if let endLabels = xEndLabels {

            AxisScale.DrawXEndLabels(leftLabel: endLabels.left, rightLabel: endLabels.right, axisY: min(0.0, ViewY(extrema.minY)), plotLeft: plotLeft, plotRight: plotRight, pointSize: scale, axisColor: axisColor)
        }

        if currentData.isEmpty {

            NSBezierPath.defaultLineWidth = oldLineWidth
            return
        }

        let dataPath = NSBezierPath()
        dataPath.lineWidth = scale

        for nextIndex in 0..<currentData.count {

            let drawPoint = NSPoint(x: currentData[nextIndex].x, y: ViewY(currentData[nextIndex].y))

            if nextIndex == 0 {

                dataPath.move(to: drawPoint)
            }
            else {

                dataPath.line(to: drawPoint)
            }
        }

        lineColor.setStroke()
        dataPath.stroke()

        NSBezierPath.defaultLineWidth = oldLineWidth
    }

}

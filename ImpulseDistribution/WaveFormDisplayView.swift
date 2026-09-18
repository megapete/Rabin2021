//
//  WaveFormDisplayView.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-02-13.
//

import Cocoa
import PchBasePackage

class WaveFormDisplayView: NSView {

    // The margins, in typographic points, which is the unit an NSView's frame is measured in. The left margin is
    // whatever the y-axis labels need (see UpdateScaleAndZoomWindow()), so the value here is only a floor.
    private let minimumMarginLeft:CGFloat = 12.0
    private let marginRight:CGFloat = 14.0
    private let marginBottom:CGFloat = 16.0
    private let marginTop:CGFloat = 16.0

    let axisColor = NSColor.darkGray
    let extremumColor = NSColor.systemYellow

    /// What the y values of the data represent. This sets the major-tick interval and the way the tick labels are
    /// formatted, so it has to be set before the data is handed over.
    var yQuantity:AxisQuantity = .unitless
    /// The crest voltage of the impulse being simulated, in volts. Sets the major-tick interval of a voltage axis.
    var peakTestVoltage:Double = 0.0

    private var scaleMultiplier:NSPoint = NSPoint()

    /// View coordinates per typographic point: the ratio the view's bounds bear to its frame. The bounds are set so
    /// that this is the same in both directions, which is what lets text be drawn at a fixed size on screen.
    private var scale:CGFloat = 1.0

    private var extrema:NSRect = NSRect()

    /// The data's y values (volts or amps) are multiplied by this on their way into view coordinates. It only exists
    /// to keep the numbers CoreGraphics has to deal with in the "low integer" range whatever the units of the
    /// simulation happen to be; it is always a power of ten, so the tick values stay exactly representable.
    private var yValueMultiplier:CGFloat = 1.0

    private var yTicks:[AxisTick] = []

    /// The data is stored in its natural units (volts or amps). The scaling to view coordinates happens at draw time.
    private var dataStore:[[NSPoint]] = []

    /// Convert a value in the data's own units into a view y coordinate
    private func ViewY(_ value:Double) -> CGFloat {

        return value * yValueMultiplier * scaleMultiplier.y
    }

    func UpdateScaleAndZoomWindow() {

        // Convert the current extrema and axes' positions into the bounds for our view and zoom to show everything.
        // The extrema rectangle is inset by the margins declared above, which are in points and so are converted to
        // view coordinates by multiplying by 'scale'.

        var extremaRect = extrema.isEmpty ? NSRect(x: 0, y: 0, width: 1000, height: 800) : extrema

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

        DLog("\(self.bounds)")

        self.needsDisplay = true
    }

    /// The two scaling factors for a given left margin. 'scale' is set by the x (time) axis and is the view-coordinate
    /// size of one point; 'yScale' then stretches the (already multiplied) y values independently so that the data
    /// fills the plot height.
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
        UpdateScaleAndZoomWindow()
    }

    func AddDataSeries(newData:[NSPoint]) {

        self.dataStore.append(newData)

        self.extrema = self.extrema.union(WaveFormDisplayView.GetExtremaFromData(data: newData))
    }

    func RemoveAllDataSeries() {

        self.dataStore = []
        self.extrema = NSRect()
        self.yTicks = []

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
        // The y-axis sits at the left-hand edge of the data (for a waveform that is t = 0); the x-axis is the zero line.
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

        if dataStore.isEmpty {

            return
        }

        let oldLineWidth = NSBezierPath.defaultLineWidth
        NSBezierPath.defaultLineWidth = scale
        var waveForms:[NSBezierPath] = []

        var moveCount = 0
        var didFirst = false
        for nextTimeStep in dataStore {

            for nextPointIndex in 0..<nextTimeStep.count {

                var drawPoint = nextTimeStep[nextPointIndex]
                drawPoint.y = ViewY(drawPoint.y)

                if !didFirst {

                    moveCount += 1
                    waveForms.append(NSBezierPath())
                    waveForms[nextPointIndex].move(to: drawPoint)
                }
                else {

                    // DLog("Num elements in waveform \(nextPointIndex) before: \(waveForms[nextPointIndex].elementCount)")
                    waveForms[nextPointIndex].line(to: drawPoint)
                }

                // DLog("Num elements in waveform \(nextPointIndex) after: \(waveForms[nextPointIndex].elementCount)")
            }

            didFirst = true
        }

        // DLog("Number of elements in first path: \(waveForms[0].elementCount)")

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

        NSBezierPath.defaultLineWidth = oldLineWidth
    }

}

//
//  StressProfileView.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2026-08-11.
//
//  The plot both stress-profile windows draw into: a quantity against height, the allowable drawn across it, and the worst point
//  named in the body of the plot.
//
//  It started inside AxialStressProfileWindow and came out here when StressProfileWindow (the radial profiles) was given the same
//  furniture. One view rather than two matters more than the file count: the two graphs are read side by side, so a difference in
//  where the ticks fall, what the allowable looks like or what the annotation says would read as a difference in the DATA. What
//  varies between the two is passed in - see `Plot`.
//
//  WHY THIS IS NOT CoilResultsDisplayView. It needs a second series (the allowable), a labelled x axis on a fixed 100 mm grid,
//  markers at named heights and an annotation block inside the plot; that view has none of those and its two remaining users -
//  the animated coil results and the initial distribution - want none of them. This one draws in plain view coordinates
//  (bounds == frame, one point = one unit), which is what lets it hand `AxisScale` a `pointSize` of 1 and reuse `DrawYAxis`
//  unchanged. CoilResultsDisplayView instead sets its bounds to the data rectangle, which is why it needs two passes to settle a
//  margin and why everything drawn in it has to be scaled by hand.
//
//  THE POINTS ARE THE MODEL'S OWN RESOLUTION AND THE LINE BETWEEN THEM IS INTERPOLATION - one value per disc-to-disc gap in the
//  axial graph, one per sampled height in the radial one. The line is drawn because a profile reads as a shape and a scatter of
//  dots does not; it is not evidence of anything between two points.
//
//  Both callers derive the allowable from the finding itself rather than re-evaluating it: allowable field is
//  averageField / averageUtilization and allowable ΔV is deltaV / averageUtilization, both exact because the field is linear in
//  the driving voltage. See docs/dielectric-stress.md.
//

import Cocoa

@MainActor
class StressProfileView:NSView {

    /// One plotted point.
    struct Point {

        /// Height above the bottom yoke, in metres.
        let z:Double
        /// What is plotted, in base SI units (volts, or volts per metre - `Plot.quantity` says which).
        let value:Double
        /// What that point is allowed, same units, or nil where there is no allowable for it.
        let allowable:Double?
        /// value / allowable. The worst point is chosen on this rather than on the raw value: a point whose allowable is lower -
        /// a wider duct, a gap facing a static ring - can be the one in trouble at a lower field, which is the same argument the
        /// report table's ranking rests on.
        let utilization:Double
    }

    /// Everything one drawn profile needs. The window builds it; the view knows nothing about coils or gaps.
    struct Plot {

        /// Sorted by height.
        let points:[Point]
        /// Sets the tick labels' units: `.stress` labels in kV/mm, `.voltage` in kV.
        let quantity:AxisQuantity
        /// The impulse crest, for a `.voltage` axis's major-tick interval. Zero for anything else.
        let peakTestVoltage:Double
        /// Rows for the annotation block, as (label, value) pairs. Empty draws no block.
        let annotation:[(label:String, value:String)]
        /// Heights (metres) worth marking with a vertical rule - where an adjacent coil ends, and the profile stops being
        /// one-dimensional. Empty for a profile with no such place in it.
        let markers:[Double]
        /// What the marked heights are, for the legend beside the first of them.
        let markerName:String

        /// True where every point has the same allowable, which is the ordinary case and the one in which the allowable really is
        /// a horizontal line.
        var allowableIsConstant:Bool {

            let allowables = points.compactMap { $0.allowable }

            guard let first = allowables.first else { return true }

            return allowables.allSatisfy { abs($0 - first) <= 1.0E-9 * max(1.0, first) }
        }

        /// The point the annotation is about.
        var worst:Point? {

            return points.max { $0.utilization < $1.utilization }
        }
    }

    var plot:Plot? = nil {

        didSet {

            self.needsDisplay = true
        }
    }

    /// The x axis is a coil height in millimetres and the grid is 100 mm. It is not derived from the span: a round grid is the
    /// point, so a 900 mm coil and a 2400 mm one are read against the same ruler.
    private static let xTickInterval = 100.0

    private let axisColor = NSColor.darkGray
    private let valueColor = NSColor.systemRed
    private let allowableColor = NSColor.systemOrange
    private let extremumColor = NSColor.systemYellow
    private let markerColor = NSColor.systemGray

    private let marginRight = 16.0
    private let marginTop = 14.0

    /// Room for the x-axis ticks, their labels, and the axis title under them.
    private var marginBottom:CGFloat { return AxisScale.XEndLabelHeight + AxisScale.labelLineHeight + 4.0 }

    override func draw(_ dirtyRect: NSRect) {

        super.draw(dirtyRect)

        // No background fill, so this graph sits on the window's own colour the way the other two do.
        guard let plot = plot, let first = plot.points.first, let last = plot.points.last else {

            return
        }

        // ---- the ranges ----
        //
        // The x range is the profile's own extent. The y range starts at zero - a profile read against an allowable is a picture
        // of how much room is left, and a y axis that did not start at zero would make a comfortable coil look alarming - and
        // reaches past whichever is higher, the worst value or the allowable, so the allowable line is always on the plot.

        let xMinimum = first.z * 1000.0
        let xMaximum = max(last.z * 1000.0, xMinimum + 1.0)

        let peakValue = plot.points.map { $0.value }.max() ?? 1.0
        let peakAllowable = plot.points.compactMap { $0.allowable }.max()
        let yMaximum = max(peakValue, peakAllowable ?? 0.0) * 1.08

        guard yMaximum > 0.0 else {

            return
        }

        // ---- the plot rectangle ----
        //
        // The vertical scale is set by the plot HEIGHT, which the y tick labels cannot affect, so the ticks are worked out first
        // and the left margin is then whatever they need.

        let yTicks = YTicks(plot: plot, peakValue: peakValue, peakAllowable: peakAllowable, yMaximum: yMaximum)

        let marginLeft = max(12.0, AxisScale.YAxisWidth(ticks: yTicks) + 4.0)

        let plotLeft = bounds.minX + marginLeft
        let plotRight = bounds.maxX - marginRight
        let plotBottom = bounds.minY + marginBottom
        let plotTop = bounds.maxY - marginTop

        guard plotRight > plotLeft, plotTop > plotBottom else {

            return
        }

        func ViewX(_ xMillimetres:Double) -> CGFloat {

            return plotLeft + (xMillimetres - xMinimum) / (xMaximum - xMinimum) * (plotRight - plotLeft)
        }

        func ViewY(_ value:Double) -> CGFloat {

            return plotBottom + value / yMaximum * (plotTop - plotBottom)
        }

        // ---- the axes ----

        AxisScale.DrawYAxis(ticks: yTicks,
                            axisX: plotLeft,
                            axisBottom: plotBottom,
                            axisTop: plotTop,
                            plotRight: plotRight,
                            pointSize: 1.0,
                            axisColor: axisColor,
                            extremumColor: extremumColor,
                            viewY: ViewY)

        AxisScale.DrawXAxis(values: AxisScale.TickValues(minimum: xMinimum, maximum: xMaximum, interval: StressProfileView.xTickInterval),
                            axisY: plotBottom,
                            plotLeft: plotLeft,
                            plotRight: plotRight,
                            pointSize: 1.0,
                            axisColor: axisColor,
                            viewX: ViewX)

        // Centred UNDER the tick labels, in the line of bottom margin reserved for it. Hung off the right-hand end it collided
        // with the last tick label, which is the one place on this axis where there is already ink.
        let xTitle = NSAttributedString(string: "Height above bottom yoke (mm)",
                                        attributes: [.font:NSFont.systemFont(ofSize: AxisScale.labelFontSize), .foregroundColor:axisColor])
        xTitle.draw(at: NSPoint(x: (plotLeft + plotRight - xTitle.size().width) / 2.0, y: bounds.minY + 1.0))

        // ---- the marked heights ----
        //
        // Where the inner coil ends, the field stops being one-dimensional and the plotted value is indicative only. The note
        // under the picker says so in words; this says WHERE, which is the half of it that matters when reading a curve.

        DrawMarkers(plot: plot, xMinimum: xMinimum, xMaximum: xMaximum, plotLeft: plotLeft, plotRight: plotRight, plotBottom: plotBottom, plotTop: plotTop, viewX: ViewX)

        // ---- the two series ----

        let curve = plot.points.map { NSPoint(x: ViewX($0.z * 1000.0), y: ViewY($0.value)) }

        Stroke(points: curve, color: valueColor, width: 1.5)

        // The allowable. Drawn dashed so that it reads as a limit rather than as a second measurement, and so that a profile whose
        // allowable happens to sit on a y tick's guide line can still be told apart from it. Points without an allowable break the
        // line rather than being joined across.
        let allowablePath = NSBezierPath()
        allowablePath.lineWidth = 1.5
        allowablePath.setLineDash([6.0, 4.0], count: 2, phase: 0.0)

        var drawing = false

        for point in plot.points {

            guard let allowable = point.allowable else {

                drawing = false
                continue
            }

            let at = NSPoint(x: ViewX(point.z * 1000.0), y: ViewY(allowable))

            drawing ? allowablePath.line(to: at) : allowablePath.move(to: at)
            drawing = true
        }

        allowableColor.setStroke()
        allowablePath.stroke()

        // ---- the worst point, and what it is ----

        guard let worst = plot.worst else {

            return
        }

        let worstAt = NSPoint(x: ViewX(worst.z * 1000.0), y: ViewY(worst.value))
        let dot = NSBezierPath(ovalIn: NSRect(x: worstAt.x - 3.5, y: worstAt.y - 3.5, width: 7.0, height: 7.0))
        valueColor.setFill()
        dot.fill()

        DrawAnnotation(rows: plot.annotation,
                       curve: curve,
                       plotLeft: plotLeft,
                       plotRight: plotRight,
                       plotBottom: plotBottom,
                       plotTop: plotTop,
                       allowableY: peakAllowable.map { ViewY(min($0, yMaximum)) })
    }

    /// The y ticks: a round grid over the whole axis, plus the two values the graph is actually read for - the worst value in the
    /// profile and the allowable it is judged against. Both are marked as extremes, so `AxisScale` runs its dashed guide line
    /// across the plot at each; a round tick that would collide with either is dropped, those two being the informative ones.
    ///
    /// The majors come from `AxisScale.Ticks` but its own extreme ticks are thrown away (except zero). It marks the ends of the
    /// range it is handed, and the top of this range is headroom above the allowable rather than a value anything reached - a tick
    /// there labels the padding.
    private func YTicks(plot:Plot, peakValue:Double, peakAllowable:Double?, yMaximum:Double) -> [AxisTick] {

        // A label's height, in data units: the same spacing rule AxisScale uses to decide two ticks are too close.
        let plotHeight = max(1.0, bounds.height - marginBottom - marginTop)
        let separation = AxisScale.labelLineHeight * yMaximum / plotHeight

        let majors = AxisScale.Ticks(minimum: 0.0,
                                     maximum: yMaximum,
                                     quantity: plot.quantity,
                                     peakTestVoltage: plot.peakTestVoltage,
                                     minimumSeparation: separation).filter { !$0.isExtremum || $0.value == 0.0 }

        // AxisScale.Label, not a local format string: a voltage axis slides through the SI prefixes with its magnitude, so a
        // profile whose ticks come out in MV must not be given a mark hand-written in kV.
        var marks = [AxisTick(value: peakValue, label: AxisScale.Label(value: peakValue, quantity: plot.quantity, axisMaximum: yMaximum), isExtremum: true)]

        if let allowable = peakAllowable, allowable > 0.0, allowable <= yMaximum, abs(allowable - peakValue) >= separation {

            marks.append(AxisTick(value: allowable,
                                  label: AxisScale.Label(value: allowable, quantity: plot.quantity, axisMaximum: yMaximum) + (plot.allowableIsConstant ? "" : " max"),
                                  isExtremum: true))
        }

        var result = majors.filter { major in !marks.contains { abs($0.value - major.value) < separation } }
        result += marks
        result.sort { $0.value < $1.value }

        return result
    }

    /// Vertical rules at the plot's marked heights, named once so the reader is not left guessing what a stray line means.
    private func DrawMarkers(plot:Plot, xMinimum:Double, xMaximum:Double, plotLeft:CGFloat, plotRight:CGFloat, plotBottom:CGFloat, plotTop:CGFloat, viewX:(Double) -> CGFloat) {

        let font = NSFont.systemFont(ofSize: AxisScale.labelFontSize)
        var named = false

        for marker in plot.markers {

            let millimetres = marker * 1000.0

            guard millimetres >= xMinimum, millimetres <= xMaximum else {

                continue
            }

            let x = viewX(millimetres)

            let rule = NSBezierPath()
            rule.lineWidth = 1.0
            rule.setLineDash([3.0, 3.0], count: 2, phase: 0.0)
            rule.move(to: NSPoint(x: x, y: plotBottom))
            rule.line(to: NSPoint(x: x, y: plotTop))
            markerColor.withAlphaComponent(0.7).setStroke()
            rule.stroke()

            guard !named, !plot.markerName.isEmpty else {

                continue
            }

            // Flipped to the left of the rule when there is not room to its right - which is the usual case, since the height a
            // coil ends at is normally near one end of the profile.
            let label = NSAttributedString(string: plot.markerName, attributes: [.font:font, .foregroundColor:markerColor])
            let width = label.size().width
            let labelX = x + 3.0 + width <= plotRight ? x + 3.0 : max(plotLeft, x - 3.0 - width)

            label.draw(at: NSPoint(x: labelX, y: plotBottom + 2.0))
            named = true
        }
    }

    private func Stroke(points:[NSPoint], color:NSColor, width:CGFloat) {

        guard points.count > 1 else {

            // A single-point profile would otherwise draw nothing at all.
            if let only = points.first {

                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: only.x - 2.0, y: only.y - 2.0, width: 4.0, height: 4.0)).fill()
            }

            return
        }

        let path = NSBezierPath()
        path.lineWidth = width
        path.move(to: points[0])

        for point in points.dropFirst() {

            path.line(to: point)
        }

        color.setStroke()
        path.stroke()
    }

    /// The numbers, in the body of the plot.
    private func DrawAnnotation(rows:[(label:String, value:String)], curve:[NSPoint], plotLeft:CGFloat, plotRight:CGFloat, plotBottom:CGFloat, plotTop:CGFloat, allowableY:CGFloat?) {

        guard !rows.isEmpty else {

            return
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .regular)
        let boldFont = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .semibold)

        let labelWidth = rows.map { NSAttributedString(string: $0.label, attributes: [.font:font]).size().width }.max() ?? 0.0
        let valueWidth = rows.map { NSAttributedString(string: $0.value, attributes: [.font:boldFont]).size().width }.max() ?? 0.0

        let lineHeight = NSAttributedString(string: "X", attributes: [.font:font]).size().height + 2.0
        let padding = 8.0

        let boxSize = NSSize(width: labelWidth + 10.0 + valueWidth + padding * 2.0, height: lineHeight * Double(rows.count) + padding * 2.0)

        // WHERE THE BOX GOES is measured, not guessed. Four places are tried - left or right, under the allowable line or up in
        // the top corner - and the one covering the least of the curve wins. Anything that would sit on the allowable line is
        // rejected outright unless every candidate does: the curve is what the reader came for and the allowable is what they are
        // judging it against, so the annotation gets whatever is left over rather than the other way round.
        //
        // "Under the allowable" is offered first because the band between the curve and its limit is usually the emptiest part of
        // the plot, and it is exactly where a top-corner box would hide the limit.
        let topCorner = plotTop - 6.0

        var tops = [topCorner]

        if let allowableY {

            tops.insert(allowableY - 8.0, at: 0)
        }

        var candidates:[NSRect] = []

        for top in tops where top - boxSize.height > plotBottom && top <= plotTop {

            for x in [plotLeft + 12.0, plotRight - boxSize.width - 12.0] {

                candidates.append(NSRect(x: x, y: top - boxSize.height, width: boxSize.width, height: boxSize.height))
            }
        }

        func Cost(_ rect:NSRect) -> Int {

            // One per plotted point the box would cover, and a flat penalty - larger than any profile's point count - for hiding
            // the allowable line.
            let covered = curve.filter { rect.contains($0) }.count
            let hidesAllowable = allowableY.map { $0 >= rect.minY && $0 <= rect.maxY } ?? false

            return covered + (hidesAllowable ? 10000 : 0)
        }

        let box = candidates.min { Cost($0) < Cost($1) } ?? NSRect(x: plotLeft + 12.0, y: topCorner - boxSize.height, width: boxSize.width, height: boxSize.height)

        let background = NSBezierPath(roundedRect: box, xRadius: 5.0, yRadius: 5.0)
        NSColor.textBackgroundColor.withAlphaComponent(0.92).setFill()
        background.fill()
        NSColor.separatorColor.setStroke()
        background.lineWidth = 1.0
        background.stroke()

        var y = box.maxY - padding - lineHeight

        for row in rows {

            NSAttributedString(string: row.label, attributes: [.font:font, .foregroundColor:NSColor.secondaryLabelColor]).draw(at: NSPoint(x: box.minX + padding, y: y))
            NSAttributedString(string: row.value, attributes: [.font:boldFont, .foregroundColor:NSColor.labelColor]).draw(at: NSPoint(x: box.minX + padding + labelWidth + 10.0, y: y))

            y -= lineHeight
        }
    }
}

//
//  AxisScale.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2026-08-05.
//
//  Tick generation and y-axis drawing shared by the two result graphs (WaveFormDisplayView and
//  CoilResultsDisplayView). Both views set their 'bounds' to the data rectangle (in data units) and let AppKit
//  do the scaling, so everything drawn here has to be expressed in view coordinates. The conversion factor is
//  passed in as 'pointSize': the size of one typographic point measured in view coordinates, which is simply the
//  view's bounds-to-frame ratio. Multiplying a size in points by it makes text and tick marks come out the same
//  size on screen whatever the data happens to be scaled by.
//

import Cocoa

/// The physical quantity shown on a graph's axis. It sets both the major-tick interval and the way the tick labels
/// are formatted.
enum AxisQuantity {

    case voltage
    case current
    /// Electric stress, in volts per metre. Labelled in kV/mm - see ``UnitScale(maxAbsolute:quantity:)`` for why that
    /// unit is fixed rather than chosen from the magnitude.
    case stress
    /// Anything whose units are arbitrary (the Fourier magnitude display, for instance). The ticks are labelled with
    /// the bare numbers, with no unit suffix.
    case unitless
}

/// One tick on an axis.
struct AxisTick {

    /// The value of the tick, in base SI units (volts or amperes)
    let value:Double
    /// The text drawn beside the tick (empty for an unlabelled tick)
    let label:String
    /// True for the two ticks that mark the extreme values reached during the simulation. They are drawn longer, in
    /// a highlight colour, and with a dashed guide line across the plot.
    let isExtremum:Bool
}

/// Namespace for the axis calculations. There is no state here: everything is a pure function of the data range.
enum AxisScale {

    // MARK: Intervals

    /// The major-tick interval, in volts, for an impulse test whose crest voltage is 'peakTestVoltage'.
    ///
    /// 25 kV divisions read well up to a 250 kV BIL (10 divisions at the top level, fewer below). Above that the
    /// axis would need 20 or more divisions to reach the crest, so the interval opens out to 100 kV.
    static func MajorVoltageInterval(peakTestVoltage:Double) -> Double {

        return abs(peakTestVoltage) <= 250.0E3 ? 25.0E3 : 100.0E3
    }

    /// A "nice" interval - 1, 2 or 5 times a power of ten - that splits 'span' into roughly 'divisions' parts.
    static func NiceInterval(span:Double, divisions:Int = 8) -> Double {

        guard span > 0, span.isFinite, divisions > 0 else {

            return 1.0
        }

        let raw = span / Double(divisions)
        let magnitude = pow(10.0, floor(log10(raw)))
        let normalized = raw / magnitude
        let multiple:Double = normalized <= 1.0 ? 1.0 : (normalized <= 2.0 ? 2.0 : (normalized <= 5.0 ? 5.0 : 10.0))

        return multiple * magnitude
    }

    /// The interval that an extreme (maximum or minimum) value is rounded to before it is shown on the axis.
    ///
    /// For a voltage this is one kilovolt. For a current it is one tenth of the value's own decade - 0.1 kA for a
    /// current in the kiloamp range, 1 kA in the ten-kiloamp range, and so on - which is the same thing as keeping
    /// two significant figures. In both cases an axis too short for the fixed rule (one that would round every value
    /// to the same label) falls back to a hundredth of the span.
    static func ExtremumInterval(value:Double, quantity:AxisQuantity, span:Double) -> Double {

        switch quantity {

        case .voltage:
            return span >= 20.0E3 ? 1.0E3 : NiceInterval(span: span, divisions: 100)

        case .stress:
            // 0.1 kV/mm. Insulation allowables are quoted to about that resolution, so rounding an extreme any finer reports a
            // precision the underlying model does not have.
            return 1.0E5

        case .current, .unitless:
            guard value != 0, value.isFinite else {

                return NiceInterval(span: span, divisions: 100)
            }

            return pow(10.0, floor(log10(abs(value))) - 1.0)
        }
    }

    /// 'value', rounded to the interval given by ``ExtremumInterval(value:quantity:span:)``.
    static func RoundedExtremum(_ value:Double, quantity:AxisQuantity, span:Double) -> Double {

        let interval = ExtremumInterval(value: value, quantity: quantity, span: span)

        guard interval > 0, interval.isFinite else {

            return value
        }

        let result = (value / interval).rounded() * interval

        // -0.0 compares equal to 0.0 but formats as "-0", so squash it here
        return result == 0 ? 0.0 : result
    }

    // MARK: Tick generation

    /// Build the tick list for a y-axis running from 'minimum' to 'maximum' (both in volts or amperes).
    ///
    /// The list is the major ticks at the interval for the quantity, plus a tick at each of the two extremes reached
    /// during the simulation, rounded per ``ExtremumInterval(value:quantity:span:)``. A major tick that would land on
    /// top of an extremum tick is dropped, the extremum being the more informative of the two.
    ///
    /// - parameter minimumSeparation: how far apart, **in data units**, two ticks have to be before their labels stop
    /// overlapping. The caller works this out from its own scale.
    static func Ticks(minimum:Double, maximum:Double, quantity:AxisQuantity, peakTestVoltage:Double, minimumSeparation:Double) -> [AxisTick] {

        guard minimum.isFinite, maximum.isFinite, maximum > minimum else {

            return []
        }

        let span = maximum - minimum

        var majorInterval:Double

        if quantity == .voltage, peakTestVoltage > 0 {

            majorInterval = MajorVoltageInterval(peakTestVoltage: peakTestVoltage)

            // The fixed interval is only useful if it actually divides this axis. A run whose voltages are a small
            // fraction of the crest (a single coil, say) would get no ticks at all, and one whose overshoot is large
            // would get too many, so fall back to a computed interval in either case.
            if span / majorInterval > 25.0 || span / majorInterval < 1.5 {

                majorInterval = NiceInterval(span: span)
            }
        }
        else {

            majorInterval = NiceInterval(span: span)
        }

        // Never put the majors closer together than their labels can be drawn
        if minimumSeparation > 0, majorInterval < minimumSeparation {

            majorInterval = NiceInterval(span: span, divisions: max(1, Int(span / minimumSeparation)))
        }

        let lowExtremum = RoundedExtremum(minimum, quantity: quantity, span: span)
        let highExtremum = RoundedExtremum(maximum, quantity: quantity, span: span)

        var values:[(value:Double, isExtremum:Bool)] = [(lowExtremum, true)]

        if abs(highExtremum - lowExtremum) >= minimumSeparation {

            values.append((highExtremum, true))
        }

        // The multiples are kept as Doubles: an axis whose values are enormous next to its span (a fraction of a volt
        // either side of a megavolt, say) would otherwise overflow the conversion. The *count* is small either way.
        let firstMultiple = ceil(minimum / majorInterval)
        let lastMultiple = floor(maximum / majorInterval)

        if lastMultiple >= firstMultiple, lastMultiple - firstMultiple < 100 {

            for nextStep in 0...Int(lastMultiple - firstMultiple) {

                let nextValue = (firstMultiple + Double(nextStep)) * majorInterval

                if values.contains(where: { abs($0.value - nextValue) < minimumSeparation }) {

                    continue
                }

                values.append((nextValue == 0 ? 0.0 : nextValue, false))
            }
        }

        values.sort(by: { $0.value < $1.value })

        guard quantity != .unitless else {

            // No units to put on the labels, so just print the numbers as compactly as they will go
            return values.map({ AxisTick(value: $0.value, label: String(format: "%g", $0.value), isExtremum: $0.isExtremum) })
        }

        let unit = UnitScale(maxAbsolute: values.map({ abs($0.value) }).max() ?? 0.0, quantity: quantity)
        let scaledValues = values.map({ $0.value / unit.divisor })
        let decimals = DecimalsNeeded(values: scaledValues)

        return zip(values, scaledValues).map({

            AxisTick(value: $0.value, label: String(format: "%.\(decimals)f%@", $1, unit.suffix), isExtremum: $0.isExtremum)
        })
    }

    /// The divisor and unit suffix to use for an axis whose largest label is 'maxAbsolute'.
    private static func UnitScale(maxAbsolute:Double, quantity:AxisQuantity) -> (divisor:Double, suffix:String) {

        let base:String

        switch quantity {

        case .voltage: base = "V"
        case .current: base = "A"

        case .stress:
            // Every transformer designer quotes stress in kV/mm, and so does every allowable in DielectricStress.swift, so this
            // axis is pinned to that unit rather than sliding through the SI prefixes the way a voltage axis does. Letting it slide
            // would label a 900 V/mm creep result in "MV/m" and an oil duct in "kV/mm" on two graphs side by side, which is exactly
            // the sort of thing that gets a number misread by a factor of a thousand. 1 kV/mm = 1e6 V/m.
            return (1.0E6, " kV/mm")

        case .unitless: return (1.0, "")
        }

        if maxAbsolute >= 1.0E6 { return (1.0E6, " M" + base) }
        if maxAbsolute >= 1.0E3 { return (1.0E3, " k" + base) }
        if maxAbsolute >= 1.0 || maxAbsolute == 0 { return (1.0, " " + base) }
        if maxAbsolute >= 1.0E-3 { return (1.0E-3, " m" + base) }

        return (1.0E-6, " µ" + base)
    }

    /// The fewest decimal places (up to 'limit') that print every one of 'values' without losing anything.
    private static func DecimalsNeeded(values:[Double], limit:Int = 3) -> Int {

        for decimals in 0...limit {

            let factor = pow(10.0, Double(decimals))

            if values.allSatisfy({ abs(($0 * factor).rounded() / factor - $0) <= 1.0E-9 * max(1.0, abs($0)) }) {

                return decimals
            }
        }

        return limit
    }

    // MARK: Drawing

    /// The size, in points, of the text used for the tick labels
    static let labelFontSize:CGFloat = 10.0
    /// The vertical space, in points, that a tick label needs to itself
    static let labelLineHeight:CGFloat = 14.0

    private static let majorTickLength:CGFloat = 6.0
    private static let extremumTickLength:CGFloat = 10.0
    private static let labelGap:CGFloat = 4.0

    /// The width, in points, that ``DrawYAxis(...)`` needs to the left of the axis line for 'ticks'. The calling view
    /// uses this as its left margin, so that the labels always fit however many digits they turn out to have.
    static func YAxisWidth(ticks:[AxisTick]) -> CGFloat {

        let font = NSFont.monospacedDigitSystemFont(ofSize: labelFontSize, weight: .regular)

        var widest:CGFloat = 0.0

        for nextTick in ticks where !nextTick.label.isEmpty {

            let label = NSAttributedString(string: nextTick.label, attributes: [.font:font])
            widest = max(widest, label.size().width)
        }

        return extremumTickLength + labelGap + widest
    }

    /// Draw a vertical axis at 'axisX' with a tick, and a right-aligned label, for every entry in 'ticks'.
    ///
    /// - parameter pointSize: one typographic point expressed in view coordinates (the bounds-to-frame ratio)
    /// - parameter plotRight: the right-hand edge of the plot area, used for the extremum guide lines
    /// - parameter viewY: converts a tick value (volts or amps) into a view y coordinate
    static func DrawYAxis(ticks:[AxisTick], axisX:CGFloat, axisBottom:CGFloat, axisTop:CGFloat, plotRight:CGFloat, pointSize:CGFloat, axisColor:NSColor, extremumColor:NSColor, viewY:(Double) -> CGFloat) {

        let axis = NSBezierPath()
        axis.lineWidth = pointSize
        axis.move(to: NSPoint(x: axisX, y: axisBottom))
        axis.line(to: NSPoint(x: axisX, y: axisTop))
        axisColor.setStroke()
        axis.stroke()

        guard !ticks.isEmpty else {

            return
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: labelFontSize * pointSize, weight: .regular)

        for nextTick in ticks {

            let y = viewY(nextTick.value)
            let color = nextTick.isExtremum ? extremumColor : axisColor
            let tickLength = (nextTick.isExtremum ? extremumTickLength : majorTickLength) * pointSize

            color.setStroke()

            let tickPath = NSBezierPath()
            tickPath.lineWidth = pointSize
            tickPath.move(to: NSPoint(x: axisX - tickLength, y: y))
            tickPath.line(to: NSPoint(x: axisX, y: y))
            tickPath.stroke()

            // The extremes are the numbers the user is actually after, so run a dashed line across the plot to show
            // which part of which trace reached them.
            if nextTick.isExtremum, plotRight > axisX {

                let guideLine = NSBezierPath()
                guideLine.lineWidth = pointSize
                guideLine.setLineDash([4.0 * pointSize, 4.0 * pointSize], count: 2, phase: 0.0)
                guideLine.move(to: NSPoint(x: axisX, y: y))
                guideLine.line(to: NSPoint(x: plotRight, y: y))
                color.withAlphaComponent(0.4).setStroke()
                guideLine.stroke()
            }

            guard !nextTick.label.isEmpty else {

                continue
            }

            let label = NSAttributedString(string: nextTick.label, attributes: [.font:font, .foregroundColor:color])
            let labelSize = label.size()
            label.draw(at: NSPoint(x: axisX - tickLength - labelGap * pointSize - labelSize.width, y: y - labelSize.height / 2.0))
        }
    }

    /// The height, in points, that ``DrawXEndLabels(...)`` needs below the axis line. A view that uses it has to make its bottom
    /// margin at least this, or the labels are drawn outside the bounds and clipped.
    static var XEndLabelHeight:CGFloat {

        return majorTickLength + labelGap + labelLineHeight
    }

    /// Every multiple of 'interval' inside [minimum, maximum].
    ///
    /// This is the x-axis counterpart of ``Ticks(minimum:maximum:quantity:peakTestVoltage:minimumSeparation:)`` and it is
    /// deliberately much simpler: it takes the interval rather than choosing one. The axis it exists for is a coil height in
    /// millimetres, where a round 100 mm grid is what a designer measures against, and a "nice" interval computed from the span
    /// would give a different grid for every coil.
    static func TickValues(minimum:Double, maximum:Double, interval:Double) -> [Double] {

        guard minimum.isFinite, maximum.isFinite, maximum > minimum, interval > 0.0 else {

            return []
        }

        let first = ceil(minimum / interval)
        let last = floor(maximum / interval)

        guard last >= first, last - first < 1000 else {

            return []
        }

        return (0...Int(last - first)).map { (first + Double($0)) * interval }
    }

    /// Draw a horizontal axis with a labelled tick at each of 'values'.
    ///
    /// Labels are thinned rather than dropped or overlapped: if consecutive labels would not fit side by side, every second one
    /// is labelled, then every third, and so on - the ticks themselves all stay, so the grid a reader is measuring against does
    /// not change with the width of the window.
    ///
    /// - parameter viewX: converts an x value (in the data's units) into a view x coordinate
    /// - parameter pointSize: one typographic point expressed in view coordinates, exactly as in ``DrawYAxis(...)``
    static func DrawXAxis(values:[Double], format:String = "%.0f", axisY:CGFloat, plotLeft:CGFloat, plotRight:CGFloat, pointSize:CGFloat, axisColor:NSColor, viewX:(Double) -> CGFloat) {

        let axis = NSBezierPath()
        axis.lineWidth = pointSize
        axis.move(to: NSPoint(x: plotLeft, y: axisY))
        axis.line(to: NSPoint(x: plotRight, y: axisY))
        axisColor.setStroke()
        axis.stroke()

        guard !values.isEmpty else {

            return
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: labelFontSize * pointSize, weight: .regular)
        let labels = values.map { NSAttributedString(string: String(format: format, $0), attributes: [.font:font, .foregroundColor:axisColor]) }

        // How many ticks apart a labelled one has to be for the labels to clear each other.
        var stride = 1

        if values.count > 1 {

            let spacing = abs(viewX(values[1]) - viewX(values[0]))
            let widest = labels.map { $0.size().width }.max() ?? 0.0

            if spacing > 0.0 {

                stride = max(1, Int(ceil((widest + labelGap * 2.0 * pointSize) / spacing)))
            }
        }

        let tickLength = majorTickLength * pointSize

        for (index, value) in values.enumerated() {

            let x = viewX(value)

            axisColor.setStroke()

            let tickPath = NSBezierPath()
            tickPath.lineWidth = pointSize
            tickPath.move(to: NSPoint(x: x, y: axisY))
            tickPath.line(to: NSPoint(x: x, y: axisY - tickLength))
            tickPath.stroke()

            guard index % stride == 0 else {

                continue
            }

            let label = labels[index]
            let size = label.size()
            label.draw(at: NSPoint(x: x - size.width / 2.0, y: axisY - tickLength - labelGap * pointSize - size.height))
        }
    }

    /// Mark and name the two ends of a horizontal axis - nothing in between.
    ///
    /// This is for an axis whose ENDS are what matter and whose intermediate values do not: the axial position along a coil, where
    /// "top" and "bottom" say everything a reader needs and a millimetre scale would only add clutter. Where the intermediate
    /// values DO matter - the axial stress profile, which is read off against a height in millimetres - use
    /// ``TickValues(minimum:maximum:interval:)`` with ``DrawXAxis(values:format:axisY:plotLeft:plotRight:pointSize:axisColor:viewX:)``.
    ///
    /// - parameter axisY: the view y coordinate of the axis line the labels hang below (the zero line, in both graph views)
    /// - parameter pointSize: one typographic point expressed in view coordinates, exactly as in ``DrawYAxis(...)``
    static func DrawXEndLabels(leftLabel:String, rightLabel:String, axisY:CGFloat, plotLeft:CGFloat, plotRight:CGFloat, pointSize:CGFloat, axisColor:NSColor) {

        guard plotRight > plotLeft else {

            return
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: labelFontSize * pointSize, weight: .regular)
        let tickLength = majorTickLength * pointSize

        axisColor.setStroke()

        for x in [plotLeft, plotRight] {

            let tickPath = NSBezierPath()
            tickPath.lineWidth = pointSize
            tickPath.move(to: NSPoint(x: x, y: axisY))
            tickPath.line(to: NSPoint(x: x, y: axisY - tickLength))
            tickPath.stroke()
        }

        let labelY = axisY - tickLength - labelGap * pointSize

        // The two labels are pushed to the outside of their own ends rather than centred on them. Centring would hang the left label
        // half over the y axis and its tick labels, which is the one place on this plot where there is already ink.
        let left = NSAttributedString(string: leftLabel, attributes: [.font:font, .foregroundColor:axisColor])
        left.draw(at: NSPoint(x: plotLeft, y: labelY - left.size().height))

        let right = NSAttributedString(string: rightLabel, attributes: [.font:font, .foregroundColor:axisColor])
        let rightSize = right.size()
        right.draw(at: NSPoint(x: plotRight - rightSize.width, y: labelY - rightSize.height))
    }
}

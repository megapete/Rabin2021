//
//  AxialStressProfileWindow.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2026-08-11.
//
//  The disc-to-disc stress profile of one coil: stress against height, with the allowable drawn across it.
//
//  This is the picture a disc winding is actually designed against. The ranked table says which gap is worst and the radial
//  profiles say what is happening between coils; this says how the axial stress is distributed along one coil - where the impulse
//  piles up, how fast it decays into the winding, and how much room is left under the allowable everywhere else.
//
//  IT IS AN ENVELOPE, exactly as StressProfileWindow's curves are: each point is the worst that gap saw at any instant of the run,
//  not one frame of the transient. The gaps do not peak together (the ones near the line end peak at t = 0+, the ones deep in the
//  winding peak later), so no single instant is the profile.
//
//  THE POINTS ARE PER GAP, AND THE LINE BETWEEN THEM IS INTERPOLATION. There is one value per disc-to-disc gap - that is the
//  resolution the node network has - plotted at the middle of its own gap and joined by straight lines. The line is drawn because
//  a profile reads as a shape and a scatter of dots does not; it is not evidence of anything between two gaps.
//
//  WHY THE ALLOWABLE IS A CURVE AND NOT A CONSTANT. It is drawn as its own series rather than as a single horizontal rule, and in
//  the ordinary case - one duct size and one paper thickness the length of the coil - every point of it is the same and it draws
//  as the horizontal line it is expected to be. But a coil with a widened duct at a tapping gap, or a gap facing a static ring
//  rather than another disc, genuinely has a different allowable there (the allowable falls with the governing layer's own
//  thickness - see docs/dielectric-stress.md), and a single rule drawn at the smallest of them would understate the margin
//  everywhere else. Where it does vary, the annotation says so out loud.
//
//  Both curves come from the SAME findings as the table and the radial graphs - AppController.StressChecks() - so the three can
//  never disagree about a model. Nothing is recomputed here: the allowable at a point is recovered from the check itself as
//  averageField / averageUtilization, and the allowable ΔV as deltaV / averageUtilization. Both are exact rather than a second
//  evaluation of the allowable, because the field is LINEAR in the driving voltage (the property DielectricStress.Scan is built
//  on): scaling ΔV by 1/utilization is precisely the ΔV that would put the governing layer at its allowable.
//
//  The view is private to this window rather than a sibling of CoilResultsDisplayView because it needs three things that view
//  does not have and that its two existing users do not want: a second series, a labelled x axis on a fixed 100 mm grid, and an
//  annotation block inside the plot. It is a plain view-coordinates drawing (bounds == frame, one point = one unit), which is
//  what lets it hand AxisScale a pointSize of 1.
//

import Cocoa
import PchBasePackage

@MainActor
class AxialStressProfileWindow:NSWindowController {

    /// One coil's profile.
    struct Profile {

        let name:String
        /// Sorted by height. Heights in metres, stresses in V/m, voltages in volts.
        let points:[Point]

        /// The worst gap in this coil - the point the annotation is about. Chosen by UTILIZATION, not by raw stress: a gap whose
        /// allowable is lower (a wider duct, or one facing a static ring) can be the one in trouble at a lower field, which is the
        /// same argument the table's ranking rests on.
        var worst:Point? {

            return points.max { $0.utilization < $1.utilization }
        }

        /// True where every gap in the coil has the same allowable, which is the ordinary case and the one in which the allowable
        /// really is a horizontal line.
        var allowableIsConstant:Bool {

            guard let first = points.first else { return true }

            return points.allSatisfy { abs($0.allowableStress - first.allowableStress) <= 1.0E-9 * max(1.0, first.allowableStress) }
        }
    }

    /// One gap.
    struct Point {

        /// The middle of the gap, in metres from the bottom yoke.
        let z:Double
        /// The average field in the governing layer, V/m.
        let stress:Double
        /// What that layer is allowed, V/m, with the design margin applied.
        let allowableStress:Double
        /// The driving voltage across the gap at its worst instant, in volts.
        let deltaV:Double
        /// The driving voltage that would put the governing layer exactly at its allowable, in volts.
        let allowableDeltaV:Double
        /// stress / allowableStress. 1.0 means the design margin is exactly used up.
        let utilization:Double
    }

    private let profiles:[Profile]

    private let graphView = ProfileView()
    private let profilePicker = NSPopUpButton()
    private let noteLabel = NSTextField(labelWithString: "")

    /// - Returns: nil if the findings hold no disc-to-disc gaps at all, which is what a model with no disc windings looks like.
    init?(checks:[DielectricStress.StressCheck], title:String) {

        var grouped:[String:[DielectricStress.StressCheck]] = [:]

        for check in checks {

            // The axial half of the profile metadata. Turn-to-turn checks are not gaps between discs and carry no height, and the
            // radial checks belong to the other graph - see StressCheckKind.isRadial.
            guard check.kind == .discToDisc, let name = check.profileName, check.profileHeight != nil else {

                continue
            }

            grouped[name, default: []].append(check)
        }

        guard !grouped.isEmpty else {

            return nil
        }

        var built:[Profile] = []

        for (name, group) in grouped {

            let points:[Point] = group.sorted { ($0.profileHeight ?? 0.0) < ($1.profileHeight ?? 0.0) }.compactMap { check in

                // A utilization of zero would mean a field of zero, which Evaluate cannot produce (it refuses a site with no
                // volts across it), but the division below is not worth risking on that.
                guard let z = check.profileHeight, check.averageUtilization > 0.0 else {

                    return nil
                }

                return Point(z: z,
                             stress: check.averageField,
                             allowableStress: check.averageField / check.averageUtilization,
                             deltaV: abs(check.deltaV),
                             allowableDeltaV: abs(check.deltaV) / check.averageUtilization,
                             utilization: check.averageUtilization)
            }

            guard !points.isEmpty else {

                continue
            }

            built.append(Profile(name: name, points: points))
        }

        guard !built.isEmpty else {

            return nil
        }

        built.sort { $0.name < $1.name }

        self.profiles = built

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = title
        window.contentMinSize = NSSize(width: 520.0, height: 360.0)

        super.init(window: window)

        BuildContent()

        // Open on the coil with the worst gap in it, not on the first one alphabetically. The picker stays in name order, which is
        // predictable to scroll through, but the first thing shown should be the coil the designer has to do something about -
        // the same worst-first discipline the report table is ranked on.
        let worstCoil = built.indices.max { (built[$0].worst?.utilization ?? 0.0) < (built[$1].worst?.utilization ?? 0.0) } ?? 0

        profilePicker.selectItem(at: worstCoil)
        ShowProfile(at: worstCoil)

        window.center()
    }

    required init?(coder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }

    private func BuildContent() {

        guard let window = self.window else {

            return
        }

        let contentView = NSView()

        profilePicker.translatesAutoresizingMaskIntoConstraints = false
        profilePicker.addItems(withTitles: profiles.map { $0.name })
        profilePicker.target = self
        profilePicker.action = #selector(profileChanged(_:))

        noteLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        noteLabel.textColor = NSColor.secondaryLabelColor
        noteLabel.lineBreakMode = .byWordWrapping
        noteLabel.maximumNumberOfLines = 0
        noteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        noteLabel.translatesAutoresizingMaskIntoConstraints = false

        graphView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(profilePicker)
        contentView.addSubview(noteLabel)
        contentView.addSubview(graphView)

        NSLayoutConstraint.activate([

            profilePicker.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            profilePicker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            profilePicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),

            noteLabel.topAnchor.constraint(equalTo: profilePicker.bottomAnchor, constant: 8),
            noteLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            noteLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            graphView.topAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 8),
            graphView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            graphView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            graphView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])

        window.contentView = contentView
    }

    @objc private func profileChanged(_ sender:Any) {

        ShowProfile(at: profilePicker.indexOfSelectedItem)
    }

    private func ShowProfile(at index:Int) {

        guard index >= 0, index < profiles.count else {

            return
        }

        let profile = profiles[index]

        graphView.profile = profile

        var note = "Envelope: the worst disc-to-disc stress each gap saw at any instant of the run, one point per gap, joined by straight lines. Allowables are DelVecchio ch. 13 impulse breakdown levels at the governing layer's own thickness, times the design margin set in Preferences."

        if !profile.allowableIsConstant {

            note += " The allowable is not the same the length of this coil — where the gap or its insulation changes, so does what that gap is allowed — so it is drawn as a curve rather than as one rule."
        }

        noteLabel.stringValue = note
    }
}

// MARK: - The plot

/// The drawing. See the file header for why this is not CoilResultsDisplayView.
private class ProfileView:NSView {

    var profile:AxialStressProfileWindow.Profile? = nil {

        didSet {

            self.needsDisplay = true
        }
    }

    /// The x axis is a coil height in millimetres and the grid the user asked for is 100 mm. It is not derived from the span: a
    /// round grid is the point, so a 900 mm coil and a 2400 mm one are read against the same ruler.
    private static let xTickInterval = 100.0

    private let axisColor = NSColor.darkGray
    private let stressColor = NSColor.systemRed
    private let allowableColor = NSColor.systemOrange
    private let extremumColor = NSColor.systemYellow

    private let marginRight = 16.0
    private let marginTop = 14.0

    /// Room for the x-axis ticks, their labels, and the axis title under them.
    private var marginBottom:CGFloat { return AxisScale.XEndLabelHeight + AxisScale.labelLineHeight + 4.0 }

    override func draw(_ dirtyRect: NSRect) {

        super.draw(dirtyRect)

        // No background fill, so this graph sits on the window's own colour the way the other two do.
        guard let profile = profile, let first = profile.points.first, let last = profile.points.last else {

            return
        }

        // ---- the ranges ----
        //
        // The x range is the coil's own extent. The y range starts at zero - a stress profile read against an allowable is a
        // picture of how much room is left, and a y axis that did not start at zero would make a comfortable coil look alarming -
        // and reaches past whichever is higher, the worst stress or the allowable, so the allowable line is always on the plot.

        let xMinimum = first.z * 1000.0
        let xMaximum = max(last.z * 1000.0, xMinimum + 1.0)

        let peakStress = profile.points.map { $0.stress }.max() ?? 1.0
        let peakAllowable = profile.points.map { $0.allowableStress }.max() ?? 1.0
        let yMaximum = max(peakStress, peakAllowable) * 1.08

        // ---- the plot rectangle ----
        //
        // CoilResultsDisplayView needs two passes here because its y scale depends on its left margin. This one does not: the
        // vertical scale is set by the plot HEIGHT, which the y tick labels cannot affect, so the ticks are worked out first and
        // the left margin is then whatever they need.

        let yTicks = YTicks(profile: profile, peakStress: peakStress, peakAllowable: peakAllowable, yMaximum: yMaximum)

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

        func ViewY(_ stress:Double) -> CGFloat {

            return plotBottom + stress / yMaximum * (plotTop - plotBottom)
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

        AxisScale.DrawXAxis(values: AxisScale.TickValues(minimum: xMinimum, maximum: xMaximum, interval: ProfileView.xTickInterval),
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

        // ---- the two series ----

        let curve = profile.points.map { NSPoint(x: ViewX($0.z * 1000.0), y: ViewY($0.stress)) }

        Stroke(points: curve, color: stressColor, width: 1.5)

        // The allowable. Drawn dashed so that it reads as a limit rather than as a second measurement, and so that a coil whose
        // allowable happens to sit on top of a y tick's guide line can still be told apart from it.
        let allowablePath = NSBezierPath()
        allowablePath.lineWidth = 1.5
        allowablePath.setLineDash([6.0, 4.0], count: 2, phase: 0.0)

        for (index, point) in profile.points.enumerated() {

            let at = NSPoint(x: ViewX(point.z * 1000.0), y: ViewY(point.allowableStress))
            index == 0 ? allowablePath.move(to: at) : allowablePath.line(to: at)
        }

        allowableColor.setStroke()
        allowablePath.stroke()

        // ---- the worst gap, and what it is ----

        guard let worst = profile.worst else {

            return
        }

        let worstAt = NSPoint(x: ViewX(worst.z * 1000.0), y: ViewY(worst.stress))
        let dot = NSBezierPath(ovalIn: NSRect(x: worstAt.x - 3.5, y: worstAt.y - 3.5, width: 7.0, height: 7.0))
        stressColor.setFill()
        dot.fill()

        DrawAnnotation(for: worst,
                       profile: profile,
                       curve: curve,
                       plotLeft: plotLeft,
                       plotRight: plotRight,
                       plotBottom: plotBottom,
                       plotTop: plotTop,
                       allowableY: ViewY(min(peakAllowable, yMaximum)))
    }

    /// The y ticks: a round grid over the whole axis, plus the two values the graph is actually read for - the worst stress in
    /// the coil and the allowable it is judged against. Both are marked as extremes, so `AxisScale` runs its dashed guide line
    /// across the plot at each; a round tick that would collide with either is dropped, those two being the informative ones.
    ///
    /// The majors come from `AxisScale.Ticks` but its own extreme ticks are thrown away (except zero). It marks the ends of the
    /// range it is handed, and the top of this range is headroom above the allowable rather than a value anything reached - a
    /// tick there labels the padding.
    private func YTicks(profile:AxialStressProfileWindow.Profile, peakStress:Double, peakAllowable:Double, yMaximum:Double) -> [AxisTick] {

        // A label's height, in data units: the same spacing rule AxisScale uses to decide two ticks are too close.
        let plotHeight = max(1.0, bounds.height - marginBottom - marginTop)
        let separation = AxisScale.labelLineHeight * yMaximum / plotHeight

        let majors = AxisScale.Ticks(minimum: 0.0,
                                     maximum: yMaximum,
                                     quantity: .stress,
                                     peakTestVoltage: 0.0,
                                     minimumSeparation: separation).filter { !$0.isExtremum || $0.value == 0.0 }

        func Label(_ stress:Double) -> String {

            return String(format: "%.2f kV/mm", stress / 1.0E6)
        }

        var marks = [AxisTick(value: peakStress, label: Label(peakStress), isExtremum: true)]

        if peakAllowable > 0.0, peakAllowable <= yMaximum, abs(peakAllowable - peakStress) >= separation {

            marks.append(AxisTick(value: peakAllowable, label: Label(peakAllowable) + (profile.allowableIsConstant ? "" : " max"), isExtremum: true))
        }

        var result = majors.filter { major in !marks.contains { abs($0.value - major.value) < separation } }
        result += marks
        result.sort { $0.value < $1.value }

        return result
    }

    private func Stroke(points:[NSPoint], color:NSColor, width:CGFloat) {

        guard points.count > 1 else {

            // A single-gap coil would otherwise draw nothing at all.
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

    /// The numbers, in the body of the plot: what the worst gap is, where it is, and how much voltage it would take to reach the
    /// allowable there. The ΔV pair is the useful one - a designer compares a withstand in kV, not a field in kV/mm.
    private func DrawAnnotation(for worst:AxialStressProfileWindow.Point, profile:AxialStressProfileWindow.Profile, curve:[NSPoint], plotLeft:CGFloat, plotRight:CGFloat, plotBottom:CGFloat, plotTop:CGFloat, allowableY:CGFloat) {

        // kV/mm throughout, matching the y axis and every allowable in DielectricStress. Two units in one window is how a stress
        // gets misread by a factor of a thousand - see the unit note in AxisScale.UnitScale.
        let lines = [("Maximum stress:", String(format: "%.2f kV/mm", worst.stress / 1.0E6)),
                     ("At height:", String(format: "%.0f mm", worst.z * 1000.0)),
                     ("ΔV there:", String(format: "%.2f kV", worst.deltaV / 1000.0)),
                     ("Allowable ΔV there:", String(format: "%.2f kV  (at %.2f kV/mm)", worst.allowableDeltaV / 1000.0, worst.allowableStress / 1.0E6)),
                     ("Utilization:", String(format: "%.0f%% of allowable", worst.utilization * 100.0))]

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .regular)
        let boldFont = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .semibold)

        let labelWidth = lines.map { NSAttributedString(string: $0.0, attributes: [.font:font]).size().width }.max() ?? 0.0
        let valueWidth = lines.map { NSAttributedString(string: $0.1, attributes: [.font:boldFont]).size().width }.max() ?? 0.0

        let lineHeight = NSAttributedString(string: "X", attributes: [.font:font]).size().height + 2.0
        let padding = 8.0

        let boxSize = NSSize(width: labelWidth + 10.0 + valueWidth + padding * 2.0, height: lineHeight * Double(lines.count) + padding * 2.0)

        // WHERE THE BOX GOES is measured, not guessed. Four places are tried - left or right, under the allowable line or up in
        // the top corner - and the one covering the least of the curve wins. Anything that would sit on the allowable line is
        // rejected outright unless every candidate does: the curve is what the reader came for and the allowable is what they are
        // judging it against, so the annotation gets whatever is left over rather than the other way round.
        //
        // "Under the allowable" is offered first because the band between the curve and its limit is usually the emptiest part of
        // the plot, and it is exactly where a top-corner box would hide the limit.
        let underAllowable = allowableY - 8.0
        let topCorner = plotTop - 6.0

        var candidates:[NSRect] = []

        for top in [underAllowable, topCorner] where top - boxSize.height > plotBottom && top <= plotTop {

            for x in [plotLeft + 12.0, plotRight - boxSize.width - 12.0] {

                candidates.append(NSRect(x: x, y: top - boxSize.height, width: boxSize.width, height: boxSize.height))
            }
        }

        func Cost(_ rect:NSRect) -> Int {

            // One per plotted gap the box would cover, and a flat penalty - larger than any coil's gap count - for hiding the
            // allowable line.
            let covered = curve.filter { rect.contains($0) }.count
            let hidesAllowable = allowableY >= rect.minY && allowableY <= rect.maxY

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

        for (label, value) in lines {

            NSAttributedString(string: label, attributes: [.font:font, .foregroundColor:NSColor.secondaryLabelColor]).draw(at: NSPoint(x: box.minX + padding, y: y))
            NSAttributedString(string: value, attributes: [.font:boldFont, .foregroundColor:NSColor.labelColor]).draw(at: NSPoint(x: box.minX + padding + labelWidth + 10.0, y: y))

            y -= lineHeight
        }
    }
}

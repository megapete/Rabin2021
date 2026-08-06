//
//  InitialDistributionWindow.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2026-08-06.
//
//  The capacitive initial distribution - the voltage the impulsed coil takes on at t = 0+, before any current has
//  flowed - plotted against axial position.
//
//  This is the classical alpha of impulse theory, and it is the first thing a designer looks at: its steepness at
//  the line end is what decides whether a winding needs interleaving, static rings or wound-in shields, long before
//  anything is known about the tail. It is also exactly the "t = 0+" instant that the dielectric stress report
//  singles out, which is why the two agree by construction - both read FrequencyDomainSolver.CapacitiveDistribution
//  rather than computing an initial distribution of their own.
//
//  IT NEEDS NO SIMULATION RUN. alpha is a purely electrostatic quantity: the s -> infinity limit of the same
//  assembly the frequency sweep uses, so all it wants is a simulation MODEL (which carries the capacitance matrix
//  and the boundary-condition row surgery). That is deliberate - the whole value of the initial distribution is that
//  it answers "is this winding going to need help?" before the expensive part. A simulation result is used only if
//  one happens to be to hand, and only to put the y axis into volts instead of per-unit.
//
//  Why only the impulsed coil. alpha is defined over every node in the model, but on a coil that is not driven it is
//  a small residual set by the shunt capacitances, and plotting it beside the driven coil's full-crest curve
//  compresses the one that matters into the bottom of the plot. A coil qualifies here if one of its nodes carries an
//  impulse connector; if more than one does, all of them are offered in the picker.
//

import Cocoa
import PchBasePackage

@MainActor
class InitialDistributionWindow:NSWindowController {

    /// One coil's initial distribution.
    struct Distribution {

        let name:String
        /// Distance DOWN FROM THE TOP of the coil, in metres, paired with the potential at that height. Sorted by that distance, so
        /// the first entry is the top of the coil. See the x-axis note in ShowDistribution().
        let points:[(depth:Double, volts:Double)]
        /// Which end of the coil the impulse is applied to, for the note under the graph.
        let impulseAtTop:Bool
        /// True if the y values are volts; false if they are per-unit (no simulation result was available to scale them).
        let isInVolts:Bool
    }

    private let distributions:[Distribution]
    private let peakTestVoltage:Double

    private let graphView = CoilResultsDisplayView()
    private let coilPicker = NSPopUpButton()
    private let noteLabel = NSTextField(labelWithString: "")

    /// - parameter distributions: one entry per impulsed coil, already in the units the graph will show.
    /// - parameter peakTestVoltage: the impulse crest in volts, or 0 if the values are per-unit. This only sets the major-tick
    /// interval - see AxisScale.MajorVoltageInterval.
    init?(distributions:[Distribution], peakTestVoltage:Double, title:String) {

        guard !distributions.isEmpty, distributions.contains(where: { $0.points.count > 1 }) else {

            return nil
        }

        self.distributions = distributions
        self.peakTestVoltage = peakTestVoltage

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 520),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = title
        window.setFrameAutosaveName("InitialDistributionWindow")

        super.init(window: window)

        BuildContent()
        ShowDistribution(at: 0)
    }

    required init?(coder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }

    private func BuildContent() {

        guard let window = self.window else {

            return
        }

        let contentView = NSView()

        coilPicker.translatesAutoresizingMaskIntoConstraints = false
        coilPicker.addItems(withTitles: distributions.map { $0.name })
        coilPicker.target = self
        coilPicker.action = #selector(coilChanged(_:))
        // With one impulsed coil - the usual case - the picker has a single entry. It is left in place rather than hidden because it
        // names the coil being plotted, which is worth saying whether or not there is a choice to make.
        coilPicker.isEnabled = distributions.count > 1

        noteLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        noteLabel.textColor = NSColor.secondaryLabelColor
        noteLabel.lineBreakMode = .byWordWrapping
        noteLabel.maximumNumberOfLines = 2
        noteLabel.translatesAutoresizingMaskIntoConstraints = false

        graphView.translatesAutoresizingMaskIntoConstraints = false
        graphView.peakTestVoltage = peakTestVoltage

        contentView.addSubview(coilPicker)
        contentView.addSubview(noteLabel)
        contentView.addSubview(graphView)

        NSLayoutConstraint.activate([

            coilPicker.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            coilPicker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            coilPicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),

            noteLabel.topAnchor.constraint(equalTo: coilPicker.bottomAnchor, constant: 8),
            noteLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            noteLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            graphView.topAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 8),
            graphView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            graphView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            graphView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])

        window.contentView = contentView
    }

    @objc private func coilChanged(_ sender:Any) {

        ShowDistribution(at: coilPicker.indexOfSelectedItem)
    }

    private func ShowDistribution(at index:Int) {

        guard index >= 0, index < distributions.count else {

            return
        }

        let distribution = distributions[index]

        guard distribution.points.count > 1 else {

            return
        }

        // THE X AXIS RUNS TOP TO BOTTOM, LEFT TO RIGHT, which is why the points carry a depth below the top of the coil rather than a
        // height above the bottom yoke. That is the orientation every textbook draws an initial distribution in, and it puts the line
        // end on the left in the usual case of a coil impulsed at the top. It is the opposite of the animated coil-results display,
        // whose x axis is a height - hence the two end labels, which is the whole reason this graph has any x-axis marking at all.
        graphView.yQuantity = distribution.isInVolts ? .voltage : .unitless
        graphView.peakTestVoltage = distribution.isInVolts ? peakTestVoltage : 0.0
        graphView.xEndLabels = (left: "Top", right: "Bottom")

        // Millimetres on the x axis, the data's own units on the y: the same convention as the other two graphs.
        let points = distribution.points.map { NSPoint(x: $0.depth * 1000.0, y: $0.volts) }

        let minX = points.map { $0.x }.min() ?? 0.0
        let maxX = points.map { $0.x }.max() ?? 1.0
        let minY = min(0.0, points.map { $0.y }.min() ?? 0.0)
        let maxY = max(points.map { $0.y }.max() ?? 1.0, 0.0)

        // Zero is forced into the range so that the x axis - which is the zero line, and which the end labels hang from - is always
        // on the plot. A distribution that never reaches zero (a coil impulsed at one end and floating at the other) would otherwise
        // have its axis drawn off the bottom of the view.
        graphView.UpdateScaleAndZoomWindow(extremaRect: NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
        graphView.currentData = points

        let units = distribution.isInVolts ? "" : " Per unit of the applied crest — no simulation has been run, so there is no crest voltage to scale by."
        let end = distribution.impulseAtTop ? "top" : "bottom"

        noteLabel.stringValue = "Capacitive (initial) distribution at t = 0+, before any current has flowed in the inductances. The impulse is applied at the \(end) of this coil.\(units)"
    }
}

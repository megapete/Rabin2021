//
//  RadialProfileWindow.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2026-08-13.
//
//  The conductor-to-conductor voltage across the radial build of a sheet or layer winding: one value per gap, innermost gap first,
//  with the paper-impulse allowable drawn across it.
//
//  WHY THIS EXISTS. The two stress-profile windows plot against HEIGHT, because a disc winding's problem is distributed along the
//  coil. A sheet or layer winding's is distributed across it - the turns run out along a radius, not around a disc - so the picture
//  that answers it has a different x axis and a different unit of resolution. Nothing else in the program looks at either winding
//  type this way: DielectricStress.AppendTurnToTurnSites takes `.disc` and skips everything else, so until this window there was no
//  turn-to-turn or layer-to-layer number for a sheet or layer coil anywhere in the report.
//
//  IT IS ONE INSTANT, NOT AN ENVELOPE, and that is the difference from the other two profile windows. The gaps of a sheet winding
//  are a series chain and the layers of a layer winding are one network, so every gap here is driven by the SAME coil voltage - they
//  all peak together, at the instant that coil's terminals are furthest apart. There is no envelope to take. Which instant that is
//  appears in the annotation, and it is the coil's own worst instant rather than the model's: see AppController.WorstInstant for why
//  the difference matters, and for why t = 0+ is one of the candidates.
//
//  WHAT THE SHAPE MEANS is not the same for the two winding types, and the note under the picker says which is on screen:
//
//   - A SHEET winding is a pure series chain, because every turn is a full-height cylinder that completely screens the next from
//     everything outside the coil. What the chain does depends entirely on whether the coil has COOLING DUCTS in it. With none, the
//     only thing that varies is the gap capacitance's growth with radius - C ∝ r makes ΔV ∝ 1/r, so the innermost gap is worst by
//     exactly the ratio of the radii, a gentle and entirely predictable slope of a few per cent. Put an oil duct in a gap and that
//     is swamped: a 6 mm duct beside 0.2 mm of paper has some fifty times the reduced thickness, so it takes some fifty times the
//     volts, and the profile becomes a flat floor with a spike standing on every ducted gap. Both shapes are real and the picture
//     says which one this coil has.
//
//   - A LAYER winding is a solved network and its profile carries real information: how much more than its share the layer at the
//     line end takes at the wavefront. The reference line in the annotation is the textbook figure, twice the volts per layer, which
//     is what a designer reaches for; the whole point of the solve is to say where the coil departs from it.
//
//  The drawing is StressProfileView, shared with the two stress-profile windows so that a reader moving between them is not misled
//  by a change in the furniture. What this window adds to it is the ordinal x axis - see StressProfileView.XAxis.
//

import Cocoa
import PchBasePackage

@MainActor
class RadialProfileWindow:NSWindowController {

    /// One radial gap: between two turns of a sheet winding, or between two layers of a layer winding.
    struct GapPoint {

        /// 0 is the innermost gap. Plotted 1-based, because a designer counts gaps from one.
        let index:Int
        /// The radius at which the gap sits, in metres.
        let radius:Double
        /// The voltage across the gap, in volts.
        let deltaV:Double
        /// The voltage that would put the governing layer exactly at its allowable, in volts, or nil where the gap could not be
        /// evaluated - no insulation in it, or no volts across it.
        let allowableDeltaV:Double?
        /// deltaV / allowableDeltaV. 1.0 means the design margin is exactly used up.
        let utilization:Double
        /// The height at which the worst voltage occurs, in metres. Nil for a sheet winding, where a gap carries the same voltage
        /// over its whole height.
        let worstHeight:Double?
        /// The material carrying the governing field, for the annotation.
        let material:String
    }

    /// Everything one of these windows draws. Built by AppController.BuildRadialProfile, so that the menu command and the scripted
    /// self-test produce the same window from the same numbers.
    struct Contents {

        let coil:Int
        let isSheet:Bool
        /// Innermost gap first.
        let points:[GapPoint]
        /// The worst gap over the reference below, or nil where there is no reference to be over - a coil grounded at both ends
        /// has none, and still has voltage across its gaps.
        let enhancement:Double?
        /// What a simple assumption gives for every gap, in volts - an even division for a sheet winding, twice the volts per layer
        /// for a layer one.
        let reference:Double
        /// How many of the gaps hold a cooling duct. Nothing else about the picture changes as much: a ducted gap carries some
        /// fifty times the volts of a gap holding only turn insulation, so the note under the graph says which shape is on screen.
        let ductedGapCount:Int
        /// The classical alpha/tanh(alpha) line-end gradient from the coil's lumped Cs and Cg, for a layer winding. Nil for a
        /// sheet winding, whose model is a closed-form series chain with no alpha in it at all.
        ///
        /// NOTE THAT ITS BASIS IS NOT THIS MODEL'S. Cs comes through CoilSeriesCapacitance and so through LayerToLayerCapacitance,
        /// which still SPREADS the ducts evenly over the gaps rather than placing them. The two therefore describe slightly
        /// different windings, and on a ducted coil they no longer have to agree closely - see TODO.md.
        let screenEstimate:Double?
        /// Rows for the annotation block, as (label, value) pairs.
        let notes:[(label:String, value:String)]
    }

    private let points:[GapPoint]
    private let isSheet:Bool
    private let enhancement:Double?
    private let reference:Double
    private let screenEstimate:Double?
    private let ductedGapCount:Int
    private let notes:[(label:String, value:String)]
    private let peakTestVoltage:Double

    private let graphView = StressProfileView()
    private let noteLabel = NSTextField(labelWithString: "")

    init(contents:Contents, peakTestVoltage:Double) {

        self.points = contents.points.sorted { $0.index < $1.index }
        self.isSheet = contents.isSheet
        self.enhancement = contents.enhancement
        self.reference = contents.reference
        self.screenEstimate = contents.screenEstimate
        self.ductedGapCount = contents.ductedGapCount
        self.notes = contents.notes
        self.peakTestVoltage = peakTestVoltage

        let coil = contents.coil
        let isSheet = contents.isSheet

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "Radial Voltage Profile — coil \(coil), \(isSheet ? "sheet" : "layer") winding"
        window.contentMinSize = NSSize(width: 520.0, height: 360.0)

        super.init(window: window)

        BuildContent()
        ShowProfile()

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

        noteLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        noteLabel.textColor = NSColor.secondaryLabelColor
        noteLabel.lineBreakMode = .byWordWrapping
        noteLabel.maximumNumberOfLines = 0
        noteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        noteLabel.translatesAutoresizingMaskIntoConstraints = false

        graphView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(noteLabel)
        contentView.addSubview(graphView)

        NSLayoutConstraint.activate([

            noteLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            noteLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            noteLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            graphView.topAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 8),
            graphView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            graphView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            graphView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])

        window.contentView = contentView
    }

    /// A voltage for the annotation block.
    ///
    /// %.1f everywhere would be tidier, but a coil grounded at both ends has a few NANOVOLTS across it rather than exactly zero,
    /// and its gaps still carry a real distribution driven by the coil beside it. Printing those as "0.0 V" next to a perfectly
    /// good enhancement ratio reads as a broken number. Anything below a volt therefore goes to scientific notation, where it is
    /// obviously negligible rather than obviously wrong.
    static func Volts(_ value:Double) -> String {

        return abs(value) >= 1.0 ? String(format: "%.1f V", value) : String(format: "%.3g V", value)
    }

    private func ShowProfile() {

        // The worst gap is chosen by UTILIZATION rather than by raw volts, for the same reason the report table is ranked that way:
        // a gap with a duct in it is allowed a great deal more than one with only paper, so the largest ΔV is not reliably the gap
        // in trouble. On a sheet winding the two agree - every gap has the same insulation - but on a layer winding with ducts at
        // some gaps and not others they do not.
        let worst = points.max { $0.utilization < $1.utilization } ?? points.max { $0.deltaV < $1.deltaV }

        var annotation = notes

        if let worst {

            annotation.append((label: "Worst gap:", value: "\(worst.index + 1) of \(points.count), at r = \(String(format: "%.1f mm", worst.radius * 1000.0))"))
            annotation.append((label: "ΔV there:", value: RadialProfileWindow.Volts(worst.deltaV)))

            if let allowable = worst.allowableDeltaV {

                // Turn-to-turn in a sheet or layer winding is normally a small fraction of what the paper withstands, which puts
                // the allowable far off the top of a y axis scaled to the data - see StressProfileView's note on
                // allowableScaleLimit. Say so, so that a reader does not go looking for a dashed line that is not there.
                let offScale = allowable > StressProfileView.allowableScaleLimit * worst.deltaV

                annotation.append((label: "Allowable ΔV:", value: "\(RadialProfileWindow.Volts(allowable)) (\(worst.material))\(offScale ? " — off scale" : "")"))
                annotation.append((label: "Utilization:", value: String(format: "%.1f%% of allowable", worst.utilization * 100.0)))
            }

            if let height = worst.worstHeight {

                annotation.append((label: "At height:", value: String(format: "%.0f mm", height * 1000.0)))
            }

            if let enhancement {

                annotation.append((label: "Over reference:", value: String(format: "%.2fx", enhancement)))
            }
            else {

                // A coil grounded at both ends. Its gaps still carry voltage - the winding beside it drives them capacitively -
                // but there is no terminal voltage to measure them against, and saying so beats printing 1.00x.
                annotation.append((label: "Over reference:", value: "n/a — the coil has no voltage across its terminals"))
            }

            if let screenEstimate {

                annotation.append((label: "alpha screen:", value: String(format: "%.2fx (alpha/tanh alpha, from lumped Cs and Cg)", screenEstimate)))
            }
        }

        graphView.plot = StressProfileView.Plot(points: points.map { StressProfileView.Point(z: Double($0.index + 1),
                                                                                            value: $0.deltaV,
                                                                                            allowable: $0.allowableDeltaV,
                                                                                            utilization: $0.utilization) },
                                                quantity: .voltage,
                                                peakTestVoltage: peakTestVoltage,
                                                annotation: annotation,
                                                markers: [],
                                                markerName: "",
                                                xAxis: .ordinal(title: isSheet ? "Gap between turns, counted outwards from the inside" : "Gap between layers, counted outwards from the inside"),
                                                allowableMayGoOffScale: true)

        if isSheet {

            var note = "Sheet winding: a series chain. Every turn is a full-height cylinder and screens the next completely, so no interior turn has a capacitance to anything outside the coil and the neighbouring coil cannot perturb the distribution — it attaches only to the two driven end turns. One instant: every gap is driven by the same coil voltage, so they all peak together."

            if ductedGapCount > 0 {

                note += " The spikes are the COOLING DUCTS. An oil duct is some fifty times the reduced thickness of the turn insulation beside it, so it takes some fifty times the volts, and it swamps the gentle 1/r slope that the radius alone would produce. Duct positions are a spacing rule, not a reading — the design file gives a count and a size only."
            }
            else {

                note += " With no duct in the winding the only thing that varies is the gap capacitance's growth with radius (C ∝ r, so ΔV ∝ 1/r), which makes the innermost gap the worst by exactly the ratio of the radii."
            }

            noteLabel.stringValue = note
        }
        else {

            noteLabel.stringValue = "Layer winding: solved as a turn-level capacitive network at the stated instant — turn-to-turn along each layer, layer-to-layer between them, and out of the innermost and outermost layers to the neighbouring coils at their own potentials. Layer turn counts are assumed equal with a short last layer, and the cooling ducts are placed at evenly spaced gaps; the design file gives counts and sizes but neither per-layer turns nor duct positions, so both are rules rather than readings. A ducted gap has a much lower layer-to-layer capacitance and so carries much more voltage. The reference is the textbook figure, twice the volts per layer."
        }
    }
}

//
//  StressProfileWindow.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2026-08-05.
//
//  Voltage-difference-versus-height profiles for the radial checks of the dielectric stress screen.
//
//  This is the picture that answers the unequal-height coil problem: when a tapping winding sits outside a main winding and is not
//  the same height, the radial voltage difference between them is not remotely uniform, and the worst of it is at the short coil's
//  end. A ranked table says which height is worst; this says why, by showing the whole profile with the coil ends marked.
//
//  It plots an ENVELOPE, not an instant. Each point is the largest radial difference that height saw at any time in the run, so one
//  curve covers the whole transient. An animation over time was considered and rejected: the radial peak at one height and the peak
//  at another happen at different instants, so no single frame of an animation shows the thing being looked for.
//
//  The plotting itself reuses CoilResultsDisplayView, which already draws a series against axial position and already carries the
//  AxisScale tick machinery. Only the enclosing window is new - CoilResultsDisplayWindow is tied to SimulationResults and node index
//  ranges, which is the wrong shape for this data.
//

import Cocoa
import PchBasePackage

@MainActor
class StressProfileWindow:NSWindowController {

    /// One profile: a named series of points against height.
    struct Profile {

        let name:String
        /// Height in metres, voltage difference in volts, average field in V/m. Sorted by height.
        let points:[(z:Double, deltaV:Double, averageField:Double)]
        /// The heights at which the screen flagged that a coil ends, where the field stops being one-dimensional.
        let endMarkers:[Double]
    }

    /// What the y axis shows. Both are worth having: the voltage difference is what a designer reads directly and compares against
    /// a withstand level, while the stress is what the insulation actually cares about and is not proportional to it - the hilo
    /// stack varies from coil pair to coil pair, so the largest voltage difference is not always the worst stress.
    private enum Quantity:Int {

        case voltageDifference
        case averageStress
    }

    private let profiles:[Profile]
    private let peakTestVoltage:Double

    private let graphView = CoilResultsDisplayView()
    private let profilePicker = NSPopUpButton()
    private let quantityPicker = NSPopUpButton()
    private let noteLabel = NSTextField(labelWithString: "")

    init?(checks:[DielectricStress.StressCheck], peakTestVoltage:Double, title:String) {

        // Assemble the profiles from the SAME findings the table shows, so the two can never disagree.
        var grouped:[String:[DielectricStress.StressCheck]] = [:]

        for check in checks {

            // RADIAL checks only. The disc-to-disc sites carry a profile name and a height as well, for the axial graph
            // (AxialStressProfileWindow); without this filter they would appear in this window's picker, under a y axis whose
            // note calls them radial.
            guard check.kind.isRadial, let name = check.profileName, check.profileHeight != nil else {

                continue
            }

            grouped[name, default: []].append(check)
        }

        guard !grouped.isEmpty else {

            return nil
        }

        var built:[Profile] = []

        for (name, group) in grouped {

            let sorted = group.sorted { ($0.profileHeight ?? 0.0) < ($1.profileHeight ?? 0.0) }

            let points = sorted.map { (z: $0.profileHeight ?? 0.0, deltaV: abs($0.deltaV), averageField: $0.averageField) }

            // A location string carrying the beyond-the-end note is where the inner coil stops.
            let markers = sorted.filter { $0.location.contains("beyond end of") }.compactMap { $0.profileHeight }

            built.append(Profile(name: name, points: points, endMarkers: markers))
        }

        built.sort { $0.name < $1.name }

        self.profiles = built
        self.peakTestVoltage = peakTestVoltage

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 520),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = title
        window.setFrameAutosaveName("StressProfileWindow")

        super.init(window: window)

        BuildContent()
        ShowProfile(at: 0)
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

        quantityPicker.translatesAutoresizingMaskIntoConstraints = false
        quantityPicker.addItems(withTitles: ["Voltage difference", "Average stress"])
        quantityPicker.target = self
        quantityPicker.action = #selector(profileChanged(_:))

        noteLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        noteLabel.textColor = NSColor.secondaryLabelColor
        noteLabel.lineBreakMode = .byWordWrapping
        noteLabel.maximumNumberOfLines = 2
        noteLabel.translatesAutoresizingMaskIntoConstraints = false

        graphView.translatesAutoresizingMaskIntoConstraints = false
        graphView.yQuantity = .voltage
        graphView.peakTestVoltage = peakTestVoltage

        contentView.addSubview(profilePicker)
        contentView.addSubview(quantityPicker)
        contentView.addSubview(noteLabel)
        contentView.addSubview(graphView)

        NSLayoutConstraint.activate([

            profilePicker.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            profilePicker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            profilePicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),

            quantityPicker.centerYAnchor.constraint(equalTo: profilePicker.centerYAnchor),
            quantityPicker.leadingAnchor.constraint(equalTo: profilePicker.trailingAnchor, constant: 12),
            quantityPicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 170),

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

        guard !profile.points.isEmpty else {

            return
        }

        let quantity = Quantity(rawValue: quantityPicker.indexOfSelectedItem) ?? .voltageDifference

        // CoilResultsDisplayView works in millimetres on the x axis and the data's own units on the y - the same convention
        // doShowCoilResults uses, so the two graphs read alike. The y axis is told which quantity it is carrying so that AxisScale
        // labels it in kV or in kV/mm as appropriate.
        graphView.yQuantity = quantity == .voltageDifference ? .voltage : .stress
        graphView.peakTestVoltage = quantity == .voltageDifference ? peakTestVoltage : 0.0

        let points = profile.points.map { NSPoint(x: $0.z * 1000.0, y: quantity == .voltageDifference ? $0.deltaV : $0.averageField) }

        let minZ = points.map { $0.x }.min() ?? 0.0
        let maxZ = points.map { $0.x }.max() ?? 1.0
        let maxV = points.map { $0.y }.max() ?? 1.0

        graphView.UpdateScaleAndZoomWindow(extremaRect: NSRect(x: minZ, y: 0.0, width: maxZ - minZ, height: maxV))
        graphView.currentData = points

        let what = quantity == .voltageDifference ? "radial voltage difference" : "average radial stress"

        if profile.endMarkers.isEmpty {

            noteLabel.stringValue = "Envelope: the largest \(what) each height saw at any time during the run."
        }
        else {

            let heights = profile.endMarkers.map { String(format: "%.0f", $0 * 1000.0) }.joined(separator: ", ")
            noteLabel.stringValue = "Envelope of the largest \(what) at each height. The inner coil ends near \(heights) mm — beyond that the field is genuinely two-dimensional and the plotted value is indicative only."
        }
    }
}

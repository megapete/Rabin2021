//
//  SelfTest.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2026-08-06.
//
//  A scripted, non-interactive run of a KNOWN design, so that the program can be exercised end to end without anybody
//  sitting at the keyboard: load a design file, apply a fixed set of terminations, build the simulation model, solve
//  the initial distribution, and write a report.
//
//  WHY THIS EXISTS. There is no test target (see CLAUDE.md), and every route to a model otherwise starts at an
//  NSOpenPanel in AppController.handleOpenFile. That makes every check in this program a hand check, which is fine for
//  a one-off verification - DielectricStress.VerifySelf() and TurnLadderModel.VerifySelf() are exactly that - but no
//  use at all as a regression net, because nobody re-runs a hand check after an unrelated edit. This runs the whole
//  pipeline from a launch argument and leaves a text report behind.
//
//  HOW TO RUN IT. The app is launched with the scenario name as a launch argument. NSUserDefaults parses "-key value"
//  launch arguments into the defaults domain automatically, so there is no argument parsing here and no risk of the
//  test path being reachable from a normal launch:
//
//      /path/to/ImpulseDistribution.app/Contents/MacOS/ImpulseDistribution -PCH_SelfTest STME0999
//
//  Add "-PCH_SelfTestTransient YES" to also run the frequency-domain sweep. That is off by default because the sweep
//  is minutes of work and most edits that could break something break it in the assembly or the capacitance, both of
//  which the initial distribution already sees.
//
//  WHERE THE FIXTURE LIVES. The app is sandboxed with only 'user-selected.read-write', so a design file anywhere else
//  on the disk is unreadable without the open panel that granted access to it. The app's OWN container is always
//  readable, so the fixture is looked for in the container's Documents folder:
//
//      ~/Library/Containers/com.huberistech.Rabin2021/Data/Documents/
//
//  Copy the design file there before running. This is deliberately not solved with a temporary-exception entitlement:
//  that would change what the shipped app is allowed to read in order to run a test.
//
//  WHERE THE RESULTS GO. The full report is written to a text file beside the fixture in that same Documents folder,
//  and a one-line summary plus the last stage reached go into UserDefaults:
//
//      defaults read com.huberistech.Rabin2021 PCH_SelfTestSummary
//      defaults read com.huberistech.Rabin2021 PCH_SelfTestStage
//      cat ~/Library/Containers/com.huberistech.Rabin2021/Data/Documents/SelfTestReport-STME0999.txt
//
//  The stage breadcrumb is written and flushed before each step. If the run hangs - and it can, because the pipeline
//  raises NSAlerts on failure and a modal alert will sit there forever with nobody to dismiss it - that key says which
//  step it hung in.
//
//  WHAT IT CHECKS. Two different things, and it is worth keeping them apart:
//
//  1. A REGRESSION BASELINE. Parsed geometry, per-coil series and ground capacitance, and the computed initial
//     distribution, all printed to enough digits to diff. This does not know what the right answer is; it tells you
//     that today's answer is or is not yesterday's.
//
//  2. A COMPARISON AGAINST DELVECCHIO SECTION 13.5.1, "Uniform Capacitance Model". The continuum model replaces the
//     winding by a uniform ladder of series capacitance and capacitance to ground, and gives the initial distribution
//     in closed form as
//
//         V(x)/V = sinh(alpha*x) / sinh(alpha),     alpha = sqrt(Cg / Cs)
//
//     with x measured from the GROUNDED end (x = 0) to the line end (x = 1), Cg the winding's total capacitance to
//     ground and Cs the winding's total series capacitance (the series combination of the per-disc values, which is
//     what PhaseModel.CoilSeriesCapacitance returns).
//
//     This is an approximation and its disagreements are as informative as its agreements. It assumes Cg and Cs are
//     UNIFORM along the winding, which the real model's are not - the end discs get Stein/end-disc treatment and the
//     ground capacitance is not uniform at the ends either. It has no inductance at all, which is why only the t = 0+
//     distribution is compared and not the transient. And it has no second coil, which is the reason alpha is
//     reported twice, bracketed (see the note on ContinuumComparison).
//

import Cocoa
import PchBasePackage
import PchExcelDesignFilePackage

@MainActor
enum SelfTest {

    // MARK: Keys

    /// The launch argument that names the scenario to run. Absent on a normal launch, which is what keeps this code
    /// unreachable in ordinary use.
    static let scenarioKey = "PCH_SelfTest"
    /// Set this to run the frequency-domain sweep as well as the initial distribution.
    static let transientKey = "PCH_SelfTestTransient"
    /// A one-line summary of the run, in UserDefaults.
    static let summaryKey = "PCH_SelfTestSummary"
    /// The last stage the run reached, flushed before each step so that a hang can be located.
    static let stageKey = "PCH_SelfTestStage"

    // MARK: Scenario description

    /// Which end of a coil a lead comes off.
    enum CoilEnd {

        case bottom
        case top
    }

    /// One terminal of the test connection: a coil end, and what it is tied to.
    struct Termination {

        let coil:Int
        let end:CoilEnd
        /// Either `.ground` or `.impulse`. Nothing else is a termination.
        let type:Connector.Location
    }

    /// A structural change made to the model after it is loaded and before the terminations go on.
    ///
    /// These are the two things a designer does when the initial distribution is too steep, and the whole reason for
    /// wanting more than one scenario: the fixture's line-end gradient can be measured with neither, with interleaving
    /// and with an intershield, on identical geometry.
    ///
    /// Both rebuild the coil into TWO-DISC Segments, which is what makes them comparable to each other and what makes
    /// the per-section numbers in the transient report mean something different from the plain case - see
    /// TransientReport. Terminations are applied afterwards for the same reason `doInterleaveSelection` leaves them to
    /// the user: `UpdateConnectors` rebuilds the connectors when Segments are swapped, and a ground applied first would
    /// not survive it.
    enum Restructure {

        /// Leave the winding as the design file describes it.
        case none
        /// Interleave the whole coil: every two adjacent discs become one interleaved Segment.
        case interleave(coil:Int)
        /// Put a wound-in shield of `turnsPerDisc` turns into every disc pair of the coil (DelVecchio 12.11).
        case woundInShield(coil:Int, turnsPerDisc:Int, connection:Segment.WoundInShieldWire.Connection)
    }

    /// Hold a coil at the radial build a wound-in shield would need, without fitting the shield.
    ///
    /// A shield does two things at once - it adds shield turns AND it widens the disc, which raises C_dd on its own because the
    /// disc has more face area. Measuring a shielded coil against an unshielded one of the original width credits the shield with
    /// both. Setting this on the plain and interleaved scenarios to the same turn count the shielded scenario uses puts all three
    /// at one geometry, so the only difference left is the electrical treatment. See `PhaseModel.radialBuildUpFloor`.
    struct MatchedBuild {

        let coil:Int
        /// The shield turn count whose radial build is to be matched - the same number the shielded scenario fits.
        let turnsPerDisc:Int
        let connection:Segment.WoundInShieldWire.Connection
    }

    /// A complete scripted run.
    struct Scenario {

        let name:String
        /// What to do to the winding before terminating it.
        let restructure:Restructure
        /// Widen a coil to a shield's build without fitting the shield. Nil leaves the geometry as the design file has it.
        let matchedBuild:MatchedBuild?
        /// The design file's name in the container's Documents folder.
        let fixtureName:String
        /// A sentence about the design, echoed into the report so that a stale report identifies itself.
        let notes:String
        let terminations:[Termination]
        let waveFormType:SimulationModel.WaveForm.Types
        /// Impulse crest, in volts.
        let peakVoltage:Double
        /// How much of the transient to record, in seconds.
        let displaySpan:Double
        /// The sweep's upper frequency, in Hz. This is the solver's only accuracy control.
        let bandwidth:Double
        /// The coil whose initial distribution is compared against the continuum model - the impulsed one.
        let continuumCoil:Int
    }

    /// The STME-0999 fixture: a real two-winding core-form design, 4160Y/2400 V LV and 69 kV delta HV, 350 kV BIL on
    /// the HV. Both LV leads and the HV neutral are grounded and the HV line end is impulsed - the standard impulse
    /// test connection, and the reason the LV appears in the model at all (a winding shorted to ground is not a
    /// winding that can be left out of the capacitance picture).
    ///
    /// It was the first fixture because its geometry is uniform: no taps, no axial gaps, a plain 70-disc continuous
    /// HV and a plain 48-turn helical LV. That is precisely the case DelVecchio 13.5.1 is written for, so a
    /// disagreement is much more likely to be this program's than the continuum model's.
    ///
    /// The three variants differ ONLY in `restructure`, which is the point: same core, same conductor, same gaps, same
    /// impulse, so the line-end gradient can be read off three times and compared without anything else having moved.
    private static func STME0999(name:String, notes:String, restructure:Restructure) -> Scenario {

        return Scenario(name: name,
                        restructure: restructure,
                        matchedBuild: nil,
                        fixtureName: "STME-0999_AndIn.txt",
                        notes: "4160Y/2400 V LV (48-turn helical), 69 kV delta HV (70-disc continuous), 350 kV full wave on the HV line end. " + notes,
                        terminations: [Termination(coil: 0, end: .bottom, type: .ground),
                                       Termination(coil: 0, end: .top, type: .ground),
                                       Termination(coil: 1, end: .bottom, type: .ground),
                                       Termination(coil: 1, end: .top, type: .impulse)],
                        waveFormType: .FullWave,
                        peakVoltage: 350.0e3,
                        displaySpan: 100.0e-6,
                        bandwidth: 10.0e6,
                        continuumCoil: 1)
    }

    /// The scenarios this build knows about, keyed by the string passed to -PCH_SelfTest.
    static let scenarios:[String:Scenario] = [

        "STME0999" : STME0999(name: "STME0999",
                              notes: "HV as designed - plain continuous discs, no interleaving and no shields.",
                              restructure: .none),

        // Interleaving is the big hammer: it raises the series capacitance of a disc pair by an order of magnitude, so
        // alpha falls and the initial distribution flattens. The 70 discs become 35 interleaved Segments.
        "STME0999-interleaved" : STME0999(name: "STME0999-interleaved",
                                          notes: "The whole HV winding interleaved.",
                                          restructure: .interleave(coil: 1)),

        // A wound-in shield is the adjustable version of the same idea (DelVecchio 12.11): it raises the pair's series
        // capacitance by an amount that goes with the shield turn count, so it lands between the two extremes and can
        // be graded. Six turns against 19.7 turns per disc. Floating is the dialog's own default connection.
        "STME0999-shield6" : STME0999(name: "STME0999-shield6",
                                      notes: "A 6-turn wound-in shield in every disc pair of the HV.",
                                      restructure: .woundInShield(coil: 1, turnsPerDisc: 6, connection: .floating)),

        // The second fixture, and the one intershielding is actually FOR. STME-0999 is a small unit with 19.7 turns per HV disc,
        // where interleaving is a perfectly practical option and a 6-turn shield is 30% of the turns; this is a 25 MVA
        // 120 kV(Y)/26.4 kV(D) unit wound in CTC on BOTH coils, where interleaving is essentially impossible and the HV carries
        // only 10.75 turns per disc, so a 5-turn shield is about half of them.
        //
        // All three variants hold the HV at the SAME radial build - the one the 5-turn shield needs - so that the shielded case is
        // not quietly credited for the extra disc face area its own wire bought it. See MatchedBuild.
        "STME0999_2" : STME0999_2(name: "STME0999_2",
                                  notes: "HV as designed - plain continuous discs, at the 5-turn shield's radial build.",
                                  restructure: .none,
                                  matchedBuild: MatchedBuild(coil: 1, turnsPerDisc: 5, connection: .floating)),

        "STME0999_2-interleaved" : STME0999_2(name: "STME0999_2-interleaved",
                                              notes: "The whole HV winding interleaved, at the 5-turn shield's radial build.",
                                              restructure: .interleave(coil: 1),
                                              matchedBuild: MatchedBuild(coil: 1, turnsPerDisc: 5, connection: .floating)),

        "STME0999_2-shield5" : STME0999_2(name: "STME0999_2-shield5",
                                          notes: "A 5-turn wound-in shield in every disc pair of the HV - about half its turns.",
                                          restructure: .woundInShield(coil: 1, turnsPerDisc: 5, connection: .floating),
                                          matchedBuild: nil)
    ]

    /// The STME-0999_2 fixture: 25 MVA, 120 kV wye to 26.4 kV delta, both coils disc-wound in CTC. 550 kV BIL on the HV.
    ///
    /// This is the regime wound-in shields exist for. CTC is a large stranded conductor, so a disc holds few turns - 688 turns
    /// over 64 discs, 10.75 each - and interleaving a CTC winding is essentially impossible to manufacture. The interleaved
    /// scenario is therefore a REFERENCE rather than a proposal: it says what the shield is being measured against.
    private static func STME0999_2(name:String, notes:String, restructure:Restructure, matchedBuild:MatchedBuild?) -> Scenario {

        return Scenario(name: name,
                        restructure: restructure,
                        matchedBuild: matchedBuild,
                        fixtureName: "STME-0999_2_AndIn.txt",
                        notes: "25 MVA. Coil 0 = 26.4 kV delta LV (262 turns, 90 discs), coil 1 = 120 kV wye HV (688 turns, 64 discs). Both coils CTC disc windings. 550 kV full wave on the HV line end. " + notes,
                        terminations: [Termination(coil: 0, end: .bottom, type: .ground),
                                       Termination(coil: 0, end: .top, type: .ground),
                                       Termination(coil: 1, end: .bottom, type: .ground),
                                       Termination(coil: 1, end: .top, type: .impulse)],
                        waveFormType: .FullWave,
                        peakVoltage: 550.0e3,
                        displaySpan: 100.0e-6,
                        bandwidth: 10.0e6,
                        continuumCoil: 1)
    }

    // MARK: Entry point

    /// Run a scenario if one was named on the command line.
    ///
    /// Called from AppDelegate.applicationDidFinishLaunching. Returns true if a self test was started, in which case
    /// the app will terminate itself when the run finishes - the caller should not do anything else.
    @discardableResult
    static func RunIfRequested(controller:AppController) -> Bool {

        guard let scenarioName = UserDefaults.standard.string(forKey: scenarioKey), !scenarioName.isEmpty else {

            return false
        }

        guard let scenario = scenarios[scenarioName] else {

            Record(report: "No scenario named '\(scenarioName)'. Known scenarios: \(scenarios.keys.sorted().joined(separator: ", "))",
                   summary: "FAILED - unknown scenario '\(scenarioName)'",
                   fileName: "SelfTestReport-\(scenarioName).txt")
            NSApp.terminate(nil)
            return true
        }

        Task {

            let report = await Run(scenario: scenario, controller: controller)

            Record(report: report.text,
                   summary: report.summary,
                   fileName: "SelfTestReport-\(scenario.name).txt")

            Stage("finished")
            NSApp.terminate(nil)
        }

        return true
    }

    // MARK: The run

    private struct Report {

        var text:String
        var summary:String
    }

    private static func Run(scenario:Scenario, controller:AppController) async -> Report {

        var text = "ImpulseDistribution self test\n"
        text += "Scenario:  \(scenario.name)\n"
        text += "Run at:    \(Date())\n"
        text += "Design:    \(scenario.notes)\n"
        text += String(repeating: "=", count: 110) + "\n\n"

        Stage("locating the fixture")

        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {

            return Report(text: text + "FAILED: the container has no Documents folder.\n", summary: "FAILED - no Documents folder")
        }

        let fixture = documents.appendingPathComponent(scenario.fixtureName)

        guard FileManager.default.fileExists(atPath: fixture.path) else {

            text += "FAILED: the design file was not found.\n"
            text += "Expected it at: \(fixture.path)\n"
            text += "Copy the design file there - the sandbox makes anywhere else unreadable without the open panel.\n"
            return Report(text: text, summary: "FAILED - fixture not found")
        }

        Stage("reading the design file")

        let xlFile:PCH_ExcelDesignFile

        do {

            xlFile = try PCH_ExcelDesignFile(designFile: fixture)
        }
        catch {

            return Report(text: text + "FAILED reading the design file: \(error)\n", summary: "FAILED - could not read the design file")
        }

        // Everything from here is the same path the UI takes, in the same order: build the model (which computes the
        // radial build-up, the FE phase, the eddy losses, the inductance matrix and the capacitance matrix), then add
        // the terminations, then create the simulation model.
        Stage("building the model (inductance + capacitance - this is the slow part)")

        await controller.updateModel(oldSegments: [], newSegments: [], xlFile: xlFile, reinitialize: true)

        guard let model = controller.currentModel else {

            return Report(text: text + "FAILED: no model was built.\n", summary: "FAILED - no model")
        }

        // The structural change goes in BEFORE the geometry is reported and before the terminations, because it swaps
        // Segments and so rebuilds both the connectors and every matrix in the model.
        Stage("restructuring the winding")

        text += "RESTRUCTURE\n"
        text += String(repeating: "-", count: 110) + "\n"

        // The build floor has to be in place before anything recomputes the geometry, so it goes on first. It only
        // reaches the model when something calls ApplyRadialBuildUp, which every path below ends in.
        var matchedOutcome:String? = nil

        if let matched = scenario.matchedBuild {

            matchedOutcome = await ApplyMatchedBuild(matched, model: model)
            text += "  \(matchedOutcome!)\n"

            guard !matchedOutcome!.hasPrefix("FAILED") else {

                return Report(text: text, summary: "FAILED - " + matchedOutcome!)
            }
        }

        let restructureOutcome = await ApplyRestructure(scenario.restructure, model: model, controller: controller)

        text += "  \(restructureOutcome)\n"

        guard !restructureOutcome.hasPrefix("FAILED") else {

            return Report(text: text, summary: "FAILED - " + restructureOutcome)
        }

        // Interleaving and shielding swap Segments, and updateModel ends in recalculateModel, so the floor has already
        // reached the geometry by now. A scenario that only sets a floor has changed nothing the model has noticed yet,
        // so it needs the recalculation asked for explicitly - the same reason recalculateModel exists separately from
        // updateModel, which cannot be called with empty Segment arrays.
        if matchedOutcome != nil, case .none = scenario.restructure {

            Stage("recomputing the geometry for the matched build")
            await controller.recalculateModel(reinitialize: false)
            text += "  (recalculated: nothing was restructured, so the build floor needed its own pass)\n"
        }

        text += "\n"

        Stage("reporting the geometry")

        text += await GeometryReport(model: model)

        Stage("applying the terminations")

        text += "TERMINATIONS\n"
        text += String(repeating: "-", count: 110) + "\n"

        var terminationsOK = true

        for nextTermination in scenario.terminations {

            let outcome = await ApplyTermination(nextTermination, model: model)
            text += "  \(outcome)\n"

            if outcome.hasPrefix("FAILED") {

                terminationsOK = false
            }
        }

        text += "\n"

        guard terminationsOK else {

            return Report(text: text + "FAILED: a termination could not be applied - see above.\n", summary: "FAILED - could not apply the terminations")
        }

        Stage("creating the simulation model")

        guard let simModel = await SimulationModel(model: model) else {

            return Report(text: text + "FAILED: the simulation model could not be created.\n", summary: "FAILED - no simulation model")
        }

        controller.currentSimModel = simModel

        Stage("solving the initial distribution")

        guard let snapshot = await simModel.Snapshot() else {

            return Report(text: text + "FAILED: the network snapshot could not be taken.\n", summary: "FAILED - no snapshot")
        }

        guard let alpha = await FrequencyDomainSolver.CapacitiveDistribution(snapshot: snapshot) else {

            return Report(text: text + "FAILED: the capacitive distribution could not be solved.\n", summary: "FAILED - no initial distribution")
        }

        Stage("comparing against the continuum model")

        let comparison = await ContinuumComparison(model: model, alpha: alpha, coil: scenario.continuumCoil)
        text += comparison.text

        var summary = comparison.summary

        // The transient is opt-in: it is minutes of work, and an edit that breaks the assembly or the capacitance has
        // already shown up in the initial distribution above.
        if UserDefaults.standard.bool(forKey: transientKey) {

            Stage("running the frequency-domain sweep")

            let waveForm = SimulationModel.WaveForm(type: scenario.waveFormType, pkVoltage: scenario.peakVoltage)

            let results = await simModel.SolveFrequencyDomain(waveForm: waveForm,
                                                             displaySpan: scenario.displaySpan,
                                                             maximumFrequency: scenario.bandwidth)

            let transient = await TransientReport(model: model, results: results, scenario: scenario)
            text += transient.text

            summary += "; " + transient.summary
        }
        else {

            text += "TRANSIENT\n"
            text += String(repeating: "-", count: 110) + "\n"
            text += "  Not run. Add -PCH_SelfTestTransient YES to include the frequency-domain sweep.\n\n"
        }

        return Report(text: text, summary: summary)
    }

    // MARK: Restructuring

    /// The result of sizing a wound-in shield for a coil.
    private enum ShieldSizing {

        case ok(wire:Segment.WoundInShieldWire, discTurns:Double, sections:[BasicSection], segments:[Segment])
        case failed(String)
    }

    /// Size the shield wire for `turnsPerDisc` turns in every disc of a coil, and gather what fitting it would need.
    ///
    /// Both the scenario that actually FITS the shield and the one that merely matches its radial build come through here, for
    /// the same reason `DielectricStress` and `SeriesCapacitance` share `DiscToDiscLayerStack`: if the two sized the wire
    /// separately they could disagree about how wide it is, and a "matched" geometry that is not actually matched would silently
    /// invalidate the comparison it exists to make.
    private static func SizeShield(coil:Int, turnsPerDisc:Int, connection:Segment.WoundInShieldWire.Connection, model:PhaseModel) async -> ShieldSizing {

        let segments = await model.CoilSegments().filter({ $0.radialPos == coil })
        let sections = segments.flatMap({ $0.basicSections })

        guard !sections.isEmpty else {

            return .failed("coil \(coil) has no sections")
        }

        // A shield crosses over at the outermost turn of a PAIR, so the pair is the unit.
        guard sections.count % 2 == 0 else {

            return .failed("coil \(coil) has \(sections.count) discs - a wound-in shield needs an even number")
        }

        guard let discTurns = sections.map({ $0.N }).min(), discTurns > 1.0 else {

            return .failed("coil \(coil) has too few turns per disc to carry a shield")
        }

        // There are only N − 1 spaces between the turns of a disc, which is the ceiling GetWoundInShieldDialog enforces on the
        // same figure.
        let maximumTurns = Int(discTurns.rounded(.down)) - 1

        guard turnsPerDisc >= 1, turnsPerDisc <= maximumTurns else {

            return .failed("\(turnsPerDisc) shield turns per disc, but coil \(coil) allows 1 to \(maximumTurns) (N = \(String(format: "%.2f", discTurns)))")
        }

        // The paper on the shield wire is sized from the working turn-to-shield voltage, so the model has to know its volts per
        // turn - which recalculateModel has already set from the design file.
        let voltsPerTurn = await model.voltsPerTurn

        guard voltsPerTurn > 0.0 else {

            return .failed("the model has no volts/turn, so the shield paper cannot be sized")
        }

        let wire = Segment.WoundInShieldWire.Standard(connection: connection,
                                                      maxTurnsPerDisc: turnsPerDisc,
                                                      discTurns: discTurns,
                                                      voltsPerTurn: voltsPerTurn,
                                                      turnInsulation: sections[0].wdgData.turn.turnInsulation)

        return .ok(wire: wire, discTurns: discTurns, sections: sections, segments: segments)
    }

    /// Hold a coil at the radial build a wound-in shield would need, without fitting the shield. See `MatchedBuild`.
    private static func ApplyMatchedBuild(_ matched:MatchedBuild, model:PhaseModel) async -> String {

        switch await SizeShield(coil: matched.coil, turnsPerDisc: matched.turnsPerDisc, connection: matched.connection, model: model) {

        case .failed(let why):

            return "FAILED: matched build: \(why)"

        case .ok(let wire, _, _, _):

            // The same figure RadialBuildUpByCoil would read off a fitted shield: turns per disc times the over-paper radial
            // dimension of one shield turn.
            let adder = Segment.WoundInShield(wire: wire, turnsPerDisc: matched.turnsPerDisc, pairCount: 1).radialBuildAdder

            await model.SetRadialBuildUpFloor([matched.coil : adder])

            return String(format: "coil %d held at the radial build of a %d-turn shield: +%.3f mm (%d turns x %.3f mm over paper)",
                          matched.coil, matched.turnsPerDisc, adder * 1000.0, matched.turnsPerDisc, wire.overPaperRadial * 1000.0)
        }
    }

    /// Interleave a coil, or put a wound-in shield into every one of its disc pairs.
    ///
    /// This is the model-level half of `AppController.doInterleaveSelection` and `doAddWoundInShields`, without the
    /// `SegmentPath` selection or the dialogs. It deliberately does NOT re-implement the guards those two carry -
    /// already-interleaved, already-shielded, non-contiguous, spans a tapping gap - because it always operates on a
    /// whole coil of a freshly loaded model, where every one of them is answered by construction. If a scenario ever
    /// restructures twice or works on part of a coil, route it through the AppController versions instead.
    ///
    /// Both paths end in `updateModel(oldSegments:newSegments:xlFile:nil, reinitialize:false)`, which does the
    /// connector fixup and then the whole recalculation - radial build-up, FE phase, eddy losses, inductance,
    /// capacitance. That is why a shield is set on each new Segment BEFORE it is handed over: it costs one pass over
    /// the geometry and the matrices rather than two.
    private static func ApplyRestructure(_ restructure:Restructure, model:PhaseModel, controller:AppController) async -> String {

        switch restructure {

        case .none:

            return "none - the winding is as the design file describes it"

        case .interleave(let coil):

            let segments = await model.CoilSegments().filter({ $0.radialPos == coil })
            let sections = segments.flatMap({ $0.basicSections })

            guard !sections.isEmpty else {

                return "FAILED: coil \(coil) has no sections to interleave"
            }

            // A pair is the unit, so an odd disc count has nowhere to put the last one.
            guard sections.count % 2 == 0 else {

                return "FAILED: coil \(coil) has \(sections.count) discs - interleaving needs an even number"
            }

            let core = await model.core
            var interleaved:[Segment] = []

            do {

                for i in stride(from: 0, to: sections.count, by: 2) {

                    interleaved.append(try Segment(basicSections: [sections[i], sections[i + 1]],
                                                   interleaved: true,
                                                   realWindowHeight: core.realWindowHeight,
                                                   useWindowHeight: core.adjustedWindHt))
                }
            }
            catch {

                return "FAILED: could not build the interleaved segments: \(error)"
            }

            await controller.updateModel(oldSegments: segments, newSegments: interleaved, xlFile: nil, reinitialize: false)

            return "interleaved coil \(coil): \(sections.count) discs -> \(interleaved.count) interleaved Segments"

        case .woundInShield(let coil, let turnsPerDisc, let connection):

            let sizing = await SizeShield(coil: coil, turnsPerDisc: turnsPerDisc, connection: connection, model: model)

            guard case .ok(let wire, _, let sections, let segments) = sizing else {

                if case .failed(let why) = sizing {

                    return "FAILED: \(why)"
                }

                return "FAILED: the shield could not be sized"
            }

            let core = await model.core
            var paired:[Segment] = []

            do {

                for i in stride(from: 0, to: sections.count, by: 2) {

                    let newSegment = try Segment(basicSections: [sections[i], sections[i + 1]],
                                                 realWindowHeight: core.realWindowHeight,
                                                 useWindowHeight: core.adjustedWindHt)

                    // Two discs to a Segment is exactly one pair per Segment.
                    await newSegment.SetWoundInShield(Segment.WoundInShield(wire: wire, turnsPerDisc: turnsPerDisc, pairCount: 1))
                    paired.append(newSegment)
                }
            }
            catch {

                return "FAILED: could not build the shielded segments: \(error)"
            }

            await controller.updateModel(oldSegments: segments, newSegments: paired, xlFile: nil, reinitialize: false)

            var outcome = "coil \(coil): \(turnsPerDisc)-turn wound-in shield (\(connection.description)) in each of \(paired.count) disc pairs"
            outcome += String(format: ", wire %.3f mm bare radial + %.3f mm insulation (two-sided)", wire.bareRadial * 1000.0, wire.insulation * 1000.0)

            return outcome
        }
    }

    // MARK: Terminations

    /// Tie one coil end to ground or to the impulse generator.
    ///
    /// This does what TransformerView.mouseDownWithAddGround / .mouseDownWithAddImpulse do when the user clicks a
    /// lead, minus the hit testing: find the floating lead at that coil end and hand its location to AddConnector,
    /// which REPLACES a floating lead rather than appending to it. Taking the location from the lead that is already
    /// there is the whole point - a coil end's lead is at .inside_lower, .outside_lower or .center_lower depending on
    /// winding type and disc count (see AppController's segment-building loop), and guessing it here would give a
    /// connector that NodeAt cannot resolve.
    private static func ApplyTermination(_ termination:Termination, model:PhaseModel) async -> String {

        let label = "coil \(termination.coil) \(termination.end == .bottom ? "bottom" : "top") -> \(termination.type)"

        let coilSegments = await model.CoilSegments().filter({ $0.radialPos == termination.coil })

        guard let segment = termination.end == .bottom ? coilSegments.first : coilSegments.last else {

            return "FAILED: \(label): coil \(termination.coil) has no segments"
        }

        let allSegments = await model.segments
        let wantLower = termination.end == .bottom

        // A coil-end lead is a termination on the Segment itself (segmentID nil) that is still floating, at a lower
        // location for the bottom of the coil and an upper one for the top.
        guard let lead = await segment.connections.first(where: {

            $0.segmentID == nil
                && $0.connector.toLocation == .floating
                && (wantLower ? $0.connector.fromIsLower : $0.connector.fromIsUpper)

        }) else {

            return "FAILED: \(label): no floating lead at that end of segment \(segment.serialNumber)"
        }

        let fromLocation = lead.connector.fromLocation

        await segment.AddConnector(segments: allSegments, fromLocation: fromLocation, toLocation: termination.type, toSegmentID: nil)

        // If the lead's location also carries jumpers to other Segments, those Segments are at the same potential and
        // have to be terminated too. A plain coil end carries none, so this loop is normally empty - it is here so
        // that this routine behaves identically to the UI path on a model where it is not.
        for nextDestination in await segment.ConnectionDestinations(fromLocation: fromLocation) {

            guard let otherID = nextDestination.segmentID,
                  let other = allSegments.first(where: { $0.serialNumber == otherID }) else {

                continue
            }

            await other.AddConnector(segments: allSegments, fromLocation: nextDestination.location, toLocation: termination.type, toSegmentID: nil)
        }

        return "\(label): applied at \(fromLocation) of segment \(segment.serialNumber)"
    }

    // MARK: Geometry

    /// What the design file actually parsed into.
    ///
    /// This is the check on PchExcelDesignFilePackage and on the model-building path, and it is the one part of the
    /// report a human can verify against the design directly: disc counts, turn counts, radii and the axial gaps
    /// between sections are all things the designer knows independently.
    private static func GeometryReport(model:PhaseModel) async -> String {

        var text = "GEOMETRY AS PARSED\n"
        text += String(repeating: "-", count: 110) + "\n"

        let coilCount = await model.CoilCount()
        let allCoilSegments = await model.CoilSegments()

        text += "  Coils: \(coilCount)   Segments: \(allCoilSegments.count)   Nodes: \(await model.nodes.count)\n"
        let core = await model.core

        text += "  Core: leg radius \(Millimetres(core.radius)), window height \(Millimetres(core.realWindowHeight)), leg centres \(Millimetres(core.legCenters))\n"
        text += "  Tank depth: \(Millimetres(await model.tankDepth))\n\n"

        for coil in 0..<coilCount {

            let segments = allCoilSegments.filter({ $0.radialPos == coil })

            guard let first = segments.first, let last = segments.last else {

                continue
            }

            var turns = 0.0
            var discCount = 0

            for nextSegment in segments {

                turns += await nextSegment.N
                discCount += nextSegment.basicSections.count
            }

            let windingType = first.basicSections[0].wdgData.type

            text += "  Coil \(coil): \(WindingTypeName(windingType))\n"
            text += "    Segments:        \(segments.count)  (\(discCount) BasicSections)\n"
            text += "    Turns:           \(String(format: "%.1f", turns))"
            text += discCount > 0 ? "  (\(String(format: "%.3f", turns / Double(discCount))) per section)\n" : "\n"
            text += "    Inside radius:   \(Millimetres(await first.r1))\n"
            text += "    Outside radius:  \(Millimetres(await first.r2))\n"
            text += "    Radial build:    \(Millimetres(await first.r2 - first.r1))\n"
            text += "    Axial extent:    \(Millimetres(await first.z1)) to \(Millimetres(await last.z2))  (height \(Millimetres(await last.z2 - first.z1)))\n"

            // The axial gaps between consecutive sections - the key spacers on a disc coil, the inter-turn gaps on a
            // helical one. Reported as a range because a uniform coil should show one number and a coil with an axial
            // gap in it should show two, and which of those you have is exactly what you want to know.
            var gaps:[Double] = []

            for i in 1..<max(segments.count, 1) {

                gaps.append(await segments[i].z1 - segments[i - 1].z2)
            }

            if let smallest = gaps.min(), let largest = gaps.max() {

                let mean = gaps.reduce(0.0, +) / Double(gaps.count)

                if largest - smallest < 1.0e-6 {

                    text += "    Axial gaps:      \(Millimetres(mean))  (uniform, \(gaps.count) of them)\n"
                }
                else {

                    text += "    Axial gaps:      \(Millimetres(smallest)) to \(Millimetres(largest)), mean \(Millimetres(mean))  (\(gaps.count) of them)\n"
                }
            }

            // The hilo under this coil: the radial gap to whatever is inside it (the core for coil 0).
            if let hilo = try? await model.HiloUnder(coil: coil) {

                text += "    Hilo under:      \(Millimetres(hilo))\n"
            }

            text += "    Series C (coil): \(Farads(try? await model.CoilSeriesCapacitance(coil: coil)))\n"

            // The per-section series capacitances, which is where a coil stops being uniform. A continuous disc coil's
            // END discs are treated differently (DelVecchio 12.63-64: an end disc has a neighbour on one side only),
            // and that shows up here as two outliers. It matters because the continuum model of 13.5.1 assumes a
            // UNIFORM Cs, so any spread in this line is a spread the comparison below cannot represent.
            var sectionCs:[Double] = []

            for nextSegment in segments {

                sectionCs.append(await nextSegment.seriesCapacitance)
            }

            if let smallestCs = sectionCs.min(), let largestCs = sectionCs.max(), let bottomCs = sectionCs.first, let topCs = sectionCs.last {

                let meanCs = sectionCs.reduce(0.0, +) / Double(sectionCs.count)
                text += "    Section Cs:      min \(Farads(smallestCs)), max \(Farads(largestCs)), mean \(Farads(meanCs))\n"
                text += "                     bottom section \(Farads(bottomCs)), top section \(Farads(topCs))"
                text += String(format: "  (%.3f and %.3f of the mean)\n", bottomCs / meanCs, topCs / meanCs)
            }

            let ground = await GroundCapacitance(model: model, coil: coil)

            text += "    Ground C direct: \(Farads(ground.direct))   to other coils: \(Farads(ground.toOtherCoils))\n"

            // The outermost coil's direct-to-ground figure is two very different things added together, and the split
            // is worth printing because it is routinely surprising - see OuterShuntCapacitance. Without it, a hand
            // calculation of "coil to tank" checked against this line looks wrong when nothing is.
            if coil == coilCount - 1, let outer = try? await model.OuterShuntCapacitance() {

                let total = outer.tank + outer.adjacentPhase
                text += "      of which:      to tank \(Farads(outer.tank)), to the adjacent phase \(Farads(outer.adjacentPhase))"
                text += total > 0.0 ? String(format: "  (%.0f%% phase-to-phase)\n", 100.0 * outer.adjacentPhase / total) : "\n"
                let neighbours = await model.adjacentPhaseCount
                let legDescription = neighbours == 0 ? "single phase - no neighbour" : (neighbours == 2 ? "a CENTRE leg" : "\(neighbours) neighbour(s)")
                text += "                     phase-to-phase gap: \(Millimetres(core.legCenters - 2.0 * (await first.r2)))  (\(neighbours) neighbouring phase(s) - \(legDescription))\n"
            }

            text += "\n"
        }

        return text
    }

    private static func WindingTypeName(_ type:BasicSectionWindingData.WdgType) -> String {

        switch type {

        case .layer:      return "layer"
        case .disc:       return "disc"
        case .helical:    return "helical"
        case .multistart: return "multistart"
        case .sheet:      return "sheet"
        }
    }

    // MARK: Capacitance to ground

    /// A coil's total capacitance to ground, split by where it goes.
    ///
    /// - direct: the shunt capacitances the model books straight to ground (toNode == -1) - the tank, the core, and
    ///   the yokes.
    /// - toOtherCoils: the shunt capacitances to nodes belonging to a DIFFERENT coil. Whether these belong in Cg is a
    ///   judgment, which is why they are counted separately rather than folded in; see ContinuumComparison.
    ///
    /// Shunt capacitances between two nodes of the SAME coil (layer-to-layer, on a layer winding) are neither - they
    /// are internal to the winding and the continuum model has no place for them. They are reported as a remainder so
    /// that their existence is never silent.
    private static func GroundCapacitance(model:PhaseModel, coil:Int) async -> (direct:Double, toOtherCoils:Double, withinCoil:Double) {

        let nodes = await model.nodes

        // node number -> the coil it belongs to. A node is bounded by at most one Segment on each side and both are in
        // the same coil, so either one answers.
        var coilOfNode:[Int:Int] = [:]

        for nextNode in nodes {

            if let radial = nextNode.aboveSegment?.radialPos ?? nextNode.belowSegment?.radialPos {

                coilOfNode[nextNode.number] = radial
            }
        }

        var direct = 0.0
        var toOtherCoils = 0.0
        var withinCoil = 0.0

        for nextNode in nodes {

            guard coilOfNode[nextNode.number] == coil else {

                continue
            }

            for nextCap in nextNode.shuntCapacitances {

                if nextCap.toNode < 0 {

                    direct += nextCap.capacitance
                }
                else if coilOfNode[nextCap.toNode] == coil {

                    withinCoil += nextCap.capacitance
                }
                else {

                    toOtherCoils += nextCap.capacitance
                }
            }
        }

        return (direct: direct, toOtherCoils: toOtherCoils, withinCoil: withinCoil)
    }

    // MARK: The continuum comparison (DelVecchio 13.5.1)

    /// Compare the computed initial distribution against DelVecchio's uniform-capacitance continuum model.
    ///
    /// THE TWO ALPHAS. DelVecchio's Cg is "the capacitance to ground of the winding", written for a single winding
    /// against a grounded surround. A real two-winding phase has an inner coil in the way, and here that coil is
    /// grounded at BOTH ends - the standard impulse test connection - so it sits very close to ground potential and
    /// its capacitance from the HV behaves almost like capacitance to ground. Almost, not exactly: it is a winding
    /// with its own series capacitance, not an equipotential surface. Rather than pick one, both are reported:
    ///
    ///     alphaDirect = sqrt(Cg_direct / Cs)                    - lower bound, tank and adjacent phase only
    ///     alphaTotal  = sqrt((Cg_direct + Cg_toOtherCoils) / Cs) - upper bound, the LV counted as ground
    ///
    /// The computed distribution should land BETWEEN the two curves, nearer the alphaTotal one. If it lands outside
    /// them, something is wrong that the continuum model's approximations do not explain.
    ///
    /// A third alpha is fitted to the computed distribution, by least squares on ln(V) - see FitAlpha for why the
    /// logarithm is load-bearing. That one is not a check on anything by itself; it is the shape question. If the
    /// computed distribution is a sinh at all the fit is tight, and a fitted alpha far outside the bracket then says
    /// the capacitances are wrong rather than the shape.
    ///
    /// The table at the end carries a LOCAL alpha per node, which is the same question asked without any fitting: it
    /// is d(ln V)/dx between neighbouring nodes, and it equals alpha wherever 13.5.1 holds. Read that column before
    /// reading any of the three fitted numbers - a coil whose local alpha drifts is a coil the continuum model cannot
    /// describe with one alpha, and no choice of estimator will change that.
    ///
    /// THE LINE-END GRADIENT is reported alongside, because it is the number a designer actually acts on. In the
    /// continuum model dV/dx at the line end is alpha/tanh(alpha) times the average gradient, and the model's own
    /// equivalent is the voltage across the end disc divided by the average voltage per disc.
    private static func ContinuumComparison(model:PhaseModel, alpha:[Double], coil:Int) async -> (text:String, summary:String) {

        var text = "INITIAL DISTRIBUTION vs. DELVECCHIO 13.5.1 (continuum model), coil \(coil)\n"
        text += String(repeating: "-", count: 110) + "\n"

        guard let profile = try? await model.CoilVoltageProfile(coil: coil), profile.count > 1 else {

            return (text + "  FAILED: coil \(coil) has no usable voltage profile.\n\n", "FAILED - no voltage profile")
        }

        guard let seriesCapacitance = try? await model.CoilSeriesCapacitance(coil: coil), seriesCapacitance > 0.0 else {

            return (text + "  FAILED: coil \(coil) has no series capacitance.\n\n", "FAILED - no series capacitance")
        }

        let ground = await GroundCapacitance(model: model, coil: coil)

        // The computed distribution, as (x, V) with x running from the grounded end to the line end. CoilVoltageProfile
        // is sorted by ascending height; which end is driven is settled by looking at where the impulse actually is,
        // not by assuming the top, because a coil can be driven from either end.
        let impulsedNodes = Set(await model.NodesOfType(connType: .impulse).map({ $0.number }))
        let drivenAtTop = impulsedNodes.contains(profile.last?.nodeIndex ?? -1)

        guard let lowZ = profile.first?.z, let highZ = profile.last?.z, highZ > lowZ else {

            return (text + "  FAILED: the coil has no axial extent.\n\n", "FAILED - no axial extent")
        }

        var points:[(x:Double, v:Double)] = []

        for nextPoint in profile {

            guard nextPoint.nodeIndex >= 0, nextPoint.nodeIndex < alpha.count else {

                continue
            }

            // x = 0 at the grounded end, 1 at the line end.
            let heightFraction = (nextPoint.z - lowZ) / (highZ - lowZ)
            points.append((x: drivenAtTop ? heightFraction : 1.0 - heightFraction, v: alpha[nextPoint.nodeIndex]))
        }

        points.sort { $0.x < $1.x }

        guard points.count > 2 else {

            return (text + "  FAILED: too few nodes to compare.\n\n", "FAILED - too few nodes")
        }

        let alphaDirect = sqrt(ground.direct / seriesCapacitance)
        let alphaTotal = sqrt((ground.direct + ground.toOtherCoils) / seriesCapacitance)
        let alphaFitted = FitAlpha(points: points)

        text += "  Driven end:            \(drivenAtTop ? "top" : "bottom")\n"
        text += "  Nodes compared:        \(points.count)\n"
        text += "  Cs (whole winding):    \(Farads(seriesCapacitance))\n"

        // NOT "to the tank". For the outermost coil this is the tank AND the adjacent phase, and on a design with tight
        // leg centres the second is the larger of the two - see OuterShuntCapacitance and the split printed in the
        // geometry section above. Labelling it "tank" here once cost an afternoon.
        text += "  Cg booked to ground:   \(Farads(ground.direct))   (tank + adjacent phase - see the split above)\n"
        text += "  Cg to other coils:     \(Farads(ground.toOtherCoils))\n"

        if ground.withinCoil > 0.0 {

            text += "  Cg within the coil:    \(Farads(ground.withinCoil))  (not part of either alpha - see GroundCapacitance)\n"
        }

        text += "\n"
        text += "  alpha (Cg to ground only): \(String(format: "%8.4f", alphaDirect))\n"
        text += "  alpha (Cg incl. LV):       \(String(format: "%8.4f", alphaTotal))\n"
        text += "  alpha (fitted to model):   \(String(format: "%8.4f", alphaFitted))\n"

        let bracketed = alphaFitted >= min(alphaDirect, alphaTotal) && alphaFitted <= max(alphaDirect, alphaTotal)
        text += "  fitted alpha is \(bracketed ? "INSIDE" : "OUTSIDE") the bracket\n\n"

        // How far the computed distribution is from each continuum curve. Both errors are absolute in per-unit of the
        // applied crest, which is the natural unit here: a 0.01 departure means one per cent of the crest, wherever on
        // the winding it happens.
        for (name, value) in [("Cg to ground", alphaDirect), ("Cg incl. LV", alphaTotal), ("fitted", alphaFitted)] {

            let deviation = Deviation(points: points, alpha: value)
            text += "  vs. alpha = \(String(format: "%7.4f", value)) (\(name)):  max \(String(format: "%.5f", deviation.max)) p.u. at x = \(String(format: "%.3f", deviation.atX)),  rms \(String(format: "%.5f", deviation.rms)) p.u.\n"
        }

        text += "\n"

        // The line-end gradient, in multiples of the average gradient.
        //
        // The divisor is the end section's own span in x, NOT 1/N. The end nodes of a coil sit at the outer face of
        // the end disc while the interior ones sit at the gap midpoints, so the end sections are about 12% shorter in
        // x than the interior ones; dividing by 1/N charges the end section for length it does not have. The continuum
        // model's equivalent is its own average slope over that same interval rather than its endpoint derivative
        // alpha/tanh(alpha), so that the two are measured over the same piece of winding.
        let lastSpan = points[points.count - 1].x - points[points.count - 2].x
        let endSectionDrop = abs(points[points.count - 1].v - points[points.count - 2].v)
        let modelEnhancement = lastSpan > 0.0 ? endSectionDrop / lastSpan : 0.0

        text += "  Line-end gradient over the end section, as a multiple of the average gradient:\n"
        text += "    model:                        \(String(format: "%8.4f", modelEnhancement))\n"

        for (name, value) in [("Cg to ground", alphaDirect), ("Cg incl. LV", alphaTotal), ("fitted", alphaFitted)] {

            let continuumDrop = 1.0 - ContinuumShape(alpha: value, x: points[points.count - 2].x)
            text += "    continuum, \(name):\(String(repeating: " ", count: max(1, 18 - name.count)))\(String(format: "%8.4f", lastSpan > 0.0 ? continuumDrop / lastSpan : 0.0))"
            text += String(format: "   (alpha/tanh(alpha) = %.4f)\n", value / tanh(value))
        }

        text += "\n"

        // The distribution itself, so that the report can be diffed against a later run, plus the LOCAL alpha between
        // each pair of nodes. The local alpha is the honest way to look at this: it is d(ln V)/dx, which is exactly
        // alpha wherever the distribution is the exponential that 13.5.1 predicts, and it needs no fitting at all. A
        // winding that really is a uniform ladder shows one number down the column. Where it drifts, the ladder is not
        // uniform, and the column says where and by how much - which a single fitted alpha cannot.
        //
        // It is meaningless near the grounded end (sinh is linear there, not exponential, and the model's values are
        // five decades down and set by coupling to the other coil rather than by alpha), so it is only printed above
        // the fitting floor.
        text += "  x (0 = grounded end)   V/Vcrest (model)   sinh fit (fitted alpha)   difference   local alpha\n"

        for (i, nextPoint) in points.enumerated() {

            let fitted = ContinuumShape(alpha: alphaFitted, x: nextPoint.x)
            text += String(format: "  %14.6f   %16.6f   %23.6f   %10.6f", nextPoint.x, nextPoint.v, fitted, nextPoint.v - fitted)

            if i > 0, points[i - 1].v >= fittingFloor, nextPoint.v > 0.0, nextPoint.x > points[i - 1].x {

                let localAlpha = log(nextPoint.v / points[i - 1].v) / (nextPoint.x - points[i - 1].x)
                text += String(format: "   %11.3f", localAlpha)
            }

            text += "\n"
        }

        text += "\n"

        let summary = String(format: "alpha: direct %.3f, incl. LV %.3f, fitted %.3f (%@ bracket); line-end gradient %.3f x average",
                             alphaDirect, alphaTotal, alphaFitted, bracketed ? "inside" : "OUTSIDE", modelEnhancement)

        return (text, summary)
    }

    /// DelVecchio 13.5.1: V(x)/V = sinh(alpha*x) / sinh(alpha), with x = 0 at the grounded end.
    ///
    /// Written in the exponential form that comes from multiplying numerator and denominator by e^-alpha:
    ///
    ///     sinh(ax)/sinh(a) = (e^(a(x-1)) - e^(-a(x+1))) / (1 - e^(-2a))
    ///
    /// which is algebraically identical but cannot overflow - every exponent is <= 0 for x in [0, 1] and a > 0. The
    /// direct form overflows at alpha ~ 710, and although no winding is anywhere near that, a fit that wanders while
    /// searching should not be able to produce an inf.
    private static func ContinuumShape(alpha:Double, x:Double) -> Double {

        // The alpha -> 0 limit is the uniform (purely inductive) distribution. Taking it explicitly avoids 0/0.
        guard alpha > 1.0e-9 else {

            return x
        }

        return (exp(alpha * (x - 1.0)) - exp(-alpha * (x + 1.0))) / (1.0 - exp(-2.0 * alpha))
    }

    /// The largest and rms departure of the computed distribution from a continuum curve of the given alpha.
    private static func Deviation(points:[(x:Double, v:Double)], alpha:Double) -> (max:Double, atX:Double, rms:Double) {

        var largest = 0.0
        var largestX = 0.0
        var sumSquares = 0.0

        for nextPoint in points {

            let error = nextPoint.v - ContinuumShape(alpha: alpha, x: nextPoint.x)

            if abs(error) > largest {

                largest = abs(error)
                largestX = nextPoint.x
            }

            sumSquares += error * error
        }

        return (max: largest, atX: largestX, rms: sqrt(sumSquares / Double(points.count)))
    }

    /// Nodes whose voltage is below this fraction of the crest take no part in the fit, and get no local alpha.
    ///
    /// Two reasons, and they are the same reason twice. ln(V) runs to minus infinity at the grounded end, so a
    /// logarithmic fit needs *some* floor. And the bottom of a real winding is not a sinh at all: down there the
    /// initial distribution is a residual set by capacitance to the other coil, four or five decades below the crest,
    /// carrying no information about alpha and a great deal of information about the LV. 0.1% of crest is well below
    /// anything a designer would look at and well above that residual.
    private static let fittingFloor = 1.0e-3

    /// The alpha whose continuum curve best fits the computed distribution, by least squares ON THE LOGARITHM.
    ///
    /// THE LOGARITHM IS NOT A DETAIL. Over most of a winding the initial distribution is an exponential - within
    /// e^(-2a), sinh(ax)/sinh(a) IS e^(a(x-1)) - so it spans four or five decades from the grounded end to the line
    /// end. A least-squares fit in V therefore sees only the top few per cent of the coil: every residual below about
    /// x = 0.9 is smaller than the rounding on the ones above it, and the fit reduces to "match the last two discs".
    /// That is exactly the region where a real winding departs from 13.5.1 the most, because the end disc has a
    /// neighbour on one side only and gets its own series capacitance (DelVecchio 12.63-64) - so the linear fit
    /// weights the least representative discs the most heavily.
    ///
    /// It is not a small effect. On the STME-0999 fixture the linear fit returned alpha = 14.75 against a winding
    /// whose local d(ln V)/dx sits at 9.3 through the middle and 10.8 near the top; the logarithmic fit returns a
    /// number in that range. The linear fit also put the answer outside the Cg bracket and so reported a disagreement
    /// with DelVecchio that was entirely an artefact of the estimator.
    ///
    /// Golden-section search rather than anything cleverer: the objective is smooth and unimodal in alpha over any
    /// range a winding can occupy (the curve family is monotone in alpha at every interior x), there is exactly one
    /// parameter, and a few hundred evaluations of a closed-form expression costs nothing. The bracket is deliberately
    /// wide - a fitted alpha that runs to either limit is itself the finding.
    private static func FitAlpha(points:[(x:Double, v:Double)]) -> Double {

        // Only the part of the winding where the distribution carries alpha - see fittingFloor.
        let fitted = points.filter({ $0.v >= fittingFloor })

        guard fitted.count >= 3 else {

            return 0.0
        }

        var low = 0.01
        var high = 60.0

        // 1/phi, the golden-section ratio.
        let ratio = 0.6180339887498949

        func SumOfSquares(_ alpha:Double) -> Double {

            var total = 0.0

            for nextPoint in fitted {

                let shape = ContinuumShape(alpha: alpha, x: nextPoint.x)

                // The shape cannot be zero for x > 0 and alpha > 0, but it can underflow at very large alpha, which
                // the search is free to try. Charge a large residual rather than taking log(0).
                guard shape > 0.0 else {

                    total += 100.0
                    continue
                }

                let error = log(nextPoint.v) - log(shape)
                total += error * error
            }

            return total
        }

        var c = high - ratio * (high - low)
        var d = low + ratio * (high - low)
        var fc = SumOfSquares(c)
        var fd = SumOfSquares(d)

        // 100 iterations shrinks the bracket by 0.618^100, which is far below any tolerance that matters; the loop is
        // bounded rather than convergence-tested so that it cannot spin on a pathological objective.
        for _ in 0..<100 {

            if fc < fd {

                high = d
                d = c
                fd = fc
                c = high - ratio * (high - low)
                fc = SumOfSquares(c)
            }
            else {

                low = c
                c = d
                fc = fd
                d = low + ratio * (high - low)
                fd = SumOfSquares(d)
            }
        }

        return (low + high) / 2.0
    }

    // MARK: The transient

    /// The peak envelope of the impulsed coil, which is what the continuum model's travelling-wave section (13.5.2)
    /// speaks to - but only qualitatively, since that section is a lossless uniform line with no second winding and no
    /// mutual inductance. This is reported as a regression baseline, not compared against a formula.
    private static func TransientReport(model:PhaseModel, results:[SimulationModel.SimulationStepResult], scenario:Scenario) async -> (text:String, summary:String) {

        var text = "TRANSIENT (frequency-domain solve)\n"
        text += String(repeating: "-", count: 110) + "\n"

        guard !results.isEmpty else {

            text += "  FAILED: the solver returned no results.\n\n"
            return (text, "transient FAILED")
        }

        text += "  Waveform:   \(scenario.waveFormType.rawValue) at \(String(format: "%.1f", scenario.peakVoltage / 1000.0)) kV crest\n"
        text += "  Span:       \(String(format: "%.1f", scenario.displaySpan * 1.0e6)) us in \(results.count) steps\n"
        text += "  Bandwidth:  \(String(format: "%.1f", scenario.bandwidth / 1.0e6)) MHz\n\n"

        guard let profile = try? await model.CoilVoltageProfile(coil: scenario.continuumCoil), !profile.isEmpty else {

            text += "  FAILED: no voltage profile for coil \(scenario.continuumCoil).\n\n"
            return (text, "transient FAILED - no voltage profile")
        }

        // HOW MUCH WINDING A "SECTION" IS. This is the thing that makes the three STME-0999 scenarios comparable or
        // not. A section is one Segment, and interleaving or shielding rebuilds the coil into TWO-disc Segments - so
        // the plain scenario's worst section voltage is across one disc while the other two are across two. Comparing
        // them directly still answers the designer's question (what does the end unit of the winding actually hold?)
        // but it is not the same amount of winding, and the report has to say so rather than leave it to be inferred
        // from a segment count in another section.
        //
        // The line-end gradient in the initial-distribution section above is the metric that IS directly comparable -
        // it is a voltage per unit of winding height, so it does not care how the coil is divided up.
        let coilSegments = await model.CoilSegments().filter({ $0.radialPos == scenario.continuumCoil })
        let discCount = coilSegments.reduce(0, { $0 + $1.basicSections.count })
        let discsPerSection = coilSegments.isEmpty ? 1 : Double(discCount) / Double(coilSegments.count)

        text += "  Sections:   \(coilSegments.count) Segments over \(discCount) discs (\(String(format: "%.2f", discsPerSection)) discs per section)\n\n"

        // Each node's worst excursion, and when it happened. The peak is tracked by absolute value but reported
        // signed, because the sign says whether a node has swung past the driven polarity - which is the interesting
        // case and the one an envelope of magnitudes hides.
        var peakVolts = [Double](repeating: 0.0, count: profile.count)
        var peakTimes = [Double](repeating: 0.0, count: profile.count)

        // The largest voltage across any single section, over the whole run. This is the turn-insulation number.
        var worstSectionDrop = 0.0
        var worstSectionIndex = 0
        var worstSectionTime = 0.0

        for nextStep in results {

            for (i, nextPoint) in profile.enumerated() {

                guard nextPoint.nodeIndex >= 0, nextPoint.nodeIndex < nextStep.volts.count else {

                    continue
                }

                let volts = nextStep.volts[nextPoint.nodeIndex]

                if abs(volts) > abs(peakVolts[i]) {

                    peakVolts[i] = volts
                    peakTimes[i] = nextStep.time
                }

                guard i > 0, profile[i - 1].nodeIndex >= 0, profile[i - 1].nodeIndex < nextStep.volts.count else {

                    continue
                }

                let drop = abs(volts - nextStep.volts[profile[i - 1].nodeIndex])

                if drop > worstSectionDrop {

                    worstSectionDrop = drop
                    worstSectionIndex = i
                    worstSectionTime = nextStep.time
                }
            }
        }

        let highest = peakVolts.enumerated().max(by: { abs($0.element) < abs($1.element) })

        if let highest {

            text += "  Highest node voltage:    \(String(format: "%.1f", highest.element / 1000.0)) kV at section \(highest.offset), t = \(String(format: "%.3f", peakTimes[highest.offset] * 1.0e6)) us"
            text += "  (\(String(format: "%.3f", highest.element / scenario.peakVoltage)) p.u.)\n"
        }

        text += "  Worst section voltage:   \(String(format: "%.1f", worstSectionDrop / 1000.0)) kV across section \(worstSectionIndex), t = \(String(format: "%.3f", worstSectionTime * 1.0e6)) us\n"
        text += "                           = \(String(format: "%.1f", worstSectionDrop / 1000.0 / discsPerSection)) kV per disc averaged over the section's \(String(format: "%.2f", discsPerSection)) discs\n"
        text += "                             (the average is NOT the internal distribution - an interleaved or shielded\n"
        text += "                              pair does not divide its voltage equally between its two discs)\n"

        // The caveat that stops this table being read as a clean bill of health on an interleaved winding. A low
        // section-to-section voltage is exactly what interleaving buys, and it is a real gain against the DISC-TO-DISC
        // stress - but it is bought by winding turns that are far apart electrically next to each other, so the
        // TURN-TO-TURN voltage inside the disc goes UP, which is why interleaved windings need heavier turn paper.
        // Nothing in this report measures that: TurnLadderModel refuses interleaved windings on purpose, because the
        // position-to-turn map is scheme-dependent and guessing it would give a confidently wrong answer.
        if let firstSegment = coilSegments.first, await firstSegment.IsInterleaved() {

            text += "\n  NOTE: this coil is interleaved, so the section voltage above is the DISC-TO-DISC stress only.\n"
            text += "        Interleaving lowers it by putting electrically distant turns side by side, which RAISES the\n"
            text += "        turn-to-turn voltage inside each disc - the reason an interleaved winding needs heavier turn\n"
            text += "        insulation. Nothing here measures that; TurnLadderModel handles continuous discs only.\n"
        }

        text += "\n"

        text += "  section   peak kV    p.u.    at t (us)\n"

        for (i, nextPeak) in peakVolts.enumerated() {

            text += String(format: "  %7d   %7.2f   %6.3f   %10.3f\n", i, nextPeak / 1000.0, nextPeak / scenario.peakVoltage, peakTimes[i] * 1.0e6)
        }

        text += "\n"

        let summary = String(format: "worst section %.1f kV over %.2f discs, peak %.3f p.u.",
                             worstSectionDrop / 1000.0, discsPerSection, (highest?.element ?? 0.0) / scenario.peakVoltage)

        return (text, summary)
    }

    // MARK: Reporting

    /// Note the step about to be attempted, and flush it.
    ///
    /// The flush is the point. The pipeline this drives raises NSAlerts on failure, and a modal alert in an app nobody
    /// is watching will sit there until the process is killed - so the last thing that reached the defaults database
    /// is the only evidence of where a hung run stopped.
    private static func Stage(_ what:String) {

        UserDefaults.standard.set(what, forKey: stageKey)
        UserDefaults.standard.synchronize()
    }

    private static func Record(report:String, summary:String, fileName:String) {

        UserDefaults.standard.set(summary, forKey: summaryKey)
        UserDefaults.standard.synchronize()

        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {

            return
        }

        // The full report goes to a file rather than to UserDefaults: it is a page or more, which `defaults read`
        // renders as one enormous escaped line. The container's Documents folder is writable without any entitlement
        // beyond the sandbox's own, which is the same reason the fixture is read from there.
        try? report.write(to: documents.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
    }

    // MARK: Formatting

    /// Metres in, millimetres out, to three decimals. Every length in the model is in metres; every length a
    /// transformer designer reads is in millimetres.
    private static func Millimetres(_ metres:Double) -> String {

        return String(format: "%.3f mm", metres * 1000.0)
    }

    private static func Farads(_ farads:Double?) -> String {

        guard let farads else {

            return "n/a"
        }

        return String(format: "%.6e F", farads)
    }
}

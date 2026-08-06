//
//  GetWoundInShieldDialog.swift
//  Rabin2021
//
//  Created by Peter Huber on 2026-08-03.
//

// Dialog for adding wound-in shields (DelVecchio ch. 12, section 12.11) to a selection of Segments.
//
// Unlike the other dialogs in this program, this one is built in code on top of an NSAlert instead of subclassing PCH_DialogBox
// with a .xib. The reason is the live readout: the whole point of choosing between DelVecchio's three shield connections is the
// trade between capacitance and the paper it costs, and that only helps if the numbers move as the user steps the shield count.
// Six labels that all recalculate on every change are far easier to keep right in code than in hand-maintained auto-layout.

import Cocoa
import PchBasePackage

@MainActor
class GetWoundInShieldDialog: NSObject {

    /// What the dialog returns: the number of shield turns per disc, and the wire (which carries the connection type and the
    /// insulation that was chosen to suit it).
    struct Result {

        let turnsPerDisc:Int
        let wire:Segment.WoundInShieldWire
    }

    // MARK: The coil's data

    /// N, the number of turns in one disc
    private let discTurns:Double
    /// The hard ceiling on the shield count. There are only N − 1 spaces between the turns of a disc.
    private let maxTurnsPerDisc:Int
    /// The working volts per turn, used to size the paper
    private let voltsPerTurn:Double
    /// τp, the two-sided paper thickness of a coil turn
    private let turnInsulation:Double
    /// The bare copper height of a coil turn, needed for the capacitance ratio
    private let bareCopperHeight:Double
    /// How many discs the user has selected, for the summary line
    private let discCount:Int

    // MARK: Controls

    private let turnsField = NSTextField(string: "")
    private let turnsStepper = NSStepper()
    private let connectionPopUp = NSPopUpButton()

    private let insulationValue = NSTextField(labelWithString: "")
    private let stressValue = NSTextField(labelWithString: "")
    private let shieldRadialValue = NSTextField(labelWithString: "")
    private let buildValue = NSTextField(labelWithString: "")
    private let capacitanceValue = NSTextField(labelWithString: "")

    /// Create the dialog. Fails if the coil cannot carry any shields at all, ie: if it has fewer than two turns per disc.
    /// - Parameter discTurns: N, turns per disc. Note that this need not be a whole number - a 250-turn, 20-disc coil gives 12.5 -
    /// so the ceiling on the shield count is floor(N) − 1.
    init?(discTurns:Double, voltsPerTurn:Double, turnInsulation:Double, bareCopperHeight:Double, discCount:Int) {

        self.discTurns = discTurns
        self.maxTurnsPerDisc = Int(discTurns.rounded(.down)) - 1
        self.voltsPerTurn = voltsPerTurn
        self.turnInsulation = turnInsulation
        self.bareCopperHeight = bareCopperHeight
        self.discCount = discCount

        guard self.maxTurnsPerDisc >= 1, voltsPerTurn > 0.0, turnInsulation > 0.0 else {

            return nil
        }

        super.init()
    }

    /// The shield count the dialog opens on. n/N ≈ 0.15 sits in the middle of the useful band: the series capacitance is linear in
    /// n, but the thing that actually matters, α = √(Cg/Cs), goes as 1/√(1 + ρn), so the marginal return falls off as n^(−3/2) and
    /// the first turn or two does most of the work. The N − 1 ceiling is a guard rail, not a target, so open on a sane value.
    private var defaultTurnsPerDisc:Int {

        return min(max(1, Int((0.15 * self.discTurns).rounded())), self.maxTurnsPerDisc)
    }

    private var selectedConnection:Segment.WoundInShieldWire.Connection {

        let index = self.connectionPopUp.indexOfSelectedItem
        let allCases = Segment.WoundInShieldWire.Connection.allCases

        return index >= 0 && index < allCases.count ? allCases[index] : .floating
    }

    private var selectedTurnsPerDisc:Int {

        return min(max(1, self.turnsStepper.integerValue), self.maxTurnsPerDisc)
    }

    private func currentWire() -> Segment.WoundInShieldWire {

        return Segment.WoundInShieldWire.Standard(connection: self.selectedConnection, maxTurnsPerDisc: self.selectedTurnsPerDisc, discTurns: self.discTurns, voltsPerTurn: self.voltsPerTurn, turnInsulation: self.turnInsulation)
    }

    /// Run the dialog. Returns nil if the user cancels.
    func runModal() -> Result? {

        let alert = NSAlert()
        alert.messageText = "Add Wound-In Shields"
        alert.informativeText = "\(self.discCount) disc\(self.discCount == 1 ? "" : "s") selected, \(self.discTurns.rounded(.down) == self.discTurns ? String(Int(self.discTurns)) : String(format: "%.1f", self.discTurns)) turns per disc. A shield turn is papered like the coil turn it sits against, and thickened further if that would leave the working stress between them above \(Int(Segment.woundInShieldMaxWorkingStress / 1000.0)) V/mm."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = self.BuildAccessoryView()

        self.UpdateReadout()

        alert.window.initialFirstResponder = self.turnsField

        guard alert.runModal() == .alertFirstButtonReturn else {

            return nil
        }

        return Result(turnsPerDisc: self.selectedTurnsPerDisc, wire: self.currentWire())
    }

    private func BuildAccessoryView() -> NSView {

        self.turnsStepper.minValue = 1
        self.turnsStepper.maxValue = Double(self.maxTurnsPerDisc)
        self.turnsStepper.increment = 1
        self.turnsStepper.valueWraps = false
        self.turnsStepper.integerValue = self.defaultTurnsPerDisc
        self.turnsStepper.target = self
        self.turnsStepper.action = #selector(self.HandleStepper(_:))

        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = NSNumber(value: self.maxTurnsPerDisc)

        self.turnsField.formatter = formatter
        self.turnsField.integerValue = self.defaultTurnsPerDisc
        self.turnsField.alignment = .right
        self.turnsField.target = self
        self.turnsField.action = #selector(self.HandleTurnsField(_:))
        self.turnsField.widthAnchor.constraint(equalToConstant: 52.0).isActive = true

        for nextCase in Segment.WoundInShieldWire.Connection.allCases {

            self.connectionPopUp.addItem(withTitle: nextCase.description)
        }

        self.connectionPopUp.selectItem(at: 0)
        self.connectionPopUp.target = self
        self.connectionPopUp.action = #selector(self.HandleConnection(_:))

        let turnsBox = NSStackView(views: [self.turnsField, self.turnsStepper])
        turnsBox.orientation = .horizontal
        turnsBox.spacing = 2.0

        let grid = NSGridView(views: [

            [NSTextField(labelWithString: "Shield turns per disc (max \(self.maxTurnsPerDisc)):"), turnsBox],
            [NSTextField(labelWithString: "Shield connection:"), self.connectionPopUp],
            [NSGridCell.emptyContentView, NSGridCell.emptyContentView],
            [NSTextField(labelWithString: "Shield insulation (2-sided):"), self.insulationValue],
            [NSTextField(labelWithString: "Turn-to-shield working stress:"), self.stressValue],
            [NSTextField(labelWithString: "Shield radial (over paper):"), self.shieldRadialValue],
            [NSTextField(labelWithString: "Added radial build per disc:"), self.buildValue],
            [NSTextField(labelWithString: "Series capacitance vs unshielded:"), self.capacitanceValue]
        ])

        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8.0
        grid.columnSpacing = 10.0

        // a plain separator between what the user sets and what falls out of it
        grid.row(at: 2).height = 6.0

        grid.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 250))
        container.addSubview(grid)

        NSLayoutConstraint.activate([

            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            grid.topAnchor.constraint(equalTo: container.topAnchor),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        container.layoutSubtreeIfNeeded()
        container.frame = NSRect(x: 0, y: 0, width: max(400.0, grid.fittingSize.width), height: grid.fittingSize.height)

        return container
    }

    @objc private func HandleStepper(_ sender:Any) {

        self.turnsField.integerValue = self.turnsStepper.integerValue
        self.UpdateReadout()
    }

    @objc private func HandleTurnsField(_ sender:Any) {

        // the formatter bounds the field, but clamp anyway so the stepper and the field can never disagree
        self.turnsStepper.integerValue = min(max(1, self.turnsField.integerValue), self.maxTurnsPerDisc)
        self.turnsField.integerValue = self.turnsStepper.integerValue
        self.UpdateReadout()
    }

    @objc private func HandleConnection(_ sender:Any) {

        self.UpdateReadout()
    }

    private func UpdateReadout() {

        let n = self.selectedTurnsPerDisc
        let connection = self.selectedConnection
        let wire = self.currentWire()

        // The copper-to-copper gap is one half-wrap from the coil turn and one from the shield turn, which with the two-sided
        // convention used throughout is exactly ½(τp + τw).
        let gap = 0.5 * (self.turnInsulation + wire.insulation)
        let vMax = connection.maxTurnToShieldVoltage(turnsPerDisc: n, discTurns: self.discTurns, voltsPerTurn: self.voltsPerTurn)
        let stress = gap > 0.0 ? vMax / gap : 0.0

        let ratio = Segment.WoundInShieldCapacitanceRatio(turnsPerDisc: n, discTurns: self.discTurns, connection: connection, turnInsulation: self.turnInsulation, shieldInsulation: wire.insulation, bareCopperHeight: self.bareCopperHeight)

        self.insulationValue.stringValue = String(format: "%.3f mm  (%.4f in)", wire.insulation * 1000.0, wire.insulation / meterPerInch)
        self.stressValue.stringValue = String(format: "%.0f V/mm  (%.0f V across %.3f mm)", stress / 1000.0, vMax, gap * 1000.0)
        self.shieldRadialValue.stringValue = String(format: "%.3f mm  (%.4f in)", wire.overPaperRadial * 1000.0, wire.overPaperRadial / meterPerInch)
        self.buildValue.stringValue = String(format: "%.2f mm  (%.4f in)", Double(n) * wire.overPaperRadial * 1000.0, Double(n) * wire.overPaperRadial / meterPerInch)
        self.capacitanceValue.stringValue = String(format: "× %.1f", ratio)
    }
}

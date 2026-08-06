//
//  StressReportWindow.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2026-08-05.
//
//  The ranked table of dielectric stress findings produced by DielectricStress.Report.
//
//  There is no .xib for this one, for the same reason GetWoundInShieldDialog has none: the window is a single table with ten
//  columns and nothing else, and keeping ten columns and their sort descriptors right in hand-maintained auto-layout is more work
//  and more breakage than building them in code.
//
//  One column carries a margin and one does not, and that asymmetry is deliberate. The AVERAGE field is judged against DelVecchio
//  chapter 13's impulse breakdown level for the governing layer's own thickness, times a design margin. The CORNER column is an
//  enhancement ratio, because chapter 13's data are uniform-gap measurements compared against average fields, so there is no
//  sourced criterion for a corner peak - see DielectricStress.Evaluate.
//
//  Rows rank on the average-field utilization, which is what lets an oil duct, a paper gap and a creep path - which fail at very
//  different stresses, and whose allowables have different distance exponents - be compared on one scale.
//

import Cocoa
import PchBasePackage

@MainActor
class StressReportWindow:NSWindowController {

    /// The findings, in the order currently displayed.
    private var checks:[DielectricStress.StressCheck]

    private let tableView = NSTableView()
    private let summaryLabel = NSTextField(labelWithString: "")

    /// The columns, in display order. The identifier doubles as the sort key.
    private enum Column:String, CaseIterable {

        case kind = "Kind"
        case location = "Location"
        case deltaV = "ΔV (kV)"
        case time = "Time (µs)"
        case path = "Layer/path (mm)"
        case material = "Material"
        case averageField = "Avg (kV/mm)"
        case averageMargin = "% of allowable"
        case peakField = "Corner (kV/mm)"
        case peakMargin = "Corner enh."

        /// Right-align everything numeric.
        var isNumeric:Bool {

            switch self {

            case .kind, .location, .material: return false
            default: return true
            }
        }
    }

    init(checks:[DielectricStress.StressCheck], title:String) {

        // Already worst-first out of DielectricStress.Scan, but sort again so this class does not depend on that.
        self.checks = checks.sorted { $0.worstUtilization > $1.worstUtilization }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = title
        window.setFrameAutosaveName("StressReportWindow")

        super.init(window: window)

        BuildContent()
    }

    required init?(coder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }

    private func BuildContent() {

        guard let window = self.window else {

            return
        }

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        // The summary line. It says how many findings are over their allowable, because that is the first thing anyone wants to know
        // and scanning a 500-row table for it is no way to find out.
        let over = checks.filter { $0.worstUtilization > 1.0 }.count
        let close = checks.filter { $0.worstUtilization > 0.8 && $0.worstUtilization <= 1.0 }.count

        summaryLabel.stringValue = "\(checks.count) locations checked — \(over) over allowable, \(close) within 20% of it. Allowables are DelVecchio ch. 13 impulse breakdown levels at each layer's own thickness, times a \(Int(DielectricStress.StressAllowable.designMargin * 100))% design margin. The corner column is an enhancement ratio, not a margin: ch. 13 has no criterion for a corner peak."
        summaryLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        summaryLabel.lineBreakMode = .byWordWrapping
        summaryLabel.maximumNumberOfLines = 2
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        for column in Column.allCases {

            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.rawValue
            tableColumn.width = column == .location ? 400 : (column == .kind ? 140 : 115)
            tableColumn.minWidth = 60
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: false)
            tableView.addTableColumn(tableColumn)
        }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.rowSizeStyle = .default
        tableView.sortDescriptors = [NSSortDescriptor(key: Column.averageMargin.rawValue, ascending: false)]

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(summaryLabel)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([

            summaryLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            summaryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            summaryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        window.contentView = contentView
    }

    // MARK: Formatting

    /// The text for one cell.
    private func Text(for check:DielectricStress.StressCheck, column:Column) -> String {

        switch column {

        case .kind:
            return check.kind.rawValue

        case .location:
            return check.location

        case .deltaV:
            return String(format: "%.2f", check.deltaV / 1000.0)

        case .time:
            // A negative time marks the t = 0+ capacitive distribution, which is not a point on the simulation's grid.
            return check.isAtCapacitiveDistribution ? "t = 0+" : String(format: "%.3f", check.time * 1.0E6)

        case .path:
            return String(format: "%.3f", check.pathLength * 1000.0)

        case .material:
            return check.material.rawValue

        case .averageField:
            return String(format: "%.2f", check.averageField / 1.0E6)

        case .averageMargin:
            return String(format: "%.0f%%", check.averageUtilization * 100.0)

        case .peakField:
            // Creep rows leave this empty rather than showing a number that would not mean anything - a tangential stress along a
            // surface has no conductor corner to concentrate at.
            guard let peak = check.peakField else { return "—" }
            return String(format: "%.2f", peak / 1.0E6)

        case .peakMargin:
            // Deliberately an enhancement RATIO and not a percentage of an allowable: chapter 13 has no criterion for a corner
            // peak, so there is nothing to take a percentage of. See DielectricStress.Evaluate.
            guard let enhancement = check.cornerEnhancement else { return "—" }
            return String(format: "%.2fx", enhancement)
        }
    }

    /// The colour for a utilization figure: over allowable is an error, close to it is a warning.
    private func Colour(forUtilization utilization:Double) -> NSColor {

        if utilization > 1.0 {

            return NSColor.systemRed
        }

        if utilization > 0.8 {

            return NSColor.systemOrange
        }

        return NSColor.labelColor
    }

    /// The value a column sorts on. Text columns sort lexically; everything else sorts on the underlying number so that, for
    /// instance, "9.5" does not come after "10.2".
    private func SortKey(for check:DielectricStress.StressCheck, column:Column) -> (number:Double?, text:String?) {

        switch column {

        case .kind: return (nil, check.kind.rawValue)
        case .location: return (nil, check.location)
        case .material: return (nil, check.material.rawValue)
        case .deltaV: return (abs(check.deltaV), nil)
        case .time: return (check.time, nil)
        case .path: return (check.pathLength, nil)
        case .averageField: return (check.averageField, nil)
        case .averageMargin: return (check.averageUtilization, nil)
        case .peakField: return (check.peakField ?? -1.0, nil)
        case .peakMargin: return (check.cornerEnhancement ?? -1.0, nil)
        }
    }
}

// MARK: - NSTableViewDataSource

extension StressReportWindow:NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {

        return checks.count
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {

        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              let column = Column(rawValue: key) else {

            return
        }

        checks.sort { lhs, rhs in

            let a = SortKey(for: lhs, column: column)
            let b = SortKey(for: rhs, column: column)

            if let an = a.number, let bn = b.number {

                return descriptor.ascending ? an < bn : an > bn
            }

            let at = a.text ?? ""
            let bt = b.text ?? ""

            return descriptor.ascending ? at < bt : at > bt
        }

        tableView.reloadData()
    }
}

// MARK: - NSTableViewDelegate

extension StressReportWindow:NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {

        guard let tableColumn = tableColumn,
              let column = Column(rawValue: tableColumn.identifier.rawValue),
              row >= 0, row < checks.count else {

            return nil
        }

        let check = checks[row]

        let identifier = tableColumn.identifier
        let cell:NSTableCellView

        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {

            cell = reused
        }
        else {

            cell = NSTableCellView()
            cell.identifier = identifier

            let field = NSTextField(labelWithString: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            field.lineBreakMode = .byTruncatingTail
            cell.addSubview(field)
            cell.textField = field

            NSLayoutConstraint.activate([

                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        guard let field = cell.textField else {

            return cell
        }

        field.stringValue = Text(for: check, column: column)
        field.alignment = column.isNumeric ? .right : .left

        // Colour only the two margin columns. Colouring the whole row would make a table where most rows are fine look alarming,
        // and the margin is the number the colour is actually about.
        switch column {

        case .averageMargin:
            field.textColor = Colour(forUtilization: check.averageUtilization)

        case .peakMargin:
            // No colour here - an enhancement ratio is not a margin, so colouring it would imply a pass/fail it does not carry.
            field.textColor = check.cornerEnhancement == nil ? NSColor.secondaryLabelColor : NSColor.labelColor

        case .peakField:
            field.textColor = check.peakField == nil ? NSColor.secondaryLabelColor : NSColor.labelColor

        default:
            field.textColor = NSColor.labelColor
        }

        return cell
    }
}

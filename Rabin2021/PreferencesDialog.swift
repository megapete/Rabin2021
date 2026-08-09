//
//  PreferencesDialog.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2026-08-09.
//
//  The Preferences… dialog (⌘,). Like GetWoundInShieldDialog, this is an NSAlert with an accessory view built in code rather
//  than a PCH_DialogBox subclass with a .xib - here because the whole point is that it is GENERATED: it walks
//  `Preference.allCases` and builds a row per preference from that preference's `Kind`. There is no list of controls to keep in
//  step with the list of preferences, and adding a preference needs no work in this file at all. See the header of
//  Preferences.swift.
//
//  The live values are held in `edited` and updated as the user types, rather than being read out of the controls when OK is
//  clicked. A text field that is still being edited when a modal alert's OK button is hit has not necessarily committed its
//  value to the cell, so reading the control at the end can silently discard the user's last keystrokes.
//

import Cocoa

@MainActor
class PreferencesDialog:NSObject, NSTextFieldDelegate {

    /// What the user has set so far, seeded with what is currently stored. This - not the controls - is what OK applies.
    private var edited:[Preference:Preference.Value] = [:]

    /// The control built for each preference, so that "Restore Defaults" can push new values back into them.
    private var controls:[Preference:NSControl] = [:]

    /// Run the dialog.
    /// - Returns: the preferences whose values actually changed (an empty set if the user clicked OK without moving anything),
    /// or nil if the user cancelled.
    func runModal() -> Set<Preference>? {

        for preference in Preference.allCases {

            self.edited[preference] = Preferences.ValueOf(preference)
        }

        let alert = NSAlert()
        alert.messageText = "Preferences"
        alert.informativeText = "These are stored in User Defaults and apply to every model from now on."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = self.BuildAccessoryView()

        if let first = Preference.allCases.first, let control = self.controls[first] {

            alert.window.initialFirstResponder = control
        }

        guard alert.runModal() == .alertFirstButtonReturn else {

            return nil
        }

        var changed:Set<Preference> = []

        for preference in Preference.allCases {

            guard let newValue = self.edited[preference], newValue != Preferences.ValueOf(preference) else {

                continue
            }

            Preferences.SetValue(newValue, of: preference)
            changed.insert(preference)
        }

        return changed
    }

    // MARK: Building the view

    private func BuildAccessoryView() -> NSView {

        var rows:[[NSView]] = []

        for preference in Preference.allCases {

            let definition = preference.definition
            let control = self.BuildControl(for: preference)

            self.controls[preference] = control

            let title = NSTextField(labelWithString: definition.title)

            let explanation = NSTextField(wrappingLabelWithString: definition.explanation)
            explanation.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            explanation.textColor = .secondaryLabelColor
            explanation.preferredMaxLayoutWidth = PreferencesDialog.explanationWidth
            explanation.isSelectable = false

            rows.append([title, control])
            rows.append([NSGridCell.emptyContentView, explanation])
            rows.append([NSGridCell.emptyContentView, NSGridCell.emptyContentView])
        }

        let restoreButton = NSButton(title: "Restore Defaults", target: self, action: #selector(self.HandleRestoreDefaults(_:)))
        restoreButton.bezelStyle = .rounded
        rows.append([NSGridCell.emptyContentView, restoreButton])

        let grid = NSGridView(views: rows)

        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.rowSpacing = 6.0
        grid.columnSpacing = 10.0

        // the blank row that separates one preference from the next
        for rowIndex in stride(from: 2, to: 3 * Preference.allCases.count, by: 3) {

            grid.row(at: rowIndex).height = 6.0
        }

        grid.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: PreferencesDialog.dialogWidth, height: 120.0))
        container.addSubview(grid)

        NSLayoutConstraint.activate([

            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            grid.topAnchor.constraint(equalTo: container.topAnchor),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        container.layoutSubtreeIfNeeded()
        container.frame = NSRect(x: 0, y: 0, width: max(PreferencesDialog.dialogWidth, grid.fittingSize.width), height: grid.fittingSize.height)

        return container
    }

    /// How wide the explanation text is allowed to run before it wraps.
    private static let explanationWidth = 320.0
    /// The minimum width of the accessory view. The grid is allowed to be wider if a control needs it.
    private static let dialogWidth = 460.0

    /// The control that edits one preference. Add a case here (and to `ValueOfControl`) when a new `Preference.Kind` is added.
    private func BuildControl(for preference:Preference) -> NSControl {

        switch preference.definition.kind {

        case .number(let minimum, let maximum, let decimals):

            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimum = NSNumber(value: minimum)
            formatter.maximum = NSNumber(value: maximum)
            formatter.minimumFractionDigits = decimals
            formatter.maximumFractionDigits = decimals

            let field = NSTextField(string: "")
            field.formatter = formatter
            field.alignment = .right
            field.delegate = self
            field.widthAnchor.constraint(equalToConstant: 72.0).isActive = true

            if case .number(let current) = Preferences.ValueOf(preference) {

                field.doubleValue = current
            }

            return field

        case .flag:

            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(self.HandleControlChanged(_:)))
            button.state = Preferences.Flag(preference) ? .on : .off

            return button
        }
    }

    /// What a control currently holds, in the form its preference expects. Nil if the field cannot be read as a number, which
    /// is what an empty or half-typed field looks like - the caller keeps the previous value in that case.
    private func ValueOfControl(_ control:NSControl, for preference:Preference) -> Preference.Value? {

        switch preference.definition.kind {

        case .number:

            // Parse with the field's own formatter rather than with Double(_:) so that a locale using a comma for the decimal
            // separator reads the same way it displays.
            guard let field = control as? NSTextField else { return nil }

            if let formatter = field.formatter as? NumberFormatter, let number = formatter.number(from: field.stringValue) {

                return .number(number.doubleValue)
            }

            return nil

        case .flag:

            guard let button = control as? NSButton else { return nil }

            return .flag(button.state == .on)
        }
    }

    // MARK: Actions

    /// A checkbox (or any control with a target/action) moved.
    @objc private func HandleControlChanged(_ sender:Any) {

        guard let control = sender as? NSControl else { return }

        self.RecordValue(of: control)
    }

    /// A text field is being typed in. This is why the dialog does not read its controls at OK time - see the file header.
    func controlTextDidChange(_ obj:Notification) {

        guard let control = obj.object as? NSControl else { return }

        self.RecordValue(of: control)
    }

    private func RecordValue(of control:NSControl) {

        for (preference, aControl) in self.controls where aControl === control {

            if let value = self.ValueOfControl(control, for: preference) {

                self.edited[preference] = value
            }
        }
    }

    @objc private func HandleRestoreDefaults(_ sender:Any) {

        for preference in Preference.allCases {

            let factoryDefault = preference.definition.factoryDefault

            self.edited[preference] = factoryDefault

            guard let control = self.controls[preference] else { continue }

            switch factoryDefault {

            case .number(let number): (control as? NSTextField)?.doubleValue = number
            case .flag(let flag): (control as? NSButton)?.state = flag ? .on : .off
            }
        }
    }
}

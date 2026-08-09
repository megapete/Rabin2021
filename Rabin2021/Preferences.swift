//
//  Preferences.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2026-08-09.
//
//  The user-settable preferences, and the one place that knows how they are stored.
//
//  HOW TO ADD A PREFERENCE
//
//   1. Add a case to `Preference`. Its raw value IS the User Defaults key, so it has to be unique, and it must not change once
//      it has shipped - renaming a key silently resets that preference for anyone who had already set it.
//   2. Add the matching case to the switch in `Preference.definition`. That switch is exhaustive, so the compiler will not let
//      you forget it, and everything else follows from what is written there: `PreferencesDialog` walks `Preference.allCases`
//      and builds a control from the `Kind`, and `RegisterFactoryDefaults` walks the same list.
//   3. Only if it needs a control that does not exist yet: add a `Kind` case, then handle it in `PreferencesDialog.BuildControl`
//      and `PreferencesDialog.ValueOfControl`. Those two switches are exhaustive as well.
//
//  Nothing else needs touching - in particular there is no list of preferences in the UI to keep in step with this one.
//
//  WHY THERE IS NO CACHE. Every read goes to `UserDefaults.standard`, which keeps its own in-memory copy, so a read is a
//  dictionary lookup. Nothing here sits in a loop that would notice: the hottest reader is the dielectric screen, and it asks
//  once per layer per site (hundreds of times per report), not once per time step. A cache would need invalidation and its own
//  synchronization, because these are read from NONISOLATED code - see `DielectricStress.StressAllowable.Strike`, which runs
//  wherever `DielectricStress.Scan` was called from. UserDefaults is thread-safe; a bare global would not be.
//

import Foundation

/// One user-settable preference. The raw value is its User Defaults key.
enum Preference:String, CaseIterable, Sendable {

    /// The fraction of DelVecchio's 50%-probability breakdown levels that the dielectric stress screen treats as allowable.
    case dielectricDesignMargin = "PCH_RABIN2021_DielectricDesignMargin"
}

extension Preference {

    /// What one preference is, what it is worth out of the box, and what kind of control edits it.
    struct Definition:Sendable {

        /// The label to the left of the control.
        let title:String
        /// The note under the control. Say what the value does and where it came from: this is the only documentation the user
        /// gets, and a preference nobody understands is worse than a hard-coded constant.
        let explanation:String
        /// What kind of value it holds, which is also what control the dialog builds for it.
        let kind:Kind
        /// What a fresh install gets, and what "Restore Defaults" puts back.
        let factoryDefault:Value
    }

    /// The kinds of value a preference can hold. Add to this only when a preference actually needs it.
    enum Kind:Sendable {

        /// A real number, edited in a text field. The bounds clamp the field AND whatever is already in User Defaults - a
        /// `defaults write` from a shell can put any number at all in there, including one that would break a calculation.
        case number(minimum:Double, maximum:Double, decimals:Int)

        /// A yes/no, edited with a checkbox.
        case flag
    }

    /// The value of a preference. Always matches its `Kind` - see `Preferences.ValueOf(_:)`.
    enum Value:Sendable, Equatable {

        case number(Double)
        case flag(Bool)

        /// The form that goes into User Defaults.
        var asPropertyList:Any {

            switch self {

            case .number(let number): return number
            case .flag(let flag): return flag
            }
        }
    }

    /// Everything the rest of the program knows about this preference.
    var definition:Definition {

        switch self {

        case .dielectricDesignMargin:

            return Definition(title: "Dielectric design margin:",
                              explanation: "The fraction of the breakdown level that the dielectric stress report is allowed to use. DelVecchio ch. 13's breakdown data are 50%-probability levels (p.368: \"some margin below these levels would be needed in actual design\"), and the book's own Figure 13.5 example is drawn with a 20% margin, ie: 0.80. Every utilization in the report scales as 1/margin, so this moves the pass/fail line - it cannot change the worst-first ranking.",
                              kind: .number(minimum: 0.10, maximum: 1.00, decimals: 2),
                              factoryDefault: .number(0.65))
        }
    }
}

/// The preference store: reads, writes, and the factory defaults. See the header of this file to add a preference.
enum Preferences {

    // MARK: Reading

    /// The current value of a preference, clamped to its definition.
    ///
    /// The returned case always matches the preference's `Kind`, whatever is actually in User Defaults - a missing key, a value
    /// of the wrong type, or a number outside the bounds all fall back or clamp rather than propagate.
    static func ValueOf(_ preference:Preference) -> Preference.Value {

        let definition = preference.definition
        let stored = UserDefaults.standard.object(forKey: preference.rawValue) as? NSNumber

        switch definition.kind {

        case .number(let minimum, let maximum, _):

            let raw:Double

            if let stored {

                raw = stored.doubleValue
            }
            else if case .number(let factory) = definition.factoryDefault {

                raw = factory
            }
            else {

                raw = minimum
            }

            return .number(min(max(raw, minimum), maximum))

        case .flag:

            if let stored {

                return .flag(stored.boolValue)
            }
            else if case .flag(let factory) = definition.factoryDefault {

                return .flag(factory)
            }

            return .flag(false)
        }
    }

    /// The value of a `.number` preference. Returns 0 if asked for a preference that is not a number, which is a programming
    /// error rather than a state the user can get into.
    static func Number(_ preference:Preference) -> Double {

        guard case .number(let number) = ValueOf(preference) else {

            return 0.0
        }

        return number
    }

    /// The value of a `.flag` preference. Returns false if asked for a preference that is not a flag.
    static func Flag(_ preference:Preference) -> Bool {

        guard case .flag(let flag) = ValueOf(preference) else {

            return false
        }

        return flag
    }

    // MARK: Writing

    /// Store a new value for a preference. A number is clamped to its definition's bounds on the way in, so nothing downstream
    /// has to re-check it.
    static func SetValue(_ value:Preference.Value, of preference:Preference) {

        var toStore = value

        if case .number(let minimum, let maximum, _) = preference.definition.kind, case .number(let number) = value {

            toStore = .number(min(max(number, minimum), maximum))
        }

        UserDefaults.standard.set(toStore.asPropertyList, forKey: preference.rawValue)
    }

    /// Put every preference back to its factory default.
    ///
    /// This REMOVES the keys rather than writing the defaults into them, so a preference the user never touched again will
    /// follow any future change to its factory default instead of being pinned to today's value.
    static func RestoreFactoryDefaults() {

        for preference in Preference.allCases {

            UserDefaults.standard.removeObject(forKey: preference.rawValue)
        }
    }

    /// Register the factory defaults with User Defaults. Called once, at launch, from `AppDelegate`.
    ///
    /// `ValueOf(_:)` falls back to the factory default on its own, so nothing here depends on this having been called - it is
    /// done anyway so that the values show up in `defaults read com.huberistech.rabin2021` and can be overridden for one run
    /// from the command line (`-PCH_RABIN2021_DielectricDesignMargin 0.8`), which is how the self-test harness reaches them.
    static func RegisterFactoryDefaults() {

        var factoryDefaults:[String:Any] = [:]

        for preference in Preference.allCases {

            factoryDefaults[preference.rawValue] = preference.definition.factoryDefault.asPropertyList
        }

        UserDefaults.standard.register(defaults: factoryDefaults)
    }

    // MARK: Self-check

    /// A runnable self-check for the store, run by hand because this program has no test target. Same pattern as
    /// `DielectricStress.VerifySelf()`: call it once from `AppDelegate.applicationDidFinishLaunching`
    ///
    ///     Preferences.VerifySelf()
    ///
    /// and read it back with
    ///
    ///     defaults read com.huberistech.rabin2021 PreferencesVerification
    ///
    /// It asserts the things that adding a preference could break, and it asserts them for EVERY case in `Preference`, so a new
    /// preference is covered the moment it is added:
    ///
    ///  1. The factory default is of the same kind as the definition says (a `.number` kind with a `.flag` default would make
    ///     `Number(_:)` return 0, which is a plausible-looking wrong answer rather than a crash).
    ///  2. The factory default lies inside its own bounds.
    ///  3. A value survives a write and a read.
    ///  4. A value outside the bounds is clamped rather than stored as given, which is what a `defaults write` from a shell can
    ///     hand it.
    ///  5. `RestoreFactoryDefaults` really does restore.
    ///
    /// Whatever the user had set is saved and put back before this returns, including the distinction between "set to the
    /// factory value" and "never set" - those are different states, since only the second one follows a future change to the
    /// factory default.
    static func VerifySelf() {

        var report:[String] = []
        var failures = 0

        func check(_ what:String, _ passed:Bool, _ detail:String = "") {

            if !passed { failures += 1 }
            report.append("\(passed ? "PASS" : "FAIL") \(what)\(detail.isEmpty ? "" : " (\(detail))")")
        }

        // save the user's world. An array of pairs rather than a dictionary: a [Preference:Any?] would have to distinguish a
        // stored nil from an absent key, which is exactly the distinction Swift dictionaries make hard to see.
        let saved:[(preference:Preference, value:Any?)] = Preference.allCases.map { ($0, UserDefaults.standard.object(forKey: $0.rawValue)) }

        for preference in Preference.allCases {

            let definition = preference.definition

            switch (definition.kind, definition.factoryDefault) {

            case (.number(let minimum, let maximum, _), .number(let factory)):

                check("\(preference.rawValue) factory default is in range", factory >= minimum && factory <= maximum, String(format: "%.3f in [%.3f, %.3f]", factory, minimum, maximum))

                // a round trip through User Defaults
                let probe = (minimum + maximum) / 2.0
                SetValue(.number(probe), of: preference)
                check("\(preference.rawValue) round trips", abs(Number(preference) - probe) < 1.0E-12, String(format: "%.6f", Number(preference)))

                // and a value the user could only get there with a 'defaults write'
                SetValue(.number(maximum * 10.0 + 1.0), of: preference)
                check("\(preference.rawValue) clamps high", Number(preference) <= maximum, String(format: "%.3f", Number(preference)))

                UserDefaults.standard.set(minimum - 1.0, forKey: preference.rawValue)
                check("\(preference.rawValue) clamps low on read", Number(preference) >= minimum, String(format: "%.3f", Number(preference)))

            case (.flag, .flag(let factory)):

                SetValue(.flag(!factory), of: preference)
                check("\(preference.rawValue) round trips", Flag(preference) == !factory)

            default:

                check("\(preference.rawValue) factory default matches its kind", false, "a \(definition.kind) preference cannot have that default")
            }

            // and back to the factory value
            RestoreFactoryDefaults()
            check("\(preference.rawValue) restores to factory", ValueOf(preference) == definition.factoryDefault, "\(ValueOf(preference))")
        }

        // put the user's world back exactly as it was
        for (preference, value) in saved {

            if let value {

                UserDefaults.standard.set(value, forKey: preference.rawValue)
            }
            else {

                UserDefaults.standard.removeObject(forKey: preference.rawValue)
            }
        }

        report.insert(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED", at: 0)
        report.append("current dielectric design margin: \(dielectricDesignMargin)")

        UserDefaults.standard.set(report, forKey: "PreferencesVerification")
        UserDefaults.standard.synchronize()
    }

    // MARK: Named accessors
    //
    // One per preference, so that call sites read as physics rather than as string lookups.

    /// The fraction of the ch. 13 breakdown levels the dielectric screen may use. See
    /// `DielectricStress.StressAllowable.designMargin`, which is where the calculation picks it up.
    static var dielectricDesignMargin:Double {

        return Number(.dielectricDesignMargin)
    }
}

//
//  ShowWaveFormsDialog.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-02-16.
//

import Cocoa
import PchBasePackage
import PchDialogBoxPackage

class ShowWaveFormsDialog: PCH_DialogBox {
    
    @IBOutlet weak var showVoltagesCheckBox: NSButton!
    @IBOutlet weak var showCurrentsCheckBox: NSButton!
    @IBOutlet weak var showFourierCheckBox: NSButton!
    
    @IBOutlet weak var coilPicker: NSPopUpButton!
    
    @IBOutlet weak var allSegmentsRadioButton: NSButton!
    @IBOutlet weak var rangeOfSegmentsRadioButton: NSButton!
    
    @IBOutlet weak var rangeFromPicker: NSPopUpButton!
    @IBOutlet weak var rangeToPicker: NSPopUpButton!
    
    var currentCoilSelection = 0
    
    let numCoils:Int

    /// Each coil's segments as a range of INDICES INTO PhaseModel.CoilSegments(), which is what the caller slices with the range
    /// this dialog produces.
    ///
    /// This used to be `highestSections`, an array of GetHighestSection(coil:) values, and the dialog rebuilt the flat offsets
    /// itself by summing `highestSections[c - 1] + 1` over the previous coils. Both halves of that were wrong once any Segment held
    /// more than one BasicSection: GetHighestSection returns an axial COORDINATE - the pristine design-file disc index, never
    /// renumbered - not a count. Interleaving the first 6 discs of a 20-disc coil leaves 17 Segments whose top one still reports
    /// axialPos 19, so the pickers offered 20 section numbers for 17 Segments and the range ran off the end of CoilSegments().
    /// Taking the ranges from PhaseModel.SegmentRange(coil:) removes the duplicated arithmetic entirely.
    let coilRanges:[ClosedRange<Int>]

    var segmentRange:Range<Int> {

        let coilSelected = coilPicker.indexOfSelectedItem
        let coilBase = coilRanges[coilSelected].lowerBound

        return (coilBase + rangeFromPicker.indexOfSelectedItem)..<(coilBase + rangeToPicker.indexOfSelectedItem + 1)
    }

    init(numCoils:Int, coilRanges:[ClosedRange<Int>]) {

        self.numCoils = numCoils
        self.coilRanges = coilRanges

        super.init(viewNibFileName: "ShowWaveFormsView", windowTitle: "Show Waveforms", hideCancel: false)
    }
    
    // awakeFromNib() is 'nonisolated' on NSObject, so assume main-actor isolation explicitly (nib
    // loading always happens on the main thread) before touching any of the outlets.
    override func awakeFromNib() {

        MainActor.assumeIsolated {

            coilPicker.removeAllItems()
            // let segments = phaseModel.CoilSegments()
            // let numCoils = segments.last!.radialPos + 1
            var coilNames:[String] = []
            for i in 1...numCoils {

                coilNames.append("\(i)")
            }
            coilPicker.addItems(withTitles: coilNames)
            coilPicker.selectItem(at: 0)

            var segNames:[String] = []

            // The pickers offer one entry per SEGMENT of the coil, and their indices are offsets into coilRanges[c] - see
            // segmentRange. The names are 1-based purely for display.
            for i in 1...coilRanges[0].count {

                segNames.append("\(i)")
            }

            rangeFromPicker.removeAllItems()
            rangeToPicker.removeAllItems()

            rangeFromPicker.addItems(withTitles: segNames)
            rangeToPicker.addItems(withTitles: segNames)

            rangeFromPicker.selectItem(at: 0)
            rangeToPicker.selectItem(at: coilRanges[0].count - 1)

            rangeFromPicker.isEnabled = false
            rangeToPicker.isEnabled = false
        }
    }
    
    @IBAction func handleSegmentSelection(_ sender: Any) {
        
        if allSegmentsRadioButton.state == .on {
            
            rangeFromPicker.isEnabled = false
            rangeToPicker.isEnabled = false
        }
        else {
            
            rangeFromPicker.isEnabled = true
            rangeToPicker.isEnabled = true
        }
    }
    
    @IBAction func handleCoilSelection(_ sender: Any) {
        
        let coilSelected = coilPicker.indexOfSelectedItem
        
        // we only do all this if the user has changed the coil selection
        if coilSelected != currentCoilSelection {
            
            let newCoilSegCount = coilRanges[coilSelected].count

            var segNames:[String] = []
            for i in 1...newCoilSegCount {

                segNames.append("\(i)")
            }

            rangeFromPicker.removeAllItems()
            rangeToPicker.removeAllItems()

            rangeFromPicker.addItems(withTitles: segNames)
            rangeToPicker.addItems(withTitles: segNames)

            rangeFromPicker.selectItem(at: 0)
            rangeToPicker.selectItem(at: newCoilSegCount - 1)
            
            currentCoilSelection = coilSelected
        }
    }
    
    @IBAction func handleFromSegmentSelection(_ sender: Any) {
        
        if rangeFromPicker.indexOfSelectedItem > rangeToPicker.indexOfSelectedItem {
            
            rangeToPicker.selectItem(at: rangeFromPicker.indexOfSelectedItem)
        }
    }
    
    @IBAction func handleToSegmentSelection(_ sender: Any) {
        
        if rangeToPicker.indexOfSelectedItem < rangeFromPicker.indexOfSelectedItem {
            
            rangeFromPicker.selectItem(at: rangeToPicker.indexOfSelectedItem)
        }
    }
    
}

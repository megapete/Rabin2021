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

    let phaseModel:PhaseModel
    let simModel:SimulationModel
    
    @IBOutlet weak var showVoltagesCheckBox: NSButton!
    @IBOutlet weak var showCurrentsCheckBox: NSButton!
    @IBOutlet weak var showFourierCheckBox: NSButton!
    
    @IBOutlet weak var coilPicker: NSPopUpButton!
    
    @IBOutlet weak var allSegmentsRadioButton: NSButton!
    @IBOutlet weak var rangeOfSegmentsRadioButton: NSButton!
    
    @IBOutlet weak var rangeFromPicker: NSPopUpButton!
    @IBOutlet weak var rangeToPicker: NSPopUpButton!
    
    var currentCoilSelection = 0
    
    var segmentRange:Range<Int> {
        
        let coilSelected = coilPicker.indexOfSelectedItem
        
        do {
            
            let coilBase = coilSelected == 0 ? 0 : try phaseModel.SegmentRange(coil: coilSelected - 1).upperBound + 1
            
            return (coilBase + rangeFromPicker.indexOfSelectedItem)..<(coilBase + rangeToPicker.indexOfSelectedItem + 1)
        }
        catch {
            
            PCH_ErrorAlert(message: error.localizedDescription)
            return 0..<0
        }
    }
    
    init?(phaseModel:PhaseModel, simModel:SimulationModel) {
        
        guard let pmM = phaseModel.M, pmM.rows == simModel.M.rows, let pmC = phaseModel.C, pmC.rows == simModel.baseC.rows else {
            
            PCH_ErrorAlert(message: "Phase Model and Simuation Model are different!")
            return nil
        }
        
        self.phaseModel = phaseModel
        self.simModel = simModel
        
        super.init(viewNibFileName: "ShowWaveFormsView", windowTitle: "Show Waveforms", hideCancel: false)
    }
    
    override func awakeFromNib() {
        
        coilPicker.removeAllItems()
        let segments = phaseModel.CoilSegments()
        let numCoils = segments.last!.radialPos + 1
        var coilNames:[String] = []
        for i in 1...numCoils {
            
            coilNames.append("\(i)")
        }
        coilPicker.addItems(withTitles: coilNames)
        coilPicker.selectItem(at: 0)
        
        var segNames:[String] = []
        if let lastSeg = try? phaseModel.GetHighestSection(coil: 0) {
            
            for i in 1...lastSeg+1 {
                
                segNames.append("\(i)")
            }
            
            rangeFromPicker.removeAllItems()
            rangeToPicker.removeAllItems()
            
            rangeFromPicker.addItems(withTitles: segNames)
            rangeToPicker.addItems(withTitles: segNames)
            
            rangeFromPicker.selectItem(at: 0)
            rangeToPicker.selectItem(at: lastSeg-1)
            
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
            
            guard let newCoilLastSeg = try? phaseModel.GetHighestSection(coil: coilSelected) else {
                
                ALog("Well that shouldn't happen...")
                PCH_ErrorAlert(message: "An impossible error has occurred!")
                return
            }
            
            var segNames:[String] = []
            for i in 1...newCoilLastSeg + 1 {
                
                segNames.append("\(i)")
            }
            
            rangeFromPicker.removeAllItems()
            rangeToPicker.removeAllItems()
            
            rangeFromPicker.addItems(withTitles: segNames)
            rangeToPicker.addItems(withTitles: segNames)
            
            rangeFromPicker.selectItem(at: 0)
            rangeToPicker.selectItem(at: newCoilLastSeg)
            
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

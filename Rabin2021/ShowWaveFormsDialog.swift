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
    
    @IBOutlet weak var coilPicker: NSPopUpButton!
    
    @IBOutlet weak var allSegmentsRadioButton: NSButton!
    @IBOutlet weak var rangeOfSegmentsRadioButton: NSButton!
    
    @IBOutlet weak var rangeFromPicker: NSPopUpButton!
    @IBOutlet weak var rangeToPicker: NSPopUpButton!
    
    
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
            
            rangeFromPicker.selectItem(at: 0)
            rangeToPicker.selectItem(at: lastSeg)
        }
        
        
    }
    
}

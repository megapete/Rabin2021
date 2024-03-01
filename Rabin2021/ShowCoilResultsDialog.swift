//
//  ShowCoilResultsDialog.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-02-29.
//

import Cocoa
import PchBasePackage
import PchDialogBoxPackage

class ShowCoilResultsDialog: PCH_DialogBox {
    
    @IBOutlet weak var voltagesCheckBox: NSButton!
    @IBOutlet weak var currentsCheckBox: NSButton!
    @IBOutlet weak var animationTimeTextField: NSTextField!
    @IBOutlet weak var coilPicker: NSPopUpButton!
    
    let phaseModel:PhaseModel
    let simModel:SimulationModel
    
    init?(phaseModel:PhaseModel, simModel:SimulationModel) {
        
        guard let pmM = phaseModel.M, pmM.rows == simModel.M.rows, let pmC = phaseModel.C, pmC.rows == simModel.baseC.rows else {
            
            PCH_ErrorAlert(message: "Phase Model and Simuation Model are different!")
            return nil
        }
        
        self.phaseModel = phaseModel
        self.simModel = simModel
        
        super.init(viewNibFileName: "ShowCoilResultsView", windowTitle: "Show Results", hideCancel: false)
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
        
        let timeFormatter = NumberFormatter()
        timeFormatter.maximumFractionDigits = 0
        animationTimeTextField.formatter = timeFormatter
        
    }
}

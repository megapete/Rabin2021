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
    let numCoils:Int
    
    //let phaseModel:PhaseModel
    //let simModel:SimulationModel
    
    init?(numCoils:Int) {
        
        self.numCoils = numCoils
        
        super.init(viewNibFileName: "ShowCoilResultsView", windowTitle: "Show Results", hideCancel: false)
    }
    
    override func awakeFromNib() {
        
        coilPicker.removeAllItems()
        
        // Task {
            
            //let segments = await phaseModel.CoilSegments()
            //let numCoils = segments.last!.radialPos + 1
            var coilNames:[String] = []
            for i in 1...self.numCoils {
                
                coilNames.append("\(i)")
            }
            coilPicker.addItems(withTitles: coilNames)
            coilPicker.selectItem(at: 0)
        // }
        
        let timeFormatter = NumberFormatter()
        timeFormatter.maximumFractionDigits = 0
        animationTimeTextField.formatter = timeFormatter
        
    }
}

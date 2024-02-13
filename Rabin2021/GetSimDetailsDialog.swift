//
//  GetSimDetailsDialog.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-02-13.
//

import Cocoa
import PchDialogBoxPackage

class SimDetailsDlog : PCH_DialogBox {
    
    @IBOutlet weak var waveFormPopUp: NSPopUpButton!
    @IBOutlet weak var voltageField: NSTextField!
    
    var waveFormStrings:[String]
    
    init(waveFormStrings:[String]) {
        
        self.waveFormStrings = waveFormStrings
        
        super.init(viewNibFileName: "GetSimDetailsView", windowTitle: "Simulation Setup", hideCancel: false)
    }
    
    override func awakeFromNib() {
        
        waveFormPopUp.removeAllItems()
        waveFormPopUp.addItems(withTitles: waveFormStrings)
        
        voltageField.formatter = NumberFormatter()
        voltageField.integerValue = 30
    }
    
}

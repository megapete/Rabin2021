//
//  CoilResultsDisplayWindow.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-02-29.
//

import Cocoa
import PchBasePackage

class CoilResultsDisplayWindow: NSWindowController {

    @IBOutlet weak var coilResultsView: CoilResultsDisplayView!
    
    var windowTitle:String = "Results"
    
    /// If true, display the voltages, otherwise display the amps
    var showVoltages:Bool = true
    
    /// The count of xDimensions must equal either the count of the 'voltages' member of resultData or the count of the 'amps' member of resultData, depending on the setting of 'showVoltages'.
    var xDimensions:[Double] = []
    var resultData:AppController.SimulationResults? = nil
    
    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        
        if let mainScreen = NSScreen.main {
            
            if let mainScreenResolution = mainScreen.deviceDescription[.resolution] as? NSSize {
                
                // the resolution is in dots/inch in the two directions (which will probably be different)
                self.coilResultsView.screenRes = mainScreenResolution
                // print("Screen resolution: \(mainScreenResolution)")
            }
            else {
                
                DLog("Couldn't get screen resolution")
            }
        }
        else {
            
            DLog("Couldn't get main screen")
        }
        
        if let wfWindow = window {
            
            wfWindow.title = windowTitle
        }
        
        coilResultsView.wantsLayer = true
        coilResultsView.layer?.backgroundColor = .black
        
        if let results = resultData, !results.stepResults.isEmpty {
            
            if showVoltages {
                
                guard xDimensions.count == results.stepResults.first!.volts.count else {
                    
                    DLog("Incompatible dimensions!")
                    return
                }
            }
        }
        else {
            
            ALog("No resultData or its step-data is empty!")
            return
        }
        
        coilResultsView.UpdateScaleAndZoomWindow()
        
    }
    
}

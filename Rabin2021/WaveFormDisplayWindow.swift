//
//  WaveFormDisplayWindow.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-02-13.
//

import Cocoa
import PchBasePackage

class WaveFormDisplayWindow: NSWindowController {

    @IBOutlet weak var waveFormView: WaveFormDisplayView!
    
    var data:[[NSPoint]] = []
    var windowTitle:String = "Waveforms"
    
    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        if let mainScreen = NSScreen.main {
            
            if let mainScreenResolution = mainScreen.deviceDescription[.resolution] as? NSSize {
                
                // the resolution is in dots/inch in the two directions (which will probably be different)
                self.waveFormView.screenRes = mainScreenResolution
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
        
        waveFormView.wantsLayer = true
        waveFormView.layer?.backgroundColor = .black
        
        waveFormView.RemoveAllDataSeries()
        
        for nextDataSeries in data {
            
            waveFormView.AddDataSeries(newData: nextDataSeries)
        }
        
        waveFormView.UpdateScaleAndZoomWindow()
    }
    
}

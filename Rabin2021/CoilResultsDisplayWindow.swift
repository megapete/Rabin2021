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
    
    @IBOutlet weak var startButton: NSButton!
    @IBOutlet weak var stopButton: NSButton!
    @IBOutlet weak var continuePauseButton: NSButton!
    
    var simTimeBrackets:ClosedRange<Double> = ClosedRange(uncheckedBounds: (0.0, 0.0))
    var currentSimTime:Double = 0.0
    var currentSimIndex:Int = 0
    var simIsRunning:Bool = false
    var simIsPaused:Bool = false
    
    var simTimer:Timer? = nil
    var animationTimeInterval:TimeInterval = 0.05 // default to updating the waveform every 20th of a second.
    var animationStride:Int = 1
    
    var windowTitle:String = "Results"
    
    /// If true, display the voltages, otherwise display the amps
    var showVoltages:Bool = true
    
    /// The count of xDimensions must equal either the count of the 'voltages' member of resultData or the count of the 'amps' member of resultData, depending on the setting of 'showVoltages'.
    /// - Note: These dimensions correspond to the height of the nodes/discs. They should be in mm.
    var xDimensions:[Double] = []
    var resultData:AppController.SimulationResults? = nil
    
    var heightMultiplier:Double = 1.0
    
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
        
        var extremaRect = NSRect(x: 0, y: 0, width: 1000, height: 800)
        if let results = resultData, !results.stepResults.isEmpty {
            
            simTimeBrackets = ClosedRange(uncheckedBounds: (results.stepResults.first!.time, results.stepResults.last!.time))
            
            if showVoltages {
                
                guard xDimensions.count == results.stepResults.first!.volts.count else {
                    
                    DLog("Incompatible dimensions!")
                    return
                }
                
                let extremeVolts = results.extremeVolts
                extremaRect.size.height = extremeVolts.max - extremeVolts.min
            }
            else {
                
                guard xDimensions.count == results.stepResults.first!.amps.count else {
                    
                    DLog("Incompatible dimensions!")
                    return
                }
                
                let extremeAmps = results.extremeAmps
                extremaRect.size.height = extremeAmps.max - extremeAmps.min
            }
        }
        else {
            
            ALog("No resultData or its step-data is empty!")
            return
        }
        
        // we want to keep the NSPoints in the "low-integer" (say, 0 to 1000) range:
        let multiplier:Double = 1000.0 / extremaRect.height
        // We want to round the multiplier down to the nearest power of 10: 10^(floor(log10(x)))
        heightMultiplier = pow(10.0, floor(log10(multiplier)))
        
        extremaRect.size.height *= heightMultiplier
        
        coilResultsView.UpdateScaleAndZoomWindow(extremaRect: extremaRect)
        
        SetButtonStates()
    }
    
    func SetButtonStates() {
        
        startButton.isEnabled = !(xDimensions.isEmpty || resultData == nil || simIsRunning)
        stopButton.isEnabled = simIsRunning
        
        continuePauseButton.title = simIsPaused ? "Continue" : "Pause"
        continuePauseButton.isEnabled = simIsRunning
    }
    
    @IBAction func handleStartPushed(_ sender: Any) {
        
        currentSimIndex = 0
        currentSimTime = simTimeBrackets.lowerBound
        doStartAnimation()
    }
    
    func doStartAnimation() {
        
        guard let results = resultData else {
            
            DLog("No results")
            return
        }
        
        if let timer = simTimer {
            
            timer.invalidate()
        }
        
        simIsRunning = true
        simIsPaused = false
        
        simTimer = Timer.scheduledTimer(withTimeInterval: animationTimeInterval, repeats: true) { timer in
            
            self.UpdatePathWithCurrentSimIndex()
            self.currentSimIndex += self.animationStride
            
            if self.currentSimIndex >= results.stepResults.count {
                
                // simulation is done
                timer.invalidate()
                self.simIsRunning = false
                self.simIsPaused = false
                
                self.SetButtonStates()
            }
        }
    }
    
    @IBAction func handleStopPushed(_ sender: Any) {
        
        doStopSimulationAndReset()
    }
    
    func doStopSimulationAndReset() {
        
        // stop the simulation
        if let timer = simTimer {
            
            timer.invalidate()
        }
        
        self.simIsRunning = false
        self.simIsPaused = false
        
        self.SetButtonStates()
    }
    
    @IBAction func handleContPushed(_ sender: Any) {
        
        guard simIsRunning else {
            
            return
        }
        
        if simIsPaused {
            
            doStartAnimation()
        }
        else {
            
            if let timer = simTimer {
                
                timer.invalidate()
            }
            
            self.simIsPaused = true
            
            self.SetButtonStates()
        }
        
    }
    
    func UpdatePathWithCurrentSimIndex() {
        
        guard currentSimIndex >= 0, let results = resultData, !results.stepResults.isEmpty, currentSimIndex < results.stepResults.count else {
            
            ALog("Bad index or no results!")
            return
        }
        
        guard simIsRunning && !simIsPaused else {
            
            return
        }
        
        let step = results.stepResults[currentSimIndex]
        let newPath = NSBezierPath()
        let yMultiplier = heightMultiplier * coilResultsView.scaleMultiplier.y
        
        // in the interest of speed, we don't check that xDimensions has the correct count
        for i in 0..<xDimensions.count {
            
            var nextPoint = NSPoint(x: xDimensions[i], y: yMultiplier * (showVoltages ? step.volts[i] : step.amps[i]))
            
            if i == 0 {
                
                newPath.move(to: nextPoint)
            }
            else {
                
                newPath.line(to: nextPoint)
            }
        }
        
        coilResultsView.currentData = newPath
        coilResultsView.needsDisplay = true
    }
}

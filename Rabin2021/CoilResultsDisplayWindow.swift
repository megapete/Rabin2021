//
//  CoilResultsDisplayWindow.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-02-29.
//

import Cocoa
import PchBasePackage

class CoilResultsDisplayWindow: NSWindowController {

    override var windowNibName: String! {
        
            return "CoilResultsDisplayWindow"
    }
    
    @IBOutlet weak var coilResultsView: CoilResultsDisplayView!
    
    @IBOutlet weak var startButton: NSButton!
    @IBOutlet weak var stopButton: NSButton!
    @IBOutlet weak var continueButton: NSButton!
    
    let simTimeBrackets:ClosedRange<Double>
    private var currentSimTime:Double = 0.0
    private var currentSimIndex:Int = 0
    private var simIsRunning:Bool = false
    private var simIsPaused:Bool = false
    
    private var simTimer:Timer? = nil
    let totalAnimationTime:TimeInterval
    private var animationTimeInterval:TimeInterval = 1.0 / 50.0 // default to updating the waveform every 50th of a second.
    private var minimumAnimationTimeInterval = 1.0 / 50.0
    private var animationStride:Int = 1
    
    let windowTitle:String
    
    /// If true, display the voltages, otherwise display the amps
    let showVoltages:Bool
    
    /// The count of xDimensions must equal either the count of the 'voltages' member of resultData or the count of the 'amps' member of resultData, depending on the setting of 'showVoltages'.
    /// - Note: These dimensions correspond to the height of the nodes/discs. They should be in mm.
    let xDimensions:[Double]
    let resultData:AppController.SimulationResults
    let segmentsToDisplay:ClosedRange<Int>
    private var heightMultiplier:Double = 1.0
    
    override var acceptsFirstResponder: Bool {
        
        return true
    }
    
    init(windowTitle:String, showVoltages:Bool, xDimensions:[Double], resultData:AppController.SimulationResults, segmentsToDisplay:ClosedRange<Int>, totalAnimationTime:TimeInterval) {
        
        self.windowTitle = windowTitle
        self.xDimensions = xDimensions
        self.resultData = resultData
        self.segmentsToDisplay = segmentsToDisplay
        self.totalAnimationTime = totalAnimationTime
        self.showVoltages = showVoltages
        let timeSpan = resultData.timeSpan
        self.simTimeBrackets = ClosedRange(uncheckedBounds: (timeSpan.begin, timeSpan.end))
        
        super.init(window: nil)
    }
    
    /// We have to implement this init to create a custom initializer. It basically creates a lot of unusable ivars then calls 'super'.
    required init?(coder: NSCoder) {
        
        self.simTimeBrackets = ClosedRange(uncheckedBounds: (0,0))
        self.totalAnimationTime = 0
        self.windowTitle = ""
        self.xDimensions = []
        self.resultData = AppController.SimulationResults(waveForm: SimulationModel.WaveForm(type: .FullWave, pkVoltage: 0.0), peakVoltage: 0.0, stepResults: [])
        self.showVoltages = false
        self.segmentsToDisplay = ClosedRange(uncheckedBounds: (0,0))
        
        super.init(coder: coder)
        ALog("Unimplemented initializer")
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        
        if let mainScreen = NSScreen.main {
            
            minimumAnimationTimeInterval = mainScreen.minimumRefreshInterval
            
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
        if !resultData.stepResults.isEmpty, !segmentsToDisplay.isEmpty {
            
            // simTimeBrackets = ClosedRange(uncheckedBounds: (results.stepResults.first!.time, results.stepResults.last!.time))
            
            animationTimeInterval = totalAnimationTime / Double(resultData.stepResults.count)
            while animationTimeInterval < minimumAnimationTimeInterval {
                
                animationStride += 1
                animationTimeInterval = totalAnimationTime / Double(resultData.stepResults.count / animationStride)
            }
            
            if showVoltages {
                
                guard xDimensions.count == (segmentsToDisplay.upperBound - segmentsToDisplay.lowerBound + 2) else {
                    
                    DLog("Incompatible dimensions!")
                    return
                }
                
                let extremeVolts = resultData.ExtremeVoltsInSegmentRange(range: segmentsToDisplay)
                extremaRect.size.height = extremeVolts.max - extremeVolts.min
                extremaRect.origin.y = extremeVolts.min
            }
            else {
                
                guard xDimensions.count == (segmentsToDisplay.upperBound - segmentsToDisplay.lowerBound + 1) else {
                    
                    DLog("Incompatible dimensions!")
                    return
                }
                
                let extremeAmps = resultData.ExtremeAmpsInSegmentRange(range: segmentsToDisplay)
                extremaRect.size.height = extremeAmps.max - extremeAmps.min
                extremaRect.origin.y = extremeAmps.min
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
        
        extremaRect.origin.y *= heightMultiplier
        extremaRect.size.height *= heightMultiplier
        
        coilResultsView.UpdateScaleAndZoomWindow(extremaRect: extremaRect)
        
        SetButtonStates()
    }
    
    func SetButtonStates() {
        
        startButton.isEnabled = !(xDimensions.isEmpty || simIsRunning)
        stopButton.isEnabled = simIsRunning
        
        continueButton.title = simIsPaused ? "Continue" : "Pause"
        continueButton.isEnabled = simIsRunning
    }
    
    @IBAction func handleStartPushed(_ sender: Any) {
        
        currentSimIndex = 0
        currentSimTime = simTimeBrackets.lowerBound
        doStartAnimation()
    }
    
    func doStartAnimation() {
        
        if let timer = simTimer {
            
            timer.invalidate()
        }
        
        simIsRunning = true
        simIsPaused = false
        SetButtonStates()
        
        simTimer = Timer.scheduledTimer(withTimeInterval: animationTimeInterval, repeats: true) { timer in
                        
            self.UpdatePathWithCurrentSimIndex()
            self.currentSimIndex += self.animationStride
            
            if self.resultData.stepResults.isEmpty || self.currentSimIndex >= self.resultData.stepResults.count {
                
                self.doStopSimulationAndReset()
                return
            }
            
            self.currentSimTime = self.resultData.stepResults[self.currentSimIndex].time
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
        
        guard currentSimIndex >= 0, !resultData.stepResults.isEmpty, currentSimIndex < resultData.stepResults.count, !segmentsToDisplay.isEmpty else {
            
            ALog("Bad index or no results!")
            return
        }
        
        guard simIsRunning && !simIsPaused else {
            
            return
        }
        
        let step = resultData.stepResults[currentSimIndex]
        let newPath = NSBezierPath()
        let yMultiplier = heightMultiplier * coilResultsView.scaleMultiplier.y
        
        // in the interest of speed, we don't check that xDimensions has the correct count
        let valOffset = segmentsToDisplay.lowerBound
        for i in 0..<xDimensions.count {
            
            let nextPoint = NSPoint(x: xDimensions[i], y: yMultiplier * (showVoltages ? step.volts[i + valOffset] : step.amps[i + valOffset]))
            
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

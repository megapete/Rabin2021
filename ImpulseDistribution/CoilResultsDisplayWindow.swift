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
    let indicesToDisplay:ClosedRange<Int>

    override var acceptsFirstResponder: Bool {
        
        return true
    }
    
    init(windowTitle:String, showVoltages:Bool, xDimensions:[Double], resultData:AppController.SimulationResults, indicesToDisplay:ClosedRange<Int>, totalAnimationTime:TimeInterval) {
        
        self.windowTitle = windowTitle
        self.xDimensions = xDimensions
        self.resultData = resultData
        self.indicesToDisplay = indicesToDisplay
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
        self.indicesToDisplay = ClosedRange(uncheckedBounds: (0,0))
        
        super.init(coder: coder)
        ALog("CoilResultsDisplayWindow was created from a nib/storyboard via init?(coder:), which leaves it with empty results and a zero display range. It has to be created programmatically with the designated initializer instead.")
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        
        if let mainScreen = NSScreen.main {

            minimumAnimationTimeInterval = mainScreen.minimumRefreshInterval
        }
        else {

            DLog("Couldn't get main screen")
        }

        if let wfWindow = window {
            
            wfWindow.title = windowTitle
        }
        
        coilResultsView.wantsLayer = true
        coilResultsView.layer?.backgroundColor = .black

        // The extrema rectangle is in the data's own units: x is the coil height in mm, y is volts or amps. The view
        // takes care of scaling it for display.
        var extremaRect = NSRect(x: xDimensions.first!, y: 0, width: xDimensions.last! - xDimensions.first!, height: 800)
        if !resultData.stepResults.isEmpty, !indicesToDisplay.isEmpty {

            // simTimeBrackets = ClosedRange(uncheckedBounds: (results.stepResults.first!.time, results.stepResults.last!.time))

            animationTimeInterval = totalAnimationTime / Double(resultData.stepResults.count)
            while animationTimeInterval < minimumAnimationTimeInterval {

                animationStride += 1
                animationTimeInterval = totalAnimationTime / Double(resultData.stepResults.count / animationStride)
            }

            guard xDimensions.count == indicesToDisplay.count else {

                DLog("Incompatible dimensions!")
                return
            }

            let extremeValues = showVoltages ? resultData.ExtremeVoltsInSegmentRange(nodeRange: indicesToDisplay) : resultData.ExtremeAmpsInSegmentRange(range: indicesToDisplay)

            // Always show the zero line, so the axis runs from min(0, minimum) to max(0, maximum) - which is not the
            // same as anchoring the origin at the minimum and using the peak-to-peak value as the height.
            extremaRect.origin.y = min(0.0, extremeValues.min)
            extremaRect.size.height = max(0.0, extremeValues.max) - extremaRect.origin.y
        }
        else {

            ALog("Cannot set up the display: the simulation produced \(resultData.stepResults.count) time steps for display range \(indicesToDisplay). Both solvers return an empty array for CANCELLATION as well as for failure, so check Task.isCancelled before treating this as an error.")
            return
        }

        coilResultsView.yQuantity = showVoltages ? .voltage : .current
        coilResultsView.peakTestVoltage = resultData.peakVoltage
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
        
        // The Timer block is @Sendable and nonisolated, but the timer is scheduled on (and fires
        // from) the main runloop, so assume main-actor isolation to reach our UI state.
        simTimer = Timer.scheduledTimer(withTimeInterval: animationTimeInterval, repeats: true) { timer in

            MainActor.assumeIsolated {

                self.UpdatePathWithCurrentSimIndex()
                self.currentSimIndex += self.animationStride

                if self.resultData.stepResults.isEmpty || self.currentSimIndex >= self.resultData.stepResults.count {

                    self.doStopSimulationAndReset()
                    return
                }

                self.currentSimTime = self.resultData.stepResults[self.currentSimIndex].time
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
        
        guard currentSimIndex >= 0, !resultData.stepResults.isEmpty, currentSimIndex < resultData.stepResults.count, !indicesToDisplay.isEmpty else {
            
            ALog("Cannot update the animation path: step index \(currentSimIndex) against \(resultData.stepResults.count) time steps, display range \(indicesToDisplay). The index must be within 0..<\(resultData.stepResults.count) and the range must be non-empty.")
            return
        }
        
        guard simIsRunning && !simIsPaused else {
            
            return
        }
        
        let step = resultData.stepResults[currentSimIndex]

        // The points are handed over in their natural units (mm and volts or amps); the view scales them at draw time.
        // in the interest of speed, we don't check that xDimensions has the correct count
        let valOffset = indicesToDisplay.lowerBound
        var newData:[NSPoint] = []

        for i in 0..<xDimensions.count {

            newData.append(NSPoint(x: xDimensions[i], y: showVoltages ? step.volts[i + valOffset] : step.amps[i + valOffset]))
        }

        coilResultsView.currentData = newData
    }
}

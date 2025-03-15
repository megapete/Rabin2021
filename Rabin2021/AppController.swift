//
//  AppController.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-06.
//

// Keys into User Defaults
// Key (String) so that the user doesn't have to go searching for the last folder he opened
private let LAST_OPENED_INPUT_FILE_KEY = "PCH_RABIN2021_LastInputFile"

let PCH_RABIN2021_IterationCount = 200

let PCH_CIR_FILETYPE = "cir"

var rb2021_progressIndicatorWindow:PCH_ProgressIndicatorWindow? = nil

import Cocoa
import Accelerate
import UniformTypeIdentifiers
@preconcurrency import ComplexModule
import RealModule
import PchBasePackage
import PchMatrixPackage
import PchExcelDesignFilePackage
import PchDialogBoxPackage
import PchProgressIndicatorPackage
import PchFiniteElementPackage

extension PchMatrix {
    
    func SubMatrix(rowRange:Range<Int>, colRange:Range<Int>) async -> PchMatrix? {
        
        guard !rowRange.isEmpty && !colRange.isEmpty else {
            
            return nil
        }
        
        // clamp the range extrema to the actual matrix dimensions
        let minRow = max(0, rowRange.lowerBound)
        let minCol = max(0, colRange.lowerBound)
        let maxRow = min(rowRange.upperBound, self.rows)
        let maxCol = min(colRange.upperBound, self.columns)
        
        let subMatrix = PchMatrix(matrixType: .general, numType: self.numType, rows: UInt(maxRow - minRow), columns: UInt(maxCol - minCol))
        
        var newI = 0
        for i in minRow..<maxRow {
            
            var newJ = 0
            for j in minCol..<maxCol {
                
                if self.numType == .Double {
                    
                    if let newValue:Double = self[i, j]  {
                        
                        await subMatrix.SetDoubleValue(value: newValue, row: newI, col: newJ)
                        // subMatrix[newI, newJ] = newValue
                    }
                }
                else {
                    
                    if let newValue:Complex = self[i, j] {
                        
                        await subMatrix.SetComplexValue(value: newValue, row: newI, col: newJ)
                        // subMatrix[newI, newJ] = newValue
                    }
                }
                
                newJ += 1
            }
            
            newI += 1
        }
        
        return subMatrix
    }
}

@MainActor
class AppController: NSObject, NSMenuItemValidation, NSWindowDelegate/*, PchFePhaseDelegate*/ {
    
    
    /// The main window of the program
    @IBOutlet weak var mainWindow: NSWindow!
    
    /// The transformer view
    @IBOutlet weak var txfoView: TransformerView!
    
    /// Menu items (for valiidation)
    /// Zooming
    @IBOutlet weak var zoomInMenuItem: NSMenuItem!
    @IBOutlet weak var zoomOutMenuItem: NSMenuItem!
    @IBOutlet weak var zoomRectMenuItem: NSMenuItem!
    @IBOutlet weak var zoomAllMenuItem: NSMenuItem!
    /// Winding / Segment menus
    @IBOutlet weak var showWdgAsSingleSegmentMenuItem: NSMenuItem!
    @IBOutlet weak var combineSegmentsIntoSingleSegmentMenuItem: NSMenuItem!
    @IBOutlet weak var interleaveSelectionMenuItem: NSMenuItem!
    @IBOutlet weak var splitSegmentToBasicSectionsMenuItem: NSMenuItem!
    
    /// Static RIngs
    @IBOutlet weak var staticRingOverMenuItem: NSMenuItem!
    @IBOutlet weak var staticRingBelowMenuItem: NSMenuItem!
    @IBOutlet weak var removeStaticRingMenuItem: NSMenuItem!
    /// Radial Shield
    @IBOutlet weak var radialShieldInsideMenuItem: NSMenuItem!
    @IBOutlet weak var removeRadialShieldMenuItem: NSMenuItem!
    
    /// Connections
    @IBOutlet weak var addImpulseMenuItem: NSMenuItem!
    @IBOutlet weak var addGroundMenuItem: NSMenuItem!
    @IBOutlet weak var addConnectionMenuItem: NSMenuItem!
    @IBOutlet weak var removeConnectionMenuItem: NSMenuItem!
    
    /// Save matrices
    @IBOutlet weak var saveMmatrixMenuItem: NSMenuItem!
    @IBOutlet weak var saveUnfactoredMmatrixMenuItem: NSMenuItem!
    @IBOutlet weak var saveBmatrixMenuItem: NSMenuItem!
    
    @IBOutlet weak var saveBaseCmatrixMenuItem: NSMenuItem!
    @IBOutlet weak var saveFixedCmatrixMenuItem: NSMenuItem!
    
    /// Saving files
    @IBOutlet weak var saveAsCirFileMenuItem: NSMenuItem!
    
    /// Simulation
    @IBOutlet weak var createSimModelMenuItem: NSMenuItem!
    @IBOutlet weak var simulateMenuItem: NSMenuItem!
    @IBOutlet weak var showWaveformsMenuItem: NSMenuItem!
    @IBOutlet weak var showCoilResultsMenuItem: NSMenuItem!
    @IBOutlet weak var showVoltageDiffsMenuItem: NSMenuItem!
    
    /// Inductance Calculations
    @IBOutlet weak var mainWdgInductanceMenuItem: NSMenuItem!
    @IBOutlet weak var mainWdgImpedanceMenuItem: NSMenuItem!
    
    /// R and Z indication on the main window
    @IBOutlet weak var rLocationTextField: NSTextField!
    @IBOutlet weak var zLocationTextField: NSTextField!
    
    /// Mode indicator
    @IBOutlet weak var modeIndicatorTextField: NSTextField!
    
    /// Inductance calculation indicators
    @IBOutlet weak var inductanceLight: NSTextField!
    @IBOutlet weak var indCalcProgInd: NSProgressIndicator!
    @IBOutlet weak var workingLabel: NSTextField!
    
    /// Window controller to display graphs
    // var graphWindowCtrl:PCH_GraphingWindow? = nil
    
    /// The current basic sections that are loaded in memory
    var currentSections:[BasicSection] = []
    
    /// The current model that is stored in memory. This is what is actually displayed in the TransformerView and what all calculations are performed upon.
    var currentModel:PhaseModel? = nil
    
    /// Simulation calculation indicators
    @IBOutlet weak var simulationLight: NSTextField!
    @IBOutlet weak var simCalcProgInd: NSProgressIndicator!
    
    /// The current simulation model that is stored in memory
    var currentSimModel:SimulationModel? = nil
    
    struct SimulationResults {
        
        let waveForm:SimulationModel.WaveForm
        let peakVoltage:Double
        let stepResults:[SimulationModel.SimulationStepResult]
        
        var numSteps:Int {
            
            get {
                
                return stepResults.count
            }
        }
        
        var timeSpan:(begin:Double, end:Double) {
            
            get {
                
                guard let beginTime = stepResults.first?.time, let endTime = stepResults.last?.time else {
                    
                    DLog("No results!")
                    return (begin:Double.greatestFiniteMagnitude, end:-Double.greatestFiniteMagnitude)
                }
                
                return (beginTime, endTime)
            }
        }
        
        var extremeVolts:(min:Double, max:Double) {
            
            get {
                
                let nodeRange:ClosedRange<Int> = 0...stepResults[0].volts.count-1
                
                return ExtremeVoltsInSegmentRange(nodeRange: nodeRange)
            }
        }
        
        var extremeAmps:(min:Double, max:Double) {
            
            get {
                
                var result = (min:Double.greatestFiniteMagnitude, max:-Double.greatestFiniteMagnitude)
                for nextStep in stepResults {
                    
                    result.min = min(nextStep.amps.min()!, result.min)
                    result.max = max(nextStep.amps.max()!, result.max)
                }
                
                return result
            }
        }
        
        func ampsFor(segment:Int) -> [Double] {
            
            guard segment <= stepResults[0].amps.count else {
                
                DLog("Illegal segment number!")
                return []
            }
            
            var result:[Double] = []
            for nextStep in stepResults {
                
                result.append(nextStep.amps[segment])
            }
            
            return result
        }
        
        func ExtremeVoltsInSegmentRange(nodeRange:ClosedRange<Int>) -> (min:Double, max:Double) {
            
            var result = (min:Double.greatestFiniteMagnitude, max:-Double.greatestFiniteMagnitude)
            for nextStep in stepResults {
                
                let segVolts = nextStep.volts[nodeRange]
                result.min = min(segVolts.min()!, result.min)
                result.max = max(segVolts.max()!, result.max)
            }
            
            return result
        }
        
        func ExtremeAmpsInSegmentRange(range:ClosedRange<Int>) -> (min:Double, max:Double) {
            
            var result = (min:Double.greatestFiniteMagnitude, max:-Double.greatestFiniteMagnitude)
            for nextStep in stepResults {
                
                let segAmps = nextStep.amps[range]
                result.min = min(segAmps.min()!, result.min)
                result.max = max(segAmps.max()!, result.max)
            }
            
            return result
        }
        
        struct Location:Hashable {
            
            let row:Int
            let col:Int
        }
        
        // If forRange is nil, the entire simulation result is used (ie: all the results at all the time steps). The range is clamped to the size of the volts array in stepResults
        func MaximumInternodalVoltages(forRange:ClosedRange<Int>? = nil) async -> PchMatrix {
            
            guard let firstResult = stepResults.first, !firstResult.volts.isEmpty else {
                
                return PchMatrix(rows: UInt(0), columns: UInt(0))
            }
            
            let lowNode = max(0, forRange?.lowerBound ?? 0)
            let highNode = min(firstResult.volts.count - 1, forRange?.upperBound ?? firstResult.volts.count - 1)
            
            if highNode - lowNode == 0 {
                
                return PchMatrix(rows: UInt(0), columns: UInt(0))
            }
            
            let nodeRange = ClosedRange(uncheckedBounds: (lowNode, highNode))
            
            var result:[Location:Double] = [:]
            var firstTimeThrough = true
            for nextResult in stepResults {
                
                let nextInterVolts = InternodalVoltages(volts: Array(nextResult.volts[nodeRange]))
                
                if firstTimeThrough {
                    
                    result = nextInterVolts
                    firstTimeThrough = false
                }
                else {
                    
                    for (location, value) in nextInterVolts {
                        
                        let prevMax = result[location]!
                        
                        if value > prevMax {
                            
                            result[location] = value
                        }
                        
                    }
                }
            }
            
            let dimension = UInt(highNode - lowNode + 1)
            let matrix = PchMatrix(matrixType: .symmetric, numType: .Double, rows: dimension, columns:dimension)
            
            for (location, value) in result {
                
                await matrix.SetDoubleValue(value: value, row: location.row, col: location.col)
            }
            
            return matrix
        }
        
        func InternodalVoltages(volts:[Double]) -> [Location:Double] {
            
            let dimension = volts.count
            
            var result:[Location:Double] = [:]
            for col in 0..<volts.count {
                
                // get the value in the col index just once
                let voltsCol = volts[col]
                for row in col+1..<volts.count {
                    
                    result[Location(row: row, col: col)] = abs(voltsCol - volts[row])
                }
            }
            
            return result
        }
        
    }
    
    /// Coil Results windows
    var coilResultsWindow:CoilResultsDisplayWindow? = nil
    // var voltageDiffsWindow:PchMatrixViewWindow? = nil
    
    /// The result of the latest simulation run that was executed
    var latestSimulationResult:SimulationResults? = nil
    
    /// The current FE model that is stored in memory (this is required becuase the inductance calcualtion takes really long and so is put into a different thread)
    var currentFePhase:PchFePhase? = nil
    
    /// The current core in memory
    var currentCore:Core? = nil
    
    /// The original xlFile used to create the current sections (originally, at least, the only way to create the Basic Sections is by importing an XL file.
    var currentXLfile:PCH_ExcelDesignFile? = nil
    
    /// The theoretical depth of the tank (used for display and ground capacitance calculations)
    var tankDepth:Double = 0.0
    
    /// The current multiplier for window height (used for old-style inductance calculations)
    var currentWindowMultiplier = 1.0
    
    /// The colors of the different layers (for display purposes only)
    static let segmentColors:[NSColor] = [.red, .blue, .orange, .purple, .yellow]
    
    /// The inductance calculation for the current model has ben done
    var inductanceIsValid:Bool = false
    
    /// The capacitance calculation for the current model has been done
    var capacitanceIsValid:Bool = false
    
    var designIsValid:Bool {
        
        get {
            
            return inductanceIsValid && capacitanceIsValid
        }
    }
    
    // MARK: Initialization
    override func awakeFromNib() {
        
        txfoView.appController = self
        
        rb2021_progressIndicatorWindow = PCH_ProgressIndicatorWindow()
        
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        
        self.rLocationTextField.formatter = formatter
        self.zLocationTextField.formatter = formatter
        
        self.rLocationTextField.doubleValue = 0
        self.zLocationTextField.doubleValue = 0
        
        self.inductanceLight.textColor = .red
        self.inductanceIsValid = false
        self.indCalcProgInd.isHidden = true
        // self.indCalcProgInd.minValue = 0.0
        // self.indCalcProgInd.maxValue = 100.0
        self.simulationLight.textColor = .red
        self.simCalcProgInd.isHidden = true
        self.workingLabel.isHidden = true
    }
    
    func InitializeController()
    {
        
    }
    
    // MARK: Long-running function completion routine(s)
    
    func didFinishInductanceCalculation() async {
        
        // the '===' operator compares references
        guard let fePhase = self.currentFePhase else {
            
            DLog("PchFePhase does not match the one in memory!")
            return
        }
        
        DLog("Got inductance completion message!")
        self.inductanceLight.textColor = await fePhase.inductanceMatrix != nil ? .green : .red
        
        self.indCalcProgInd.stopAnimation(self)
        self.indCalcProgInd.isHidden = true
        if self.latestSimulationResult != nil {
            
            self.simulationLight.textColor = .yellow
        }
        // only hide the "Working..." label if the simulation calculation is not currently running
        self.workingLabel.isHidden = self.simCalcProgInd.isHidden
        
        guard let model = self.currentModel, let feIndMatrix = await fePhase.inductanceMatrix else {
            
            DLog("Model is nil or matrix is invalid (or nil)!")
            return
        }
        
        DLog("Energy (from Inductance): \(await fePhase.EnergyFromInductance())")
        
        do {
            
            let unfactoredM = await PchMatrix(srcMatrix: feIndMatrix)
            let M = try await feIndMatrix.FactorizedAs(.Cholesky)
            await model.SetInductanceMatrices(unfactoreM: unfactoredM, M:M)
            inductanceIsValid = true
        }
        catch {
            
            let alert = NSAlert(error: error)
            let _ = alert.runModal()
            return
        }
    }
    
    func didFinishSimulationRun() async {
        
        DLog("Got simulation-run completion message!")
        
        self.simulationLight.textColor = latestSimulationResult != nil ? .green : .red
        
        self.simCalcProgInd.stopAnimation(self)
        self.simCalcProgInd.isHidden = true
        // only hide the "Working..." label if the inductance calculation is not currently running
        self.workingLabel.isHidden = self.indCalcProgInd.isHidden
    }
    
    /*
    func updatePuCompletedInductanceCalculation(puComplete: Double, phase: PchFePhase) async {
        
        // the '===' operator compares references
        guard let fePhase = self.currentFePhase, fePhase === phase else {
            
            DLog("PchFePhase does not match the one in memory!")
            return
        }
        
        self.indCalcProgInd.doubleValue = puComplete * 100.0
    } */
    
    // MARK: Transformer update routines
    
    /// Function to update the model. If the 'reinitialize' parameter is 'true', then the 'oldSegments' and 'newSegments' parameters are ignored and a new model is created using the xlFile. _It is assumed that oldSegments and newSegments are contiguous and in correct order_. In general, it is assumed that one of either oldSegments or newSegments has only a single member in it.
    /// - Parameter oldSegments: An array of Segments that are to be removed from the model. Must be contiguous and in order.
    /// - Parameter newSegments: An array of Segments to insert into the model. Must be contiguous and in order.
    /// - Parameter xFile: The ExcelDesignFile that was inputted. If this is non-nil and 'reinitialize' is set to true, the existing model is overwtitten using the contents of the file.
    /// - Parameter reinitialize: Boolean value set to true if the entire memory should be reinitialized. If xlFile is non-nil, the it is used to overwrite the exisitng model. Otherwise, the model is reinitialized using the BasicSections in the AppController's currentSections array.
    func updateModel(oldSegments:[Segment], newSegments:[Segment], xlFile:PCH_ExcelDesignFile?, reinitialize:Bool) async {
        
        if reinitialize {
            
            if let file = xlFile {
                
                self.tankDepth = file.tankDepth
                
                // The idea here is to create the current model as a Core and an array of BasicSections and save it into the class' currentSections property
                self.currentCore = Core(diameter: file.core.diameter, realWindowHeight: file.core.windowHeight, legCenters: file.core.legCenters)
                
                // replace any currently saved basic sections with the new ones
                self.currentSections = self.createBasicSections(xlFile: file)
                
                self.currentXLfile = file
            }
            
            if self.currentSections.count == 0 {
                
                PCH_ErrorAlert(message: "There are no basic sections!", info: nil)
            }
            
            // initialize the model so that all the BasicSections are modeled
            self.currentModel = await self.initializeModel(basicSections: self.currentSections)
            
            self.initializeViews()
        }
        else {
            
            guard let model = self.currentModel else {
                
                PCH_ErrorAlert(message: "The model does not exist!", info: "Cannot change segments")
                return
            }
            
            await model.RemoveSegments(badSegments: oldSegments)
            
            do {
                
                try await model.UpdateConnectors(oldSegments: oldSegments, newSegments: newSegments)
                
                try await model.AddSegments(newSegments: newSegments)
            }
            catch {
                
                let alert = NSAlert(error: error)
                let _ = alert.runModal()
                return
            }
        }
        
        guard let model = self.currentModel, let excelFile = self.currentXLfile else {
            
            PCH_ErrorAlert(message: "The model and/or Excel file do/does not exist!", info: "Impossible to continue!")
            return
        }
        
        inductanceIsValid = false
        capacitanceIsValid = false
        
        guard let fePhase = await CreateFePhase(xlFile: excelFile, model: model) else {
            
            PCH_ErrorAlert(message: "Could not create finite element model!")
            return
        }
        
        self.currentFePhase = fePhase
        
        // To calculate the eddy losses, we need to make some assumptions regarding the amp-turn distribution. The method used here should be considered _temporary_. It would be better to have the program analyze the current connections (as selected by the user) and figure out the voltages and kVA.
        // For now, we will assume the following:
        // 1. Separate windings with the same terminal number are assumed to be 'main' windings (higher kVA) and 'tapping' windings (lower kVA)
        //    1a) The tap will be the one where the tapping winding has the same current direction as the main winding (this will cause small (I think) errors depending on the actual tap selected by the user)
        //    1b) For double-stacked windings, it is assumed that they will be connected in parallel
        // 2. The nominal transformer kVA will be equal to the full kVA of terminal 2
        // 3. If there is a 3rd (or 4th...) terminal make sure that its kVA is correctly set. It is assumed that the kVA of non-Terminal-2 windings are negative with respect to Terminal 2 and that the total amp-turns equal 0.
        // 4. Volts/Turn is selected from the sum of voltages of terminal 2 divided by the sum of turns of terminal 2
        // 5. Terminal number greater than 2 have only a SINGLE COIL associated with them
        var refKVA = 0.0
        var terms:Set<Int> = []
        for nextWinding in excelFile.windings {
            
            if nextWinding.terminal.terminalNumber == 0 {
                
                continue
            }
            
            if nextWinding.terminal.terminalNumber == 2 {
                
                refKVA += nextWinding.terminal.kVA
            }
            
            terms.insert(nextWinding.terminal.terminalNumber)
        }
        
        guard terms.count >= 2 else {
            
            PCH_ErrorAlert(message: "Not enough terminals!")
            return
        }
        
        guard refKVA > 0 else {
            
            PCH_ErrorAlert(message: "No winding has been assigned to terminal number 2!")
            return
        }
        
        // the index into these arrays is the terminal number minus 1
        var term2volts:Double = 0.0
        var turns:[Double] = Array(repeating: 0.0, count: terms.count)
        for nextTerm in terms {
            
            for nextWinding in excelFile.windings {
                
                if nextWinding.terminal.terminalNumber == nextTerm {
                    
                    let wdgTurns = nextWinding.numTurns.max // / (nextWinding.isDoubleStack ? 2.0 : 1.0)
                    turns[nextTerm - 1] += wdgTurns
                    
                    if nextTerm == 2 {
                        
                        let phFactor = nextWinding.terminal.connection == .wye ? SQRT3 : 1.0
                        let wdgVolts = nextWinding.terminal.lineVolts / phFactor // / (nextWinding.isDoubleStack ? 2.0 : 1.0)
                        term2volts += wdgVolts
                    }
                }
            }
        }
        
        let voltsPerTurn = term2volts / turns[1]
        
        var kvas:[Double] = Array(repeating: 0.0, count: terms.count)
        kvas[1] = refKVA
        var otherTermskVA = refKVA
        var otherTerms = terms
        otherTerms.remove(1)
        otherTerms.remove(2)
        while otherTerms.count > 0 {
            
            let nextTerm = otherTerms.first!
                
            for nextWdg in excelFile.windings {
                
                if nextWdg.terminal.terminalNumber == nextTerm {
                    
                    kvas[nextTerm - 1] = nextWdg.terminal.kVA
                    otherTermskVA -= nextWdg.terminal.kVA
                    otherTerms.remove(nextTerm)
                    break
                }
            }
        }
        
        kvas[0] = otherTermskVA
        var currents:[Double] = Array(repeating: 0.0, count: terms.count)
        
        for nextTerm in terms {
            
            let voltage = turns[nextTerm - 1] * voltsPerTurn
            currents[nextTerm - 1] = kvas[nextTerm - 1] * 1000.0 / Double(excelFile.numPhases) / voltage
        }
        
        var firstSegmentIndex = 0
        for wdgIndex in 0..<excelFile.windings.count {
            
            do {
                
                let lastSegmentIndex = try await model.GetHighestSection(coil: wdgIndex) + firstSegmentIndex
                for segIndex in firstSegmentIndex...lastSegmentIndex {
                    
                    let currentDirection = excelFile.windings[wdgIndex].terminal.terminalNumber == 2 ? -1.0 : 1.0
                    // let currentDivider = excelFile.windings[wdgIndex].isDoubleStack ? 2.0 : 1.0
                    await fePhase.SetSeriesRmsCurrentForSection(segIndex, rmsAmps: Complex(currents[excelFile.windings[wdgIndex].terminal.terminalNumber - 1] * currentDirection))
                    // fePhase.window.sections[segIndex].seriesRmsCurrent = Complex(currents[excelFile.windings[wdgIndex].terminal.terminalNumber - 1] * currentDirection) // / currentDivider)
                }
                
                firstSegmentIndex = lastSegmentIndex + 1
            }
            catch {
                
                let alert = NSAlert(error: error)
                let _ = alert.runModal()
                return
            }
        }
        
        do {
            
            let fullMesh = try await fePhase.GetFullModelAndSolve()
            DLog("Energy (mesh): \(await fullMesh.MagneticEnergy())")
            DLog("Energy (phase): \(await fePhase.MagneticEnergy(useMesh: fullMesh))")
        }
        catch {
            
            let alert = NSAlert(error: error)
            let _ = alert.runModal()
            return
        }
        
        
        guard await fePhase.GetEddyLosses() else {
            
            PCH_ErrorAlert(message: "Could not get eddy losses!")
            return
        }
        
        for i in await 0..<model.segments.count {
            
            let axialPU = await fePhase.window.sections[i].eddyLossDueToAxialFlux / fePhase.window.sections[i].resistiveLoss
            let radialPU = await fePhase.window.sections[i].eddyLossDueToRadialFlux / fePhase.window.sections[i].resistiveLoss
            await model.segments[i].SetEddyLossesPU(radial: radialPU, axial: axialPU)
            
        }
        
        self.inductanceLight.textColor = .red
        self.workingLabel.isHidden = false
        self.indCalcProgInd.isHidden = false
        self.indCalcProgInd.startAnimation(self)
        // self.indCalcProgInd.doubleValue = 0.0
        
        do {
        
            try await fePhase.CalculateInductanceMatrix(useConcurrency: true, assumeSymmetric: true)
            
            guard let indMatrix = await fePhase.inductanceMatrix else {
                
                PCH_ErrorAlert(message: "An impossible error has occurred!")
                return
            }
            
            await model.SetInductanceMatrices(unfactoreM: indMatrix, M: try await indMatrix.FactorizedAs(.Cholesky))
        
            await didFinishInductanceCalculation()
            
            try await model.CalculateCapacitanceMatrix()
            capacitanceIsValid = true
            // DLog("Coil 0 Cs: \(try model.CoilSeriesCapacitance(coil: 0))")
            // DLog("Coil 1 Cs: \(try model.CoilSeriesCapacitance(coil: 1))")
        }
        catch {
            
            let alert = NSAlert(error: error)
            let _ = alert.runModal()
            return
        }
        
        if !reinitialize {
            
            self.updateViews()
        }
    }
    
    /// Initialize the model using the BasicSections already created. If currentXLFile is non-nil, some extra initialziation is done _USING THAT FILE_. **If this behaviour is not desired, set currentXLFile to nil before calling this function.** If there is already a model in memory, it is lost.
    func initializeModel(basicSections:[BasicSection]) async -> PhaseModel?
    {
        // a transformer needs at least two basic sections, so...
        guard basicSections.count > 1 else {
            
            return nil
        }
        
        var result:[Segment] = []
        
        Segment.resetSerialNumber()
        
        let numCoils = BasicSection.NumberOfCoils(basicSections: basicSections)
        
        guard numCoils > 0 else {
            
            return nil
        }
        
        for coil in 0..<numCoils {
            
            var coilIsDoubleStack = false
            var coilHasEmbeddedTaps = false
            
            // locations are the basicSection index immediately UNDER the pertinent gap
            var centerGapLocation = -1
            var lowerGapLocation = -1
            var upperGapLocation = -1
            
            if let xlFile = self.currentXLfile {
                
                let wdg = xlFile.windings[coil]
                coilIsDoubleStack = wdg.isDoubleStack
                coilHasEmbeddedTaps = wdg.numTurns.max != wdg.numTurns.nom || wdg.numTurns.min != wdg.numTurns.nom
                let numDiscs = wdg.numAxialSections
                
                // use != for XOR
                if coilIsDoubleStack != coilHasEmbeddedTaps {
                    
                    centerGapLocation = numDiscs / 2 - 1
                }
                
                // only cut the upper and lower gaps if the coil is double-stacked AND has taps
                if coilIsDoubleStack && coilHasEmbeddedTaps {
                    
                    lowerGapLocation = numDiscs / 4 - 1
                    upperGapLocation = numDiscs * 3 / 4 - 1
                }
            }
            
            let axialIndices = BasicSection.CoilEnds(coil: coil, basicSections: basicSections)
            
            guard axialIndices.first >= 0, axialIndices.last >= 0 else {
                
                return nil
            }
            
            centerGapLocation = centerGapLocation >= 0 ? centerGapLocation + axialIndices.first : -1
            lowerGapLocation = lowerGapLocation >= 0 ? lowerGapLocation + axialIndices.first : -1
            upperGapLocation = upperGapLocation >= 0 ? upperGapLocation + axialIndices.first : -1
            
            // Initialize the first connector as though the coil type is a layer/sheet
            var incomingConnector = Connector(fromLocation: .inside_lower, toLocation: .floating)
            // Change the connector for the different coil types
            let wdgType = basicSections[axialIndices.first].wdgData.type
            if wdgType == .helical {
                
                incomingConnector = Connector(fromLocation: .center_lower, toLocation: .floating)
            }
            else if wdgType == .disc {
                
                let numDiscs = BasicSection.NumAxialSections(coil: coil, basicSections: basicSections)
                if numDiscs % 2 == 0 {
                    
                    incomingConnector = Connector(fromLocation: .outside_lower, toLocation: .floating)
                }
                else {
                    
                    incomingConnector = Connector(fromLocation: .inside_lower, toLocation: .floating)
                }
            }
            
            var lastSegment:Segment? = nil
            var outgoingConnector = incomingConnector
            var forceUpperConnector = false
            
            
            do {
                
                for nextSectionIndex in axialIndices.first...axialIndices.last {
                    
                    let nextSection = basicSections[nextSectionIndex]
                    
                    let newSegment = try Segment(basicSections: [nextSection],  realWindowHeight: self.currentCore!.realWindowHeight, useWindowHeight: self.currentWindowMultiplier * self.currentCore!.realWindowHeight)
                    
                    // The "incoming" connection
                    let incomingConnection = Segment.Connection(segmentID: lastSegment?.serialNumber, connector: incomingConnector, equivalentConnections: [])
                    await newSegment.AppendConnection(connection: incomingConnection)
                    // newSegment.connections.append(incomingConnection)
                    
                    // The "outgoing" connection for the previous Segment
                    if let prevSegment = lastSegment {
                        
                        let outgoingConnection = Segment.Connection(segmentID: newSegment.serialNumber, connector: outgoingConnector)
                        await prevSegment.AppendConnection(connection: outgoingConnection)
                        // prevSegment.connections.append(outgoingConnection)
                        await prevSegment.AddEquivalentConnections(to: outgoingConnection, equ: [Segment.Connection.EquivalentConnection(parent: newSegment.serialNumber, connection: incomingConnection)])
                        // The outgoingConnection of the previous section is equivalent to the incomingConnection of this section, so mark it as such
                        await newSegment.AddEquivalentConnections(to: incomingConnection, equ: [Segment.Connection.EquivalentConnection(parent: prevSegment.serialNumber, connection: outgoingConnection)])
                    }
                    
                    // set up the connector for the outgoing connection next time through the loop
                    
                    // first we need to fix things if we had offload tapping gaps on the previous pass through the loop
                    if forceUpperConnector {
                        
                        if incomingConnector.fromIsOutside {
                            
                            incomingConnector = Connector(fromLocation: .outside_lower, toLocation: incomingConnector.toLocation)
                        }
                        else {
                            
                            incomingConnector = Connector(fromLocation: .inside_lower, toLocation: incomingConnector.toLocation)
                        }
                        
                        forceUpperConnector = false
                    }
                    
                    let fromConnection = Connector.AlternatingLocation(lastLocation: incomingConnector.fromLocation)
                    let toConnection = Connector.StandardToLocation(fromLocation: fromConnection)
                    outgoingConnector = Connector(fromLocation: fromConnection, toLocation: toConnection)
                    incomingConnector = Connector(fromLocation: toConnection, toLocation: fromConnection)
                    
                    // we need to add the final outgoing connector for the last axial section (or tapping/DV gaps)
                    if nextSectionIndex == axialIndices.last || nextSectionIndex == centerGapLocation || nextSectionIndex == lowerGapLocation || nextSectionIndex == upperGapLocation {
                        
                        outgoingConnector = Connector(fromLocation: fromConnection, toLocation: .floating)
                        
                        // we need to do some fancy stuff for tapping gaps so that the view shows their terminations correctly
                        if (nextSectionIndex != axialIndices.last) {
                            
                            if outgoingConnector.fromIsOutside {
                                
                                outgoingConnector = Connector(fromLocation: .outside_center, toLocation: .floating)
                                incomingConnector = Connector(fromLocation: .outside_center, toLocation: .floating)
                            }
                            else {
                                
                                outgoingConnector = Connector(fromLocation: .inside_center, toLocation: .floating)
                                incomingConnector = Connector(fromLocation: .inside_center, toLocation: .floating)
                            }
                            
                            forceUpperConnector = true
                        }
                        
                        await newSegment.AppendConnection(connection: Segment.Connection(segmentID: nil, connector: outgoingConnector))
                        // newSegment.connections.append(Segment.Connection(segmentID: nil, connector: outgoingConnector))
                        lastSegment = nil
                    }
                    else {
                        
                        lastSegment = newSegment
                    }
                    
                    result.append(newSegment)
                }
                
            }
            catch {
                
                let alert = NSAlert(error: error)
                let _ = alert.runModal()
                return nil
            }
            
        }

        return PhaseModel(segments: result, core: self.currentCore!, tankDepth: self.tankDepth)
    }
    
    func createBasicSections(xlFile:PCH_ExcelDesignFile) -> [BasicSection] {
        
        // First off, we need to find the axial centers of the coils. We do this by finding the highest coil (max electrical height) and adding half that height to its bottom-edge-pack dimension. Other coils are then inserted into the model using that same center for all coils.
        var maxHeight = 0.0
        var maxHtEdgePack = 0.0
        for nextWinding in xlFile.windings {
            
            if nextWinding.electricalHeight > maxHeight {
                maxHeight = nextWinding.electricalHeight
                maxHtEdgePack = nextWinding.bottomEdgePack
            }
        }
        
        let axialCenter = maxHtEdgePack + maxHeight / 2.0
        
        var result:[BasicSection] = []
        
        var radialPos = 0
        
        for nextWinding in xlFile.windings {
            
            var axialPos = 0
            let wType = nextWinding.windingType
            
            // let numMainRadialSections = 1 + (wType == .layer ? nextWinding.numRadialDucts : 0)
            
            var mainGaps:[Double] = []
            var totalMainGapDimn = 0.0
            if nextWinding.bottomDvGap > 0.0 {
                mainGaps.append(nextWinding.bottomDvGap)
                totalMainGapDimn += nextWinding.bottomDvGap
            }
            if nextWinding.centerGap > 0.0 {
                mainGaps.append(nextWinding.centerGap)
                totalMainGapDimn += nextWinding.centerGap
            }
            if nextWinding.topDvGap > 0.0 {
                mainGaps.append(nextWinding.topDvGap)
                totalMainGapDimn += nextWinding.topDvGap
            }
            
            let numMainGaps = Double(mainGaps.count)
            
            // let turnInsulation = nextWinding.turnDefinition.cable.insulation
            
            // We treat disc coils and helical coils the same way (specifically, we treat helical coils as disc coils with 1 turn per disc). For now, all other coil types are treated as one huge lumped section that spans the entire radial build by the electrical height. Note that the series capacitance calculations for those types of coils should still be done properly.
            if wType == .disc || wType == .helix {
                
                let numDiscs:Double = (wType == .disc ? Double(nextWinding.numAxialSections) : nextWinding.numTurns.max)
                let turnsPerDisc:Double = (wType == .disc ? Double(nextWinding.numTurns.max) / numDiscs : 1.0)
                
                let numStandardGaps = numDiscs - 1.0 - numMainGaps
                
                let discHt = (nextWinding.electricalHeight - (numStandardGaps * nextWinding.stdAxialGap + totalMainGapDimn) * 0.98) / numDiscs
                let discPitch = discHt + nextWinding.stdAxialGap * 0.98
                
                var perSectionDiscs:[Int] = []
                if mainGaps.count == 0 {
                    
                    perSectionDiscs = [Int(numDiscs)]
                }
                else if mainGaps.count == 1 {
                    
                    let lowerSectionDiscs = Int(round(numDiscs / 2.0))
                    let upperSectionDiscs = Int(numDiscs) - lowerSectionDiscs
                    perSectionDiscs = [lowerSectionDiscs, upperSectionDiscs]
                }
                else if mainGaps.count == 2 {
                    
                    let middleSectionDiscs = Int(round(numDiscs / 2.0))
                    let lowerSectionDiscs = Int(round((numDiscs - Double(middleSectionDiscs)) / 2.0))
                    let upperSectionDiscs = Int(numDiscs) - middleSectionDiscs - lowerSectionDiscs
                    perSectionDiscs = [lowerSectionDiscs, middleSectionDiscs, upperSectionDiscs]
                }
                else {
                    let middleSectionDiscs = round(numDiscs / 2.0)
                    let mid1 = Int(round(middleSectionDiscs / 2.0))
                    let mid2 = Int(middleSectionDiscs) - mid1
                    let outerSectionDiscs = numDiscs - middleSectionDiscs
                    let low = Int(round(outerSectionDiscs / 2.0))
                    let high = Int(outerSectionDiscs) - low
                    perSectionDiscs = [low, mid1, mid2, high]
                }
                
                var gapIndex = 0
                var currentZ = axialCenter - nextWinding.electricalHeight / 2.0
                
                for nextMainSection in perSectionDiscs {
                    
                    for sectionIndex in 0..<nextMainSection {
                        
                        let nextAxialPos = axialPos + sectionIndex
                        
                        let wdgData = BasicSectionWindingData(type: wType == .disc ? .disc : .helical, discData: BasicSectionWindingData.DiscData(numAxialColumns: nextWinding.numAxialColumns, axialColumnWidth: nextWinding.spacerWidth), layers: BasicSectionWindingData.LayerData(numLayers: 1, interLayerInsulation: 0, ducts: BasicSectionWindingData.LayerData.DuctData(numDucts: 0, ductDimn: 0)), turn: BasicSectionWindingData.TurnData(radialDimn: nextWinding.turnDefinition.radialDimension, axialDimn: nextWinding.turnDefinition.axialDimension, turnInsulation: nextWinding.turnDefinition.cable.strandInsulation + nextWinding.turnDefinition.cable.insulation, resistancePerMeter: nextWinding.turnDefinition.resistancePerMeterAt20C, strandRadial: nextWinding.turnDefinition.cable.strandRadialDimension, strandAxial: nextWinding.turnDefinition.cable.strandAxialDimension))
                        
                        let newBasicSection = BasicSection(location: LocStruct(radial: radialPos, axial: nextAxialPos), N: turnsPerDisc, I: nextWinding.I, wdgData: wdgData, rect: NSRect(x: nextWinding.innerDiameter / 2.0, y: currentZ, width: nextWinding.electricalRadialBuild, height: discHt))
                        
                        result.append(newBasicSection)
                        
                        currentZ += discPitch
                    }
                    
                    if gapIndex < mainGaps.count {
                        
                        currentZ += (mainGaps[gapIndex] - discPitch + discHt)
                        print("Gap center: \(currentZ - mainGaps[gapIndex] / 2.0)")
                        gapIndex += 1
                    }
                    
                    axialPos += nextMainSection
                }
                
            }
            else {
                
                var bsWdgType:BasicSectionWindingData.WdgType = .sheet
                if nextWinding.windingType == .layer || nextWinding.windingType == .section {
                    bsWdgType = .layer
                }
                else if nextWinding.windingType == .multistart {
                    bsWdgType = .multistart
                }
                
                let layerData = BasicSectionWindingData.LayerData(numLayers: bsWdgType == .disc ? Int(nextWinding.numTurns.max) : nextWinding.numRadialSections, interLayerInsulation: nextWinding.interLayerInsulation, ducts: BasicSectionWindingData.LayerData.DuctData(numDucts: nextWinding.numRadialDucts, ductDimn: nextWinding.radialDuctDimension))
                
                let turnData = BasicSectionWindingData.TurnData(radialDimn: nextWinding.turnDefinition.radialDimension, axialDimn: nextWinding.turnDefinition.axialDimension, turnInsulation: nextWinding.turnDefinition.cable.strandInsulation + nextWinding.turnDefinition.cable.insulation, resistancePerMeter: nextWinding.turnDefinition.resistancePerMeterAt20C, strandRadial: nextWinding.turnDefinition.cable.strandRadialDimension, strandAxial: nextWinding.turnDefinition.cable.strandAxialDimension)
                
                let newBasicSection = BasicSection(location: LocStruct(radial: radialPos, axial: axialPos), N: nextWinding.numTurns.max, I: nextWinding.I, wdgData: BasicSectionWindingData(type: bsWdgType, discData: BasicSectionWindingData.DiscData(numAxialColumns: nextWinding.numAxialColumns, axialColumnWidth: nextWinding.spacerWidth), layers: layerData, turn: turnData), rect: NSRect(x: nextWinding.innerDiameter / 2.0, y: axialCenter - nextWinding.electricalHeight / 2.0, width: nextWinding.electricalRadialBuild, height: nextWinding.electricalHeight))
                
                result.append(newBasicSection)
            }
            
            // set up for next time through the loop
            radialPos += 1
        }
        
        return result
    }
    
    /// Function to create the finite-element model that we'll use to get the inductance matrix and eddy losses for the current PhaseModel. It is assumed that 'model' has already been updated (or created) using 'xlFile'.
    func CreateFePhase(xlFile:PCH_ExcelDesignFile, model:PhaseModel) async -> PchFePhase? {
        
        let coilSegments = await model.CoilSegments()
        // do some simple checks to see if the xlFile and the model match, at least in terms of the number of coils and their basic sections
        guard let lastSegment = coilSegments.last, lastSegment.radialPos == xlFile.windings.count - 1 else {
            
            DLog("xlFile and model coil count do not match!")
            return nil
        }
        
        var totalBasicSections = 0
        for nextSegment in coilSegments {
            
            totalBasicSections += nextSegment.basicSections.count
        }
        
        var totalFileSections = 0
        for nextWinding in xlFile.windings {
            
            let wType = nextWinding.windingType
            
            if wType == .disc {
                
                totalFileSections += nextWinding.numAxialSections
            }
            else if wType == .helix {
                
                totalFileSections += Int(nextWinding.numTurns.max)
            }
            else {
                
                totalFileSections += 1
            }
        }
        
        guard totalFileSections == totalBasicSections else {
            
            DLog("xlFile and model section count do not match!")
            return nil
        }
        
        // Ok, we'll assume that the two models are compatible. Create the finite element sections & window
        var feSections:[PchFePhase.Section] = []
        for nextSegment in coilSegments {
            
            let wdg = xlFile.windings[nextSegment.radialPos]
            let wdgTurn = wdg.turnDefinition
            let strandsPerTurn = wdgTurn.numCablesAxial * wdgTurn.numCablesRadial * (wdgTurn.cable.conductor == .ctc ? wdgTurn.cable.numCTCstrands :  wdgTurn.cable.numStrandsAxial * wdgTurn.cable.numStrandsRadial)
            // default to a layer (or multi-start) winding (we always assume a 1-layer winding for this)
            var numTurnsRadially = Double(wdg.numRadialSections)
            if wdg.windingType == .disc || wdg.windingType == .sheet {
                
                numTurnsRadially = wdg.numTurns.max / Double(wdg.numAxialSections)
            }
            else if wdg.windingType == .helix {
                
                numTurnsRadially = 1.0
            }
            
            let newFeSection = await PchFePhase.Section(innerRadius: nextSegment.r1, radialBuild: nextSegment.r2 - nextSegment.r1, zMin: nextSegment.z1, zMax: nextSegment.z2, totalTurns: nextSegment.N, activeTurns: nextSegment.N, seriesRmsCurrent: Complex(nextSegment.I), frequency: xlFile.frequency, strandsPerTurn: Double(strandsPerTurn), strandsPerLayer: numTurnsRadially * Double(wdgTurn.numCablesRadial) * Double(wdgTurn.cable.numStrandsRadial), strandRadial: wdgTurn.cable.strandRadialDimension, strandAxial: wdgTurn.cable.strandAxialDimension, strandConductor: .CU, numAxialColumns: Double(wdg.numAxialColumns), axialColumnWidth: wdg.spacerWidth)
            
            feSections.append(newFeSection)
        }
        
        let coreCenterToTank = xlFile.tankDepth / 2.0
        let windowHt = xlFile.core.windowHeight
        let constPotPt = NSPoint(x: coreCenterToTank, y: windowHt / 2)
        let feWindow = PchFePhase.Window(zMin: 0.0, zMax: windowHt, rMin: xlFile.core.radius, rMax: coreCenterToTank, constPotentialPoint: constPotPt, sections: feSections)
        
        let fePhase = PchFePhase(window: feWindow)
        
        return fePhase
    }
    
    // MARK: Testing routines
    
    // MARK: Simulation routines
    @IBAction func handleCreateSimStruct(_ sender: Any) {
        
        Task {
            
            guard let newModel = await SimulationModel(model: self.currentModel!) else {
                
                PCH_ErrorAlert(message: "Could not create simulation model!")
                return
            }
            
            currentSimModel = newModel
        }
    }
    
    @IBAction func handleDoSimulate(_ sender: Any) {
        
        guard let simModel = self.currentSimModel else {
            
            DLog("No simulation model!")
            return
        }
        
        var waveForms:[String] = []
        SimulationModel.WaveForm.Types.allCases.forEach {

            waveForms.append($0.rawValue)
        }
        
        let simDetailsDlog = SimDetailsDlog(waveFormStrings: waveForms)
        
        if simDetailsDlog.runModal() == .OK {
            
            self.latestSimulationResult = nil
            let peakVoltage = simDetailsDlog.voltageField.doubleValue * 1000
            guard abs(peakVoltage) >= 10000 else {
                
                PCH_ErrorAlert(message: "Cannot simulate with a voltage less than 10kV!")
                return
            }
            
            Task {
                
                let wfIndex = simDetailsDlog.waveFormPopUp.indexOfSelectedItem
                let waveForm = SimulationModel.WaveForm(type: SimulationModel.WaveForm.Types.allCases[wfIndex], pkVoltage: peakVoltage)
                
                simulationLight.textColor = .red
                simCalcProgInd.isHidden = false
                simCalcProgInd.startAnimation(self)
                workingLabel.isHidden = false
                
                let simResult = await simModel.DoSimulate(waveForm: waveForm, startTime: 0.0, endTime: waveForm.timeToZero, epsilon: 200.0 / 0.05E-6)
                
                if simResult.isEmpty {
                    
                    PCH_ErrorAlert(message: "Simulation failed!")
                    await didFinishSimulationRun()
                    return
                }
                
                self.latestSimulationResult = SimulationResults(waveForm: waveForm, peakVoltage: peakVoltage, stepResults: simResult)
                await didFinishSimulationRun()
            }
        }
    }
    
    @IBAction func handleShowWaveforms(_ sender: Any) {
        
        guard let phModel = self.currentModel, self.currentSimModel != nil else {
            
            DLog("No simulation model!")
            return
        }
        
        Task {
            
            let numCoils = await phModel.CoilCount()
            var highestSects:[Int] = []
            for i in 0..<numCoils {
                
                do {
                    try await highestSects.append(phModel.GetHighestSection(coil: i))
                }
                catch {
                    
                    let alert = NSAlert(error: error)
                    let _ = alert.runModal()
                    return
                }
            }
            
            let showWaveFormDlog = ShowWaveFormsDialog(numCoils: numCoils, highestSections: highestSects)
            
            if showWaveFormDlog.runModal() == .OK {
                
                let segmentRange = showWaveFormDlog.segmentRange
                DLog("Segment range: \(segmentRange)")
                
                await self.doShowWaveforms(segments: segmentRange, showVoltage: showWaveFormDlog.showVoltagesCheckBox.state == .on, showCurrent: showWaveFormDlog.showCurrentsCheckBox.state == .on, showFourier: showWaveFormDlog.showFourierCheckBox.state == .on)
                
            }
        }
    }
    
    /// Show the requested waveforms. Current waveforms are displayed for the given Segments while voltage waveforms are shown for nodes located above and below the given Segments
    /// - note: If both 'showVoltage" and 'showCurrent' are false, the routine does nothing
    func doShowWaveforms(segments:Range<Int>, showVoltage:Bool, showCurrent:Bool, showFourier:Bool) async {
        
        guard let simResult = latestSimulationResult, let model = currentModel, !segments.isEmpty && (showVoltage || showCurrent || showFourier) else {
            
            return
        }
        
        if showCurrent {
            
            let dataStride = simResult.numSteps > 1000 ? simResult.numSteps / 1000 : 1
            
            let waveformWind = WaveFormDisplayWindow(windowNibName: "WaveFormDisplayWindow")
            waveformWind.windowTitle = "Current Waveforms: Segments [\(segments.first!)-\(segments.last!)]"
            
            var maxValue = -Double.greatestFiniteMagnitude
            var minValue = Double.greatestFiniteMagnitude
            
            var wfData:[[NSPoint]] = []
            for nextResultIndex in stride(from: 0, to: simResult.numSteps, by: dataStride) {
                
                let nextResult = simResult.stepResults[nextResultIndex]
                
                var stepData:[NSPoint] = []
                let x = nextResult.time * 1.0E6
                for nextSegment in segments {
                    
                    let amps = nextResult.amps[nextSegment]
                    maxValue = max(amps, maxValue)
                    minValue = min(amps, minValue)
                    let newPoint = NSPoint(x: x, y: amps)
                    stepData.append(newPoint)
                }
                
                wfData.append(stepData)
            }
            
            // only calculate and apply a multiplier if the results are not all zeros
            if abs(minValue) > 0 || abs(maxValue) > 0 {
                
                // we want to keep the NSPoints in the "low-integer" (say, 0 to 1000) range:
                let height = abs(maxValue - minValue)
                var multiplier = 1000.0 / height
                // We want to round the multiplier down to the nearest power of 10: 10^(floor(log10(x)))
                multiplier = pow(10.0, floor(log10(multiplier)))
                
                for i in 0..<wfData.count {
                    
                    for j in 0..<wfData[i].count {
                        
                        wfData[i][j].y *= multiplier
                    }
                }
            }
            
            waveformWind.data = wfData
            waveformWind.showWindow(self)
        }
        
        if showFourier {
            
            // only show the Fourier transform for the last segment in the range
            let origSignal = simResult.ampsFor(segment: segments.upperBound - 1).compactMap({ Float($0)})
            
            // get rid of the dc-component of the signal (from https://sam-koblenski.blogspot.com/2015/11/everyday-dsp-for-programmers-dc-and.html)
            var signal:[Float] = []
            
            let alpha:Float = 0.9
            var wPrev:Float = 0.0
            for x_t in origSignal {
                
                let wNew = x_t + alpha * wPrev;
                signal.append(wNew - wPrev)
                wPrev = wNew
            }
            
            let n = signal.count
            let log2n = vDSP_Length(log2(Float(n)))
            
            guard let fftSetUp = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else {
                                            
                DLog("Can't create FFT Setup.")
                return
            }
            
            let halfN = Int(n / 2)
            var forwardInputReal = [Float](repeating: 0, count: halfN)
            var forwardInputImag = [Float](repeating: 0, count: halfN)
            var forwardOutputReal = [Float](repeating: 0, count: halfN)
            var forwardOutputImag = [Float](repeating: 0, count: halfN)
            
            forwardInputReal.withUnsafeMutableBufferPointer { forwardInputRealPtr in
                forwardInputImag.withUnsafeMutableBufferPointer { forwardInputImagPtr in
                    forwardOutputReal.withUnsafeMutableBufferPointer { forwardOutputRealPtr in
                        forwardOutputImag.withUnsafeMutableBufferPointer { forwardOutputImagPtr in
                            
                            // Create a `DSPSplitComplex` to contain the signal.
                            var forwardInput = DSPSplitComplex(realp: forwardInputRealPtr.baseAddress!,
                                                               imagp: forwardInputImagPtr.baseAddress!)
                            
                            // Convert the real values in `signal` to complex numbers.
                            signal.withUnsafeBytes {
                                vDSP.convert(interleavedComplexVector: [DSPComplex]($0.bindMemory(to: DSPComplex.self)),
                                             toSplitComplexVector: &forwardInput)
                            }
                            
                            // Create a `DSPSplitComplex` to receive the FFT result.
                            var forwardOutput = DSPSplitComplex(realp: forwardOutputRealPtr.baseAddress!,
                                                                imagp: forwardOutputImagPtr.baseAddress!)
                            
                            // Perform the forward FFT.
                            fftSetUp.forward(input: forwardInput,
                                             output: &forwardOutput)
                        }
                    }
                }
            }
            
            var xFFT:[Double] = []
            var maxIndex = -1
            var maxMag = 0.0
            for i in 0..<halfN {
                
                let compVal = Complex(Double(forwardOutputReal[i]), Double(forwardOutputImag[i]))
                let mag = compVal.length
                if mag > maxMag {
                    
                    maxMag = mag
                    maxIndex = i
                }
                
                xFFT.append(mag)
            }
            
            let fs = 1.0 / (100.0E-6 / Double(n))
            let fundFreq = Double(maxIndex) * fs / Double(n)
            DLog("Fundamental frequency: \(fundFreq)")
            
            let autospectrum = [Float](unsafeUninitializedCapacity: halfN) {
                autospectrumBuffer, initializedCount in
                
                // The `vDSP_zaspec` function accumulates its output. Clear the
                // uninitialized `autospectrumBuffer` before computing the spectrum.
                vDSP.clear(&autospectrumBuffer)
                
                forwardOutputReal.withUnsafeMutableBufferPointer { forwardOutputRealPtr in
                    forwardOutputImag.withUnsafeMutableBufferPointer { forwardOutputImagPtr in
                        
                        var frequencyDomain = DSPSplitComplex(realp: forwardOutputRealPtr.baseAddress!,
                                                              imagp: forwardOutputImagPtr.baseAddress!)
                        
                        vDSP_zaspec(&frequencyDomain,
                                    autospectrumBuffer.baseAddress!,
                                    vDSP_Length(halfN))
                    }
                }
                
                initializedCount = halfN
            }
            
            let waveformWind = WaveFormDisplayWindow(windowNibName: "WaveFormDisplayWindow")
            waveformWind.windowTitle = "Fourier transform for segment: \(segments.upperBound - 1)"
            
            var maxValue = -Double.greatestFiniteMagnitude
            var minValue = Double.greatestFiniteMagnitude
            
            var wfData:[[NSPoint]] = []
            
            var x = 0.5
            for nextValue in autospectrum {
                
                maxValue = max(Double(nextValue), maxValue)
                minValue = min(Double(nextValue), minValue)
                let newPoint = NSPoint(x: x, y: Double(nextValue))
                wfData.append([newPoint])
                x += 1.0
            }
            
            // only calculate and apply a multiplier if the results are not all zeros
            if abs(minValue) > 0 || abs(maxValue) > 0 {
                
                // we want to keep the NSPoints in the "low-integer" (say, 0 to 1000) range:
                let height = abs(maxValue - minValue)
                var multiplier = 1000.0 / height
                // We want to round the multiplier down to the nearest power of 10: 10^(floor(log10(x)))
                multiplier = pow(10.0, floor(log10(multiplier)))
                
                for i in 0..<wfData.count {
                    
                    for j in 0..<wfData[i].count {
                        
                        wfData[i][j].y *= multiplier
                    }
                }
            }
            
            waveformWind.data = wfData
            waveformWind.showWindow(self)
            
        }
        
        if showVoltage {
            
            let dataStride = simResult.numSteps > 1000 ? simResult.numSteps / 1000 : 1
            
            // we need to convert the segment numbers passed in to their associated nodes (top and bottom) without repeats
            var nodeSet:Set<Int> = []
            let segmentsToShow = await model.CoilSegments()[segments]
            for nextNode in await model.nodes {
                
                if let belowSeg = nextNode.belowSegment {
                    
                    if segmentsToShow.contains(belowSeg) {
                        
                        nodeSet.insert(nextNode.number)
                    }
                }
                if let aboveSeg = nextNode.aboveSegment {
                    
                    if segmentsToShow.contains(aboveSeg) {
                        
                        nodeSet.insert(nextNode.number)
                    }
                }
            }
            let nodes:[Int] = Array(nodeSet).sorted(by: { $0 < $1 })
            
            let waveformWind = WaveFormDisplayWindow(windowNibName: "WaveFormDisplayWindow")
            waveformWind.windowTitle = "Voltage Waveforms: Nodes to segments [\(segments.first!)-\(segments.last!)]"
            
            var maxValue = -Double.greatestFiniteMagnitude
            var minValue = Double.greatestFiniteMagnitude
            
            var wfData:[[NSPoint]] = []
            for nextResultIndex in stride(from: 0, to: simResult.numSteps, by: dataStride) {
                
                let nextResult = simResult.stepResults[nextResultIndex]
                var stepData:[NSPoint] = []
                let x = nextResult.time * 1.0E6
                for nextNode in nodes {
                    
                    let volts = nextResult.volts[nextNode]
                    maxValue = max(volts, maxValue)
                    minValue = min(volts, minValue)
                    let newPoint = NSPoint(x: x, y: volts)
                    stepData.append(newPoint)
                }
                
                wfData.append(stepData)
            }
            
            DLog("Max / Min Voltages: \(maxValue)V / \(minValue)V")
            
            // only calculate and apply a multiplier if the results are not all zeros
            if abs(minValue) > 0 || abs(maxValue) > 0 {
                
                // we want to keep the NSPoints in the "low-integer" (say, 0 to 1000) range:
                let height = abs(maxValue - minValue)
                var multiplier = 1000.0 / height
                // We want to round the multiplier down to the nearest power of 10: 10^(floor(log10(x)))
                multiplier = pow(10.0, floor(log10(multiplier)))
                
                for i in 0..<wfData.count {
                    
                    for j in 0..<wfData[i].count {
                        
                        wfData[i][j].y *= multiplier
                    }
                }
            }
            
            waveformWind.data = wfData
            waveformWind.showWindow(self)
        }
    }
    
    @IBAction func handleShowMaxVoltageDiffs(_ sender: Any) {
        
        doShowMaxVoltageDiffs()
    }
    
    func doShowMaxVoltageDiffs(nodeRange:ClosedRange<Int>? = nil) {
        
        guard let simResult = self.latestSimulationResult else {
            
            PCH_ErrorAlert(message: "You must run the simulation first!")
            return
        }
        
        Task {
            
            // the routine we are calling will take care of clamping the nodeRange to acceptable values
            let maxMatrix = await simResult.MaximumInternodalVoltages(forRange: nodeRange)
            
            let maxWindow = maxMatrix.GetViewer()
            maxWindow.window?.title = "Maximum Internodal Voltages"
            maxWindow.showWindow(self)
        }
    }
    
    
    @IBAction func handleShowCoilResults(_ sender: Any) {
        
        guard let phModel = self.currentModel, self.currentSimModel != nil else {
            
            DLog("No simulation model!")
            return
        }
        
        Task {
            
            let coilCount = await phModel.CoilCount()
            guard let showCoilResultsDlog = ShowCoilResultsDialog(numCoils: coilCount) else {
                
                DLog("Couldn't open dialog box!")
                return
            }
            
            if showCoilResultsDlog.runModal() == .OK {
                
                let coilSelected = showCoilResultsDlog.coilPicker.indexOfSelectedItem
                
                var segmentRange:ClosedRange<Int> = 0...0
                
                do {
                    
                    segmentRange = try await phModel.SegmentRange(coil: coilSelected)
                    // let coilBase = coilSelected == 0 ? 0 : try phModel.GetHighestSection(coil: coilSelected - 1) + 1
                    // let coilTop = try phModel.GetHighestSection(coil: coilSelected) + coilBase
                    // segmentRange = coilBase...coilTop
                }
                catch {
                    
                    PCH_ErrorAlert(message: error.localizedDescription)
                    return
                }
                
                await doShowCoilResults(totalAnimationTime: showCoilResultsDlog.animationTimeTextField.doubleValue, segments: segmentRange, showVoltage: showCoilResultsDlog.voltagesCheckBox.state == .on, showCurrent: showCoilResultsDlog.currentsCheckBox.state == .on)
            }
        }
    }
    
    func doShowCoilResults(totalAnimationTime:Double, segments:ClosedRange<Int>, showVoltage:Bool, showCurrent:Bool) async {
        
        guard let phModel = self.currentModel, let simResult = self.latestSimulationResult, !segments.isEmpty else {
            
            DLog("No model or simulation results!")
            return
        }
        
        if showVoltage {
            
            // The node dimensions will look wrong for end discs that do not have static rings (the above/below value returned by AxialSpacesAboutSegment() will be half the distance to the core) so we'll set a maximum for those
            let greatestExtremeDimension = 0.1 * meterPerInch
            // For offload taps (and, eventually, breaks within the coil) set the distance to the "floating" node as 1mm
            let axialBreakDimension = 0.001
            
            do {
                
                let coilSegments = await phModel.CoilSegments()
                let coilIndex = coilSegments[segments.lowerBound].radialPos
                let highestSection = try await phModel.GetHighestSection(coil: coilIndex)
                
                // var runningDim = 0.0 // try phModel.AxialSpacesAboutSegment(segment: coilSegments[segments.lowerBound]).below / 2.0
                /*
                if coilSegments[segments.lowerBound].axialPos == 0 {
                    
                    runningDim = min(greatestExtremeDimension, runningDim)
                } */
                
                var xDims:[Double] = [] // [runningDim * 1000.0]
                
                for segIndex in segments {
                    
                    let theSegment = coilSegments[segIndex]
                    
                    let realAxialSpaces = try await phModel.AxialSpacesAboutSegment(segment: theSegment)
                    var axialSpaceBelow = realAxialSpaces.below / 2.0
                    var axialSpaceAbove = realAxialSpaces.above / 2.0
                    
                    // we'll fix some variables for taking care of coil starts, ends, and tapping breaks
                    if theSegment.axialPos == 0 {
                        
                        xDims = await [(theSegment.z1 - greatestExtremeDimension) * 1000.0]
                        axialSpaceBelow = greatestExtremeDimension
                    }
                    else if segIndex == segments.lowerBound {
                        
                        xDims = await [(theSegment.z1 - axialSpaceBelow) * 1000.0]
                    }
                    else if theSegment.axialPos == highestSection {
                        
                        axialSpaceAbove = greatestExtremeDimension
                    }
                    else {
                        
                        let prevSegment = coilSegments[segIndex - 1]
                        let nextSegment = coilSegments[segIndex + 1]
                        let tappingGapBelow = await phModel.IsTappingGap(segment1: prevSegment, segment2: theSegment)
                        let tappingGapAbove = await phModel.IsTappingGap(segment1: theSegment, segment2: nextSegment)
                        if tappingGapAbove {
                            
                            axialSpaceAbove = axialBreakDimension
                        }
                        else if tappingGapBelow {
                            
                            let startDim = await theSegment.z1 - axialBreakDimension
                            xDims.append(startDim * 1000.0)
                            axialSpaceBelow = axialBreakDimension
                        }
                    }
                    
                    /*
                    let realAxialSpaces = try phModel.AxialSpacesAboutSegment(segment: theSegment)
                    let axialSpaceBelow = theSegment.axialPos == 0 ? min(greatestExtremeDimension, realAxialSpaces.below / 2.0) : realAxialSpaces.below / 2.0
                    let axialSpaceAbove = theSegment.axialPos == highestSection ? min(greatestExtremeDimension, realAxialSpaces.above / 2.0) : realAxialSpaces.above / 2.0
                    */
                    let newDim = await xDims.last! / 1000.0 + axialSpaceBelow + theSegment.rect.height + axialSpaceAbove
                    // segment dimensions are in meters, convert to mm
                    xDims.append(newDim * 1000.0)
                }
                
                let lowNode = await phModel.AdjacentNodes(to: coilSegments[segments.lowerBound]).below
                let hiNode = await phModel.AdjacentNodes(to: coilSegments[segments.upperBound]).above
                
                self.coilResultsWindow = CoilResultsDisplayWindow(windowTitle: "Voltage: Segments [\(segments.lowerBound)-\(segments.upperBound)]", showVoltages: true, xDimensions: xDims, resultData: simResult, indicesToDisplay: ClosedRange(uncheckedBounds: (lowNode, hiNode)), totalAnimationTime: totalAnimationTime)
                
                self.coilResultsWindow!.showWindow(self)
            }
            catch {
                
                PCH_ErrorAlert(message: error.localizedDescription)
                return
            }
        }
    }
    
    // MARK: Matrix display routines
    
    @IBAction func handleShowBaseCmatrix(_ sender: Any) {
        
        guard let model = self.currentModel else {
            
            return
        }
        
        Task {
            
            guard let Cmatrix = await model.C else {
                
                return
            }
            
            let capWindow = Cmatrix.GetViewer()
            capWindow.window?.title = "Base (unfixed) Capacitance Matrix"
            capWindow.showWindow(self)
        }
    }
    
    
    @IBAction func handleShowUnfactoredMmatrix(_ sender: Any) {
        
        guard let model = self.currentModel else {
            
            return
        }
        
        Task {
            
            guard let Mmatrix = await model.unfactoredM else {
                
                return
            }
            
            let mWindow = Mmatrix.GetViewer()
            mWindow.window?.title = "Unfactored Inductance Matrix"
            mWindow.showWindow(self)
        }
    }
    
    // MARK: File routines
    func doOpen(fileURL:URL) -> Bool {
        
        if !FileManager.default.fileExists(atPath: fileURL.path)
        {
            let alert = NSAlert()
            alert.messageText = "The file does not exist!"
            alert.alertStyle = .critical
            let _ = alert.runModal()
            return false
        }
        
        do {
            
            // create the current Transformer from the Excel design file
            let xlFile = try PCH_ExcelDesignFile(designFile: fileURL)
            
            // if we make it here, we have successfully opened the file, so save it as the "last successfully opened file"
            UserDefaults.standard.set(fileURL, forKey: LAST_OPENED_INPUT_FILE_KEY)
                
            NSDocumentController.shared.noteNewRecentDocumentURL(fileURL)
            
            Task {
                await self.updateModel(oldSegments: [], newSegments: [], xlFile: xlFile, reinitialize: true)
            }
            
            self.mainWindow.title = fileURL.lastPathComponent
                        
            return true
        }
        catch
        {
            let alert = NSAlert(error: error)
            let _ = alert.runModal()
            return false
        }
    }
    
    /// Save the unfactored inductance matrix as a CSV file
    @IBAction func handleSaveRawMmatrix(_ sender: Any) {
        
        guard let model = self.currentModel else {
            
            return
        }
        
        guard let uttptxtType = UTType(filenameExtension: "txt") else {
            
            DLog("Couldn't create UTType for txt!");
            return;
        }
        
        Task {
            
            guard let Mmatrix = await model.unfactoredM else {
                return
            }
            let csvFileString = await Mmatrix.csv
            
            let savePanel = NSSavePanel()
            savePanel.title = "Inductance Matrix"
            savePanel.message = "Save Unfactored Inductance Matrix as CSV file"
            // savePanel.allowedFileTypes = ["txt"]
            savePanel.allowedContentTypes = [uttptxtType];
            savePanel.allowsOtherFileTypes = false
            
            if savePanel.runModal() == .OK
            {
                if let fileUrl = savePanel.url
                {
                    do {
                        
                        try csvFileString.write(to: fileUrl, atomically: false, encoding: .utf8)
                    }
                    catch {
                        
                        let alert = NSAlert(error: error)
                        let _ = alert.runModal()
                        return
                    }
                }
            }
        }
    }
    
    /// Save the factored inductance 
    @IBAction func handleSaveMmatrix(_ sender: Any) {
        
        guard let model = self.currentModel else {
            
            return
        }
        
        guard let uttptxtType = UTType(filenameExtension: "txt") else {
            
            DLog("Couldn't create UTType for txt!");
            return;
        }
        
        Task {
            
            guard let Mmatrix = await model.M else {
                return
            }
            let csvFileString = await Mmatrix.csv
            
            let savePanel = NSSavePanel()
            savePanel.title = "Inductance Matrix"
            savePanel.message = "Save Inductance Matrix as CSV file"
            // savePanel.allowedFileTypes = ["txt"]
            savePanel.allowedContentTypes = [uttptxtType];
            savePanel.allowsOtherFileTypes = false
            
            if savePanel.runModal() == .OK
            {
                if let fileUrl = savePanel.url
                {
                    do {
                        
                        try csvFileString.write(to: fileUrl, atomically: false, encoding: .utf8)
                    }
                    catch {
                        
                        let alert = NSAlert(error: error)
                        let _ = alert.runModal()
                        return
                    }
                }
            }
        }
    }
    
    @IBAction func handleBmatrixSave(_ sender: Any) {
        
        guard let model = self.currentModel else {
            
            return
        }
        
        guard let uttptxtType = UTType(filenameExtension: "txt") else {
            
            DLog("Couldn't create UTType for txt!")
            return
        }
        
        Task {
            
            do {
                
                let Bmatrix = try await model.GetBmatrix()
                
                let csvFileString = await Bmatrix.csv
                
                let savePanel = NSSavePanel()
                savePanel.title = "B Matrix"
                savePanel.message = "Save B Matrix as CSV file"
                // savePanel.allowedFileTypes = ["txt"]
                savePanel.allowedContentTypes = [uttptxtType];
                savePanel.allowsOtherFileTypes = false
                
                if savePanel.runModal() == .OK
                {
                    if let fileUrl = savePanel.url
                    {
                        try csvFileString.write(to: fileUrl, atomically: false, encoding: .utf8)
                    }
                }
            }
            catch {
                
                let alert = NSAlert(error: error)
                let _ = alert.runModal()
                return
            }
        }
    }
    
    
    @IBAction func handleSaveBaseCmatrix(_ sender: Any) {
        
        guard let model = self.currentModel else {
            
            return
        }
        
        guard let uttptxtType = UTType(filenameExtension: "txt") else {
            
            DLog("Couldn't create UTType for txt!")
            return
        }
        
        Task {
            
            guard let Cmatrix = await model.C  else {
                return
            }
            let csvFileString = await Cmatrix.csv
            
            let savePanel = NSSavePanel()
            savePanel.title = "Base Capacitance Matrix"
            savePanel.message = "Save Capacitance Matrix as CSV file"
            // savePanel.allowedFileTypes = ["txt"]
            savePanel.allowedContentTypes = [uttptxtType]
            savePanel.allowsOtherFileTypes = false
            
            if savePanel.runModal() == .OK
            {
                if let fileUrl = savePanel.url
                {
                    do {
                        
                        try csvFileString.write(to: fileUrl, atomically: false, encoding: .utf8)
                    }
                    catch {
                        
                        let alert = NSAlert(error: error)
                        let _ = alert.runModal()
                        return
                    }
                }
            }
        }
    }
    
    @IBAction func handleSaveFixedCmatrix(_ sender: Any) {
        
        guard let model = self.currentModel else {
            
            return
        }
        
        guard let uttptxtType = UTType(filenameExtension: "txt") else {
            
            DLog("Couldn't create UTType for txt!")
            return
        }
        
        Task {
            
            guard let Cmatrix = await model.fixedC else {
                return
            }
            let csvFileString = await Cmatrix.csv
            
            let savePanel = NSSavePanel()
            savePanel.title = "Fixed Capacitance Matrix"
            savePanel.message = "Save Capacitance Matrix as CSV file"
            savePanel.allowedContentTypes = [uttptxtType]
            savePanel.allowsOtherFileTypes = false
            
            if savePanel.runModal() == .OK
            {
                if let fileUrl = savePanel.url
                {
                    do {
                        
                        try csvFileString.write(to: fileUrl, atomically: false, encoding: .utf8)
                    }
                    catch {
                        
                        let alert = NSAlert(error: error)
                        let _ = alert.runModal()
                        return
                    }
                }
            }
        }
    }
    
    
    // MARK: Zoom functions
    @IBAction func handleZoomIn(_ sender: Any) {
        
        self.txfoView.handleZoomIn()
    }
    
    
    
    
    @IBAction func handleZoomOut(_ sender: Any) {
        
        self.txfoView.handleZoomOut()
    }
    
    
    
    
    @IBAction func handleZoomAll(_ sender: Any) {
        
        guard self.currentModel != nil, /* model.segments.count > 0,*/ let core = self.currentCore else
        {
            return
        }
        
        self.txfoView.handleZoomAll(coreRadius: CGFloat(core.radius), windowHt: CGFloat(core.realWindowHeight), tankWallR: CGFloat(self.tankDepth / 2.0))
    }
    
    
    
    
    @IBAction func handleZoomRect(_ sender: Any) {
        
        guard self.currentModel != nil /*, model.segments.count > 0 */ else
        {
            return
        }
        
        self.txfoView.mode = .zoomRect
    }
    
    // MARK: Coordinate update function
    func updateCoordinates(rValue:Double, zValue:Double) {
        
        self.rLocationTextField.doubleValue = rValue
        self.zLocationTextField.doubleValue = zValue
    }
    
   
    
    // MARK: View functions
    // This function does the following things:
    // 1) Shows the main window (if its hidden)
    // 2) Sets the bounds of the transformer view to the window of the transformer (does a "zoom all" using the current transformer core)
    // 3) Calls updateViews() to draw the coil segments
    func initializeViews()
    {
        self.mainWindow.makeKeyAndOrderFront(self)
        
        self.handleZoomAll(self)
        
        self.updateViews()
    }
    
    func updateViews()
    {
        // self.txfoView.segments = []
        
        Task {
            
            guard let model = self.currentModel else
            {
                return
            }
            
            let segs = await model.segments
            
            guard segs.count > 0 else {
                return
            }
            
            self.txfoView.currentSegments = []
            
            self.txfoView.removeAllToolTips()
            
            // See the comment for the TransformerView property 'segments' to see why I coded this in this way
            var newSegmentPaths:[SegmentPath] = []
            for nextSegment in segs
            {
                let pathColor = AppController.segmentColors[nextSegment.radialPos % AppController.segmentColors.count]
                
                var newSegPath = await SegmentPath(segment: nextSegment, segRect: nextSegment.rect, segIsStaticRing: nextSegment.isStaticRing, segmentColor: pathColor)
                // var newSegPath = SegmentPath(segment: nextSegment, segmentColor: pathColor)
                
                newSegPath.toolTipTag = self.txfoView.addToolTip(newSegPath.GetRect(), owner: self.txfoView as Any, userData: nil)
                
                newSegmentPaths.append(newSegPath)
            }
            
            self.txfoView.segments = newSegmentPaths
            self.txfoView.needsDisplay = true
        }
    }
    
    // MARK: Menu routines
    
    @IBAction func handleWdgAsSingleSegment(_ sender: Any) {
        
        self.doWdgAsSingleSegment()
    }
    
    func doWdgAsSingleSegment(segmentPath:SegmentPath? = nil) {
        
        
    }
    
    @IBAction func handleCombineSelectionIntoSingleSegment(_ sender: Any) {
        
        self.doCombineSelectionIntoSingleSegment(segmentPaths: self.txfoView.currentSegments)
    }
    
    func doCombineSelectionIntoSingleSegment(segmentPaths:[SegmentPath]) {
        
        guard let model = self.currentModel, segmentPaths.count > 1 else {
            
            return
        }
        
        var segments:[Segment] = []
        for nextPath in segmentPaths {
            
            segments.append(nextPath.segment)
        }
        
        segments.sort(by: { lhs, rhs in
            
            if lhs.radialPos != rhs.radialPos {
                
                return lhs.radialPos < rhs.radialPos
            }
            
            return lhs.axialPos < rhs.axialPos
        })
        
        Task {
            
            if await model.SegmentsAreContiguous(segments: segments) {
                
                var newBasicSectionArray:[BasicSection] = []
                
                
                
                for nextSegment in segments {
                    
                    newBasicSectionArray.append(contentsOf: nextSegment.basicSections)
                }
                
                
                do {
                    
                    // we need to keep track of static rings that are at the ends of new (combined) Segments
                    let bottomStaticRing = try await model.StaticRingBelow(segment: segments.first!, recursiveCheck: false)
                    let topStaticRing = try await model.StaticRingAbove(segment: segments.last!, recursiveCheck: false)
                    
                    let combinedSegment = try Segment(basicSections: newBasicSectionArray, realWindowHeight: model.core.realWindowHeight, useWindowHeight: model.core.adjustedWindHt)
                    
                    await self.updateModel(oldSegments: segments, newSegments: [combinedSegment], xlFile: nil, reinitialize: false)
                    
                    var capMatrixNeedsUpdate = false
                    
                    if bottomStaticRing != nil {
                        
                        let bSR = try await model.AddStaticRing(adjacentSegment: combinedSegment, above: false)
                        try await model.InsertSegment(newSegment: bSR)
                        try await model.RemoveStaticRing(staticRing: bottomStaticRing!)
                        capMatrixNeedsUpdate = true
                    }
                    
                    if topStaticRing != nil {
                        
                        let tSR = try await model.AddStaticRing(adjacentSegment: combinedSegment, above: true)
                        try await model.InsertSegment(newSegment: tSR)
                        try await model.RemoveStaticRing(staticRing: topStaticRing!)
                        capMatrixNeedsUpdate = true
                    }
                    
                    if capMatrixNeedsUpdate {
                        
                        try await model.CalculateCapacitanceMatrix()
                        //print("Coil 0 Cs: \(try model.CoilSeriesCapacitance(coil: 0))")
                        //print("Coil 1 Cs: \(try model.CoilSeriesCapacitance(coil: 1))")
                    }
                }
                catch {
                    
                    let alert = NSAlert(error: error)
                    let _ = alert.runModal()
                    return
                }
                
            }
            else {
                
                PCH_ErrorAlert(message: "Segments must be from the same coil and be contiguous to combine them!", info: nil)
            }
        }
    }

    
    @IBAction func handleInterleaveSelection(_ sender: Any) {
        
        self.doInterleaveSelection(segmentPaths: self.txfoView.currentSegments)
    }
    
    func doInterleaveSelection(segmentPaths:[SegmentPath]) {
        
        guard let model = self.currentModel, segmentPaths.count > 0 else {
            
            return
        }
        
        Task {
            
            /* This is taken care of in the for-loop immediately following...
            guard !segmentPaths.contains(where: { $0.segment.IsInterleaved()}) else {
                
                PCH_ErrorAlert(message: "The selection contains at least one interleaved segment!", info: "Cannot 'double-interleave'")
                return
            } */
            
            var segments:[Segment] = []
            for nextPath in segmentPaths {
                
                if await nextPath.segment.IsInterleaved() {
                    PCH_ErrorAlert(message: "The selection contains at least one interleaved segment!", info: "Cannot 'double-interleave'")
                    return
                }
                segments.append(nextPath.segment)
            }
            
            segments.sort(by: { lhs, rhs in
                
                if lhs.radialPos != rhs.radialPos {
                    
                    return lhs.radialPos < rhs.radialPos
                }
                
                return lhs.axialPos < rhs.axialPos
            })
            
            
            
            if await model.SegmentsAreContiguous(segments: segments) {
                
                var basicSections:[BasicSection] = []
                for nextSegment in segments {
                    
                    basicSections.append(contentsOf: nextSegment.basicSections)
                }
                
                guard basicSections.count % 2 == 0 else {
                    
                    PCH_ErrorAlert(message: "There must be an even number of total discs to create interleaved segments!", info: nil)
                    return
                }
                
                
                do {
                    
                    var interleavedSegments:[Segment] = []
                    
                    for i in stride(from: 0, to: basicSections.count, by: 2) {
                        
                        interleavedSegments.append(try Segment(basicSections: [basicSections[i], basicSections[i+1]], interleaved: true, realWindowHeight: model.core.realWindowHeight, useWindowHeight: model.core.adjustedWindHt))
                    }
                    
                    await self.updateModel(oldSegments: segments, newSegments: interleavedSegments, xlFile: nil, reinitialize: false)
                }
                catch {
                    
                    let alert = NSAlert(error: error)
                    let _ = alert.runModal()
                    return
                }
            }
            
            else {
                
                PCH_ErrorAlert(message: "Segments must be from the same coil and be contiguous to interleave them!", info: nil)
            }
        }
    }
    
    @IBAction func handleSplitSegmentIntoBasicSections(_ sender: Any) {
        
        guard self.currentModel != nil, self.txfoView.currentSegments.count == 1 else {
            
            return
        }
        
        self.doSplitSegmentIntoBasicSections(segmentPath: self.txfoView.currentSegments[0])
    }
    
    func doSplitSegmentIntoBasicSections(segmentPath:SegmentPath) {
        
        guard let model = self.currentModel, segmentPath.segment.basicSections.count > 1 else {
            
            return
        }
        
        let segment = segmentPath.segment
        var newSegments:[Segment] = []
        
        Task {
            
            do {
                
                for nextBasicSection in segment.basicSections {
                    
                    newSegments.append(try Segment(basicSections: [nextBasicSection], interleaved: false, isStaticRing: false, isRadialShield: false, realWindowHeight: model.core.realWindowHeight, useWindowHeight: model.core.adjustedWindHt))
                }
                
                await self.updateModel(oldSegments: [segment], newSegments: newSegments, xlFile: nil, reinitialize: false)
            }
            catch {
                
                let alert = NSAlert(error: error)
                let _ = alert.runModal()
                return
            }
        }
    }
    
    @IBAction func handleAddGround(_ sender: Any) {
        
        self.doAddGround()
    }
    
    func doAddGround() {
        
        guard self.currentModel != nil else {
            
            return
        }
        
        self.txfoView.mode = .addGround
    }
    
    @IBAction func handleAddImpulse(_ sender: Any) {
        
        self.doAddImpulse()
    }
    
    func doAddImpulse() {
        
        guard self.currentModel != nil else {
            
            return
        }
        
        self.txfoView.mode = .addImpulse
    }
    
    @IBAction func handleAddConnection(_ sender: Any) {
        
        self.doAddConnection()
    }
    
    func doAddConnection() {
        
        guard self.currentModel != nil else {
            
            return
        }
        
        self.txfoView.mode = .addConnection
    }
    
    @IBAction func handleRemoveConnection(_ sender: Any) {
        
        self.doRemoveConnection()
    }
    
    func doRemoveConnection() {
        
        guard self.currentModel != nil else {
            
            return
        }
        
        self.txfoView.mode = .removeConnector
    }
    
    // next two functions for adding a static ring over the selection
    @IBAction func handleAddStaticRingOver(_ sender: Any) {
        
        self.doAddStaticRingOver()
    }
    
    func doAddStaticRingOver(segmentPath:SegmentPath? = nil) {
        
        guard let model = self.currentModel, self.txfoView.currentSegments.count > 0 else {
            
            return
        }
        
        let currentSegment = segmentPath == nil ? self.txfoView.currentSegments[0] : segmentPath!
        
        Task {
            do {
                
                let newStaticRing = try await model.AddStaticRing(adjacentSegment: currentSegment.segment, above: true)
                
                try await model.InsertSegment(newSegment: newStaticRing)
                
                try await model.CalculateCapacitanceMatrix()
                // print("Coil 1 Cs: \(try model.CoilSeriesCapacitance(coil: currentSegment.segment.radialPos))")
                
                // var newSegPath = await SegmentPath(segment: newStaticRing, segRect: newStaticRing.rect, segIsStaticRing: true, segmentColor: currentSegment.segmentColor)
                await self.txfoView.segments.append(SegmentPath(segment: newStaticRing, segRect: newStaticRing.rect, segIsStaticRing: true, segmentColor: currentSegment.segmentColor))
                self.txfoView.currentSegments = [self.txfoView.segments.last!]
                
                self.txfoView.needsDisplay = true
            }
            catch {
                
                let alert = NSAlert(error: error)
                let _ = alert.runModal()
                return
            }
        }
    }
    
    // next two functions for adding a static ring under the selection
    @IBAction func handleAddStaticRingBelow(_ sender: Any) {
        
        self.doAddStaticRingBelow()
    }
    
    func doAddStaticRingBelow(segmentPath:SegmentPath? = nil) {
        
        guard let model = self.currentModel, self.txfoView.currentSegments.count > 0 else {
            
            return
        }
        
        let currentSegment = segmentPath == nil ? self.txfoView.currentSegments[0] : segmentPath!
        
        Task {
            
            do {
                
                let newStaticRing = try await model.AddStaticRing(adjacentSegment: currentSegment.segment, above: false)
                
                try await model.InsertSegment(newSegment: newStaticRing)
                
                try await model.CalculateCapacitanceMatrix()
                print("Coil 1 Cs: \(try await model.CoilSeriesCapacitance(coil: currentSegment.segment.radialPos))")
                
                await self.txfoView.segments.append(SegmentPath(segment: newStaticRing, segRect: newStaticRing.rect, segIsStaticRing: true, segmentColor: currentSegment.segmentColor))
                self.txfoView.currentSegments = [self.txfoView.segments.last!]
                
                self.txfoView.needsDisplay = true
            }
            catch {
                
                let alert = NSAlert(error: error)
                let _ = alert.runModal()
                return
            }
        }
    }
    
    // next two functions for removing a static ring
    @IBAction func handleRemoveStaticRing(_ sender: Any) {
        
        self.doRemoveStaticRing()
    }
    
    func doRemoveStaticRing(segmentPath:SegmentPath? = nil) {
        
        guard let model = self.currentModel, self.txfoView.currentSegments.count > 0 else {
            
            return
        }
        
        let currentSegment = segmentPath == nil ? self.txfoView.currentSegments[0] : segmentPath!
        
        Task {
            
            do {
                
                try await model.RemoveStaticRing(staticRing: currentSegment.segment)
                
                self.txfoView.segments.remove(at: self.txfoView.currentSegmentIndices[0])
                
                
                self.txfoView.currentSegments = []
                self.txfoView.needsDisplay = true
            }
            catch {
                
                let alert = NSAlert(error: error)
                let _ = alert.runModal()
                return
            }
        }
    }
    
    // next two functions for adding a radial shield
    @IBAction func handleAddRadialShield(_ sender: Any) {
        
        self.doAddRadialShield()
    }
    
    func doAddRadialShield(segmentPath:SegmentPath? = nil) {
        
        guard let model = self.currentModel, self.txfoView.currentSegments.count > 0 else {
            
            return
        }
        
        let currentSegment = segmentPath == nil ? self.txfoView.currentSegments[0] : segmentPath!
        
        let getHiloDlog = GetNumberDialog(descriptiveText: "Gap to shield:", unitsText: "meters", noteText: "Must be less then the hilo under the coil", windowTitle: "Add Radial Shield")
        
        if getHiloDlog.runModal() == .cancel {
            
            return
        }
        
        let hilo = getHiloDlog.numberValue
        
        if hilo <= 0 {
            
            return
        }
        
        Task {
            
            do {
                
                // let hilo = 0.012
                let newRadialShield = try await model.AddRadialShieldInside(coil: currentSegment.segment.location.radial, hiloToShield: hilo)
                
                try await model.InsertSegment(newSegment: newRadialShield)
                await self.txfoView.segments.append(SegmentPath(segment: newRadialShield, segRect: newRadialShield.rect, segIsStaticRing: false, segmentColor: .green))
                // self.txfoView.segments.append(SegmentPath(segment: newRadialShield, segmentColor: .green))
                self.txfoView.currentSegments = [self.txfoView.segments.last!]
                
                self.txfoView.needsDisplay = true
            }
            catch {
                
                let alert = NSAlert(error: error)
                let _ = alert.runModal()
                return
            }
        }
    }
    
    // next two functions for removing a radial shield
    @IBAction func handleRemoveRadialShield(_ sender: Any) {
        
        self.doRemoveRadialShield()
    }
    
    func doRemoveRadialShield(segmentPath:SegmentPath? = nil) {
        
        guard let model = self.currentModel, self.txfoView.currentSegments.count > 0 else {
            
            return
        }
        
        let currentSegment = segmentPath == nil ? self.txfoView.currentSegments[0] : segmentPath!
        
        Task {
            
            do {
                
                try await model.RemoveRadialShield(radialShield: currentSegment.segment)
                
                self.txfoView.segments.remove(at: self.txfoView.currentSegmentIndices[0])
                
                self.txfoView.currentSegments = []
                self.txfoView.needsDisplay = true
            }
            catch {
                
                let alert = NSAlert(error: error)
                let _ = alert.runModal()
                return
            }
        }
    }
    
    /*
    @IBAction func handleShowGraph(_ sender: Any) {
        
        DLog("Creating window controller")
        
        self.graphWindowCtrl = PCH_GraphingWindow(graphBounds: NSRect(x: -10.0, y: -10.0, width: 1000.0, height: 400.0))
        
        
    } */
    
    
    @IBAction func handleOpenFile(_ sender: Any) {
        
        let openPanel = NSOpenPanel()
        
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.title = "Design file"
        openPanel.message = "Open a valid Excel-design-sheet-generated file"
        openPanel.allowsMultipleSelection = false
        
        // If there was a previously successfully opened design file, set that file's directory as the default, otherwise go to the user's Documents folder
        if let lastFile = UserDefaults.standard.url(forKey: LAST_OPENED_INPUT_FILE_KEY)
        {
            openPanel.directoryURL = lastFile.deletingLastPathComponent()
        }
        else
        {
            openPanel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        
        if openPanel.runModal() == .OK
        {
            if let fileURL = openPanel.url
            {
                let _ = self.doOpen(fileURL: fileURL)
            }
            else
            {
                DLog("This shouldn't ever happen...")
            }
        }
    }
    
    @IBAction func HandleSaveAsCIRfile(_ sender: Any) {
        
        let saveAsPanel = NSSavePanel()
        saveAsPanel.title = "SPICE File"
        saveAsPanel.message = "Save SPICE (.cir) File"
        
        guard let cirType = UTType(filenameExtension: PCH_CIR_FILETYPE, conformingTo: .utf8PlainText) else {
            
            DLog("Could not create file type!")
            return
        }
        
        saveAsPanel.allowedContentTypes = [cirType]
        saveAsPanel.allowsOtherFileTypes = false
        
        Task {
            
            if saveAsPanel.runModal() == .OK
            {
                if let fileURL = saveAsPanel.url
                {
                    if let fileString = await self.doCreateCirFile(filename: fileURL.path) {
                        
                        do {
                            
                            try fileString.write(to: fileURL, atomically: false, encoding: .utf8)
                        }
                        catch {
                            
                            let alert = NSAlert(error: error)
                            let _ = alert.runModal()
                            return
                        }
                    }
                    else {
                        
                        let alert = NSAlert()
                        alert.messageText = "Could not create CIR file from the current model!"
                        alert.alertStyle = .warning
                        let _ = alert.runModal()
                        return
                    }
                }
                else {
                    
                    let alert = NSAlert()
                    alert.messageText = "Illegal URL when creating CIR file."
                    alert.alertStyle = .warning
                    let _ = alert.runModal()
                    return
                }
            }
        }
        
    }
    
    func doCreateCirFile(filename:String) async -> String? {
        
        guard let model = self.currentModel else {
            
            DLog("No model is currently defined!")
            return nil
        }
        
        var result:String = "FILE: " + filename.uppercased() + "\n"
        
        // The initial resistance-to-self-inductance id index is 40000
        var resistanceToInductanceIndexID = 40000
        // The initial shunt capacitance id index is 50000
        var shuntIndexID = 50000
        
        for nextNode in await model.nodes {
            
            // Start with shunt capacitances from this node
            for nextShuntCap in nextNode.shuntCapacitances {
                
                // make sure we only define the shunt capacitance in one direction
                if nextShuntCap.toNode > nextNode.number {
                    
                    let shuntCap = String(format: "C%d %d %d %.4E\n", shuntIndexID, nextNode.number, nextShuntCap.toNode, nextShuntCap.capacitance)
                    shuntIndexID += 1
                    result += shuntCap
                }
            }
            
            let Cj = await nextNode.belowSegment != nil ? nextNode.belowSegment!.seriesCapacitance : 0.0
            let Cj1 = await nextNode.aboveSegment != nil ? nextNode.aboveSegment!.seriesCapacitance : 0.0
            
            guard Cj > 0.0 || Cj1 > 0.0 else {
                
                let alert = NSAlert()
                alert.messageText = "The node has no segments!"
                alert.alertStyle = .warning
                let _ = alert.runModal()
                return nil
            }
            
            if let belowSeg = nextNode.belowSegment {
                
                let prevNodeNumber = nextNode.number - 1
                
                // The series capacitance
                let seriesCap = String(format: "C%d %d %d %.4E\n", belowSeg.serialNumber, prevNodeNumber, nextNode.number, Cj)
                
                // The series resistance
                let seriesRes = await String(format: "R%d %d %d %.4E\n", belowSeg.serialNumber, prevNodeNumber, nextNode.number, belowSeg.resistance())
                
            }
        }
        
        result += ".end\n"
        
        return result
    }
    
    @IBAction func handleMainWdgInductances(_ sender: Any) {
        
        Task {
            
            let indMatrix = await self.doMainWindingInductances()
        }
        
    }
    
    /// Function to calculate the self-inductance of each main winding (as defined by the XL file) as well as the mutual inductance to every other main winding. It is assumed that all Segments of all Windings are in the circuit. The amp values are those calculated using the highest kVA in the XL file.
    /// - Returns: A matrix where entry i,i is the self-inductance of the winding in the 'i' radial position (0 closest to the core), and entry i,j (and j,i) is the mutual inductance beyween coil i and coil j
    func doMainWindingInductances() async -> PchMatrix? {
        
        guard let model = self.currentModel, let xlFile = currentXLfile, let iMatrix = await model.unfactoredM , let fePhase = self.currentFePhase else {
            
            DLog("A valid model, a valid XL file, and an unfactored inductance matrix must be defined!")
            return nil
        }
        
        let indMatrix = await PchMatrix(srcMatrix: iMatrix)
        
        let segments = await model.CoilSegments()
        let numCoils = segments.last!.radialPos + 1
        
        let coilIndMatrix = PchMatrix(matrixType: .general, numType: .Double, rows: UInt(numCoils), columns: UInt(numCoils))
        
        // NOTE: This all assumes that the index in the 'segments' array matches the index in the 'indMatrix' matrix, which I believe it does
        do {
            for i in 0..<numCoils {
            
                let segRange = try await model.SegmentRange(coil: i)
                
                for nextRow in segRange {
                    
                    for nextCol in segRange {
                        
                        if let nextValue:Double = await indMatrix[nextRow, nextCol], let oldValue:Double = await coilIndMatrix[i, i] {
                            
                            // The mutual inductances should be doubled, but ONLY if we are reading them once. The matrix is symmetrical and we'll just go over every single entry and add it.
                            await coilIndMatrix.SetDoubleValue(value: oldValue + nextValue, row: i, col: i)
                            // coilIndMatrix[i, i] = oldValue + nextValue
                        }
                        else {
                            
                            ALog("Error!")
                        }
                    }
                }
            }
        }
        catch {
            
            let alert = NSAlert(error: error)
            let _ = alert.runModal()
            return nil
        }
        
        // get the energy from the last PchFePhase used
        let leakageEnergy = await fePhase.EnergyFromInductance()
        DLog("Energy: \(leakageEnergy)")
        
        // use DelVecchio eq. 4.22 to solve for M12
        let section0 = await fePhase.window.sections[0]
        // Current calculations are a pain because this routine assumes all turns are in the circuit. For a coil with off-load taps, this is the low-current tap, which is NOT what is saved as the 'seriesRMSCurremt'. That is actually the nominal current.
        let I0 = await (section0.seriesRmsCurrent * Complex(sqrt(2))).length
        guard let section1Index = try? await model.SegmentRange(coil: 1).lowerBound else {
            
            DLog("Bad section index!")
            return nil
        }
        let section1 = await fePhase.window.sections[section1Index]
        let I1 = await -(section1.seriesRmsCurrent * Complex(sqrt(2))).length
        var M12 = 2 * leakageEnergy
        M12 -= await coilIndMatrix[0, 0]! * I0 * I0
        await M12 -= coilIndMatrix[1, 1]! * I1 * I1
        M12 /= 2
        M12 /= I0
        M12 /= I1
        await coilIndMatrix.SetDoubleValue(value: M12, row: 0, col: 1)
        await coilIndMatrix.SetDoubleValue(value: M12, row: 1, col: 0)
        // coilIndMatrix[0, 1] = M12
        // coilIndMatrix[1, 0] = M12
        
        print(coilIndMatrix)
        return coilIndMatrix
    }
    
    /*
    @IBAction func handleWdgImpedancePairs(_ sender: Any) {
        
        let kvaImp = doWindingImpedance(coil1: 0, coil2: 1)
        
        if kvaImp.baseVA != 0 && kvaImp.impedancePU != 0 {
            
            print("Impedance: \(kvaImp.impedancePU * 100)% at \(kvaImp.baseVA) kVA")
        }
    } */
    
    /*
    /// Function to get the impedance (in p.u. of the winding with the higher VA) between two coils. If the VA of the two windings is different, the higher of the two is used to do the calculation. Note that if an error occurs (like if coil1 = coil2 or one of the coils does not exist), the tuple (0,0) is returned.
    /// - Parameter coil1: One of the two coils of the calculation, as referred to by its radial position in the phase (0-based)
    /// - Parameter coil2: The other coil in the calculation
    /// - Returns: A tuple where 'baseVA' is the VA upon which the impedance is based; where impedancePU is the impedance in p.u. between the windings at that base
    func doWindingImpedance(coil1:Int, coil2:Int) -> (baseVA:Double, impedancePU:Double) {
        
        guard let model = self.currentModel, let xlFile = currentXLfile else {
            
            DLog("Both a valid model and a valid XL file must be defined!")
            return (0, 0)
        }
        
        guard let energy = try? model.TotalMagneticEnergy(coil1: coil1, coil2: coil2) else {
            
            DLog("Could not calculate energy! (Bad coil designation(s)")
            return (0 , 0)
        }
        
        // if we get here, then coil1 and coil2 are valid and the energy calculation has been successfully done
        let baseVA = 1000.0 / Double(xlFile.numPhases) * (xlFile.windings[coil1].terminal.kVA >= xlFile.windings[coil2].terminal.kVA ? xlFile.windings[coil1].terminal.kVA : xlFile.windings[coil2].terminal.kVA)
        
        // this comes from the Andersen paper for transformer flux calculation using finite elements
        let impedance = (2.0 * π * xlFile.frequency) / baseVA * energy
        
        return (baseVA, impedance)
    } */
    
    // MARK: Menu Validation
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        
        if menuItem == self.zoomInMenuItem || menuItem == self.zoomOutMenuItem || menuItem == self.zoomRectMenuItem || menuItem == self.zoomRectMenuItem || menuItem == self.addGroundMenuItem || menuItem == self.addImpulseMenuItem || menuItem == self.addConnectionMenuItem || menuItem == self.removeConnectionMenuItem || menuItem == self.saveAsCirFileMenuItem || menuItem == saveBmatrixMenuItem {
            
            return self.currentModel != nil
        }
        
        if menuItem == self.mainWdgInductanceMenuItem || menuItem == self.mainWdgImpedanceMenuItem {
            
            return self.currentModel != nil && self.currentXLfile != nil && inductanceIsValid
        }
        
        // get local copies of variables that we access often
        let currentSegs = self.txfoView.currentSegments
        let currentSegsCount = currentSegs.count
        
        if menuItem == self.staticRingOverMenuItem || menuItem == self.staticRingBelowMenuItem || menuItem == self.radialShieldInsideMenuItem {
            
            return self.currentModel != nil && currentSegsCount == 1 && !currentSegs[0].segment.isStaticRing && !currentSegs[0].segment.isRadialShield
        }
        
        if menuItem == self.removeStaticRingMenuItem {
            
            return self.currentModel != nil && currentSegsCount == 1 && currentSegs[0].segment.isStaticRing
        }
        
        if menuItem == self.removeRadialShieldMenuItem {
            
            return self.currentModel != nil && currentSegsCount == 1 && currentSegs[0].segment.isRadialShield
        }
        
        if menuItem == self.combineSegmentsIntoSingleSegmentMenuItem {
            
            return self.currentModel != nil && currentSegsCount > 1 && !self.txfoView.currentSegmentsContainMoreThanOneWinding && !currentSegs.contains(where: {$0.segment.isStaticRing}) && !currentSegs.contains(where: {$0.segment.isRadialShield})
        }
        
        if menuItem == self.interleaveSelectionMenuItem {
            
            var totalBasicSections = 0
            for nextSegment in currentSegs {
                
                totalBasicSections += nextSegment.segment.basicSections.count
            }
            
            return self.currentModel != nil && totalBasicSections > 1 && totalBasicSections % 2 == 0 && !self.txfoView.currentSegmentsContainMoreThanOneWinding && currentSegs[0].segment.basicSections[0].wdgData.type == .disc && !currentSegs.contains(where: {$0.segment.isStaticRing}) && !currentSegs.contains(where: {$0.segment.isRadialShield})
        }
        
        if menuItem == self.showWdgAsSingleSegmentMenuItem {
            
            return self.currentModel != nil && currentSegsCount > 0 && !self.txfoView.currentSegmentsContainMoreThanOneWinding
        }
        
        if menuItem == self.splitSegmentToBasicSectionsMenuItem {
            
            return self.currentModel != nil && currentSegsCount == 1 && currentSegs[0].segment.basicSections.count > 1 && !currentSegs.contains(where: {$0.segment.isStaticRing}) && !currentSegs.contains(where: {$0.segment.isRadialShield})
        }
        
        if menuItem == self.saveMmatrixMenuItem {
            
            return self.currentModel != nil && inductanceIsValid
        }
        
        if menuItem == self.saveUnfactoredMmatrixMenuItem {
            
            return self.currentModel != nil && inductanceIsValid
        }
        
        if menuItem == self.createSimModelMenuItem {
            
            return self.currentModel != nil && self.designIsValid
        }
        
        if menuItem == self.simulateMenuItem {
            
            return self.currentModel != nil && self.designIsValid && self.currentSimModel != nil
        }
        
        if menuItem == self.showWaveformsMenuItem || menuItem == self.showCoilResultsMenuItem || menuItem == self.showVoltageDiffsMenuItem {
            
            return self.currentModel != nil && self.currentSimModel != nil && self.latestSimulationResult != nil
        }
        
        if menuItem == self.saveBaseCmatrixMenuItem {
            
            return self.currentModel != nil && self.capacitanceIsValid
        }
        
        if menuItem == self.saveFixedCmatrixMenuItem {
            
            return self.currentModel != nil && self.capacitanceIsValid
        }
        
        // default to true
        return true
    }
    
    
}

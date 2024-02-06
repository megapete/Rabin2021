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
import UniformTypeIdentifiers
import ComplexModule
import RealModule
import PchBasePackage
import PchMatrixPackage
import PchExcelDesignFilePackage
import PchDialogBoxPackage
import PchProgressIndicatorPackage
import PchFiniteElementPackage

class AppController: NSObject, NSMenuItemValidation, NSWindowDelegate, PchFePhaseDelegate {
    
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
    @IBOutlet weak var indCalcLabel: NSTextField!
    
    /// Window controller to display graphs
    // var graphWindowCtrl:PCH_GraphingWindow? = nil
    
    /// The current basic sections that are loaded in memory
    var currentSections:[BasicSection] = []
    
    /// The current model that is stored in memory. This is what is actually displayed in the TransformerView and what all calculations are performed upon.
    var currentModel:PhaseModel? = nil
    
    /// The current FE model that is stored in memory (this is required becuase the inductance calcualtion takes really long and so is put into a different thread)
    var currentFePhase:PchFePhase? = nil
    
    /// The current core in memory
    var currentCore:Core? = nil
    
    /// The original xlFile used to create the current sections (originally, at least, the only way to create the Basic Sections is by importing an XL file.
    var currentXLfile:PCH_ExcelDesignFile? = nil
    
    /// The theoretical depth of the tank (used for display and ground capacitance calculations)
    var tankDepth:Double = 0.0
    
    /// The current multiplier for window height (used for inductance calculations)
    var currentWindowMultiplier = 3.0
    
    /// The colors of the different layers (for display purposes only)
    static let segmentColors:[NSColor] = [.red, .blue, .orange, .purple, .yellow]
    
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
        self.indCalcProgInd.isHidden = true
        self.indCalcProgInd.minValue = 0.0
        self.indCalcProgInd.maxValue = 100.0
        self.indCalcLabel.isHidden = true
    }
    
    func InitializeController()
    {
        
    }
    
    // MARK: PchFePhaseDelegate routine(s)
    func didFinishInductanceCalculation(phase:PchFePhase) {
        
        // the '===' operator compares references
        guard let fePhase = self.currentFePhase, fePhase === phase else {
            
            DLog("PchFePhase does not match the one in memory!")
            return
        }
        
        DLog("Got inductance completion message!")
        self.inductanceLight.textColor = fePhase.inductanceMatrix != nil && fePhase.inductanceMatrixIsValid ? .green : .red
        
        self.indCalcProgInd.isHidden = true
        self.indCalcLabel.isHidden = true
        
        guard let model = self.currentModel, let feIndMatrix = fePhase.inductanceMatrix, fePhase.inductanceMatrixIsValid else {
            
            DLog("Model is nil or matrix is invalid (or nil)!")
            return
        }
        
        print("Energy (from Inductance): \(fePhase.EnergyFromInductance())")
        
        // save the Cholesky-factored form of the inductance matrix for later computations
        let indMatrix = PchMatrix(srcMatrix: feIndMatrix)
        guard indMatrix.TestPositiveDefinite(overwriteExistingMatrix: true) else {
            
            DLog("Matrix is not positive-definite!")
            return
        }
        
        model.M = indMatrix
    }
    
    func updatePuCompletedInductanceCalculation(puComplete: Double, phase: PchFePhase) {
        
        // the '===' operator compares references
        guard let fePhase = self.currentFePhase, fePhase === phase else {
            
            DLog("PchFePhase does not match the one in memory!")
            return
        }
        
        self.indCalcProgInd.doubleValue = puComplete * 100.0
    }
    
    // MARK: Transformer update routines
    
    /// Function to update the model. If the 'reinitialize' parameter is 'true', then the 'oldSegments' and 'newSegments' parameters are ignored and a new model is created using the xlFile. _It is assumed that oldSegments and newSegments are contiguous and in correct order_. In general, it is assumed that one of either oldSegments or newSegments has only a single member in it.
    /// - Parameter oldSegments: An array of Segments that are to be removed from the model. Must be contiguous and in order.
    /// - Parameter newSegments: An array of Segments to insert into the model. Must be contiguous and in order.
    /// - Parameter xFile: The ExcelDesignFile that was inputted. If this is non-nil and 'reinitialize' is set to true, the existing model is overwtitten using the contents of the file.
    /// - Parameter reinitialize: Boolean value set to true if the entire memory should be reinitialized. If xlFile is non-nil, the it is used to overwrite the exisitng model. Otherwise, the model is reinitialized using the BasicSections in the AppController's currentSections array.
    func updateModel(oldSegments:[Segment], newSegments:[Segment], xlFile:PCH_ExcelDesignFile?, reinitialize:Bool) {
        
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
            self.currentModel = self.initializeModel(basicSections: self.currentSections)
            
            self.initializeViews()
        }
        else {
            
            guard let model = self.currentModel else {
                
                PCH_ErrorAlert(message: "The model does not exist!", info: "Cannot change segments")
                return
            }
            
            model.RemoveSegments(badSegments: oldSegments)
            
            do {
                
                try model.UpdateConnectors(oldSegments: oldSegments, newSegments: newSegments)
                
                try model.AddSegments(newSegments: newSegments)
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
        
        guard let fePhase = CreateFePhase(xlFile: excelFile, model: model) else {
            
            PCH_ErrorAlert(message: "Could not create finite element model!")
            return
        }
        
        guard let feMesh = fePhase.CreateFE_Model() else {
            
            PCH_ErrorAlert(message: "Could not create mesh!")
            return
        }
        
        fePhase.magneticMesh = feMesh
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
                
                let lastSegmentIndex = try model.GetHighestSection(coil: wdgIndex) + firstSegmentIndex
                for segIndex in firstSegmentIndex...lastSegmentIndex {
                    
                    let currentDirection = excelFile.windings[wdgIndex].terminal.terminalNumber == 2 ? -1.0 : 1.0
                    // let currentDivider = excelFile.windings[wdgIndex].isDoubleStack ? 2.0 : 1.0
                    fePhase.window.sections[segIndex].seriesRmsCurrent = Complex(currents[excelFile.windings[wdgIndex].terminal.terminalNumber - 1] * currentDirection) // / currentDivider)
                }
                
                firstSegmentIndex = lastSegmentIndex + 1
            }
            catch {
                
                let alert = NSAlert(error: error)
                let _ = alert.runModal()
                return
            }
        }
        
        guard let _ = fePhase.GetFullModelAndSolve() else {
            
            PCH_ErrorAlert(message: "Could not solve full model!")
            return
        }
        
        guard fePhase.GetEddyLosses() else {
            
            PCH_ErrorAlert(message: "Could not get eddy losses!")
            return
        }
        
        for i in 0..<model.segments.count {
            
            model.segments[i].eddyLossPU = fePhase.window.sections[i].EddyLossPU(atTemp: 20.0)
        }
        
        self.inductanceLight.textColor = .red
        self.indCalcLabel.isHidden = false
        self.indCalcProgInd.isHidden = false
        self.indCalcProgInd.doubleValue = 0.0
        
        fePhase.SetInductanceMatrix()
        // model.M = fePhase.inductanceMatrix;
        
        do {
        
            try model.CalculateCapacitanceMatrix()
            DLog("Coil 0 Cs: \(try model.CoilSeriesCapacitance(coil: 0))")
            DLog("Coil 1 Cs: \(try model.CoilSeriesCapacitance(coil: 1))")
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
    
    /// Initialize the model using the xlFile. If there is already a model in memory, it is lost.
    func initializeModel(basicSections:[BasicSection]) -> PhaseModel?
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
            
            // print("Doing connectors for coil \(coil)")
            
            let axialIndices = BasicSection.CoilEnds(coil: coil, basicSections: basicSections)
            
            guard axialIndices.first >= 0, axialIndices.last >= 0 else {
                
                return nil
            }
            
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
            
            do {
                
                for nextSectionIndex in axialIndices.first...axialIndices.last {
                    
                    let nextSection = basicSections[nextSectionIndex]
                    
                    let newSegment = try Segment(basicSections: [nextSection],  realWindowHeight: self.currentCore!.realWindowHeight, useWindowHeight: self.currentWindowMultiplier * self.currentCore!.realWindowHeight)
                    
                    // The "incoming" connection
                    let incomingConnection = Segment.Connection(segment: lastSegment, connector: incomingConnector, equivalentConnections: [])
                    newSegment.connections.append(incomingConnection)
                    
                    // The "outgoing" connection for the previous Segment
                    if let prevSegment = lastSegment {
                        
                        let outgoingConnection = Segment.Connection(segment: newSegment, connector: outgoingConnector)
                        prevSegment.connections.append(outgoingConnection)
                        // The outgoingConnection of the previous section is equivalent to the incomingConnection of this section, so mark it as such
                        newSegment.AddEquivalentConnections(to: incomingConnection, equ: [Segment.Connection.EquivalentConnection(parent: prevSegment, connection: outgoingConnection)])
                    }
                    
                    // set up the connector for the outgoing connection next time through the loop
                    let fromConnection = Connector.AlternatingLocation(lastLocation: incomingConnector.fromLocation)
                    let toConnection = Connector.StandardToLocation(fromLocation: fromConnection)
                    outgoingConnector = Connector(fromLocation: fromConnection, toLocation: toConnection)
                    incomingConnector = Connector(fromLocation: toConnection, toLocation: fromConnection)
                    
                    // we need to add the final outgoing connector for the last axial section
                    if nextSectionIndex == axialIndices.last {
                        
                        outgoingConnector = Connector(fromLocation: fromConnection, toLocation: .floating)
                        newSegment.connections.append(Segment.Connection(segment: nil, connector: outgoingConnector))
                    }
                    
                    lastSegment = newSegment
                    
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
                        
                        let wdgData = BasicSectionWindingData(type: wType == .disc ? .disc : .helical, discData: BasicSectionWindingData.DiscData(numAxialColumns: nextWinding.numAxialColumns, axialColumnWidth: nextWinding.spacerWidth), layers: BasicSectionWindingData.LayerData(numLayers: 1, interLayerInsulation: 0, ducts: BasicSectionWindingData.LayerData.DuctData(numDucts: 0, ductDimn: 0)), turn: BasicSectionWindingData.TurnData(radialDimn: nextWinding.turnDefinition.radialDimension, axialDimn: nextWinding.turnDefinition.axialDimension, turnInsulation: nextWinding.turnDefinition.cable.strandInsulation + nextWinding.turnDefinition.cable.insulation, resistancePerMeter: nextWinding.turnDefinition.resistancePerMeterAt20C))
                        
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
                
                let turnData = BasicSectionWindingData.TurnData(radialDimn: nextWinding.turnDefinition.radialDimension, axialDimn: nextWinding.turnDefinition.axialDimension, turnInsulation: nextWinding.turnDefinition.cable.strandInsulation + nextWinding.turnDefinition.cable.insulation, resistancePerMeter: nextWinding.turnDefinition.resistancePerMeterAt20C)
                
                let newBasicSection = BasicSection(location: LocStruct(radial: radialPos, axial: axialPos), N: nextWinding.numTurns.max, I: nextWinding.I, wdgData: BasicSectionWindingData(type: bsWdgType, discData: BasicSectionWindingData.DiscData(numAxialColumns: nextWinding.numAxialColumns, axialColumnWidth: nextWinding.spacerWidth), layers: layerData, turn: turnData), rect: NSRect(x: nextWinding.innerDiameter / 2.0, y: axialCenter - nextWinding.electricalHeight / 2.0, width: nextWinding.electricalRadialBuild, height: nextWinding.electricalHeight))
                
                result.append(newBasicSection)
            }
            
            // set up for next time through the loop
            radialPos += 1
        }
        
        return result
    }
    
    /// Function to create the finite-element model that we'll use to get the inductance matrix and eddy losses for the current PhaseModel. It is assumed that 'model' has already been updated (or created) using 'xlFile'.
    func CreateFePhase(xlFile:PCH_ExcelDesignFile, model:PhaseModel) -> PchFePhase? {
        
        let coilSegments = model.CoilSegments()
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
            
            let newFeSection = PchFePhase.Section(innerRadius: nextSegment.r1, radialBuild: nextSegment.r2 - nextSegment.r1, zMin: nextSegment.z1, zMax: nextSegment.z2, totalTurns: nextSegment.N, activeTurns: nextSegment.N, seriesRmsCurrent: Complex(nextSegment.I), frequency: xlFile.frequency, strandsPerTurn: Double(strandsPerTurn), strandsPerLayer: numTurnsRadially * Double(wdgTurn.numCablesRadial) * Double(wdgTurn.cable.numStrandsRadial), strandRadial: wdgTurn.cable.strandRadialDimension, strandAxial: wdgTurn.cable.strandAxialDimension, strandConductor: .CU, numAxialColumns: Double(wdg.numAxialColumns), axialColumnWidth: wdg.spacerWidth)
            
            feSections.append(newFeSection)
        }
        
        let coreCenterToTank = xlFile.tankDepth / 2.0
        let windowHt = xlFile.core.windowHeight
        let constPotPt = NSPoint(x: coreCenterToTank, y: windowHt / 2)
        let feWindow = PchFePhase.Window(zMin: 0.0, zMax: windowHt, rMin: xlFile.core.radius, rMax: coreCenterToTank, constPotentialPoint: constPotPt, sections: feSections)
        
        let fePhase = PchFePhase(window: feWindow, delegate: self)
        
        return fePhase
    }
    
    // MARK: Testing routines
    
    @IBAction func handleCreateSimStruct(_ sender: Any) {
        
        let testStruct = SimulationModel(model: self.currentModel!)
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
            
            self.updateModel(oldSegments: [], newSegments: [], xlFile: xlFile, reinitialize: true)
            
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
    
    @IBAction func handleSaveRawMmatrix(_ sender: Any) {
        
        guard let feModel = self.currentFePhase, let Mmatrix = feModel.inductanceMatrix, feModel.inductanceMatrixIsValid else {
            
            DLog("FeModel or inductance matrix nil (or invalid)!")
            return
        }
        
        guard let uttptxtType = UTType(filenameExtension: "txt") else {
            
            DLog("Couldn't create UTType for txt!");
            return;
        }
        
        let csvFileString = Mmatrix.csv
        
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
    
    @IBAction func handleSaveMmatrix(_ sender: Any) {
        
        guard let model = self.currentModel, let Mmatrix = model.M else {
            
            return
        }
        
        guard let uttptxtType = UTType(filenameExtension: "txt") else {
            
            DLog("Couldn't create UTType for txt!");
            return;
        }
        
        let csvFileString = Mmatrix.csv
        
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
    
    @IBAction func handleBmatrixSave(_ sender: Any) {
        
        guard let model = self.currentModel else {
            
            return
        }
        
        guard let uttptxtType = UTType(filenameExtension: "txt") else {
            
            DLog("Couldn't create UTType for txt!")
            return
        }
        
        guard let Bmatrix = try? model.GetBmatrix() else {
            
            DLog("Couldn't calculate B matrix!")
            return
        }
        
        let csvFileString = Bmatrix.csv
        
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
    
    
    @IBAction func handleSaveBaseCmatrix(_ sender: Any) {
        
        guard let model = self.currentModel, let Cmatrix = model.C else {
            
            return
        }
        
        guard let uttptxtType = UTType(filenameExtension: "txt") else {
            
            DLog("Couldn't create UTType for txt!")
            return
        }
        
        let csvFileString = Cmatrix.csv
        
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
    
    @IBAction func handleSaveFixedCmatrix(_ sender: Any) {
        /*
        guard let model = self.currentModel, let Cmatrix = model.fixedC else {
            
            return
        }
        
        let csvFileString = Cmatrix.csv
        
        let savePanel = NSSavePanel()
        savePanel.title = "Fixed Capacitance Matrix"
        savePanel.message = "Save Capacitance Matrix as CSV file"
        savePanel.allowedFileTypes = ["txt"]
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
         */
    }
    
    
    // MARK: Zoom functions
    @IBAction func handleZoomIn(_ sender: Any) {
        
        self.txfoView.handleZoomIn()
    }
    
    
    
    
    @IBAction func handleZoomOut(_ sender: Any) {
        
        self.txfoView.handleZoomOut()
    }
    
    
    
    
    @IBAction func handleZoomAll(_ sender: Any) {
        
        guard let model = self.currentModel, model.segments.count > 0, let core = self.currentCore else
        {
            return
        }
        
        self.txfoView.handleZoomAll(coreRadius: CGFloat(core.radius), windowHt: CGFloat(core.realWindowHeight), tankWallR: CGFloat(self.tankDepth / 2.0))
    }
    
    
    
    
    @IBAction func handleZoomRect(_ sender: Any) {
        
        guard let model = self.currentModel, model.segments.count > 0 else
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
        guard let model = self.currentModel, model.segments.count > 0 else
        {
            return
        }
        
        // self.txfoView.segments = []
        self.txfoView.currentSegments = []
        
        self.txfoView.removeAllToolTips()
        
        // See the comment for the TransformerView property 'segments' to see why I coded this in this way
        var newSegmentPaths:[SegmentPath] = []
        for nextSegment in model.segments
        {
            let pathColor = AppController.segmentColors[nextSegment.radialPos % AppController.segmentColors.count]
            
            var newSegPath = SegmentPath(segment: nextSegment, segmentColor: pathColor)
            
            newSegPath.toolTipTag = self.txfoView.addToolTip(newSegPath.rect, owner: self.txfoView as Any, userData: nil)
            
            newSegmentPaths.append(newSegPath)
        }
        
        self.txfoView.segments = newSegmentPaths
        self.txfoView.needsDisplay = true
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
        
        if model.SegmentsAreContiguous(segments: segments) {
            
            var newBasicSectionArray:[BasicSection] = []
            
            
            
            for nextSegment in segments {
                
                newBasicSectionArray.append(contentsOf: nextSegment.basicSections)
            }
                        
            do {
                
                // we need to keep track of static rings that are at the ends of new (combined) Segments
                let bottomStaticRing = try model.StaticRingBelow(segment: segments.first!, recursiveCheck: false)
                let topStaticRing = try model.StaticRingAbove(segment: segments.last!, recursiveCheck: false)
                
                let combinedSegment = try Segment(basicSections: newBasicSectionArray, realWindowHeight: model.core.realWindowHeight, useWindowHeight: model.core.adjustedWindHt)
                
                self.updateModel(oldSegments: segments, newSegments: [combinedSegment], xlFile: nil, reinitialize: false)
                
                var capMatrixNeedsUpdate = false
                
                if bottomStaticRing != nil {
                    
                    let bSR = try model.AddStaticRing(adjacentSegment: combinedSegment, above: false)
                    try model.InsertSegment(newSegment: bSR)
                    try model.RemoveStaticRing(staticRing: bottomStaticRing!)
                    capMatrixNeedsUpdate = true
                }
                
                if topStaticRing != nil {
                    
                    let tSR = try model.AddStaticRing(adjacentSegment: combinedSegment, above: true)
                    try model.InsertSegment(newSegment: tSR)
                    try model.RemoveStaticRing(staticRing: topStaticRing!)
                    capMatrixNeedsUpdate = true
                }
                
                if capMatrixNeedsUpdate {
                    
                    try model.CalculateCapacitanceMatrix()
                    print("Coil 0 Cs: \(try model.CoilSeriesCapacitance(coil: 0))")
                    print("Coil 1 Cs: \(try model.CoilSeriesCapacitance(coil: 1))")
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

    
    @IBAction func handleInterleaveSelection(_ sender: Any) {
        
        self.doInterleaveSelection(segmentPaths: self.txfoView.currentSegments)
    }
    
    func doInterleaveSelection(segmentPaths:[SegmentPath]) {
        
        guard let model = self.currentModel, segmentPaths.count > 0 else {
            
            return
        }
        
        guard !segmentPaths.contains(where: {$0.segment.interleaved}) else {
            
            PCH_ErrorAlert(message: "The selection contains at least one interleaved segment!", info: "Cannot 'double-interleave'")
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
        
        if model.SegmentsAreContiguous(segments: segments) {
            
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
                
                self.updateModel(oldSegments: segments, newSegments: interleavedSegments, xlFile: nil, reinitialize: false)
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
        
        do {
            
            for nextBasicSection in segment.basicSections {
                
                newSegments.append(try Segment(basicSections: [nextBasicSection], interleaved: false, isStaticRing: false, isRadialShield: false, realWindowHeight: model.core.realWindowHeight, useWindowHeight: model.core.adjustedWindHt))
            }
            
            self.updateModel(oldSegments: [segment], newSegments: newSegments, xlFile: nil, reinitialize: false)
        }
        catch {
            
            let alert = NSAlert(error: error)
            let _ = alert.runModal()
            return
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
        
        do {
            
            let newStaticRing = try model.AddStaticRing(adjacentSegment: currentSegment.segment, above: true)
            
            try model.InsertSegment(newSegment: newStaticRing)
            
            try model.CalculateCapacitanceMatrix()
            // print("Coil 1 Cs: \(try model.CoilSeriesCapacitance(coil: currentSegment.segment.radialPos))")
            
            self.txfoView.segments.append(SegmentPath(segment: newStaticRing, segmentColor: currentSegment.segmentColor))
            self.txfoView.currentSegments = [self.txfoView.segments.last!]
            
            self.txfoView.needsDisplay = true
        }
        catch {
            
            let alert = NSAlert(error: error)
            let _ = alert.runModal()
            return
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
        
        do {
            
            let newStaticRing = try model.AddStaticRing(adjacentSegment: currentSegment.segment, above: false)
            
            try model.InsertSegment(newSegment: newStaticRing)
            
            try model.CalculateCapacitanceMatrix()
            print("Coil 1 Cs: \(try model.CoilSeriesCapacitance(coil: currentSegment.segment.radialPos))")
            
            self.txfoView.segments.append(SegmentPath(segment: newStaticRing, segmentColor: currentSegment.segmentColor))
            self.txfoView.currentSegments = [self.txfoView.segments.last!]
            
            self.txfoView.needsDisplay = true
        }
        catch {
            
            let alert = NSAlert(error: error)
            let _ = alert.runModal()
            return
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
        
        do {
            
            try model.RemoveStaticRing(staticRing: currentSegment.segment)
            
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
        
        do {
            
            // let hilo = 0.012
            let newRadialShield = try model.AddRadialShieldInside(coil: currentSegment.segment.location.radial, hiloToShield: hilo)
            
            try model.InsertSegment(newSegment: newRadialShield)
            self.txfoView.segments.append(SegmentPath(segment: newRadialShield, segmentColor: .green))
            self.txfoView.currentSegments = [self.txfoView.segments.last!]
            
            self.txfoView.needsDisplay = true
        }
        catch {
            
            let alert = NSAlert(error: error)
            let _ = alert.runModal()
            return
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
        
        do {
            
            try model.RemoveRadialShield(radialShield: currentSegment.segment)
            
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
        
        if saveAsPanel.runModal() == .OK
        {
            if let fileURL = saveAsPanel.url
            {
                if let fileString = self.doCreateCirFile(filename: fileURL.path) {
                    
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
    
    func doCreateCirFile(filename:String) -> String? {
        
        guard let model = self.currentModel else {
            
            DLog("No model is currently defined!")
            return nil
        }
        
        var result:String = "FILE: " + filename.uppercased() + "\n"
        
        // The initial resistance-to-self-inductance id index is 40000
        var resistanceToInductanceIndexID = 40000
        // The initial shunt capacitance id index is 50000
        var shuntIndexID = 50000
        
        for nextNode in model.nodes {
            
            // Start with shunt capacitances from this node
            for nextShuntCap in nextNode.shuntCapacitances {
                
                // make sure we only define the shunt capacitance in one direction
                if nextShuntCap.toNode > nextNode.number {
                    
                    let shuntCap = String(format: "C%d %d %d %.4E\n", shuntIndexID, nextNode.number, nextShuntCap.toNode, nextShuntCap.capacitance)
                    shuntIndexID += 1
                    result += shuntCap
                }
            }
            
            let Cj = nextNode.belowSegment != nil ? nextNode.belowSegment!.seriesCapacitance : 0.0
            let Cj1 = nextNode.aboveSegment != nil ? nextNode.aboveSegment!.seriesCapacitance : 0.0
            
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
                let seriesRes = String(format: "R%d %d %d %.4E\n", belowSeg.serialNumber, prevNodeNumber, nextNode.number, belowSeg.resistance())
                
            }
        }
        
        result += ".end\n"
        
        return result
    }
    
    @IBAction func handleMainWdgInductances(_ sender: Any) {
        
        
        
    }
    
    /// Function to calculate the self-inductance of each main winding (as defined by the XL file) as well as the mutual inductance to every other main winding. It is assumed that all Segments of all Windings are in the circuit. The amp values are those calculated using the highest kVA in the XL file.
    /// - Returns: A matrix where entry i,i is the self-inductance of the winding in the 'i' radial position (0 closest to the core), and entry i,j (and j,i) is the mutual inductance beyween coil i and coil j
    func doMainWindingInductances() /* -> PCH_BaseClass_Matrix? */ {
        
        guard let model = self.currentModel, let xlFile = currentXLfile else {
            
            DLog("Both a valid model and a valid XL file must be defined!")
            return // nil
        }
        
        return // nil
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
            
            return self.currentModel != nil && self.currentXLfile != nil
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
            
            return self.currentModel != nil && totalBasicSections > 1 && totalBasicSections % 2 == 0 && !self.txfoView.currentSegmentsContainMoreThanOneWinding && currentSegs[0].segment.basicSections[0].wdgData.type == .disc && !currentSegs.contains(where: {$0.segment.interleaved}) && !currentSegs.contains(where: {$0.segment.isStaticRing}) && !currentSegs.contains(where: {$0.segment.isRadialShield})
        }
        
        if menuItem == self.showWdgAsSingleSegmentMenuItem {
            
            return self.currentModel != nil && currentSegsCount > 0 && !self.txfoView.currentSegmentsContainMoreThanOneWinding
        }
        
        if menuItem == self.splitSegmentToBasicSectionsMenuItem {
            
            return self.currentModel != nil && currentSegsCount == 1 && currentSegs[0].segment.basicSections.count > 1 && !currentSegs.contains(where: {$0.segment.isStaticRing}) && !currentSegs.contains(where: {$0.segment.isRadialShield})
        }
        
        if menuItem == self.saveMmatrixMenuItem {
            
            return self.currentModel != nil && self.currentModel!.M != nil
        }
        
        if menuItem == self.saveUnfactoredMmatrixMenuItem {
            
            return self.currentFePhase != nil && self.currentFePhase!.inductanceMatrix != nil && self.currentFePhase!.inductanceMatrixIsValid
        }
        
        if menuItem == self.saveBaseCmatrixMenuItem {
            
            return self.currentModel != nil && self.currentModel!.C != nil
        }
        
        if menuItem == self.saveFixedCmatrixMenuItem {
            
            return self.currentModel != nil && self.currentModel!.fixedC != nil
        }
        
        // default to true
        return true
    }
    
    
}

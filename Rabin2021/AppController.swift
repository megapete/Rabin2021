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

import Cocoa

class AppController: NSObject, NSMenuItemValidation, NSWindowDelegate {
    
    /// The main window of the program
    @IBOutlet weak var mainWindow: NSWindow!
    
    /// The transformer view
    @IBOutlet weak var txfoView: TransformerView!
    
    /// Window controller to display graphs
    var graphWindowCtrl:PCH_GraphingWindow? = nil
    
    /// The current basic sections that are loaded in memory
    var currentSections:[BasicSection] = []
    
    /// The current model that is stored in memory. This is what is actually displayed in the TransformerView and what all calculations are performed upon.
    var currentModel:PhaseModel? = nil
    
    /// The current core in memory
    var currentCore:Core? = nil
    
    /// The theoretical depth of the tank (used for display and ground capacitance calculations)
    var tankDepth:Double = 0.0
    
    /// The current multiplier for window height (used for inductance calculations)
    var currentWindowMultiplier = 3.0
    
    /// The colors of the different layers (for display purposes only)
    static let segmentColors:[NSColor] = [.red, .blue, .green, .orange, .purple]
    
    // MARK: Initialization
    override func awakeFromNib() {
        
        txfoView.appController = self
    }
    
    func InitializeController()
    {
        
    }
    
    // MARK: Transformer update routines
    
    /// Function to update the model
    /// - Parameter xFile: The ExcelDesignFile that was inputted
    /// - Parameter reinitialize: Boolean value set to true if the entire memory should be reinitialized
    func updateModel(xlFile:PCH_ExcelDesignFile, reinitialize:Bool) {
        
        self.tankDepth = xlFile.tankDepth
        
        // The idea here is to create the current model as a Core and an array of BasicSections and save it into the class' currentSections property
        self.currentCore = Core(diameter: xlFile.core.diameter, realWindowHeight: xlFile.core.windowHeight, legCenters: xlFile.core.legCenters)
        
        // replace any currently saved basic sections with the new ones
        self.currentSections = self.createBasicSections(xlFile: xlFile)
        
        // initialize the model so that all the BasicSections are modeled
        self.currentModel = self.initializeModel(basicSections: self.currentSections)
        
        self.initializeViews()
        
        print("There are \(self.currentSections.count) sections in the model")
        
    }
    
    func initializeModel(basicSections:[BasicSection]) -> PhaseModel?
    {
        var result:[Segment] = []
        
        Segment.resetSerialNumber()
        
        for nextSection in basicSections {
            
            guard let newSegment = Segment(basicSections: [nextSection],  realWindowHeight: self.currentCore!.realWindowHeight, useWindowHeight: self.currentWindowMultiplier * self.currentCore!.realWindowHeight) else {
                
                ALog("Could not create Segment!")
                return nil
            }
            
            result.append(newSegment)
        }
        
        return PhaseModel(segments: result, core: self.currentCore!)
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
            
            // let numMainAxialSections = 1.0 + numMainGaps
            
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
                        
                        let newBasicSection = BasicSection(location: LocStruct(radial: radialPos, axial: nextAxialPos), N: turnsPerDisc, I: nextWinding.I, wdgType: wType, rect: NSRect(x: nextWinding.innerDiameter / 2.0, y: currentZ, width: nextWinding.electricalRadialBuild, height: discHt))
                        
                        result.append(newBasicSection)
                        
                        currentZ += discPitch
                    }
                    
                    if gapIndex < mainGaps.count {
                        
                        currentZ += (mainGaps[gapIndex] - discPitch)
                        print("Gap center: \(currentZ - mainGaps[gapIndex] / 2.0)")
                        gapIndex += 1
                    }
                    
                    axialPos += nextMainSection
                }
                
            }
            else {
                
                let newBasicSection = BasicSection(location: LocStruct(radial: radialPos, axial: axialPos), N: nextWinding.numTurns.max, I: nextWinding.I, wdgType: wType, rect: NSRect(x: nextWinding.innerDiameter / 2.0, y: axialCenter - nextWinding.electricalHeight / 2.0, width: nextWinding.electricalRadialBuild, height: nextWinding.electricalHeight))
                
                result.append(newBasicSection)
            }
            
            // set up for next time through the loop
            radialPos += 1
        }
        
        return result
    }
    
    // MARK: Testing routines
    @IBAction func handleGetCoil1J(_ sender: Any) {
        
        let dlog = GetNumberDialog(descriptiveText: "Z-Value", unitsText: "metres", noteText: "", windowTitle: "Get Coil1 J")
        
        if dlog.runModal() == .OK {
            
            print("Z = \(dlog.numberValue)")
            print("J = \(self.currentModel!.J(radialPos: 0, realZ: dlog.numberValue))")
        }
    }
    
    @IBAction func handleShowCoil1J(_ sender: Any) {
        
        guard let model = self.currentModel, model.segments.count > 0 else {
            
            return
        }
        
        let integerFormatter = NumberFormatter()
        integerFormatter.numberStyle = .none
        integerFormatter.minimum = 0
        integerFormatter.maximum = NSNumber(integerLiteral: model.segments.count - 1)
        
        let coilNumDlog = GetNumberDialog(descriptiveText: "Coil Number:", unitsText: "", noteText: "(0 is closest to core)", windowTitle: "J For Coil", initialValue: 0.0, fieldFormatter: integerFormatter)
        
        if coilNumDlog.runModal() == .cancel {
            
            return
        }
        
        let radialPos = Int(coilNumDlog.numberValue)
        
        let L = model.realWindowHeight
        
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        var points:[NSPoint] = []
        
        let numPoints = 1000
        for i in 0...numPoints {
            
            print("Point \(i)")
            let ii = Double(i)
            let nextX = ii / Double(numPoints) * L
            
            let nextY = model.J(radialPos: radialPos, realZ: nextX) / 1000.0
            
            minY = min(minY, nextY)
            maxY = max(maxY, nextY)
            
            points.append(NSPoint(x: nextX * 1000, y: nextY))
        }
        
        let grafWidth = L * 1.1 * 1000
        let grafHeight = (maxY - minY) * 1.1
        
        let origin = NSPoint(x: -grafWidth * 0.05, y: -(abs(minY) + grafHeight * 0.05))
        let size = NSSize(width: grafWidth, height: grafHeight)
        
        self.graphWindowCtrl = PCH_GraphingWindow(graphBounds: NSRect(origin: origin, size: size))
        
        self.graphWindowCtrl!.graphView.showAxes(show: true)
        self.graphWindowCtrl!.graphView.dataPaths = [PCH_GraphingView.DataPath(color: AppController.segmentColors[radialPos], points: points)]
        self.graphWindowCtrl!.graphView.needsDisplay = true
    }
    
    @IBAction func handleChangeCoil1(_ sender: Any) {
        
        let sections1 = Array(self.currentSections[0...35])
        let sections2 = Array(self.currentSections[36...71])
        Segment.resetSerialNumber()
        let segment1 = Segment(basicSections: sections1, interleaved: false, realWindowHeight: self.currentCore!.realWindowHeight, useWindowHeight: self.currentCore!.adjustedWindHt)
        let segment2 = Segment(basicSections: sections2, interleaved: false, realWindowHeight: self.currentCore!.realWindowHeight, useWindowHeight: self.currentCore!.adjustedWindHt)
        
        let model = PhaseModel(segments: [segment1!, segment2!], core: self.currentCore!)
        
        let L = model.realWindowHeight
        
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        var points:[NSPoint] = []
        
        print("Checking two-section coil")
        let numPoints = 1000
        for i in 0...numPoints {
            
            print("Point \(i)")
            let ii = Double(i)
            let nextX = ii / Double(numPoints) * L
            
            let nextY = model.J(radialPos: 0, realZ: nextX) / 1000.0
            
            minY = min(minY, nextY)
            maxY = max(maxY, nextY)
            
            points.append(NSPoint(x: nextX * 1000, y: nextY))
        }
        
        let grafWidth = L * 1.1 * 1000
        let grafHeight = (maxY - minY) * 1.1
        
        let origin = NSPoint(x: -grafWidth * 0.05, y: -(abs(minY) + grafHeight * 0.05))
        let size = NSSize(width: grafWidth, height: grafHeight)
        
        self.graphWindowCtrl = PCH_GraphingWindow(graphBounds: NSRect(origin: origin, size: size))
        
        self.graphWindowCtrl!.graphView.showAxes(show: true)
        self.graphWindowCtrl!.graphView.dataPaths = [PCH_GraphingView.DataPath(color: .red, points: points)]
        self.graphWindowCtrl!.graphView.needsDisplay = true
    }
    
    @IBAction func handleTestEVMethod(_ sender: Any) {
        
        let core = Core(diameter: 0.15, realWindowHeight: 0.3, legCenters: 0.25)
        let N1 = 1.0
        let I1 = 1.0
        let N4 = 2.0
        let I4 = I1 * N1 / N4
        let basicSection1 = BasicSection(location: LocStruct(radial: 0, axial: 2), N: N1, I: I1, wdgType: .disc, rect: NSRect(x: 0.091, y: 0.268, width: 0.004, height: 0.004))
        let basicSection2 = BasicSection(location: LocStruct(radial: 0, axial: 1), N: 1, I: 1, wdgType: .disc, rect: NSRect(x: 0.091, y: 0.268 - 0.008, width: 0.004, height: 0.004))
        let basicSection3 = BasicSection(location: LocStruct(radial: 0, axial: 0), N: 1, I: 1, wdgType: .disc, rect: NSRect(x: 0.091, y: 0.268 - 0.016, width: 0.004, height: 0.004))
        let basicSection4 = BasicSection(location: LocStruct(radial: 1, axial: 0), N: N4, I: I4, wdgType: .disc, rect: NSRect(x: 0.100, y: 0.268, width: 0.004, height: 0.004))
        let segment1 = Segment(basicSections: [basicSection1], interleaved: false, realWindowHeight: 0.3, useWindowHeight: 0.3)
        let segment2 = Segment(basicSections: [basicSection2], interleaved: false, realWindowHeight: 0.3, useWindowHeight: 0.3)
        let segment3 = Segment(basicSections: [basicSection3], interleaved: false, realWindowHeight: 0.3, useWindowHeight: 0.3)
        let segment4 = Segment(basicSections: [basicSection4], interleaved: false, realWindowHeight: 0.3, useWindowHeight: 0.3)
        
        let EVLtest1 = EslamianVahidiSegment(segment: segment1!, core: core)
        let EVLtest2 = EslamianVahidiSegment(segment: segment2!, core: core)
        let EVLtest3 = EslamianVahidiSegment(segment: segment3!, core: core)
        let EVLtest4 = EslamianVahidiSegment(segment: segment4!, core: core)
        
        print("Mutual inductance 1-2: \(EVLtest1.M_pu_InWindow(otherSegment: EVLtest2))")
        print("Mutual inductance 2-1: \(EVLtest2.M_pu_InWindow(otherSegment: EVLtest1))")
        print("Mutual inductance 1-3: \(EVLtest1.M_pu_InWindow(otherSegment: EVLtest3))")
        
        let L1 = EVLtest1.L_pu_InWindow()
        let L4 = EVLtest4.L_pu_InWindow()
        let M14 = EVLtest1.M_pu_InWindow(otherSegment: EVLtest4)
        print("Self-inductance (per-unit-length, in window) #1: \(EVLtest1.L_pu_InWindow())")
        print("Self-Inductance (per-unit-length, in window) #4: \(EVLtest4.L_pu_InWindow())")
        
        print("Mutual inductance (per-unit-length, in window) 1-4: \(EVLtest1.M_pu_InWindow(otherSegment: EVLtest4))")
        print("Mutual inductance (per-unit-length, in window) 4-1: \(EVLtest4.M_pu_InWindow(otherSegment: EVLtest1))")
        
        let energy14 = L1 * I1 * I1 + L4 * I4 * I4 + 2 * M14 * I1 * I4
        
        print("Energy: \(energy14)")
        
        print("Self-inductance (per-unit-length, outside window) #1: \(EVLtest1.M_pu_OutsideWindow(otherSegment: EVLtest1))")
        print("Mutual inductance (per-unit-length, outside window) 1-2: \(EVLtest1.M_pu_OutsideWindow(otherSegment: EVLtest2))")
    }
    
    @IBAction func handleGetInductances(_ sender: Any) {
        
        guard let model = self.currentModel, model.segments.count > 0, let core = self.currentCore else {
            
            return
        }
        
        var EV:[EslamianVahidiSegment] = []
        
        for nextSegment in model.segments {
            
            EV.append(EslamianVahidiSegment(segment: nextSegment, core: core))
        }
        
        let M = PCH_BaseClass_Matrix(matrixType: .general, numType: .Double, rows: UInt(EV.count), columns: UInt(EV.count))
        
        print("Getting in-window inductances...")
        for i in 0..<EV.count {
            
            print("Segment #\(i)")
            // Get self-inductance
            let iR1 = EV[i].segment.r1
            let iR2 = EV[i].segment.r2
            M[i, i] = EV[i].L_pu_InWindow() * π * (iR1 + iR2)
            
            for j in i+1..<EV.count {
                
                if j % 50 == 0 {
                    print("To: \(j)")
                }
                
                let innerRadius = min(iR1, EV[j].segment.r1)
                let outerRadius = max(iR2, EV[j].segment.r2)
                // let meanRadius = (innerRadius + outerRadius) / 2.0
                let multiplier = π * (innerRadius + outerRadius)
                let nextM:Double = EV[i].M_pu_InWindow(otherSegment: EV[j]) * multiplier
                
                M[i, j] = nextM
                M[j, i] = nextM
            }
        }
        print("Done!")
        
        print("Inductance array is positive definite: \(M.TestPositiveDefinite())")
    }
    
    @IBAction func handleGetIndMatrix(_ sender: Any) {
        
        guard let model = self.currentModel, model.segments.count > 0, let core = self.currentCore else {
            
            return
        }
        
        print("Creating EV Segments...")
        let evSegments = EslamianVahidiSegment.Create_EV_Array(segments: model.segments, core: core)
        print("Done!\n\nCreating inductance matrix...")
        guard let _ = EslamianVahidiSegment.InductanceMatrix(evSegments: evSegments) else {
            
            DLog("SHIT!")
            return
        }
        
        print("Done!")
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
            
            self.updateModel(xlFile: xlFile, reinitialize: true)
            
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
        
        self.txfoView.segments = []
        
        self.txfoView.removeAllToolTips()
        
        for nextSegment in model.segments
        {
            let pathColor = AppController.segmentColors[nextSegment.radialPos % AppController.segmentColors.count]
            
            var newSegPath = SegmentPath(segment: nextSegment, segmentColor: pathColor)
            
            newSegPath.toolTipTag = self.txfoView.addToolTip(newSegPath.rect, owner: self.txfoView as Any, userData: nil)
            
            // update the currently-selected segment in the TransformerView
            if let currentSegment = self.txfoView.currentSegment
            {
                if currentSegment.segment.serialNumber == nextSegment.serialNumber
                {
                    self.txfoView.currentSegment = newSegPath
                }
            }
            
            self.txfoView.segments.append(newSegPath)
        }
        
        self.txfoView.needsDisplay = true
        
    }
    
    // MARK: Menu routines
    
    @IBAction func handleShowGraph(_ sender: Any) {
        
        DLog("Creating window controller")
        
        self.graphWindowCtrl = PCH_GraphingWindow(graphBounds: NSRect(x: -10.0, y: -10.0, width: 1000.0, height: 400.0))
        
        
    }
    
    
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
    
    // MARK: Menu Validation
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        
        return true
    }
}

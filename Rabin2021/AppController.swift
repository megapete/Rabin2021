//
//  AppController.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-06.
//

// Keys into User Defaults
// Key (String) so that the user doesn't have to go searching for the last folder he opened
let LAST_OPENED_INPUT_FILE_KEY = "PCH_RABIN2021_LastInputFile"

import Cocoa

class AppController: NSObject, NSMenuItemValidation, NSWindowDelegate {
    
    /// The main window of the program
    @IBOutlet weak var mainWindow: NSWindow!
    
    /// The current basic sections that are loaded in memory
    var currentSections:[BasicSection] = []
    
    /// The current core in memory
    var currentCore:Core? = nil
    
    // MARK: Initialization
    func InitializeController()
    {
        
    }
    
    // MARK: Transformer update routines
    
    /// Function to update the model
    /// - Parameter xFile: The ExcelDesignFile that was inputted
    /// - Parameter reinitialize: Boolean value set to true if the entire memory should be reinitialized
    func updateModel(xlFile:PCH_ExcelDesignFile, reinitialize:Bool) {
        
        // The idea here is to create the current model as a Core and an array of BasicSections and save it into the class' currentSections property
        self.currentCore = Core(diameter: xlFile.core.diameter, realWindowHeight: xlFile.core.windowHeight)
        
        // replace any currently saved sections with the new model
        self.currentSections = createBasicSections(xlFile: xlFile)
        
        print("There are \(self.currentSections.count) sections in the model")
        
    }
    
    func createBasicSections(xlFile:PCH_ExcelDesignFile) -> [BasicSection] {
        
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
                var currentZ = nextWinding.bottomEdgePack
                
                for nextMainSection in perSectionDiscs {
                    
                    for sectionIndex in 0..<nextMainSection {
                        
                        let nextAxialPos = axialPos + sectionIndex
                        
                        let newBasicSection = BasicSection(location: LocStruct(radial: radialPos, axial: nextAxialPos), N: turnsPerDisc, I: nextWinding.I, rect: NSRect(x: nextWinding.innerDiameter / 2.0, y: currentZ, width: nextWinding.electricalRadialBuild, height: discHt))
                        
                        result.append(newBasicSection)
                        
                        currentZ += discPitch
                    }
                    
                    if gapIndex < mainGaps.count {
                        
                        currentZ += (mainGaps[gapIndex] - discPitch)
                        gapIndex += 1
                    }
                    
                    axialPos += nextMainSection
                }
                
            }
            else {
                
                let newBasicSection = BasicSection(location: LocStruct(radial: radialPos, axial: axialPos), N: nextWinding.numTurns.max, I: nextWinding.I, rect: NSRect(x: nextWinding.innerDiameter / 2.0, y: nextWinding.bottomEdgePack, width: nextWinding.electricalRadialBuild, height: nextWinding.electricalHeight))
                
                result.append(newBasicSection)
            }
            
            // set up for next time through the loop
            radialPos += 1
        }
        
        return result
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
        
        guard let txfo = self.currentTxfo else
        {
            return
        }
        
        self.txfoView.handleZoomAll(coreRadius: CGFloat(txfo.core.diameter / 2.0), windowHt: CGFloat(txfo.core.windHt), tankWallR: CGFloat(txfo.DistanceFromCoreCenterToTankWall()))
    }
    
    @IBAction func handleZoomRect(_ sender: Any) {
        
        guard self.currentTxfo != nil else
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
        guard let txfo = self.currentTxfo else
        {
            return
        }
        
        self.txfoView.segments = []
        
        self.txfoView.removeAllToolTips()
        
        for nextWdg in txfo.windings
        {
            for nextLayer in nextWdg.layers
            {
                if nextLayer.parentTerminal.andersenNumber < 1
                {
                    continue
                }
                
                let pathColor = TerminalsView.termColors[nextLayer.parentTerminal.andersenNumber - 1]
                
                for nextSegment in nextLayer.segments
                {
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
            }
        }
        
        if !self.fluxLinesAreHidden
        {
            self.doShowHideFluxLines(hide: false)
        }
        else
        {
            self.txfoView.needsDisplay = true
        }
        
        let termSet = txfo.AvailableTerminals()
        
        for nextTerm in termSet
        {
            do
            {
                let terminals = try txfo.TerminalsFromAndersenNumber(termNum: nextTerm)
                var isRef = false
                if let refTerm = txfo.vpnRefTerm
                {
                    if refTerm == nextTerm
                    {
                        isRef = true
                    }
                }
                
                let termLineVolts = try txfo.TerminalLineVoltage(terminal: nextTerm)
                let termVA = try round(txfo.TotalVA(terminal: nextTerm) / 1.0E3) * 1.0E3
                
                self.termsView.SetTermData(termNum: nextTerm, name: terminals[0].name, displayVolts: termLineVolts, VA: termVA, connection: terminals[0].connection, isReference: isRef)
            }
            catch
            {
                // An error occurred
                let alert = NSAlert(error: error)
                let _ = alert.runModal()
                return
            }
        }
        
        self.termsView.UpdateScData()
        
        do
        {
            let vpn = try txfo.VoltsPerTurn()
            self.dataView.SetVpN(newVpN: vpn, refTerm: txfo.vpnRefTerm)
            
            // amp-turns are guaranteed to be 0 if forceAmpTurnsBalance is true
            let newNI = self.preferences.generalPrefs.forceAmpTurnBalance ? 0.0 : try txfo.AmpTurns(forceBalance: self.preferences.generalPrefs.forceAmpTurnBalance, showDistributionDialog: false)
            self.dataView.SetAmpereTurns(newNI: newNI, refTerm: txfo.niRefTerm)
            
            if self.preferences.generalPrefs.keepImpedanceUpdated && txfo.scResults != nil
            {
                self.dataView.SetImpedance(newImpPU: txfo.scResults!.puImpedance, baseMVA: txfo.scResults!.baseMVA)
            }
            else
            {
                self.dataView.SetImpedance(newImpPU: nil, baseMVA: nil)
            }
        }
        catch
        {
            let alert = NSAlert(error: error)
            let _ = alert.runModal()
            return
        }
       
        self.dataView.ResetWarnings()
        
        let warnings = txfo.CheckForWarnings()
        
        for nextWarning in warnings
        {
            self.dataView.AddWarning(warning: nextWarning)
        }
        
        self.dataView.UpdateWarningField()
    }
    
    // MARK: Menu routines
    
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

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
    
    /// The current basic sections that are loaded in memory (used for drawing, among other things)
    var currentSections:[BasicSection] = []
    
    /// The current core in memory
    var currentCore:Core? = nil
    
    // MARK: Transformer update routines
    func updateModel(xlFile:PCH_ExcelDesignFile) {
        
        // The idea here is to create the current model as a Core and an array of BasicSections and save it into the class' currentSections property
        self.currentCore = Core(diameter: xlFile.core.diameter, realWindowHeight: xlFile.core.windowHeight)
        
        // replace any currently saved sections with the new model
        self.currentSections = createBasicSections(xlFile: xlFile)
        
    }
    
    func createBasicSections(xlFile:PCH_ExcelDesignFile) -> [BasicSection] {
        
        var result:[BasicSection] = []
        
        var radialPos = 0
        
        for nextWinding in xlFile.windings {
            
            var axialPos = 0
            let wType = nextWinding.windingType
            
            let numMainRadialSections = 1 + (wType == .layer ? nextWinding.numRadialDucts : 0)
            
            let numMainGaps = (nextWinding.centerGap > 0.0 ? 1 : 0) + (nextWinding.bottomDvGap > 0.0 ? 1 : 0) + (nextWinding.topDvGap > 0.0 ? 1 : 0)
            let numMainAxialSections = 1 + numMainGaps
            
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
    
    
    // MARK: Menu Validation
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        
        return true
    }
}

//
//  AppController.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-06.
//

import Cocoa

class AppController: NSObject, NSMenuItemValidation, NSWindowDelegate {
    
    @IBOutlet weak var mainWindow: NSWindow!
    
    // MARK: File routines
    func doOpen(fileURL:URL) -> Bool
    {
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
            let newTxfo = try PCH_ExcelDesignFile(designFile: fileURL)
            
    
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

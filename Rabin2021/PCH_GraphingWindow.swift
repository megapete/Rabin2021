//
//  PCH_GraphingWindow.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-15.
//

import Cocoa

class PCH_GraphingWindow: NSWindowController, NSWindowDelegate {
    
    @IBOutlet weak var graphView: PCH_GraphingView!
    
    @IBOutlet weak var xLocField: NSTextField!
    @IBOutlet weak var yLocField: NSTextField!
    
    /*
    override var windowNibName: NSNib.Name? {
        get {
            return "PCH_GraphingWindow"
        }
    } */
    
    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        
        print("In windowDidLoad")
        
        graphView.owner = self
    }
    
    func windowDidResize(_ notification: Notification) {
        
        // reset the bounds of the view
    }
    
    
    
}

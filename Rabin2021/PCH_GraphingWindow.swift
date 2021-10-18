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
    
    var bounds:NSRect = NSRect()
    
    init(graphBounds:NSRect) {
        
        super.init(window: nil)
        DLog("Loading NIB")
        if Bundle.main.loadNibNamed("PCH_GraphingWindow", owner: self, topLevelObjects: nil) {
            DLog("NIB loaded")
        }
        else {
            DLog("NIB DID NOT LOAD")
            return
        }
        
        self.showWindow(self)
        self.graphView.wantsLayer = true
        self.graphView.layer?.backgroundColor = .white
        graphView.bounds = graphBounds
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    
    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        
        DLog("Setting view attributes")
        
        // graphView.owner = self
        graphView.wantsLayer = true
        graphView.layer?.backgroundColor = .white
        graphView.bounds = self.bounds
    }
    
    func windowDidResize(_ notification: Notification) {
        
        // reset the bounds of the view
    }
    
    
    
}

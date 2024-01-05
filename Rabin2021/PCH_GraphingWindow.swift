//
//  PCH_GraphingWindow.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-15.
//

import Cocoa
import PchBasePackage

class PCH_GraphingWindow: NSWindowController, NSWindowDelegate {
    
    @IBOutlet weak var graphView: PCH_GraphingView!
    
    @IBOutlet weak var xLocField: NSTextField!
    @IBOutlet weak var yLocField: NSTextField!
    
    var locationFormatter = NumberFormatter()
    
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
        
        if let gWindow = self.window {
            gWindow.acceptsMouseMovedEvents = true
        }
        else {
            DLog("Window not set")
        }
        
        self.graphView.wantsLayer = true
        self.graphView.layer?.backgroundColor = .white
        self.graphView.owner = self
        graphView.bounds = graphBounds
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func awakeFromNib() {
        
        self.locationFormatter.minimumIntegerDigits = 2
        self.locationFormatter.maximumFractionDigits = 3
        
        self.xLocField.formatter = self.locationFormatter
        self.yLocField.formatter = self.locationFormatter
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    }
    
    func windowDidResize(_ notification: Notification) {
        
        // reset the bounds of the view
    }
    
    
    
}

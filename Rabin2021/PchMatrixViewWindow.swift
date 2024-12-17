//
//  PchMatrixViewWindow.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-12-16.
//

import Cocoa
import PchBasePackage
import PchMatrixPackage

class PchMatrixViewWindow: NSWindowController {

    override var windowNibName: String! {
        
        return "PchMatrixViewWindow"
    }
    
    @IBOutlet var viewController: PchMatrixView!
    
    private let matrix:PchMatrix
    
    init(matrix:PchMatrix) {
        
        self.matrix = matrix
        super.init(window: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        viewController.matrix = self.matrix
        
        self.window?.contentView?.addSubview(viewController.view)
    }
    
}

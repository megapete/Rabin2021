//
//  PCH_ProgressIndicatorWindow.swift
//  ImpulseModeler
//
//  Created by PeterCoolAssHuber on 2018-02-24.
//  Copyright © 2018 Peter Huber. All rights reserved.
//

// This is a simple determinate bar-type progress indicator that should be used as a sheet. The method for use is as follows:
// 1) Somewhere in the calling file (the init() routine of a class or struct is perfect) create the instance of the PCH_ProgressIndicatorWindow.
// 2) Just before you need the indicator, call UpdateIndicator() to set all the values for it (including the underlying text). Note that it is always possible to directly set the properties instead, but make sure that the window has loaded first.
// 3) Call beginSheet(:NSWindow:CompletionRoutine) using the parent window as the receiver and passing in the .window property of the PCH_ProgressIndicatorWindow as the NSWindow
// 4) Create a dispatch queue ("myqueue") and use an .async call on the long-time code you want to run
// 5) Occasionaly, within the long-time code, call DispatchQueue.main.async { myProgressIndicatorWindow.UpdateIndicator(value: updatedValue) }
// NOTE: It is necessary to call the update function on the main thread
// 6) When the long-time code is done (but you are still in the myqueue.async block) call endSheet, BUT!!!! Make sure you encapsulate the call in a "DispatchQueue.main.async" block.

import Cocoa

class PCH_ProgressIndicatorWindow: NSWindowController {

    @IBOutlet var indicator: NSProgressIndicator!
    @IBOutlet var indicatorText: NSTextField!
    
    var minValue:Double = 0.0
    var maxValue:Double = 100.0
    var currentValue:Double = 0.0
    var text:String = ""
    
    convenience init()
    {
        self.init(windowNibName: "PCH_ProgressIndicatorWindow")
    }
    
    func ResetIndicator()
    {
        self.currentValue = self.minValue
        
        if self.isWindowLoaded
        {
            self.indicator.doubleValue = self.currentValue
        }
    }
    
    func Increment(by incVal:Double) {
        
        self.currentValue += incVal
        
        if self.isWindowLoaded
        {
            self.indicator.doubleValue = self.currentValue
        }
    }
    
    func UpdateIndicator(value:Double, minValue:Double? = nil, maxValue:Double? = nil, text:String? = nil)
    {
        self.currentValue = value
        
        if minValue != nil
        {
            self.minValue = minValue!
        }
        
        if maxValue != nil
        {
            self.maxValue = maxValue!
        }
        
        if text != nil
        {
            self.text = text!
        }
        
        if self.isWindowLoaded
        {
            self.indicator.minValue = self.minValue
            self.indicator.maxValue = self.maxValue
            self.indicator.doubleValue = self.currentValue
            self.indicatorText.stringValue = self.text
        }
        
    }
    
    override func windowDidLoad()
    {
        super.windowDidLoad()
        
        // DLog("Loaded!")

        self.indicator.minValue = self.minValue
        self.indicator.maxValue = self.maxValue
        self.indicator.doubleValue = self.currentValue
        self.indicatorText.stringValue = self.text
        
    }
    
}

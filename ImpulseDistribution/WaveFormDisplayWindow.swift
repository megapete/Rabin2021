//
//  WaveFormDisplayWindow.swift
//  ImpulseDistribution
//
//  Created by Peter Huber on 2024-02-13.
//

import Cocoa

class WaveFormDisplayWindow: NSWindowController {

    @IBOutlet weak var waveFormView: WaveFormDisplayView!

    // The data to display. Note that to avoid slowing done the interface too much, it is recommended to limit the number of data series (to say, 1000). This is the responsibility of the calling routine.
    // The y values are in their natural units (volts or amps) - the view takes care of scaling them for display.
    var data:[[NSPoint]] = []
    var windowTitle:String = "Waveforms"

    /// What the y values of 'data' represent. Sets the y-axis tick interval and the label units.
    var yQuantity:AxisQuantity = .unitless
    /// The crest voltage of the simulated impulse, in volts
    var peakTestVoltage:Double = 0.0

    override func windowDidLoad() {
        super.windowDidLoad()

        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        if let wfWindow = window {

            wfWindow.title = windowTitle
        }

        waveFormView.wantsLayer = true
        waveFormView.layer?.backgroundColor = .black

        waveFormView.yQuantity = yQuantity
        waveFormView.peakTestVoltage = peakTestVoltage

        waveFormView.RemoveAllDataSeries()

        for nextDataSeries in data {

            waveFormView.AddDataSeries(newData: nextDataSeries)
        }

        waveFormView.UpdateScaleAndZoomWindow()
    }

}

//
//  AppDelegate.swift
//  Rabin2021
//
//  Created by Peter Huber on 2021-10-06.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var appController: AppController!
    @IBOutlet var window: NSWindow!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application

        // The factory defaults for the user preferences. Preferences.ValueOf() falls back on its own if this never runs, so
        // nothing depends on the ordering here - it is done so that the values are visible to 'defaults read' and can be
        // overridden for a single run from the command line. See Preferences.swift.
        Preferences.RegisterFactoryDefaults()

        // A scripted test run, if one was asked for on the command line. This does nothing at all on a normal launch -
        // it needs the -PCH_SelfTest launch argument - and when it does run it terminates the app itself. See
        // SelfTest.swift for how to invoke it and where the report comes out.
        SelfTest.RunIfRequested(controller: appController)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    func application(_ sender:NSApplication, openFile filename:String) -> Bool
    {
        let fixedFileName = (filename as NSString).expandingTildeInPath
        
        let url = URL(fileURLWithPath: fixedFileName, isDirectory: false)
        
        return appController.doOpen(fileURL: url)
    }


}


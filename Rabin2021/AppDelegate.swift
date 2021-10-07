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


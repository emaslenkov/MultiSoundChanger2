//
//  AppDelegate.swift
//  MultiSoundChanger
//
//  Created by Dmitry Medyuho on 02.04.17.
//  Copyright © 2017 Dmitry Medyuho. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    private let applicationController: ApplicationController = ApplicationControllerImp()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        MediaKeyRemapper.installSignalHandlers()
        // The remapping is applied by MediaManager once accessibility is actually granted —
        // remapping without a working key tap would leave the user with dead volume keys.
        applicationController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MediaKeyRemapper.revert()
    }
}

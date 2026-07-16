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
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        installSignalHandlers()
        // The remapping is applied by MediaManager once accessibility is actually granted —
        // remapping without a working key tap would leave the user with dead volume keys.
        applicationController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        applicationController.stop()
    }

    /// SIGTERM/SIGINT run the exact same teardown as a clean quit: hidutil remap, system volume
    /// icon, aggregate lifecycle all go through `ApplicationController.stop()`, so there is exactly
    /// one path to keep in sync rather than three (see `.claude/rules/system-side-effects.md`).
    /// `SIGKILL` can't be caught — documented as a known limitation in README.
    private func installSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT] {
            // Suppress the default disposition, otherwise the process dies before the handler runs.
            signal(signalNumber, SIG_IGN)

            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.applicationController.stop()
                exit(EXIT_SUCCESS)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}

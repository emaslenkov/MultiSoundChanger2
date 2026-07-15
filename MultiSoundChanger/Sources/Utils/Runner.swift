//
//  Runner.swift
//  MultiSoundChanger
//
//  Created by Dmitry Medyuho on 22.04.21.
//  Copyright © 2021 Dmitry Medyuho. All rights reserved.
//

import Cocoa

enum Runner {
    @discardableResult
    static func shell(_ command: String) -> String? {
        let task = Process()
        let pipe = Pipe()

        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: Constants.Paths.shell)

        do {
            try task.run()
        } catch {
            Logger.error(Constants.InnerMessages.shellLaunchError(command: command, error: error.localizedDescription))
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        return output
    }

    static func launchApplication(bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            Logger.error(Constants.InnerMessages.applicationNotFound(bundleIdentifier: bundleIdentifier))
            return
        }

        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error = error {
                Logger.error(Constants.InnerMessages.applicationLaunchError(
                    bundleIdentifier: bundleIdentifier,
                    error: error.localizedDescription
                ))
            }
        }
    }
}

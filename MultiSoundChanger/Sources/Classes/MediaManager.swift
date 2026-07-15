//
//  MediaManager.swift
//  MultiSoundChanger
//
//  Created by Dmitry Medyuho on 15.11.2020.
//  Copyright © 2020 Dmitry Medyuho. All rights reserved.
//

import Cocoa
import Foundation
import MediaKeyTap

// MARK: - Protocols

protocol MediaManagerDelegate: AnyObject {
    func onMediaKeyTap(mediaKey: MediaKey)
}

protocol MediaManager: AnyObject {
    func listenMediaKeyTaps()
    func showOSD(volume: Float, muted: Bool)
}

// MARK: - Implementation

final class MediaManagerImpl: MediaManager {
    private weak var delegate: MediaManagerDelegate?
    private var mediaKeyTap: MediaKeyTap?
    
    init(delegate: MediaManagerDelegate) {
        self.delegate = delegate
    }
    
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    // MARK: Public
    
    func listenMediaKeyTaps() {
        observeMediaKeyOnAccessibiltiyApiChange()
        startMediaKeyTap()
    }
    
    func showOSD(volume: Float, muted: Bool) {
        // OSD.framework's OSDUIHelper no longer draws on macOS 26, so the app renders its own HUD
        VolumeHUD.shared.show(volume: volume, muted: muted)
    }
    
    // MARK: Private
    
    @discardableResult
    private func acquirePrivileges() -> Bool {
        let trusted = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let privOptions = [trusted: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(privOptions)

        if accessEnabled {
            Logger.warning(Constants.InnerMessages.accessEnabled)
        } else {
            Logger.warning(Constants.InnerMessages.accessDenied)
        }

        return accessEnabled
    }

    /// The remapping is tied to the key tap, and deliberately so.
    ///
    /// Remapping hides the volume keys from the system so this app can handle them. Without
    /// accessibility there is no key tap to handle anything — so remapping would leave the user with
    /// volume keys that do nothing at all. Better to hand the keys back to the system and let them
    /// work normally until the permission is granted; `onAccessibilityNotification` brings us back
    /// here the moment it is.
    private func startMediaKeyTap() {
        guard acquirePrivileges() else {
            mediaKeyTap?.stop()
            mediaKeyTap = nil
            MediaKeyRemapper.revert()
            Logger.warning(Constants.InnerMessages.remapSkippedNoAccess)
            return
        }

        MediaKeyRemapper.apply()

        let keys: [MediaKey] = [
            .volumeUp,
            .volumeDown,
            .mute
        ]

        mediaKeyTap?.stop()
        mediaKeyTap = MediaKeyTap(delegate: self, for: keys, observeBuiltIn: true)
        mediaKeyTap?.start()
    }
    
    private func observeMediaKeyOnAccessibiltiyApiChange() {
        let notificaion = NSNotification.Name(rawValue: Constants.Notifications.accessibility)
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(onAccessibilityNotification),
            name: notificaion,
            object: nil
        )
    }
    
    @objc
    private func onAccessibilityNotification(_ aNotification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.startMediaKeyTap()
        }
    }
}

// MARK: - MediaKeyTapDelegate

extension MediaManagerImpl: MediaKeyTapDelegate {
    func handle(mediaKey: MediaKey, event: KeyEvent?, modifiers: NSEvent.ModifierFlags?) {
        delegate?.onMediaKeyTap(mediaKey: mediaKey)
    }
}

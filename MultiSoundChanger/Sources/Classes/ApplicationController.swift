//
//  ApplicationController.swift
//  MultiSoundChanger
//
//  Created by Dmitry Medyuho on 20.04.21.
//  Copyright © 2021 Dmitry Medyuho. All rights reserved.
//

import Foundation
import MediaKeyTap

// MARK: - Protocols

protocol ApplicationController: AnyObject {
    func start()
    func stop()
}

// MARK: - Implementation

final class ApplicationControllerImpl: ApplicationController {
    private let audio: Audio = AudioImpl()
    private lazy var aggregateDeviceManager: AggregateDeviceManager = AggregateDeviceManagerImpl(audio: audio)
    private lazy var audioManager: AudioManager = AudioManagerImpl(audio: audio, aggregateDeviceManager: aggregateDeviceManager)
    private lazy var systemVolumeIconController: SystemVolumeIconController = SystemVolumeIconControllerImpl()
    private lazy var launchAtLoginController: LaunchAtLoginController = LaunchAtLoginControllerImpl()
    private lazy var mediaManager: MediaManager = MediaManagerImpl(delegate: self)
    private lazy var statusBarController: StatusBarController = StatusBarControllerImpl(
        audioManager: audioManager,
        systemVolumeIconController: systemVolumeIconController,
        launchAtLoginController: launchAtLoginController
    )

    func start() {
        audioManager.restoreSelectionAtLaunch()

        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.hideSystemVolumeIcon) {
            systemVolumeIconController.hide()
        } else {
            systemVolumeIconController.repairIfNeeded()
        }

        statusBarController.createMenu()
        mediaManager.listenMediaKeyTaps()

        // Follow the system default output when it changes from outside the app (headphones
        // auto-switch, Control Center, another app). The listener fires on the main queue; the
        // audio manager reconciles our selection, and only a real change refreshes the menu (A-10).
        audio.addDefaultOutputDeviceListener { [weak self] in
            guard let self = self else {
                return
            }
            if self.audioManager.reconcileWithSystemDefault() {
                self.statusBarController.refreshAfterExternalChange()
            }
        }
    }

    /// Teardown for a clean quit and for SIGTERM/SIGINT (see `AppDelegate`). Deliberately does
    /// *not* touch the multi-output aggregate: the hybrid lifecycle (PLAN-multi-output.md,
    /// decision 3) already destroys it the moment the selection collapses below 2 devices, live,
    /// as it happens — a still-active (≥2) selection is meant to be left standing at exit, so
    /// there is nothing left to do here.
    func stop() {
        audio.removeDefaultOutputDeviceListener()

        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.hideSystemVolumeIcon) {
            systemVolumeIconController.restore()
        }
        MediaKeyRemapper.revert()
    }
}

// MARK: - MediaManagerDelegate

extension ApplicationControllerImpl: MediaManagerDelegate {
    func onMediaKeyTap(mediaKey: MediaKey) {
        guard let selectedDeviceVolume = audioManager.getSelectedDeviceVolume() else {
            return
        }
        
        // Snap-to-grid before stepping (VolumeMath): key presses always land on multiples of 1/16.
        var volume: Float = VolumeMath.snapped(selectedDeviceVolume)

        switch mediaKey {
        case .volumeUp:
            volume = VolumeMath.increased(from: selectedDeviceVolume)
            audioManager.setSelectedDeviceVolume(masterChannelLevel: volume, leftChannelLevel: volume, rightChannelLevel: volume)

        case .volumeDown:
            volume = VolumeMath.decreased(from: selectedDeviceVolume)
            audioManager.setSelectedDeviceVolume(masterChannelLevel: volume, leftChannelLevel: volume, rightChannelLevel: volume)

        case .mute:
            audioManager.toggleMute()
            if audioManager.isSelectedDeviceMuted() {
                volume = 0
            } else {
                volume = audioManager.getSelectedDeviceVolume() ?? 0
            }
            
        default:
            break
        }
        
        let correctedVolume = volume * 100

        statusBarController.updateVolume(value: correctedVolume)
        mediaManager.showOSD(volume: correctedVolume, muted: audioManager.isMuted)
        
        Logger.debug(Constants.InnerMessages.selectedDeviceVolume(volume: String(correctedVolume)))
    }
}

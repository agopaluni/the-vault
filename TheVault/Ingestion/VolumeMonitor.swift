//
//  VolumeMonitor.swift
//  The Vault
//
//  Watches for volumes mounting / unmounting via NSWorkspace notifications so
//  the sidebar can grey out sources whose drive (SD card, SSD, external) was
//  ejected, and light them back up when re-attached.
//

import Foundation
import AppKit

@MainActor
final class VolumeMonitor: ObservableObject {
    /// Called whenever a volume mounts or unmounts so the store can re-check.
    var onChange: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification
        ]
        for name in names {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.onChange?()
            }
            observers.append(token)
        }
    }

    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.forEach { nc.removeObserver($0) }
        observers.removeAll()
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        observers.forEach { nc.removeObserver($0) }
    }
}

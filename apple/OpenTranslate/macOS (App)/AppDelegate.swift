//
//  AppDelegate.swift
//  macOS (App)
//
//  Created by Nikita Rabykin on 19.6.2026.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.windows.forEach { window in
            window.title = "OpenTranslate"
            window.styleMask.insert(.resizable)
            window.contentMinSize = NSSize(width: 720, height: 520)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

}

// ScreenMonitor.swift
import AppKit
import Observation

@Observable
class ScreenMonitor {
    var panels: [CGDirectDisplayID: MirrorDockPanel] = [:]
    var dockState: DockState

    private func readEnabledScreen(_ key: String) -> Bool? {
        guard let dict = UserDefaults.standard.dictionary(forKey: "enabledScreens"),
              let value = dict[key] else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private func writeEnabledScreens(_ screens: [String: Bool]) {
        UserDefaults.standard.set(screens, forKey: "enabledScreens")
    }

    private var allEnabledScreens: [String: Bool] {
        guard let dict = UserDefaults.standard.dictionary(forKey: "enabledScreens") else { return [:] }
        var result: [String: Bool] = [:]
        for (key, value) in dict {
            if let num = value as? NSNumber {
                result[key] = num.boolValue
            }
        }
        return result
    }

    init(dockState: DockState) {
        self.dockState = dockState
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        refreshPanels()
    }

    @objc private func screensChanged() {
        refreshPanels()
    }

    /// The main display is the one that owns the menu bar (always NSScreen.screens.first).
    /// The native Dock lives there, so the mirror must never be drawn on it.
    static func isMainDisplay(_ screen: NSScreen) -> Bool {
        guard let mainScreen = NSScreen.screens.first,
              let mainID = displayID(for: mainScreen),
              let screenID = displayID(for: screen) else { return false }
        return screenID == mainID
    }

    static var mainDisplayID: CGDirectDisplayID? {
        guard let mainScreen = NSScreen.screens.first else { return nil }
        return displayID(for: mainScreen)
    }

    /// Displays that should host a mirror dock: every connected screen except the main one,
    /// further filtered by the per-screen toggle stored in Settings.
    func targetDisplayIDs() -> [CGDirectDisplayID] {
        NSScreen.screens.compactMap { screen -> CGDirectDisplayID? in
            guard let id = ScreenMonitor.displayID(for: screen) else { return nil }
            guard !ScreenMonitor.isMainDisplay(screen) else { return nil }
            return isEnabled(id) ? id : nil
        }
    }

    func refreshPanels() {
        let targets = Set(targetDisplayIDs())

        // Tear down panels whose screen is gone, became the main display, or was switched off.
        for id in panels.keys where !targets.contains(id) {
            panels[id]?.close()
            panels.removeValue(forKey: id)
        }

        // Create or reposition panels on the remaining (secondary) displays.
        for screen in NSScreen.screens {
            guard let displayID = ScreenMonitor.displayID(for: screen),
                  targets.contains(displayID) else { continue }
            if let panel = panels[displayID] {
                panel.updatePosition()
            } else {
                panels[displayID] = MirrorDockPanel(screen: screen, dockState: dockState)
            }
        }
    }

    func isEnabled(_ displayID: CGDirectDisplayID) -> Bool {
        // The main display is always excluded, regardless of what Settings stored earlier.
        if displayID == ScreenMonitor.mainDisplayID { return false }
        if let stored = readEnabledScreen(String(displayID)) {
            return stored
        }
        return true
    }

    func setEnabled(_ displayID: CGDirectDisplayID, enabled: Bool) {
        var current = allEnabledScreens
        current[String(displayID)] = enabled
        writeEnabledScreens(current)
        refreshPanels()
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

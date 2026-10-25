// DockConfigReader.swift
import Foundation
import AppKit

// MARK: - DockConfigReader

struct DockConfigReader {

    /// Parses the macOS Dock preferences plist and returns the items and display settings.
    /// If the plist cannot be read, returns empty items with default tileSize/orientation.
    static func parse() -> (items: [DockItem], tileSize: CGFloat, orientation: String) {
        let plistPath = NSHomeDirectory() + "/Library/Preferences/com.apple.dock.plist"
        let plistURL = URL(fileURLWithPath: plistPath)

        guard
            let data = try? Data(contentsOf: plistURL),
            let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let plist = raw as? [String: Any]
        else {
            return (items: [], tileSize: 49, orientation: "bottom")
        }

        let tileSize = CGFloat((plist["tilesize"] as? Int) ?? 49)
        let orientation = (plist["orientation"] as? String) ?? "bottom"

        var items: [DockItem] = []

        // persistent-apps
        if let persistentApps = plist["persistent-apps"] as? [[String: Any]] {
            for entry in persistentApps {
                if let item = parsePersistentApp(entry, section: .pinnedApps) {
                    items.append(item)
                }
            }
        }

        // recent-apps
        if let recentApps = plist["recent-apps"] as? [[String: Any]] {
            for entry in recentApps {
                if let item = parsePersistentApp(entry, section: .recentApps) {
                    items.append(item)
                }
            }
        }

        // persistent-others (folders, files)
        if let persistentOthers = plist["persistent-others"] as? [[String: Any]] {
            for entry in persistentOthers {
                if let item = parsePersistentOther(entry) {
                    items.append(item)
                }
            }
        }

        // Inject system items that the real Dock renders but are NOT stored as
        // tiles in com.apple.dock.plist:
        //  - Finder is always shown at the far left (like the native Dock).
        //  - Trash is always shown at the far right of the "others" section.
        if let finder = Self.makeFinderItem() {
            items.insert(finder, at: 0)
        }
        if let trash = Self.makeTrashItem(isFull: plist["trash-full"] as? Bool ?? false) {
            items.append(trash)
        }

        return (items: items, tileSize: tileSize, orientation: orientation)
    }

    // MARK: - System items (Finder / Trash)

    /// The real Dock always shows Finder at the far left, but it is not a
    /// persistent-app tile in the plist — synthesize it so the mirror matches.
    private static func makeFinderItem() -> DockItem? {
        let path = "/System/Library/CoreServices/Finder.app"
        let icon = NSWorkspace.shared.icon(forFile: path)
        let isRunning = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first != nil
        return DockItem(
            id: "system-finder",
            name: "Finder",
            bundleIdentifier: "com.apple.finder",
            path: path,
            icon: icon,
            isRunning: isRunning,
            section: .pinnedApps
        )
    }

    /// The real Dock always shows the Trash at the far right, but it is rendered
    /// by the system (not a persistent-other tile) — synthesize it so the mirror matches.
    private static func makeTrashItem(isFull: Bool) -> DockItem? {
        let trashPath = (NSHomeDirectory() as NSString).appendingPathComponent(".Trash")
        let icon = NSImage(named: isFull ? "NSImageNameTrashFull" : "NSImageNameTrashEmpty")
            ?? NSWorkspace.shared.icon(forFile: trashPath)
        return DockItem(
            id: "system-trash",
            name: "废纸篓",
            bundleIdentifier: nil,
            path: trashPath,
            icon: icon,
            section: .persistentOthers
        )
    }

    // MARK: - Private helpers

    /// Parses a persistent-apps or recent-apps entry.
    private static func parsePersistentApp(_ entry: [String: Any], section: DockSection) -> DockItem? {
        guard
            let tileData = entry["tile-data"] as? [String: Any],
            let fileData = tileData["file-data"] as? [String: Any],
            let urlString = fileData["_CFURLString"] as? String,
            let url = URL(string: urlString)
        else {
            return nil
        }

        let path = url.path
        let name = (tileData["file-label"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let bundleIdentifier = tileData["bundle-identifier"] as? String
        let icon = NSWorkspace.shared.icon(forFile: path)

        return DockItem(
            name: name,
            bundleIdentifier: bundleIdentifier,
            path: path,
            icon: icon,
            section: section
        )
    }

    /// Parses a persistent-others entry (folders, stacks, files).
    private static func parsePersistentOther(_ entry: [String: Any]) -> DockItem? {
        guard
            let tileData = entry["tile-data"] as? [String: Any],
            let fileData = tileData["file-data"] as? [String: Any],
            let urlString = fileData["_CFURLString"] as? String,
            let url = URL(string: urlString)
        else {
            return nil
        }

        let path = url.path
        let name = (tileData["file-label"] as? String) ?? url.lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: path)

        return DockItem(
            name: name,
            bundleIdentifier: nil,
            path: path,
            icon: icon,
            section: .persistentOthers
        )
    }
}

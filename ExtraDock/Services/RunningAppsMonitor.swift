// RunningAppsMonitor.swift
import AppKit
import Combine

/// Snapshot of one running application that the native Dock would show.
struct RunningAppInfo {
    let name: String
    let bundleIdentifier: String?
    let path: String
    let launchDate: Date
}

class RunningAppsMonitor: ObservableObject {
    private(set) var runningBundleIDs: Set<String> = []
    /// Regular (Dock-visible) applications, ordered by launch time like the native Dock.
    private(set) var runningApps: [RunningAppInfo] = []
    private var observation: NSKeyValueObservation?
    var onChange: ((Set<String>) -> Void)?

    init() {
        refresh()
        observation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    private func refresh() {
        let apps: [RunningAppInfo] = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
            .compactMap { app in
                guard let url = app.bundleURL else { return nil }
                return RunningAppInfo(
                    name: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                    bundleIdentifier: app.bundleIdentifier,
                    path: url.path,
                    launchDate: app.launchDate ?? Date()
                )
            }

        let ids = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        if ids != runningBundleIDs || apps.map(\.path) != runningApps.map(\.path) {
            runningBundleIDs = ids
            runningApps = apps
            onChange?(ids)
        }
    }
}

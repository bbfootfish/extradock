import SwiftUI

struct DockBarView: View {
    var dockState: DockState

    var body: some View {
        HStack(spacing: 0) {
            let apps = appItems()
            let others = otherItems()
            let size = dockState.scaledTileSize

            if !apps.isEmpty {
                ForEach(apps) { item in DockItemView(item: item, tileSize: size) }
            }
            if !apps.isEmpty && !others.isEmpty {
                DockSeparatorView(height: size)
            }
            if !others.isEmpty {
                ForEach(others) { item in DockItemView(item: item, tileSize: size) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    /// Everything left of the separator: Finder, pinned apps, running apps and recent apps —
    /// exactly like the native Dock, which uses a single separator before the folders/Trash.
    private func appItems() -> [DockItem] {
        dockState.items.filter { $0.section != .persistentOthers }
    }

    private func otherItems() -> [DockItem] {
        dockState.items.filter { $0.section == .persistentOthers }
    }
}

import AppKit
import SwiftUI
import StackbarCore

/// What the dropdown panel shows.
@MainActor
@Observable
final class DropdownModel {
    struct Item: Identifiable {
        var id: UInt32 { menuBarItem.window.windowID }
        var menuBarItem: MenuBarItem
        /// Position in the grid (`DropdownGrid`), panel content coordinates.
        var frame: Rect
        /// The latest capture; nil until the item was on-screen once.
        var image: NSImage?
        /// Shown instead of the image when there is none (items behind the notch).
        var appIcon: NSImage?
        /// "App – Item" for the footer.
        var name: String
    }

    static let minimumWidth = 240.0

    var items: [Item] = []
    var gridWidth = 0.0
    var gridHeight = 0.0
    var hovered: UInt32?
    var permissions = PermissionState.current
    /// The last refresh found no items left of the divider.
    var isEmpty = false
    /// Why the last refresh couldn't run, if it couldn't.
    var notice: String?
    @ObservationIgnored var onSelect: (MenuBarItem) -> Void = { _ in }

    var width: Double { max(gridWidth, Self.minimumWidth) }

    var footer: String {
        if let hovered, let item = items.first(where: { $0.id == hovered }) { return item.name }
        if let notice { return notice }
        if !permissions.accessibility {
            return "Stackbar needs Accessibility to find the dropdown items and open their menus."
        }
        if isEmpty {
            return "No items in the dropdown yet. Right-click the Stackbar icon → Show All Items, "
                + "then ⌘-drag items to the left of the divider (the slanted line)."
        }
        if !permissions.screenRecording {
            return "Grant Screen Recording to see the items' current images."
        }
        return items.isEmpty ? "Looking for items…" : "Click an item to open its menu."
    }
}

struct DropdownView: View {
    @Bindable var model: DropdownModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.items.isEmpty {
                ZStack(alignment: .topLeading) {
                    ForEach(model.items) { item in
                        DropdownCell(item: item, isHovered: model.hovered == item.id) {
                            model.onSelect(item.menuBarItem)
                        }
                        .onHover { inside in
                            if inside {
                                model.hovered = item.id
                            } else if model.hovered == item.id {
                                model.hovered = nil
                            }
                        }
                        .offset(x: item.frame.x, y: item.frame.y)
                    }
                }
                .frame(width: model.gridWidth, height: model.gridHeight, alignment: .topLeading)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(model.footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if model.hovered == nil {
                    if !model.permissions.accessibility {
                        Button("Grant") { PermissionState.requestAccessibility() }.controlSize(.small)
                    } else if !model.permissions.screenRecording {
                        Button("Grant") { PermissionState.requestScreenRecording() }.controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, model.items.isEmpty ? 8 : 2)
            .padding(.bottom, 8)
        }
        .frame(width: model.width, alignment: .leading)
    }
}

/// One item: its captured image at menu bar size, or its app's icon.
private struct DropdownCell: View {
    var item: DropdownModel.Item
    var isHovered: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.15) : Color.clear)
                if let image = item.image {
                    Image(nsImage: image)
                } else if let icon = item.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "questionmark.square.dashed")
                }
            }
            .frame(width: item.frame.width, height: item.frame.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

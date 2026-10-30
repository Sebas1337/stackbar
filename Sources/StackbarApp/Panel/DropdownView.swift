import AppKit
import SwiftUI
import StackbarCore

/// What the dropdown panel shows: one row per dropdown item, like a menu.
@MainActor
@Observable
final class DropdownModel {
    struct Item: Identifiable {
        var id: UInt32 { menuBarItem.window.windowID }
        var menuBarItem: MenuBarItem
        /// The item's size in the menu bar; its image is shown at this size.
        var size: CGSize
        /// The latest capture; nil until the item was captured once.
        var image: NSImage?
        /// Shown instead of the image when there is none.
        var appIcon: NSImage?
        /// "App – Item".
        var name: String
    }

    static let minimumWidth = 220.0
    static let maximumWidth = 360.0

    var items: [Item] = []
    var hovered: UInt32?
    var permissions = PermissionState.current
    /// The last refresh found no items left of the divider.
    var isEmpty = false
    /// Why the last refresh couldn't run, if it couldn't.
    var notice: String?
    /// A capture is running (the update button is disabled meanwhile).
    var isUpdating = false
    @ObservationIgnored var onSelect: (MenuBarItem) -> Void = { _ in }
    @ObservationIgnored var onUpdate: () -> Void = {}
    @ObservationIgnored var onSettings: () -> Void = {}

    var dropdownItems: [Item] { items.filter { $0.menuBarItem.section == .dropdown } }
    /// Bar items macOS hides because the bar is full (`MenuBarLayout.panelItems`).
    var hiddenBarItems: [Item] { items.filter { $0.menuBarItem.section == .bar } }

    /// All images in one column, as wide as the widest item.
    var imageColumnWidth: CGFloat { items.map(\.size.width).max() ?? 0 }

    /// A line under the rows, only when something needs saying.
    var footer: String? {
        if let notice { return notice }
        if !permissions.accessibility {
            return "Stackbar needs Accessibility to find the dropdown items and open their menus."
        }
        if isEmpty {
            return "No items in the dropdown yet. Open Settings and drag items into the Dropdown list."
        }
        if !permissions.screenRecording {
            return "Grant Screen Recording to see the items' current images."
        }
        return items.isEmpty ? "Looking for items…" : nil
    }
}

struct DropdownView: View {
    @Bindable var model: DropdownModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.dropdownItems) { item in row(item) }
            if !model.hiddenBarItems.isEmpty {
                // Bar items a full menu bar hides: reachable nowhere else.
                Text("Hidden: the menu bar is full")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, model.dropdownItems.isEmpty ? 2 : 8)
                    .padding(.bottom, 2)
                ForEach(model.hiddenBarItems) { item in row(item) }
            }
            if let footer = model.footer {
                HStack(alignment: .firstTextBaseline) {
                    Text(footer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if !model.permissions.accessibility {
                        Button("Grant") { PermissionState.requestAccessibility() }.controlSize(.small)
                    } else if !model.permissions.screenRecording {
                        Button("Grant") { PermissionState.requestScreenRecording() }.controlSize(.small)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            Divider().padding(.vertical, 3)
            HStack {
                Button {
                    model.onSettings()
                } label: {
                    Label("Settings…", systemImage: "gearshape").font(.caption)
                }
                .buttonStyle(.borderless)
                Spacer()
                if !model.items.isEmpty {
                    // Images are captured once; capturing flashes the menu bar and shows macOS's
                    // screen recording indicator, so refreshing them is the user's call.
                    Button {
                        model.onUpdate()
                    } label: {
                        Label(model.isUpdating ? "Updating…" : "Update Images", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isUpdating)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 3)
        }
        .padding(5)
        .frame(minWidth: DropdownModel.minimumWidth, maxWidth: DropdownModel.maximumWidth, alignment: .leading)
    }

    private func row(_ item: DropdownModel.Item) -> some View {
        DropdownRow(item: item, imageWidth: model.imageColumnWidth, isHovered: model.hovered == item.id) {
            model.onSelect(item.menuBarItem)
        }
        .onHover { inside in
            if inside {
                model.hovered = item.id
            } else if model.hovered == item.id {
                model.hovered = nil
            }
        }
    }
}

/// One item: its captured image (or its app's icon) and its name, highlighted on hover like a
/// menu item.
private struct DropdownRow: View {
    var item: DropdownModel.Item
    var imageWidth: CGFloat
    var isHovered: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Group {
                    if let image = item.image {
                        Image(nsImage: image)
                    } else if let icon = item.appIcon {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "questionmark.square.dashed")
                    }
                }
                .frame(width: imageWidth, height: item.size.height)
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isHovered ? Color.white : Color.primary)
                Spacer(minLength: 8)
            }
            .padding(.trailing, 6)
            .background(
                RoundedRectangle(cornerRadius: 5).fill(isHovered ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

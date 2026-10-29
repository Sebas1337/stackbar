import AppKit
import SwiftUI
import StackbarCore

/// Settings: two lists, Menu Bar and Dropdown; dragging an item from one to the other moves it.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drag items between the lists. Stackbar moves them in the menu bar for you; the cursor hides for a moment while it does.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                SectionList(title: "Menu Bar", subtitle: "Always visible", section: .bar, model: model)
                SectionList(title: "Dropdown", subtitle: "In Stackbar's panel", section: .dropdown, model: model)
            }
            if let notice = model.notice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let status = model.status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 380)
    }
}

/// One list; items dropped on it are assigned to its section.
private struct SectionList: View {
    var title: String
    var subtitle: String
    var section: StackbarCore.Section
    var model: SettingsModel
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.rows(in: section)) { row in
                        SettingsRow(row: row, imageWidth: model.imageWidth, isDark: model.menuBarIsDark)
                            .modifier(Draggable(row: row))
                            .contextMenu {
                                if row.canMove {
                                    let other: StackbarCore.Section = section == .bar ? .dropdown : .bar
                                    Button(other == .bar ? "Move to Menu Bar" : "Move to Dropdown") {
                                        model.onAssign(row, other)
                                    }
                                }
                            }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isTargeted ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isTargeted ? 2 : 1)
            )
            .dropDestination(for: String.self) { ids, _ in
                model.drop(ids, into: section)
                return true
            } isTargeted: { isTargeted = $0 }
        }
    }
}

/// Only movable rows can be dragged.
private struct Draggable: ViewModifier {
    var row: SettingsModel.Row

    func body(content: Content) -> some View {
        if row.canMove {
            content.draggable(row.id) { Text(row.name).padding(4) }
        } else {
            content
        }
    }
}

/// An item's image on the menu bar's background (or its app's icon) and its name.
private struct SettingsRow: View {
    var row: SettingsModel.Row
    var imageWidth: CGFloat
    var isDark: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let image = row.appearance?.image {
                    Image(nsImage: image)
                } else if let icon = row.appearance?.appIcon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                } else {
                    Image(systemName: "questionmark.square.dashed")
                }
            }
            .frame(width: imageWidth, height: row.appearance?.size.height ?? 24)
            .background(RoundedRectangle(cornerRadius: 4).fill(isDark ? Color(white: 0.16) : Color(white: 0.9)))
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).lineLimit(1).truncationMode(.tail)
                if let caption = row.caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(row.canMove ? 1 : 0.5)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

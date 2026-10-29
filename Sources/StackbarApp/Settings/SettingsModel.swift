import AppKit
import StackbarCore

/// What the Settings window shows: every item in the Menu Bar or the Dropdown list, by its
/// assignment when it has one (so a drag shows at once, before the move has run).
@MainActor
@Observable
final class SettingsModel {
    struct Row: Identifiable {
        /// The window id, or "saved:" + index for an assigned item that isn't in the menu bar.
        var id: String
        /// Nil for an assigned item that isn't in the menu bar (its app isn't running).
        var item: MenuBarItem?
        var appearance: ItemAppearance?
        var name: String
        var section: Section
        /// Why it can't be moved, or what is happening to it.
        var caption: String?
        var canMove: Bool
    }

    var rows: [Row] = []
    /// The last arrangement, in words.
    var status: String?
    /// A missing permission, in words.
    var notice: String?
    /// The captured images were drawn for the menu bar: they get its background.
    var menuBarIsDark = false
    @ObservationIgnored var onAssign: (Row, Section) -> Void = { _, _ in }

    func rows(in section: Section) -> [Row] {
        rows.filter { $0.section == section }
    }

    /// All images in one column, as wide as the widest item.
    var imageWidth: CGFloat { rows.compactMap { $0.appearance?.size.width }.max() ?? 24 }

    /// Rows dropped on `section`'s list.
    func drop(_ ids: [String], into section: Section) {
        for id in ids {
            guard let row = rows.first(where: { $0.id == id }), row.canMove, row.section != section else { continue }
            onAssign(row, section)
        }
    }
}

import Foundation

/// Where an item lives: in the menu bar (right of the divider) or in Stackbar's dropdown panel
/// (left of the divider, off-screen while collapsed).
public enum Section: String, Codable, Sendable, CaseIterable {
    case bar
    case dropdown
}

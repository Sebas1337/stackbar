import SwiftUI

/// The Settings window's content: the item lists and the General settings (docs/PLAN.md M5).
struct SettingsTabsView: View {
    var items: SettingsModel
    var general: GeneralSettingsModel

    var body: some View {
        TabView {
            SettingsView(model: items)
                .tabItem { Label("Items", systemImage: "rectangle.stack") }
            GeneralSettingsView(model: general)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
    }
}

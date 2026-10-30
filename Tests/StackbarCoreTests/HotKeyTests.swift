import Testing
@testable import StackbarCore

struct HotKeyTests {
    @Test func displaysModifiersInMacOSOrder() {
        let key = HotKey(keyCode: 1, modifiers: [.command, .shift, .option, .control], key: "S")
        #expect(key.displayString == "⌃⌥⇧⌘S")
        #expect(HotKey(keyCode: 49, modifiers: [.option], key: "Space").displayString == "⌥Space")
    }

    @Test func needsControlOptionOrCommand() {
        #expect(HotKey(keyCode: 1, modifiers: [.command], key: "S").isValid)
        #expect(HotKey(keyCode: 1, modifiers: [.control, .shift], key: "S").isValid)
        #expect(!HotKey(keyCode: 1, modifiers: [.shift], key: "S").isValid)
        #expect(!HotKey(keyCode: 1, modifiers: [], key: "S").isValid)
        #expect(!HotKey(keyCode: 1, modifiers: [.command], key: "").isValid)
    }
}

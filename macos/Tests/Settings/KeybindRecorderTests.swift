import AppKit
import Testing
@testable import Ghostty

@Suite
struct KeybindRecorderTests {
    @Test func configNamesMatchGhosttyKeybindSyntax() {
        #expect(Ghostty.Input.Key.a.configName == "a")
        #expect(Ghostty.Input.Key.z.configName == "z")
        #expect(Ghostty.Input.Key.digit0.configName == "0")
        #expect(Ghostty.Input.Key.digit9.configName == "9")
        #expect(Ghostty.Input.Key.arrowUp.configName == "arrow_up")
        #expect(Ghostty.Input.Key.pageDown.configName == "page_down")
        #expect(Ghostty.Input.Key.numpad0.configName == "numpad_0")
        #expect(Ghostty.Input.Key.launchApp1.configName == "launch_app_1")
        #expect(Ghostty.Input.Key.f1.configName == "f1")
        #expect(Ghostty.Input.Key.f20.configName == "f20")
        #expect(Ghostty.Input.Key.space.configName == "space")
        #expect(Ghostty.Input.Key.tab.configName == "tab")
        #expect(Ghostty.Input.Key.enter.configName == "enter")
        #expect(Ghostty.Input.Key.escape.configName == "escape")
    }

    @Test func keyCodeLookupFeedsRecorderConfigNames() throws {
        try #require(Ghostty.Input.Key(keyCode: 0x0000)?.configName == "a")
        try #require(Ghostty.Input.Key(keyCode: 0x001d)?.configName == "0")
        try #require(Ghostty.Input.Key(keyCode: 0x007e)?.configName == "arrow_up")
        try #require(Ghostty.Input.Key(keyCode: 0x007a)?.configName == "f1")
        try #require(Ghostty.Input.Key(keyCode: 0x0031)?.configName == "space")
        try #require(Ghostty.Input.Key(keyCode: 0x0030)?.configName == "tab")
        try #require(Ghostty.Input.Key(keyCode: 0x0024)?.configName == "enter")
        try #require(Ghostty.Input.Key(keyCode: 0x0035)?.configName == "escape")
    }

    @Test func modifierOnlyKeysAreSkippedByRecorder() {
        #expect(Ghostty.Input.Key.shiftLeft.isModifierOnlyKey)
        #expect(Ghostty.Input.Key.controlRight.isModifierOnlyKey)
        #expect(Ghostty.Input.Key.altLeft.isModifierOnlyKey)
        #expect(Ghostty.Input.Key.metaRight.isModifierOnlyKey)
        #expect(Ghostty.Input.Key.capsLock.isModifierOnlyKey)
        #expect(!Ghostty.Input.Key.a.isModifierOnlyKey)
        #expect(!Ghostty.Input.Key.arrowUp.isModifierOnlyKey)
    }

    @Test func recorderFormatsKeyCodeTriggers() {
        #expect(KeybindRecorder.trigger(keyCode: 0x007e, modifierFlags: .command) == "cmd+arrow_up")
        #expect(KeybindRecorder.trigger(keyCode: 0x007a, modifierFlags: .control) == "ctrl+f1")
        #expect(KeybindRecorder.trigger(keyCode: 0x0030, modifierFlags: .option) == "alt+tab")
        #expect(KeybindRecorder.trigger(keyCode: 0x001d, modifierFlags: .shift) == "shift+0")
        #expect(KeybindRecorder.trigger(keyCode: 0x0038, modifierFlags: .shift) == nil)
    }
}
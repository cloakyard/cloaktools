import AppKit
import Carbon.HIToolbox
import CloakToolsCore
import SwiftUI

/// Register only the selected shortcut with the system. No global keyboard monitor is needed.
@MainActor
final class DropZoneShortcut {
    private var registered: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    private var current: DropZoneKey?

    func configure(_ key: DropZoneKey?, action: @escaping () -> Void) -> Bool {
        self.action = action
        if key == current { return true }
        if let registered { UnregisterEventHotKey(registered) }
        registered = nil
        current = nil
        guard let key else { return true }
        let required = UInt32(cmdKey | controlKey | optionKey)
        guard key.code < 128, key.modifiers & required != 0,
              key.modifiers & ~UInt32(cmdKey | controlKey | optionKey | shiftKey) == 0 else { return false }
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, reference in
                guard let event, let reference else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                      id.signature == 0x43544F50, id.id == 1 else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated { Unmanaged<DropZoneShortcut>.fromOpaque(reference).takeUnretainedValue().action?() }
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return false }
        }
        let id = EventHotKeyID(signature: 0x43544F50, id: 1)
        let result = RegisterEventHotKey(UInt32(key.code), key.modifiers, id, GetApplicationEventTarget(), 0, &registered)
        guard result == noErr else { return false }
        current = key
        return true
    }

    isolated deinit {
        if let registered { UnregisterEventHotKey(registered) }
        if let handler { RemoveEventHandler(handler) }
    }
}

struct DropZoneShortcutSetting: View {
    let model: AppModel
    @State private var recording = false
    var body: some View {
        LabeledContent("Show Drop Zone shortcut") {
            HStack {
                if recording {
                    ShortcutCapture { key in
                        recording = false
                        if let key { model.update { $0.dropZoneKey = key } }
                    }.frame(width: 164, height: 28)
                    Button("Cancel") { recording = false }.buttonStyle(.borderless)
                } else {
                    Button(model.preferences.dropZoneKey?.label ?? "Record Shortcut…") { recording = true }
                        .accessibilityLabel("Record global Drop Zone shortcut")
                    if model.preferences.dropZoneKey != nil {
                        Button("Clear") { model.update { $0.dropZoneKey = nil } }.buttonStyle(.borderless)
                    }
                }
            }
        }
        if let error = model.dropZoneShortcutError { Text(error).foregroundStyle(.secondary).font(.caption) }
    }
}

private struct ShortcutCapture: NSViewRepresentable {
    let finish: (DropZoneKey?) -> Void
    func makeNSView(context: Context) -> Recorder {
        let label = Recorder(labelWithString: "Press a shortcut…")
        label.alignment = .center
        label.finish = finish
        label.setAccessibilityLabel("Press a letter or number with Command, Control or Option. Escape cancels.")
        return label
    }
    func updateNSView(_ view: Recorder, context: Context) { view.finish = finish }
    final class Recorder: NSTextField {
        var finish: ((DropZoneKey?) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { window.makeFirstResponder(self) }
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == kVK_Escape { finish?(nil); return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.intersection([.command, .control, .option]).isEmpty,
                  let char = event.charactersIgnoringModifiers?.uppercased(), char.count == 1,
                  char.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains) else { NSSound.beep(); return }
            var modifiers: UInt32 = 0
            var label = ""
            for (flag, mask, symbol): (NSEvent.ModifierFlags, Int, String) in [(.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")] {
                if flags.contains(flag) { modifiers |= UInt32(mask); label += symbol }
            }
            finish?(DropZoneKey(code: event.keyCode, modifiers: modifiers, label: label + char))
        }
    }
}

import SwiftUI
import Carbon
import AppKit

struct HotkeyRecorderView: View {
    @State private var isRecording = false
    @State private var keyCode: UInt32
    @State private var modifiers: UInt32

    init() {
        _keyCode = State(initialValue: HotkeyManager.savedKeyCode())
        _modifiers = State(initialValue: HotkeyManager.savedModifiers())
    }

    private var displayString: String {
        HotkeyManager.displayString(keyCode: keyCode, modifiers: modifiers)
    }

    private var isDefault: Bool {
        keyCode == Constants.Hotkey.defaultKeyCode && modifiers == Constants.Hotkey.defaultModifiers
    }

    var body: some View {
        HStack(spacing: 8) {
            HotkeyRecorderField(
                isRecording: $isRecording,
                keyCode: $keyCode,
                modifiers: $modifiers,
                displayString: displayString
            )
            .frame(width: 140, height: 22)

            Button {
                resetToDefault()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isDefault ? .tertiary : .secondary)
            .disabled(isDefault)
            .help("Reset to default (⌥Space)")
        }
    }

    private func resetToDefault() {
        keyCode = Constants.Hotkey.defaultKeyCode
        modifiers = Constants.Hotkey.defaultModifiers
        HotkeyManager.resetToDefault()
    }
}

struct HotkeyRecorderField: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    let displayString: String

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.delegate = context.coordinator
        view.displayString = displayString
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.displayString = displayString
        nsView.isRecording = isRecording
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: HotkeyRecorderDelegate {
        var parent: HotkeyRecorderField

        init(_ parent: HotkeyRecorderField) {
            self.parent = parent
        }

        func hotkeyRecorderDidStartRecording() {
            parent.isRecording = true
        }

        func hotkeyRecorderDidEndRecording() {
            parent.isRecording = false
        }

        func hotkeyRecorderDidRecordHotkey(keyCode: UInt32, modifiers: UInt32) {
            parent.keyCode = keyCode
            parent.modifiers = modifiers
            parent.isRecording = false
            HotkeyManager.saveHotkey(keyCode: keyCode, modifiers: modifiers)
        }
    }
}

protocol HotkeyRecorderDelegate: AnyObject {
    func hotkeyRecorderDidStartRecording()
    func hotkeyRecorderDidEndRecording()
    func hotkeyRecorderDidRecordHotkey(keyCode: UInt32, modifiers: UInt32)
}

class HotkeyRecorderNSView: NSView {
    weak var delegate: HotkeyRecorderDelegate?

    var displayString: String = "" {
        didSet { needsDisplay = true }
    }

    var isRecording: Bool = false {
        didSet { needsDisplay = true }
    }

    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 4
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            // Click again to cancel
            isRecording = false
            delegate?.hotkeyRecorderDidEndRecording()
        } else {
            isRecording = true
            delegate?.hotkeyRecorderDidStartRecording()
            window?.makeFirstResponder(self)
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let keyCode = UInt32(event.keyCode)

        // Ignore modifier-only key presses
        if isModifierOnlyKeyCode(keyCode) {
            return
        }

        let modifiers = carbonModifiers(from: event.modifierFlags)
        delegate?.hotkeyRecorderDidRecordHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    override func flagsChanged(with event: NSEvent) {
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            delegate?.hotkeyRecorderDidEndRecording()
            needsDisplay = true
        }
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let bgColor: NSColor
        if isRecording {
            bgColor = NSColor.controlAccentColor.withAlphaComponent(0.15)
        } else if isHovered {
            bgColor = NSColor.quaternaryLabelColor
        } else {
            bgColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.5)
        }

        bgColor.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        path.fill()

        NSColor.separatorColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()

        let text: String
        let textColor: NSColor

        if isRecording {
            text = "Type Shortcut"
            textColor = .secondaryLabelColor
        } else {
            text = displayString
            textColor = .labelColor
        }

        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attributedString.draw(in: textRect)
    }

    private func isModifierOnlyKeyCode(_ keyCode: UInt32) -> Bool {
        // Shift, Control, Option, Command keys
        return [0x38, 0x3C, 0x3B, 0x3E, 0x3A, 0x3D, 0x37, 0x36].contains(keyCode)
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }
}

import AppKit

enum MenuBarIcon {
    static func make(enabled: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size)
        image.isTemplate = true

        image.lockFocus()
        defer { image.unlockFocus() }

        let bg = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 20, height: 16), xRadius: 4.5, yRadius: 4.5)
        let stroke = enabled ? NSColor.labelColor : NSColor.secondaryLabelColor
        stroke.setStroke()
        bg.lineWidth = 1.6
        bg.stroke()

        let fill = enabled ? NSColor.labelColor.withAlphaComponent(0.18) : NSColor.secondaryLabelColor.withAlphaComponent(0.08)
        fill.setFill()
        bg.fill()

        stroke.setStroke()

        let vertical = NSBezierPath()
        vertical.move(to: NSPoint(x: 11, y: 3))
        vertical.line(to: NSPoint(x: 11, y: 15))
        vertical.lineWidth = 1.3
        vertical.stroke()

        let horizontal = NSBezierPath()
        horizontal.move(to: NSPoint(x: 3.5, y: 9))
        horizontal.line(to: NSPoint(x: 18.5, y: 9))
        horizontal.lineWidth = 1.3
        horizontal.stroke()

        return image
    }
}

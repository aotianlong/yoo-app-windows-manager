import AppKit

enum MenuBarIcon {
    static func make(enabled: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        let stroke = NSColor.black.withAlphaComponent(enabled ? 1 : 0.48)
        let bg = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 20, height: 16), xRadius: 4, yRadius: 4)
        stroke.setStroke()
        bg.lineWidth = 1.45
        bg.stroke()

        // 上方保留简化的二分窗口结构，下方放置 yoo 品牌字样。
        let horizontal = NSBezierPath()
        horizontal.move(to: NSPoint(x: 2.2, y: 11.2))
        horizontal.line(to: NSPoint(x: 19.8, y: 11.2))
        horizontal.lineWidth = 1.15
        horizontal.stroke()

        let vertical = NSBezierPath()
        vertical.move(to: NSPoint(x: 9, y: 11.2))
        vertical.line(to: NSPoint(x: 9, y: 16))
        vertical.lineWidth = 1.15
        vertical.stroke()

        let text = NSAttributedString(
            string: "yoo",
            attributes: [
                .font: NSFont.systemFont(ofSize: 8.3, weight: .bold),
                .foregroundColor: stroke,
                .kern: -0.35,
            ]
        )
        let textSize = text.size()
        text.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: 1.45))

        image.isTemplate = true
        return image
    }
}

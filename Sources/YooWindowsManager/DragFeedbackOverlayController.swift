import AppKit

@MainActor
final class DragFeedbackOverlayController {
    enum State {
        case restore
        case swap
    }

    private let panel: NSPanel
    private let feedbackView = DragFeedbackView(frame: .zero)

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = feedbackView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    func show(frame: CGRect, state: State) {
        feedbackView.state = state
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private final class DragFeedbackView: NSView {
    var state: DragFeedbackOverlayController.State = .restore {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let isSwap = state == .swap
        let color = isSwap ? NSColor.systemGreen : NSColor.systemOrange
        color.withAlphaComponent(0.16).setFill()
        bounds.fill()

        color.withAlphaComponent(0.95).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 12, yRadius: 12)
        border.lineWidth = 6
        border.stroke()

        let text = isSwap ? "⇄  松开交换" : "↩  松开恢复"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: color.withAlphaComponent(0.92),
        ]
        let attributed = NSAttributedString(string: "  \(text)  ", attributes: attributes)
        let size = attributed.size()
        let point = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        attributed.draw(at: point)
    }
}

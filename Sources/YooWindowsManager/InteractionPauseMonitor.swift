import AppKit

/// 在用户拖动窗口时暂停自动布局，松手后延迟再应用。
@MainActor
final class InteractionPauseMonitor {
    var onDragBegan: ((CGPoint) -> Void)?
    var onDragChanged: ((CGPoint) -> Void)?
    var onDragEndedImmediately: (() -> Void)?
    var onInteractionEnded: ((CGPoint) -> Void)?

    private var isDragging = false
    private var mouseDownPoint: CGPoint?
    private var suppressLayoutUntil = Date.distantPast
    private var globalDownMonitor: Any?
    private var globalDragMonitor: Any?
    private var globalUpMonitor: Any?
    private var endWorkItem: DispatchWorkItem?

    var shouldSuppressLayout: Bool {
        isDragging || Date() < suppressLayoutUntil
    }

    func start() {
        guard globalDragMonitor == nil else { return }

        globalDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.mouseDownPoint = NSEvent.mouseLocation
            }
        }
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let location = NSEvent.mouseLocation
                let wasDragging = self.isDragging
                self.isDragging = true
                self.endWorkItem?.cancel()
                if !wasDragging {
                    self.onDragBegan?(self.mouseDownPoint ?? location)
                }
                self.onDragChanged?(location)
            }
        }
        globalUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isDragging else { return }
                self.finishInteraction(dropPoint: NSEvent.mouseLocation)
            }
        }
    }

    private func finishInteraction(dropPoint: CGPoint) {
        isDragging = false
        mouseDownPoint = nil
        onDragEndedImmediately?()
        suppressLayoutUntil = Date().addingTimeInterval(0.85)
        endWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isDragging else { return }
            self.onInteractionEnded?(dropPoint)
        }
        endWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: work)
    }

    func stop() {
        if let globalDownMonitor {
            NSEvent.removeMonitor(globalDownMonitor)
        }
        if let globalDragMonitor {
            NSEvent.removeMonitor(globalDragMonitor)
        }
        if let globalUpMonitor {
            NSEvent.removeMonitor(globalUpMonitor)
        }
        globalDownMonitor = nil
        globalDragMonitor = nil
        globalUpMonitor = nil
        isDragging = false
        mouseDownPoint = nil
        suppressLayoutUntil = .distantPast
    }
}

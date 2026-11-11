import AppKit

/// 在用户拖动窗口时暂停自动布局，松手后延迟再应用。
@MainActor
final class InteractionPauseMonitor {
    var onInteractionEnded: (() -> Void)?

    private var isDragging = false
    private var suppressLayoutUntil = Date.distantPast
    private var globalDragMonitor: Any?
    private var globalUpMonitor: Any?
    private var endWorkItem: DispatchWorkItem?

    var shouldSuppressLayout: Bool {
        isDragging || Date() < suppressLayoutUntil
    }

    func start() {
        guard globalDragMonitor == nil else { return }

        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.isDragging = true
                self?.endWorkItem?.cancel()
            }
        }
        globalUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isDragging else { return }
                self.finishInteraction()
            }
        }
    }

    private func finishInteraction() {
        isDragging = false
        suppressLayoutUntil = Date().addingTimeInterval(0.85)
        endWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isDragging else { return }
            self.onInteractionEnded?()
        }
        endWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: work)
    }

    func stop() {
        if let globalDragMonitor {
            NSEvent.removeMonitor(globalDragMonitor)
        }
        if let globalUpMonitor {
            NSEvent.removeMonitor(globalUpMonitor)
        }
        globalDragMonitor = nil
        globalUpMonitor = nil
        isDragging = false
        suppressLayoutUntil = .distantPast
    }
}

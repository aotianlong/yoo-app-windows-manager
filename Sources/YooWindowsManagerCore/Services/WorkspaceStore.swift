import AppKit
import CoreGraphics
import Foundation

public final class WorkspaceStore: @unchecked Sendable {
    private let lock = NSLock()
    private var workspaces: [String: LayoutWorkspace] = [:]
    private let persistenceURL: URL

    public init(persistenceURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("YooWindowsManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.persistenceURL = persistenceURL ?? dir.appendingPathComponent("workspaces.json")
        load()
        syncScreens()
    }

    public func allWorkspaces() -> [LayoutWorkspace] {
        lock.lock()
        defer { lock.unlock() }
        return Array(workspaces.values).sorted { $0.screenName < $1.screenName }
    }

    public func workspace(for screen: NSScreen) -> LayoutWorkspace {
        lock.lock()
        defer { lock.unlock() }
        let id = screenKey(screen)
        if let existing = workspaces[id] {
            return existing
        }
        let created = LayoutWorkspace(id: id, screenName: id, usableFrame: screenUsableFrame(screen))
        workspaces[id] = created
        return created
    }

    public func update(_ workspace: LayoutWorkspace) {
        lock.lock()
        workspaces[workspace.id] = workspace
        lock.unlock()
        save()
    }

    public func syncScreens() {
        lock.lock()
        for screen in NSScreen.screens {
            let id = screenKey(screen)
            let frame = screenUsableFrame(screen)
            if var existing = workspaces[id] {
                existing.usableFrame = frame
                existing.screenName = id
                workspaces[id] = existing
            } else {
                workspaces[id] = LayoutWorkspace(id: id, screenName: id, usableFrame: frame)
            }
        }
        lock.unlock()
        save()
    }

    private func screenKey(_ screen: NSScreen) -> String {
        screen.localizedName
    }

    private func screenUsableFrame(_ screen: NSScreen) -> CGRect {
        screen.visibleFrame
    }

    private func load() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let decoded = try? JSONDecoder().decode([String: LayoutWorkspace].self, from: data)
        else { return }
        workspaces = decoded
    }

    private func save() {
        lock.lock()
        let snapshot = workspaces
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: persistenceURL, options: .atomic)
    }
}

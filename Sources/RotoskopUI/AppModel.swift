import Foundation
import RotoskopGit
import SwiftUI

/// Shared app state for the iOS shell.
@MainActor
public final class AppModel: ObservableObject {
    @Published public var projects: [ProjectRecord] = []
    @Published public var errorMessage: String?
    @Published public var isBusy = false
    @Published public var hasPAT: Bool = false
    /// Target emulator clock (MHz); persisted in UserDefaults.
    @Published public var clockMHz: Double = EmulationPreferences.clockMHz {
        didSet {
            let clamped = EmulationPreferences.clamp(clockMHz)
            if clamped != clockMHz {
                clockMHz = clamped
                return
            }
            EmulationPreferences.clockMHz = clockMHz
        }
    }

    public let store: ProjectStore
    public let patStore: any PATStore

    public init(store: ProjectStore, patStore: any PATStore) {
        self.store = store
        self.patStore = patStore
        self.clockMHz = EmulationPreferences.clockMHz
        refresh()
    }

    public static func makeDefault() throws -> AppModel {
        let pat = KeychainPATStore()
        let root = try ProjectStore.defaultRootURL()
        let store = try ProjectStore(rootURL: root, patStore: pat)
        return AppModel(store: store, patStore: pat)
    }

    public func refresh() {
        projects = store.projects()
        hasPAT = (try? patStore.load())?.isEmpty == false
    }

    public func savePAT(_ token: String) throws {
        try patStore.save(token)
        refresh()
    }

    public func clearPAT() throws {
        try patStore.clear()
        refresh()
    }

    public func clone(remoteURL: String) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            _ = try await store.addClone(remoteURL: remoteURL)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func remove(_ project: ProjectRecord) {
        errorMessage = nil
        do {
            try store.remove(project)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

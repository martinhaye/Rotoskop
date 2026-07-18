import Foundation

/// App-managed project list and clone storage (DESIGN §1.1 / §7.1).
public final class ProjectStore: @unchecked Sendable {
    public let rootURL: URL
    private let patStore: any PATStore
    private let fileManager: FileManager
    private let lock = NSLock()
    private var records: [ProjectRecord]

    private var manifestURL: URL {
        rootURL.appendingPathComponent("projects.json", isDirectory: false)
    }

    private var clonesURL: URL {
        rootURL.appendingPathComponent("Clones", isDirectory: true)
    }

    public init(
        rootURL: URL,
        patStore: any PATStore = KeychainPATStore(),
        fileManager: FileManager = .default
    ) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.patStore = patStore
        self.fileManager = fileManager
        try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: self.rootURL.appendingPathComponent("Clones", isDirectory: true), withIntermediateDirectories: true)
        self.records = []
        self.records = try Self.loadManifest(from: manifestURL, fileManager: fileManager)
    }

    /// Default app-managed root under Application Support.
    public static func defaultRootURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("Rotoskop", isDirectory: true)
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    public func projects() -> [ProjectRecord] {
        withLock {
            records.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    public func localURL(for project: ProjectRecord) -> URL {
        clonesURL.appendingPathComponent(project.directoryName, isDirectory: true)
    }

    public func openRepository(for project: ProjectRecord) throws -> GitRepository {
        try GitRepository(opening: localURL(for: project), patStore: patStore)
    }

    /// Clone into app storage and add to the list.
    @discardableResult
    public func addClone(remoteURL: String, directoryName: String? = nil) async throws -> ProjectRecord {
        let url = try GitURL.normalizeHTTPS(remoteURL)
        let dirName = directoryName ?? GitURL.suggestedDirectoryName(from: url)
        let destination = clonesURL.appendingPathComponent(dirName, isDirectory: true)

        let exists = withLock { records.contains { $0.directoryName == dirName } }
        if exists || fileManager.fileExists(atPath: destination.path) {
            throw GitError(.projectExists(dirName))
        }

        _ = try await GitRepository.clone(from: url.absoluteString, to: destination, patStore: patStore)

        let record = ProjectRecord(
            name: dirName,
            remoteURL: url.absoluteString,
            directoryName: dirName
        )
        try withLock {
            records.append(record)
            try saveManifestUnlocked()
        }
        return record
    }

    /// Remove from the list and delete the local clone (DESIGN §1.1).
    public func remove(_ project: ProjectRecord) throws {
        try withLock {
            guard let index = records.firstIndex(where: { $0.id == project.id }) else {
                throw GitError(.projectNotFound(project.name))
            }
            let url = clonesURL.appendingPathComponent(project.directoryName, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            records.remove(at: index)
            try saveManifestUnlocked()
        }
    }

    // MARK: - Manifest

    private func saveManifestUnlocked() throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: manifestURL, options: .atomic)
    }

    private static func loadManifest(from url: URL, fileManager: FileManager) throws -> [ProjectRecord] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ProjectRecord].self, from: data)
    }
}

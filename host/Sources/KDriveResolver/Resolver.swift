import Foundation

/// One configured sync of a kDrive, as recorded in the client's `.parms.db`.
public struct SyncConfig: Equatable, Sendable {
    /// Local root folder of the sync, e.g. `/Users/tristan/kDrive`.
    public let localPath: String
    /// Absolute path of this sync's `.sync_<hash>.db`.
    public let syncDbPath: String
    /// Remote id of the folder mapped to `localPath`; the root of this sync's node tree.
    public let targetNodeId: String?
}

/// What the resolver could make of a kDrive file id.
public enum Resolution: Equatable, Sendable {
    /// The item is in a sync's database and present on disk.
    case localPath(String)
    /// The item is known to a sync but missing from disk (deleted behind the client's back,
    /// or the sync root is on an unmounted volume).
    case missingOnDisk(String)
    /// No sync of this drive knows the id: not synced, or outside every synced subfolder.
    case notSynced
    /// The client has no sync configured for this drive at all.
    case driveNotSynced
}

/// Maps kDrive remote file ids to local paths by reading the desktop client's own databases.
///
/// Everything here is derived from the client source (`libparms/db/parmsdb.cpp`,
/// `libsyncengine/db/syncdb.cpp`, `libcommonserver/db/db.cpp`); nothing talks to the network.
public struct Resolver: Sendable {
    /// `~/Library/Application Support/kDrive` on macOS. Injectable so tests can point at fixtures.
    public let appSupportDirectory: URL
    private let fileExists: @Sendable (String) -> Bool

    public init(
        appSupportDirectory: URL,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.appSupportDirectory = appSupportDirectory
        self.fileExists = fileExists
    }

    /// The default location of the client's databases for the current user.
    public static var defaultAppSupportDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/kDrive", isDirectory: true)
    }

    public var parmsDatabasePath: String {
        appSupportDirectory.appendingPathComponent(".parms.db").path
    }

    /// Every sync configured for `driveId`, in the order the client stores them.
    public func syncs(forDriveId driveId: Int) throws -> [SyncConfig] {
        let connection = try SQLiteConnection(path: parmsDatabasePath)
        var syncs: [SyncConfig] = []
        try connection.query(
            """
            SELECT s.localPath, s.dbPath, s.targetNodeId
            FROM sync s JOIN drive d ON d.dbId = s.driveDbId
            WHERE d.driveId = ?1 AND COALESCE(s.toDelete, 0) = 0
            ORDER BY s.dbId
            """,
            bind: [.int(Int64(driveId))]
        ) { row in
            if let localPath = row.text(0), let dbPath = row.text(1), !localPath.isEmpty, !dbPath.isEmpty {
                syncs.append(SyncConfig(
                    localPath: localPath,
                    syncDbPath: absolute(dbPath),
                    targetNodeId: row.text(2)
                ))
            }
            return true
        }
        return syncs
    }

    /// Resolves a remote file id to a local path, trying every sync of the drive.
    public func resolve(fileId: String, driveId: Int) throws -> Resolution {
        let syncs = try syncs(forDriveId: driveId)
        guard !syncs.isEmpty else { return .driveNotSynced }

        var knownButMissing: String?
        for sync in syncs {
            guard let relativePath = try relativePath(ofFileId: fileId, in: sync) else { continue }
            let path = relativePath.isEmpty
                ? sync.localPath
                : (sync.localPath as NSString).appendingPathComponent(relativePath)
            if fileExists(path) { return .localPath(path) }
            knownButMissing = knownButMissing ?? path
        }
        if let knownButMissing { return .missingOnDisk(knownButMissing) }
        return .notSynced
    }

    /// Walks the `node` table from the item up to the sync root, assembling its path.
    ///
    /// Returns nil when the id is not in this sync's database, and "" when the id *is* the
    /// sync root. The root row has a NULL `parentNodeId` and an empty name.
    func relativePath(ofFileId fileId: String, in sync: SyncConfig) throws -> String? {
        let connection = try SQLiteConnection(path: sync.syncDbPath)

        var current: Int64?
        try connection.query(
            "SELECT nodeId FROM node WHERE nodeIdDrive = ?1",
            bind: [.text(fileId)]
        ) { row in
            current = row.int(0)
            return false
        }
        guard var nodeId = current else { return nil }

        var components: [String] = []
        // The tree is at most a few hundred deep; the bound only stops a corrupted parent cycle
        // from hanging the host.
        for _ in 0 ..< 512 {
            var name: String?
            var parent: Int64?
            var found = false
            try connection.query(
                "SELECT nameLocal, parentNodeId FROM node WHERE nodeId = ?1",
                bind: [.int(nodeId)]
            ) { row in
                found = true
                name = row.text(0)
                parent = row.int(1)
                return false
            }
            guard found else { break }
            guard let parent else { break } // reached the root node
            if let name, !name.isEmpty { components.append(name) }
            nodeId = parent
        }

        return components.reversed().joined(separator: "/")
    }

    private func absolute(_ path: String) -> String {
        (path as NSString).isAbsolutePath
            ? path
            : appSupportDirectory.appendingPathComponent(path).path
    }
}

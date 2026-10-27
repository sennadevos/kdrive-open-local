import CSQLite
import Foundation

/// Builds throwaway copies of the kDrive client's databases.
///
/// The schemas are copied verbatim from the client source so the tests fail if our reader drifts
/// from what the client actually writes:
///   - `sync` and `drive`: src/libparms/db/parmsdb.cpp
///   - `node`:             src/libsyncengine/db/syncdb.cpp
enum Fixtures {
    /// Creates `.parms.db` and the sync databases it points at inside a fresh directory.
    static func appSupportDirectory(
        syncs: [SyncFixture],
        drives: [(dbId: Int, driveId: Int)]
    ) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kdrive-open-local-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let parms = directory.appendingPathComponent(".parms.db").path
        try write(to: parms) { db in
            try exec(db, """
                CREATE TABLE drive(dbId INTEGER PRIMARY KEY, driveId INTEGER, accountDbId INTEGER,
                    driveName TEXT, size INTEGER, color TEXT, notifications INTEGER, admin INTEGER) WITHOUT ROWID;
                CREATE TABLE sync(dbId INTEGER PRIMARY KEY, driveDbId INTEGER, localPath TEXT, localNodeId TEXT,
                    targetPath TEXT, targetNodeId TEXT, paused INTEGER, supportVfs INTEGER, virtualFileMode INTEGER,
                    dbPath TEXT, notificationsDisabled INTEGER, hasFullyCompleted INTEGER, navigationPaneClsid TEXT,
                    listingCursor TEXT, listingCursorTimestamp INTEGER, toDelete INTEGER, vfsRegisteredAt INTEGER) WITHOUT ROWID;
                """)
            for drive in drives {
                try exec(db, "INSERT INTO drive (dbId, driveId) VALUES (\(drive.dbId), \(drive.driveId));")
            }
            for (index, sync) in syncs.enumerated() {
                let dbPath = directory.appendingPathComponent(sync.dbFileName).path
                try exec(db, """
                    INSERT INTO sync (dbId, driveDbId, localPath, targetNodeId, dbPath, toDelete)
                    VALUES (\(index + 1), \(sync.driveDbId), '\(quote(sync.localPath))',
                            '\(quote(sync.rootNodeIdDrive))', '\(quote(dbPath))', \(sync.toDelete ? 1 : 0));
                    """)
            }
        }

        for sync in syncs {
            try writeSyncDatabase(sync, in: directory)
        }
        return directory
    }

    private static func writeSyncDatabase(_ sync: SyncFixture, in directory: URL) throws {
        try write(to: directory.appendingPathComponent(sync.dbFileName).path) { db in
            try exec(db, """
                CREATE TABLE node(nodeId INTEGER PRIMARY KEY, parentNodeId INTEGER, nameLocal TEXT, nameDrive TEXT,
                    nodeIdLocal TEXT, nodeIdDrive TEXT, created INTEGER, lastModifiedLocal INTEGER,
                    lastModifiedDrive INTEGER, type INTEGER, size INTEGER, checksum TEXT, status INTEGER, syncing INTEGER);
                """)
            // The root row as the client writes it: no parent, empty names, remote id = targetNodeId.
            try exec(db, """
                INSERT INTO node (nodeId, parentNodeId, nameLocal, nameDrive, nodeIdLocal, nodeIdDrive, type)
                VALUES (1, NULL, '', '', '1', '\(quote(sync.rootNodeIdDrive))', 1);
                """)
            for node in sync.nodes {
                let parent = node.parentNodeId.map(String.init) ?? "NULL"
                try exec(db, """
                    INSERT INTO node (nodeId, parentNodeId, nameLocal, nameDrive, nodeIdLocal, nodeIdDrive, type)
                    VALUES (\(node.nodeId), \(parent), '\(quote(node.name))', '\(quote(node.name))',
                            'L\(node.nodeId)', '\(quote(node.nodeIdDrive))', \(node.isDirectory ? 1 : 2));
                    """)
            }
        }
    }

    private static func write(to path: String, _ body: (OpaquePointer) throws -> Void) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
            throw FixtureError.message("cannot create \(path)")
        }
        defer { sqlite3_close_v2(db) }
        try body(db)
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw FixtureError.message("\(message) while running: \(sql)")
        }
    }

    private static func quote(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    enum FixtureError: Error { case message(String) }
}

struct SyncFixture {
    var driveDbId: Int = 1
    var localPath: String
    var dbFileName: String = ".sync_abc123.db"
    var rootNodeIdDrive: String = "1"
    var toDelete: Bool = false
    var nodes: [NodeFixture] = []
}

struct NodeFixture {
    let nodeId: Int
    /// nil only to build a deliberately broken tree.
    let parentNodeId: Int?
    let name: String
    let nodeIdDrive: String
    var isDirectory: Bool = false
}

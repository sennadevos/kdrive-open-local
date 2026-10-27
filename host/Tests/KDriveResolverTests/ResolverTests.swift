import XCTest
@testable import KDriveResolver

final class ResolverTests: XCTestCase {
    private let drive = (dbId: 1, driveId: 2133736)

    /// A sync rooted at /Users/tristan/kDrive containing Projects/Rator/notes.md.
    private func standardSync(localPath: String = "/Users/tristan/kDrive") -> SyncFixture {
        SyncFixture(
            localPath: localPath,
            nodes: [
                NodeFixture(nodeId: 2, parentNodeId: 1, name: "Projects", nodeIdDrive: "100", isDirectory: true),
                NodeFixture(nodeId: 3, parentNodeId: 2, name: "Rator", nodeIdDrive: "200", isDirectory: true),
                NodeFixture(nodeId: 4, parentNodeId: 3, name: "notes.md", nodeIdDrive: "300"),
            ]
        )
    }

    private func resolver(_ directory: URL, existing: Set<String>) -> Resolver {
        Resolver(appSupportDirectory: directory, fileExists: { existing.contains($0) })
    }

    func testResolvesNestedFile() throws {
        let directory = try Fixtures.appSupportDirectory(syncs: [standardSync()], drives: [drive])
        let path = "/Users/tristan/kDrive/Projects/Rator/notes.md"
        XCTAssertEqual(
            try resolver(directory, existing: [path]).resolve(fileId: "300", driveId: drive.driveId),
            .localPath(path)
        )
    }

    func testResolvesFolder() throws {
        let directory = try Fixtures.appSupportDirectory(syncs: [standardSync()], drives: [drive])
        let path = "/Users/tristan/kDrive/Projects"
        XCTAssertEqual(
            try resolver(directory, existing: [path]).resolve(fileId: "100", driveId: drive.driveId),
            .localPath(path)
        )
    }

    func testResolvesTheSyncRootItself() throws {
        // The root node carries the remote id of the folder the sync is mapped to, and an empty
        // name; the path must come out as the sync root, not as a trailing slash.
        var sync = standardSync()
        sync.rootNodeIdDrive = "99"
        let directory = try Fixtures.appSupportDirectory(syncs: [sync], drives: [drive])
        XCTAssertEqual(
            try resolver(directory, existing: ["/Users/tristan/kDrive"]).resolve(fileId: "99", driveId: drive.driveId),
            .localPath("/Users/tristan/kDrive")
        )
    }

    func testUnknownFileIdIsNotSynced() throws {
        let directory = try Fixtures.appSupportDirectory(syncs: [standardSync()], drives: [drive])
        XCTAssertEqual(
            try resolver(directory, existing: []).resolve(fileId: "404", driveId: drive.driveId),
            .notSynced
        )
    }

    func testUnknownDriveIsReportedSeparately() throws {
        let directory = try Fixtures.appSupportDirectory(syncs: [standardSync()], drives: [drive])
        XCTAssertEqual(
            try resolver(directory, existing: []).resolve(fileId: "300", driveId: 999),
            .driveNotSynced
        )
    }

    func testKnownFileMissingFromDiskDoesNotClaimSuccess() throws {
        let directory = try Fixtures.appSupportDirectory(syncs: [standardSync()], drives: [drive])
        XCTAssertEqual(
            try resolver(directory, existing: []).resolve(fileId: "300", driveId: drive.driveId),
            .missingOnDisk("/Users/tristan/kDrive/Projects/Rator/notes.md")
        )
    }

    func testSearchesEverySyncOfTheDrive() throws {
        // Two syncs of the same drive; the id lives only in the second one.
        var second = SyncFixture(
            localPath: "/Users/tristan/Shared",
            dbFileName: ".sync_def456.db",
            nodes: [NodeFixture(nodeId: 2, parentNodeId: 1, name: "report.pdf", nodeIdDrive: "777")]
        )
        second.driveDbId = drive.dbId
        let directory = try Fixtures.appSupportDirectory(syncs: [standardSync(), second], drives: [drive])
        let path = "/Users/tristan/Shared/report.pdf"
        XCTAssertEqual(
            try resolver(directory, existing: [path]).resolve(fileId: "777", driveId: drive.driveId),
            .localPath(path)
        )
    }

    func testSyncMarkedForDeletionIsIgnored() throws {
        var sync = standardSync()
        sync.toDelete = true
        let directory = try Fixtures.appSupportDirectory(syncs: [sync], drives: [drive])
        XCTAssertEqual(
            try resolver(directory, existing: []).resolve(fileId: "300", driveId: drive.driveId),
            .driveNotSynced
        )
    }

    func testSyncRootContainingAQuestionMarkIsNotTruncated() throws {
        // The sync db path goes into a SQLite file: URI, so unescaped ? or # would silently
        // turn the rest of the path into a query string.
        var sync = standardSync()
        sync.dbFileName = ".sync_q#1.db"
        let directory = try Fixtures.appSupportDirectory(syncs: [sync], drives: [drive])
        let path = "/Users/tristan/kDrive/Projects/Rator/notes.md"
        XCTAssertEqual(
            try resolver(directory, existing: [path]).resolve(fileId: "300", driveId: drive.driveId),
            .localPath(path)
        )
    }

    func testParentCycleDoesNotHang() throws {
        // A corrupted tree where two nodes are each other's parent must terminate.
        let sync = SyncFixture(
            localPath: "/Users/tristan/kDrive",
            nodes: [
                NodeFixture(nodeId: 2, parentNodeId: 3, name: "a", nodeIdDrive: "10", isDirectory: true),
                NodeFixture(nodeId: 3, parentNodeId: 2, name: "b", nodeIdDrive: "11", isDirectory: true),
            ]
        )
        let directory = try Fixtures.appSupportDirectory(syncs: [sync], drives: [drive])
        _ = try resolver(directory, existing: []).resolve(fileId: "10", driveId: drive.driveId)
    }

    func testMissingParmsDatabaseThrows() {
        let directory = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        XCTAssertThrowsError(try resolver(directory, existing: []).resolve(fileId: "1", driveId: drive.driveId))
    }

    func testSyncsAreListedForTheDrive() throws {
        let directory = try Fixtures.appSupportDirectory(syncs: [standardSync()], drives: [drive])
        let syncs = try resolver(directory, existing: []).syncs(forDriveId: drive.driveId)
        XCTAssertEqual(syncs.count, 1)
        XCTAssertEqual(syncs.first?.localPath, "/Users/tristan/kDrive")
        XCTAssertTrue(syncs.first?.syncDbPath.hasSuffix(".sync_abc123.db") == true)
    }
}

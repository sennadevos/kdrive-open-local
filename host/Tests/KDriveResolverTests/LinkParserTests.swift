import XCTest
@testable import KDriveResolver

final class LinkParserTests: XCTestCase {
    func testPrivateRedirectLink() {
        XCTAssertEqual(
            LinkParser.parse("https://kdrive.infomaniak.com/app/drive/2133736/redirect/987654"),
            DriveLink(driveId: 2133736, fileId: "987654")
        )
    }

    func testWebAppFileLink() {
        XCTAssertEqual(
            LinkParser.parse("https://kdrive.infomaniak.com/app/drive/2133736/files/42"),
            DriveLink(driveId: 2133736, fileId: "42")
        )
    }

    func testKSuiteLink() {
        XCTAssertEqual(
            LinkParser.parse("https://ksuite.infomaniak.com/0/kdrive/app/drive/2133736/files/42"),
            DriveLink(driveId: 2133736, fileId: "42")
        )
    }

    func testPreviewLinkPointsAtTheFileNotTheFolder() {
        XCTAssertEqual(
            LinkParser.parse("https://kdrive.infomaniak.com/app/drive/2133736/files/10/preview/image/55"),
            DriveLink(driveId: 2133736, fileId: "55")
        )
    }

    func testQueryStringAndFragmentAreIgnored() {
        XCTAssertEqual(
            LinkParser.parse("https://kdrive.infomaniak.com/app/drive/2133736/redirect/7?from=mail#x"),
            DriveLink(driveId: 2133736, fileId: "7")
        )
    }

    func testRejectsLinksWeCannotResolve() {
        let unsupported = [
            "https://kdrive.infomaniak.com/app/drive/2133736",            // drive root listing
            "https://kdrive.infomaniak.com/app/drive/2133736/trash",      // not an item route
            "https://kdrive.infomaniak.com/app/drive/abc/redirect/1",     // non-numeric drive
            "https://kdrive.infomaniak.com/app/drive/2133736/redirect/",  // no id
            "https://example.com/app/drive/2133736/redirect/1",           // wrong host
            "https://kdrive.infomaniak.com.evil.test/app/drive/1/files/2", // lookalike host
            "not a url at all",
        ]
        for link in unsupported {
            XCTAssertNil(LinkParser.parse(link), "should not have parsed \(link)")
        }
    }
}

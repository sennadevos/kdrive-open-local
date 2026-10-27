import Foundation

/// A kDrive item identified by a web link.
public struct DriveLink: Equatable, Sendable {
    public let driveId: Int
    public let fileId: String

    public init(driveId: Int, fileId: String) {
        self.driveId = driveId
        self.fileId = fileId
    }
}

/// Recognises the kDrive web links that point at a single item.
///
/// The extension does only a coarse host match and hands the whole URL over, so this is the one
/// place that knows the link shapes.
public enum LinkParser {
    /// Hosts whose links can name a drive item.
    public static let hosts: Set<String> = ["kdrive.infomaniak.com", "ksuite.infomaniak.com"]

    public static func parse(_ urlString: String) -> DriveLink? {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased(),
              hosts.contains(host)
        else { return nil }

        let components = url.pathComponents.filter { $0 != "/" }

        // Both forms contain `.../app/drive/<driveId>/...`; the ksuite one is prefixed with the
        // kSuite workspace and product, e.g. /0/kdrive/app/drive/2133736/files/123.
        guard let driveIndex = components.firstIndex(of: "drive"),
              driveIndex > 0, components[driveIndex - 1] == "app",
              components.index(after: driveIndex) < components.endIndex,
              let driveId = Int(components[driveIndex + 1])
        else { return nil }

        let rest = Array(components[(driveIndex + 2)...])
        guard let kind = rest.first else { return nil }

        switch kind {
        case "redirect":
            // The client's own private link: /app/drive/<driveId>/redirect/<fileId>
            guard rest.count >= 2, isId(rest[1]) else { return nil }
            return DriveLink(driveId: driveId, fileId: rest[1])
        case "files":
            // Web app: /files/<id>, or /files/<folderId>/preview/<kind>/<fileId> where the item
            // being looked at is the last id, not the folder.
            guard rest.count >= 2, isId(rest[1]) else { return nil }
            if let previewIndex = rest.firstIndex(of: "preview"),
               let last = rest.last, previewIndex > 1, isId(last) {
                return DriveLink(driveId: driveId, fileId: last)
            }
            return DriveLink(driveId: driveId, fileId: rest[1])
        default:
            return nil
        }
    }

    /// kDrive file ids are decimal; anything else is a route segment we do not understand.
    private static func isId(_ component: String) -> Bool {
        !component.isEmpty && component.allSatisfy(\.isNumber)
    }
}

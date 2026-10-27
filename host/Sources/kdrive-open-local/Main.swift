import Foundation
import KDriveResolver

/// What the extension asks for.
struct Request: Decodable {
    let url: String
    /// Echoed back so the extension can match a reply to its request.
    let id: Int?
    /// What to do with a file that is not a folder. Folders always just open in the Finder.
    let fileAction: String?
}

/// What the extension gets back. Only `.opened` means the navigation should be cancelled.
struct Response: Encodable {
    let id: Int?
    let status: String
    var path: String?
    var detail: String?

    static func opened(id: Int?, path: String) -> Response {
        Response(id: id, status: "opened", path: path)
    }

    static func passThrough(id: Int?, status: String, detail: String? = nil) -> Response {
        Response(id: id, status: status, path: nil, detail: detail)
    }
}

@main
struct KDriveOpenLocal {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()

        // Debugging aid: `kdrive-open-local --resolve <url>` prints the same JSON the extension
        // would receive, without the length framing.
        if arguments.first == "--resolve", let url = arguments.dropFirst().first {
            let response = handle(Request(url: url, id: nil, fileAction: nil))
            FileHandle.standardOutput.write(encode(response))
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        // Firefox passes the manifest path (and on some platforms the extension id) as argv;
        // anything we do not recognise means "run the native messaging loop".
        runMessageLoop()
    }

    private static func runMessageLoop() {
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput
        // `try?` flattens the optional: nil means either end of input or a read error, and
        // both mean the same thing here — stop.
        while let message = try? NativeMessaging.readMessage(from: input) {
            let response: Response
            if let request = try? JSONDecoder().decode(Request.self, from: message) {
                response = handle(request)
            } else {
                response = .passThrough(id: nil, status: "error", detail: "malformed request")
            }
            guard (try? NativeMessaging.writeMessage(encode(response), to: output)) != nil else { return }
        }
    }

    static func handle(_ request: Request) -> Response {
        guard let link = LinkParser.parse(request.url) else {
            return .passThrough(id: request.id, status: "notALink")
        }

        let resolver = Resolver(appSupportDirectory: Resolver.defaultAppSupportDirectory)
        let resolution: Resolution
        do {
            resolution = try resolver.resolve(fileId: link.fileId, driveId: link.driveId)
        } catch {
            // A missing or unreadable .parms.db is the normal case on a Mac without the client,
            // so this is not worth shouting about: let the link open in the browser.
            return .passThrough(id: request.id, status: "error", detail: String(describing: error))
        }

        switch resolution {
        case let .localPath(path):
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            let action: Finder.Action = isDirectory.boolValue
                ? .open
                : (request.fileAction == "open" ? .open : .reveal)
            do {
                try Finder.perform(action, on: path)
                return .opened(id: request.id, path: path)
            } catch {
                return .passThrough(id: request.id, status: "error", detail: String(describing: error))
            }
        case let .missingOnDisk(path):
            return .passThrough(id: request.id, status: "missingOnDisk", detail: path)
        case .notSynced:
            return .passThrough(id: request.id, status: "notSynced")
        case .driveNotSynced:
            return .passThrough(id: request.id, status: "driveNotSynced")
        }
    }

    private static func encode(_ response: Response) -> Data {
        (try? JSONEncoder().encode(response)) ?? Data(#"{"status":"error"}"#.utf8)
    }
}

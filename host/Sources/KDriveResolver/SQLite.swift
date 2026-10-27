import CSQLite
import Foundation

/// Errors raised while reading one of the kDrive client databases.
public enum SQLiteError: Error, CustomStringConvertible {
    case open(path: String, message: String)
    case prepare(sql: String, message: String)
    case step(message: String)

    public var description: String {
        switch self {
        case let .open(path, message): return "cannot open \(path): \(message)"
        case let .prepare(sql, message): return "cannot prepare \(sql): \(message)"
        case let .step(message): return "query failed: \(message)"
        }
    }
}

/// A read-only connection to a SQLite file.
///
/// The kDrive client keeps its databases in WAL mode and holds them open while it runs, so we
/// never write and never take anything stronger than a shared read lock.
final class SQLiteConnection {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let uri = "file:\(SQLiteConnection.percentEncode(path))?mode=ro"
        guard sqlite3_open_v2(uri, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            sqlite3_close_v2(handle)
            throw SQLiteError.open(path: path, message: message)
        }
        sqlite3_busy_timeout(handle, 2000)
        self.handle = handle
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Runs `sql` and calls `row` for each result row until it returns false.
    func query(_ sql: String, bind: [SQLiteValue] = [], row: (SQLiteRow) -> Bool) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError.prepare(sql: sql, message: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in bind.enumerated() {
            value.bind(to: statement, at: Int32(index + 1))
        }

        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                if !row(SQLiteRow(statement: statement)) { return }
            case SQLITE_DONE:
                return
            default:
                throw SQLiteError.step(message: String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    /// Percent-encodes a filesystem path for use in a SQLite `file:` URI. `?` and `#` would
    /// otherwise start the query or fragment, and kDrive sync roots are user-named folders.
    private static func percentEncode(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }
}

/// A value bound to a statement parameter.
enum SQLiteValue {
    case text(String)
    case int(Int64)

    fileprivate func bind(to statement: OpaquePointer, at index: Int32) {
        switch self {
        case let .text(value):
            // SQLITE_TRANSIENT: sqlite copies the bytes, so the Swift string need not outlive this call.
            sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        case let .int(value):
            sqlite3_bind_int64(statement, index, value)
        }
    }
}

/// One result row, valid only inside the `row` callback that received it.
struct SQLiteRow {
    fileprivate let statement: OpaquePointer

    func text(_ column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: bytes)
    }

    func int(_ column: Int32) -> Int64? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, column)
    }
}

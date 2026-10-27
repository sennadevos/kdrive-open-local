import Foundation

/// Firefox's native messaging framing: a 32-bit native-endian length, then that many bytes of
/// UTF-8 JSON, repeated until the browser closes the pipe.
enum NativeMessaging {
    /// Reads one message, or nil at end of input.
    static func readMessage(from handle: FileHandle) throws -> Data? {
        guard let header = try read(handle, exactly: 4) else { return nil }
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        // Firefox itself caps messages at 1 MB; anything larger is a desynchronised stream.
        guard length > 0, length <= 1024 * 1024 else { return nil }
        return try read(handle, exactly: Int(length))
    }

    static func writeMessage(_ payload: Data, to handle: FileHandle) throws {
        var length = UInt32(payload.count)
        var framed = Data(bytes: &length, count: 4)
        framed.append(payload)
        try handle.write(contentsOf: framed)
    }

    private static func read(_ handle: FileHandle, exactly count: Int) throws -> Data? {
        var buffer = Data()
        while buffer.count < count {
            guard let chunk = try handle.read(upToCount: count - buffer.count), !chunk.isEmpty else {
                return nil
            }
            buffer.append(chunk)
        }
        return buffer
    }
}

import Foundation

/// Byte-level Server-Sent Events (SSE) parser preserving blank-line delimiters for `URLSession.bytes`.

nonisolated struct SSEEvent: Equatable, Sendable {
    let event: String
    let data: Data
    let retryMs: Int?
}

/// Incrementally parses UTF-8 SSE frames (`event:`, `data:`, `retry:`, `:comment`, blank-line flush).
nonisolated struct SSEFrameParser: Sendable {
    private var lineBuffer: [UInt8] = []
    private var currentEventName: String = "message"
    private var dataLines: [String] = []
    private var pendingRetryMs: Int?

    init() {}

    mutating func append(byte: UInt8) -> SSEEvent? {
        if byte == 0x0A { // `\n`
            return finishCurrentLine()
        } else if byte != 0x0D { // ignore `\r` so CRLF and LF behave identically
            lineBuffer.append(byte)
        }
        return nil
    }

    mutating func finishStream() -> SSEEvent? {
        var emitted: SSEEvent?
        if !lineBuffer.isEmpty {
            emitted = finishCurrentLine()
        }
        if let flushed = flushEventIfReady() {
            return flushed
        }
        return emitted
    }

    private mutating func finishCurrentLine() -> SSEEvent? {
        let line = String(decoding: lineBuffer, as: UTF8.self)
        lineBuffer.removeAll(keepingCapacity: true)

        if line.isEmpty {
            return flushEventIfReady()
        }
        if line.hasPrefix(":") {
            return nil
        }

        let field: String
        let value: String
        if let colonIndex = line.firstIndex(of: ":") {
            field = String(line[..<colonIndex])
            let afterColon = line.index(after: colonIndex)
            if afterColon < line.endIndex, line[afterColon] == " " {
                value = String(line[line.index(after: afterColon)...])
            } else {
                value = String(line[afterColon...])
            }
        } else {
            field = line
            value = ""
        }

        switch field {
        case "event":
            currentEventName = value.isEmpty ? "message" : value
        case "data":
            dataLines.append(value)
        case "retry":
            if let retryMs = Int(value), retryMs >= 0 {
                pendingRetryMs = retryMs
            }
        default:
            break
        }
        return nil
    }

    private mutating func flushEventIfReady() -> SSEEvent? {
        guard !dataLines.isEmpty else {
            currentEventName = "message"
            return nil
        }
        let joined = dataLines.joined(separator: "\n")
        let event = SSEEvent(
            event: currentEventName,
            data: Data(joined.utf8),
            retryMs: pendingRetryMs
        )
        currentEventName = "message"
        dataLines.removeAll(keepingCapacity: true)
        pendingRetryMs = nil
        return event
    }
}

import Foundation

public enum Paths {
    nonisolated(unsafe) public static var home: URL = ProcessInfo.processInfo.environment["BOSS_HOME"]
        .map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser

    public static var claude: URL { home.appendingPathComponent(".claude") }
    public static var codex: URL { home.appendingPathComponent(".codex") }
    public static var cursor: URL { home.appendingPathComponent(".cursor") }
    public static var pi: URL { home.appendingPathComponent(".pi") }
    public static var omp: URL { home.appendingPathComponent(".omp") }

    public static var appSupport: URL {
        let base = ProcessInfo.processInfo.environment["BOSS_HOME"] != nil
            ? home.appendingPathComponent("Library/Application Support")
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("TheBoss")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

struct JSONLTail {
    private(set) var offset: UInt64 = 0
    private(set) var size: UInt64 = 0

    mutating func readNewLines(path: String) -> (lines: [Data], reset: Bool) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = (attrs[.size] as? NSNumber)?.uint64Value else { return ([], false) }
        var reset = false
        if fileSize < offset {
            offset = 0
            reset = true
        }
        size = fileSize
        guard fileSize > offset, let handle = FileHandle(forReadingAtPath: path) else { return ([], reset) }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.readToEnd(), !data.isEmpty,
                  let lastNewline = data.lastIndex(of: 0x0A) else { return ([], reset) }
            let complete = data[data.startIndex...lastNewline]
            offset += UInt64(complete.count)
            return (complete.split(separator: 0x0A, omittingEmptySubsequences: true).map { Data($0) }, reset)
        } catch {
            return ([], reset)
        }
    }

    mutating func readNewObjects(path: String) -> (objects: [[String: Any]], reset: Bool) {
        let (lines, reset) = readNewLines(path: path)
        return (lines.compactMap(Self.object), reset)
    }

    static func object(_ line: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: line) as? [String: Any]
    }
}

extension Data {
    func containsBytes(_ needle: String) -> Bool {
        range(of: Data(needle.utf8)) != nil
    }

    func captures(after marker: String, limit: Int = 64) -> [String] {
        let markerData = Data(marker.utf8)
        var result: [String] = []
        var searchStart = startIndex
        while let found = range(of: markerData, in: searchStart..<endIndex) {
            var cursor = found.upperBound
            var bytes: [UInt8] = []
            while cursor < endIndex, self[cursor] != 0x22, bytes.count < 200 {
                bytes.append(self[cursor])
                cursor = index(after: cursor)
            }
            if let string = String(bytes: bytes, encoding: .utf8) { result.append(string) }
            searchStart = cursor
            if result.count >= limit { break }
        }
        return result
    }
}

enum ISODate {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func parse(_ value: Any?) -> Date? {
        if let string = value as? String {
            return fractional.date(from: string) ?? plain.date(from: string)
        }
        if let number = value as? Double {
            return Date(timeIntervalSince1970: number > 1e12 ? number / 1000 : number)
        }
        if let number = value as? Int {
            let n = Double(number)
            return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
        }
        return nil
    }
}

enum DayKey {
    nonisolated(unsafe) private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func of(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ key: String) -> Date? { formatter.date(from: key) }
}

func fileModificationDate(_ path: String) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
}

func isProcessAlive(_ pid: Int32) -> Bool {
    if kill(pid, 0) == 0 { return true }
    return errno == EPERM
}

extension String {
    func truncated(_ limit: Int) -> String {
        count > limit ? String(prefix(limit - 1)) + "…" : self
    }

    var singleLine: String {
        split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

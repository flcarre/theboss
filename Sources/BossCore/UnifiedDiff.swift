import Foundation

public enum DiffLineKind: Sendable, Hashable {
    case context, added, removed, header
}

public struct DiffLine: Sendable, Hashable {
    public var kind: DiffLineKind
    public var text: String
}

public enum UnifiedDiff {
    public static func lines(old: String, new: String, path: String, context: Int = 3) -> [DiffLine] {
        let a = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        let ops = edits(a, b)
        guard ops.contains(where: { $0.kind != .context }) else { return [] }

        var result: [DiffLine] = [
            DiffLine(kind: .header, text: "--- \(old.isEmpty ? "/dev/null" : "a/" + path)"),
            DiffLine(kind: .header, text: "+++ b/\(path)"),
        ]
        let changes = ops.indices.filter { ops[$0].kind != .context }
        var groups: [(Int, Int)] = []
        for change in changes {
            if let last = groups.last, change - last.1 <= context * 2 {
                groups[groups.count - 1].1 = change
            } else {
                groups.append((change, change))
            }
        }
        for (first, last) in groups {
            let start = max(0, first - context)
            let end = min(ops.count, last + context + 1)
            let hunk = Array(ops[start..<end])
            let oldStart = (hunk.first { $0.kind != .added }?.oldIndex).map { $0 + 1 } ?? (ops[start].oldIndex ?? 0)
            let newStart = (hunk.first { $0.kind != .removed }?.newIndex).map { $0 + 1 } ?? (ops[start].newIndex ?? 0)
            let oldCount = hunk.filter { $0.kind != .added }.count
            let newCount = hunk.filter { $0.kind != .removed }.count
            result.append(DiffLine(kind: .header, text: "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"))
            for op in hunk {
                let prefix = op.kind == .added ? "+" : op.kind == .removed ? "-" : " "
                result.append(DiffLine(kind: op.kind, text: prefix + op.text))
            }
        }
        return result
    }

    public static func text(old: String, new: String, path: String) -> String {
        lines(old: old, new: new, path: path).map(\.text).joined(separator: "\n")
    }

    struct Op {
        var kind: DiffLineKind
        var text: String
        var oldIndex: Int?
        var newIndex: Int?
    }

    static func edits(_ a: [String], _ b: [String]) -> [Op] {
        let n = a.count, m = b.count
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }
        var ops: [Op] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n && j < m && a[i] == b[j] {
                ops.append(Op(kind: .context, text: a[i], oldIndex: i, newIndex: j))
                i += 1; j += 1
            } else if j < m && (i == n || table[i][j + 1] >= table[i + 1][j]) {
                ops.append(Op(kind: .added, text: b[j], oldIndex: i, newIndex: j))
                j += 1
            } else {
                ops.append(Op(kind: .removed, text: a[i], oldIndex: i, newIndex: j))
                i += 1
            }
        }
        return ops
    }
}

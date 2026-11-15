import Foundation

/// 白名单条目与匹配结果（与 Android 版 WhitelistStore 对应）
struct WhitelistEntry: Identifiable, Equatable {
    let name: String
    let id: String
    let threshold: Int
    var id_key: String { "\(name)|\(id)|\(threshold)" }
    var id_value: String { id.isEmpty ? name : id }
}

struct MatchResult: Identifiable, Equatable {
    let entry: WhitelistEntry
    let displayName: String
    let likeCount: Int
    let overThreshold: Bool
    var id: String { "\(displayName)|\(entry.id)|\(likeCount)" }
}

enum WhitelistStore {
    /// 解析白名单文本：["名称:id:阈值", ...] 或每行一条 名称:id:阈值
    static func parse(_ raw: String) -> [WhitelistEntry] {
        var out: [WhitelistEntry] = []
        var seen = Set<String>()

        func push(_ name: String, _ id: String, _ threshold: Int) {
            let key = "\(name)|\(id)"
            guard !seen.contains(key) else { return }
            seen.insert(key)
            out.append(WhitelistEntry(name: name, id: id, threshold: threshold))
        }

        // 去掉首尾 [ ] 与引号后，按 , 拆分；也支持每行一条
        var parts: [String] = []
        if raw.contains("[") {
            var s = raw
            s = s.replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .replacingOccurrences(of: "\"", with: "")
            parts = s.split(whereSeparator: { ",\n".contains($0) }).map { String($0) }
        } else {
            parts = raw.split(separator: "\n").map { String($0) }
        }

        for p in parts {
            let seg = p.split(separator: ":", omittingEmptySubsequences: false).map { String($0) }
            guard seg.count >= 3 else { continue }
            let name = seg[0].trimmingCharacters(in: .whitespaces)
            let id = seg[1].trimmingCharacters(in: .whitespaces)
            let threshold = Int(seg[2].trimmingCharacters(in: .whitespaces)) ?? 0
            guard !name.isEmpty else { continue }
            push(name, id, threshold)
        }
        return out
    }
}

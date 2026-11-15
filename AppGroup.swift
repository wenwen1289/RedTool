import Foundation
import UIKit

/// 主 App 与 Broadcast 扩展共用的数据通道（App Group）
enum AppGroup {
    static let suiteName = "group.com.wenwen1289.RedTool"
    private static let keyWhitelist = "whitelist_raw"
    private static let keyMatches = "live_matches"

    static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    /// 免费签名可能剥掉 App Group 权限
    static var groupAvailable: Bool { defaults != nil }

    // ===== 剪贴板兜底通道（无权限要求） =====
    static let pasteboardPrefix = "REDTOOL_WHITELIST::"

    /// App 侧：把白名单写入系统剪贴板（扩展启动时读取）
    static func copyWhitelistToPasteboard(_ raw: String) {
        UIPasteboard.general.string = pasteboardPrefix + raw
    }

    /// 扩展侧：从剪贴板读取白名单（带前缀校验，避免误读用户剪贴板内容）
    static func loadWhitelistFromPasteboard() -> String? {
        guard let s = UIPasteboard.general.string,
              s.hasPrefix(pasteboardPrefix) else { return nil }
        return String(s.dropFirst(pasteboardPrefix.count))
    }

    // 白名单
    static func saveWhitelist(_ raw: String) {
        defaults?.set(raw, forKey: keyWhitelist)
    }

    static func loadWhitelistRaw() -> String {
        defaults?.string(forKey: keyWhitelist) ?? ""
    }

    // 实时匹配结果
    struct StoredMatch: Codable {
        let displayName: String
        let likeCount: Int
        let overThreshold: Bool
        let entryName: String
        let entryId: String
        let entryThreshold: Int
        let timestamp: Date
    }

    static func saveMatches(_ matches: [MatchResult]) {
        let stored = matches.map {
            StoredMatch(displayName: $0.displayName,
                        likeCount: $0.likeCount,
                        overThreshold: $0.overThreshold,
                        entryName: $0.entry.name,
                        entryId: $0.entry.id,
                        entryThreshold: $0.entry.threshold,
                        timestamp: Date())
        }
        if let data = try? JSONEncoder().encode(stored) {
            defaults?.set(data, forKey: keyMatches)
        }
    }

    static func loadMatches() -> [MatchResult] {
        guard let data = defaults?.data(forKey: keyMatches),
              let stored = try? JSONDecoder().decode([StoredMatch].self, from: data) else { return [] }
        return stored.map {
            MatchResult(entry: WhitelistEntry(name: $0.entryName,
                                              id: $0.entryId,
                                              threshold: $0.entryThreshold),
                        displayName: $0.displayName,
                        likeCount: $0.likeCount,
                        overThreshold: $0.overThreshold)
        }
    }
}

/// 共享日志（App 与扩展都写入；5 分钟自动清理，最多 500 条）
enum AppLog {
    struct Entry: Codable, Identifiable, Equatable {
        let ts: Date
        let level: String
        let msg: String
        var id: String { "\(ts.timeIntervalSince1970)|\(level)|\(msg)" }
    }

    private static let key = "app_logs"
    private static let maxAge: TimeInterval = 5 * 60   // 5 分钟自动清理
    private static let maxLines = 500

    static func append(_ level: String, _ msg: String) {
        var list = load()
        list.append(Entry(ts: Date(), level: level, msg: msg))
        if let data = try? JSONEncoder().encode(list) {
            AppGroup.defaults?.set(data, forKey: key)
        }
    }

    static func load() -> [Entry] {
        guard let data = AppGroup.defaults?.data(forKey: key),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        let cutoff = Date().addingTimeInterval(-maxAge)
        let kept = list.filter { $0.ts >= cutoff }.suffix(maxLines)
        return Array(kept)
    }

    static func clear() {
        AppGroup.defaults?.removeObject(forKey: key)
    }
}

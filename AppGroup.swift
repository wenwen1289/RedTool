import Foundation

/// 主 App 与 Broadcast 扩展共用的数据通道（App Group）
enum AppGroup {
    static let suiteName = "group.redbooktool"
    private static let keyWhitelist = "whitelist_raw"
    private static let keyMatches = "live_matches"

    static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

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

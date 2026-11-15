import Foundation
import UIKit
import Vision
import CoreVideo

/// OCR 识别 + 白名单匹配（主 App 与 Broadcast 扩展共用）
enum ScreenshotAnalyzer {

    /// 小红书卡片描述格式：……来自 作者名 123赞 / 1.2万赞
    private static let cardPattern = try! NSRegularExpression(
        pattern: "来自\\s*(.+?)\\s*([0-9][0-9,.]*)\\s*(万|[wW])?\\+?赞")

    /// 普通文本里的点赞模式：作者名 123赞
    private static let likePattern = try! NSRegularExpression(
        pattern: "^([^\\n]{1,30}?)\\s+([0-9][0-9,.]*)\\s*(万|[wW])?\\+?赞\\s*$")

    struct Candidate {
        let name: String
        let likeCount: Int
    }

    // MARK: - 入口

    /// 截图分析（主 App）
    static func analyze(image: UIImage, whitelist: [WhitelistEntry]) -> [MatchResult] {
        guard let cg = image.cgImage else { return [] }
        let lines = recognizeText(cgImage: cg)
        return analyze(lines: lines, whitelist: whitelist)
    }

    /// 已识别的文本行 → 匹配（扩展实时帧也走这里）
    static func analyze(lines: [String], whitelist: [WhitelistEntry]) -> [MatchResult] {
        let candidates = extractCandidates(from: lines)
        return match(candidates: candidates, whitelist: whitelist)
    }

    /// 静态图 OCR（主 App 截图识别用，供日志输出原始行）
    static func recognizeText(cgImage: CGImage) -> [String] {
        var results: [String] = []
        let request = VNRecognizeTextRequest { req, _ in
            guard let obs = req.results as? [VNRecognizedTextObservation] else { return }
            for o in obs {
                if let t = o.topCandidates(1).first?.string {
                    results.append(t)
                }
            }
        }
        request.recognitionLevel = .fast          // 实时帧用 fast，保证帧率
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
        return results
    }

    // MARK: - OCR（静态图）

    private static func recognizeText(cgImage: CGImage) -> [String] {
        var results: [String] = []
        let request = VNRecognizeTextRequest { req, _ in
            guard let obs = req.results as? [VNRecognizedTextObservation] else { return }
            for o in obs {
                if let t = o.topCandidates(1).first?.string {
                    results.append(t)
                }
            }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return results
    }

    // MARK: - 提取候选（名称 + 点赞数）

    /// 纯数字点赞行（小红书 feed 卡片：作者名与点赞数是两行，数字行不带"赞"字）
    private static let pureCountPattern = try! NSRegularExpression(
        pattern: "^([0-9][0-9,.]*)\\s*(万|[wW])?\\+?$")

    private static func extractCandidates(from lines: [String]) -> [Candidate] {
        var out: [Candidate] = []
        var seen = Set<String>()
        var prevName: String?

        for raw in lines {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty, s.count <= 100 else { continue }

            // 卡片描述：……来自 作者 N赞
            if let m = cardPattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let name = group(m, 1, in: s), let cnt = group(m, 2, in: s) {
                add(name: name, raw: cnt, wan: group(m, 3, in: s), out: &out, seen: &seen)
                prevName = nil
                continue
            }
            // 同一行：作者名 N赞
            if let m = likePattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let name = group(m, 1, in: s), let cnt = group(m, 2, in: s) {
                add(name: name, raw: cnt, wan: group(m, 3, in: s), out: &out, seen: &seen)
                prevName = nil
                continue
            }
            // 两行结构：上一行作者名 + 本行纯数字（可带万/w/+）
            if let m = pureCountPattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let cnt = group(m, 1, in: s), let name = prevName {
                add(name: name, raw: cnt, wan: group(m, 2, in: s), out: &out, seen: &seen)
                prevName = nil
                continue
            }
            // 记录可能的作者名（短文本、非纯数字、非噪声）
            if s.count <= 30, !isNoise(s), pureCountPattern.firstMatch(
                in: s, range: NSRange(s.startIndex..., in: s)) == nil {
                prevName = s
            } else {
                prevName = nil
            }
        }
        return out
    }

    private static func isNoise(_ name: String) -> Bool {
        let noise = ["笔记", "视频", "图文", "直播", "来自", "赞", "小红书", "关注", "搜索"]
        return noise.contains(where: { name.contains($0) })
    }

    private static func add(name rawName: String, raw: String, wan: String?,
                            out: inout [Candidate], seen: inout Set<String>) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if isNoise(name) { return }
        guard !seen.contains(name) else { return }
        seen.insert(name)
        out.append(Candidate(name: name, likeCount: parseCount(raw: raw, wan: wan)))
    }

    /// 600 / 1,234 / 1.2万 / 3w / 999+
    static func parseCount(raw: String, wan: String?) -> Int {
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "+", with: "")
        if let wan = wan, wan.lowercased() == "万" || wan.lowercased() == "w" {
            let parts = cleaned.split(separator: ".")
            let intPart = Int(parts.first ?? "0") ?? 0
            let frac = parts.count > 1 ? Double("0." + parts[1]) ?? 0 : 0
            return Int((Double(intPart) + frac) * 10000)
        }
        let digits = cleaned.replacingOccurrences(of: ".", with: "")
        return Int(digits) ?? Int.max
    }

    private static func group(_ m: NSTextCheckingResult, _ idx: Int, in s: String) -> String? {
        guard let r = Range(m.range(at: idx), in: s) else { return nil }
        return String(s[r])
    }

    // MARK: - 匹配（完全/前缀匹配，按名称+id 去重）

    static func match(candidates: [Candidate], whitelist: [WhitelistEntry]) -> [MatchResult] {
        var out: [MatchResult] = []
        var seen = Set<String>()

        for c in candidates {
            let dn = c.name.trimmingCharacters(in: .whitespaces)
            for e in whitelist {
                let exact = dn == e.name
                let prefix = !exact && dn.hasPrefix(e.name)
                guard exact || prefix else { continue }
                let key = "\(dn)|\(e.id)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                out.append(MatchResult(entry: e,
                                       displayName: dn,
                                       likeCount: c.likeCount,
                                       overThreshold: c.likeCount >= e.threshold))
            }
        }
        return out
    }
}

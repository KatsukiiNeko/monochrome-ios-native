// EQTextFormat.swift: import and export the AutoEQ / Equalizer APO text format.
import Foundation

public struct EQImportSummary: Equatable, Sendable {
    public var filters: [FilterSpec]
    public var preampDB: Double?
    public var applied: Int
    public var ignored: [String]
    public var clamped: [String]
    public var truncated: Int

    public init(
        filters: [FilterSpec] = [],
        preampDB: Double? = nil,
        applied: Int = 0,
        ignored: [String] = [],
        clamped: [String] = [],
        truncated: Int = 0
    ) {
        self.filters = filters
        self.preampDB = preampDB
        self.applied = applied
        self.ignored = ignored
        self.clamped = clamped
        self.truncated = truncated
    }

    /// One short line for the import result banner.
    public var summaryText: String {
        var parts = ["\(applied) filter\(applied == 1 ? "" : "s")"]
        if !clamped.isEmpty { parts.append("\(clamped.count) clamped") }
        if truncated > 0 { parts.append("\(truncated) skipped") }
        if !ignored.isEmpty { parts.append("\(ignored.count) ignored") }
        return parts.joined(separator: " · ")
    }
}

public enum EQTextFormat {
    public static func parse(_ text: String, maxFilters: Int = EQSettings.maximumFilters) -> EQImportSummary {
        var summary = EQImportSummary()
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line.lowercased().hasPrefix("preamp") {
                if let value = number(after: ":", in: line) {
                    summary.preampDB = min(max(value, -24), 24)
                } else {
                    summary.ignored.append(line)
                }
                continue
            }

            guard line.lowercased().hasPrefix("filter") else {
                summary.ignored.append(line)
                continue
            }
            guard summary.filters.count < maxFilters else {
                summary.truncated += 1
                continue
            }
            guard let parsed = parseFilterLine(line) else {
                summary.ignored.append(line)
                continue
            }
            if parsed.wasClamped {
                summary.clamped.append(line)
            }
            summary.filters.append(parsed.spec)
        }
        summary.applied = summary.filters.count
        return summary
    }

    public static func export(filters: [FilterSpec], preampDB: Double?) -> String {
        var lines: [String] = []
        if let preampDB {
            lines.append("Preamp: \(format(preampDB, decimals: 1)) dB")
        }
        for (index, spec) in filters.enumerated() {
            let type = typeName(for: spec.kind)
            let state = spec.enabled ? "ON" : "OFF"
            let frequency = format(spec.frequency, decimals: spec.frequency < 100 ? 1 : 0)
            var line = "Filter \(index + 1): \(state) \(type) Fc \(frequency) Hz"
            if spec.kind.usesGain {
                line += " Gain \(format(spec.gainDB, decimals: 1)) dB"
            }
            line += " Q \(format(spec.q, decimals: 2))"
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Parsing

    private struct Parsed {
        var spec: FilterSpec
        var wasClamped: Bool
    }

    private static func parseFilterLine(_ line: String) -> Parsed? {
        let body = line.split(separator: ":", maxSplits: 1).count == 2
            ? String(line.split(separator: ":", maxSplits: 1)[1])
            : line
        let tokens = body.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let first = tokens.first else { return nil }

        let enabled: Bool
        let typeToken: String
        if first.caseInsensitiveCompare("ON") == .orderedSame || first.caseInsensitiveCompare("OFF") == .orderedSame {
            enabled = first.caseInsensitiveCompare("ON") == .orderedSame
            guard tokens.count > 1 else { return nil }
            typeToken = tokens[1]
        } else {
            enabled = true
            typeToken = first
        }
        guard let kind = kind(for: typeToken) else { return nil }

        guard let rawFrequency = value(after: ["fc", "f", "freq"], in: tokens),
              let rawGain = kind.usesGain ? value(after: ["gain", "g"], in: tokens) : 0
        else { return nil }

        var q: Double
        if let rawQ = value(after: ["q"], in: tokens) {
            q = rawQ
        } else if let slope = value(after: ["s", "slope"], in: tokens), kind.usesGain {
            q = qFromSlope(slope, gainDB: rawGain)
        } else {
            q = kind.defaultQ
        }

        let spec = FilterSpec(
            kind: kind,
            frequency: rawFrequency,
            gainDB: rawGain,
            q: q,
            enabled: enabled
        )
        let clamped = abs(spec.frequency - rawFrequency) > 1e-9
            || (kind.usesGain && abs(spec.gainDB - rawGain) > 1e-9)
            || abs(spec.q - q) > 1e-9
        return Parsed(spec: spec, wasClamped: clamped)
    }

    /// Converts a shelf slope `S` to the cookbook Q.
    private static func qFromSlope(_ slope: Double, gainDB: Double) -> Double {
        let s = min(max(slope, 0.1), 1)
        let a = pow(10, gainDB / 40)
        let inverseQ = sqrt(max((a + 1 / a) * (1 / s - 1) + 2, 1e-9))
        return inverseQ > 0 ? 1 / inverseQ : 0.7071
    }

    private static func value(after keywords: [String], in tokens: [String]) -> Double? {
        for (index, token) in tokens.enumerated() {
            guard keywords.contains(token.lowercased()) else { continue }
            for next in tokens.dropFirst(index + 1) {
                if let number = Double(next.replacingOccurrences(of: ",", with: ".")) {
                    return number
                }
                if next.lowercased() == "hz" || next.lowercased() == "db" { continue }
            }
        }
        return nil
    }

    private static func number(after character: Character, in line: String) -> Double? {
        guard let range = line.range(of: String(character)) else { return nil }
        let tail = line[range.upperBound...]
        for token in tail.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            if let value = Double(token.replacingOccurrences(of: ",", with: ".")) {
                return value
            }
        }
        return nil
    }

    private static func kind(for token: String) -> BiquadKind? {
        switch token.uppercased() {
        case "PK", "PEAK", "PEQ": .peak
        case "LS", "LSC", "LOWSHELF": .lowShelf
        case "HS", "HSC", "HIGHSHELF": .highShelf
        case "HP", "HPF": .highPass
        case "LP", "LPF": .lowPass
        case "NO", "NOTCH": .notch
        default: nil
        }
    }

    private static func typeName(for kind: BiquadKind) -> String {
        switch kind {
        case .peak: "PK"
        case .lowShelf: "LS"
        case .highShelf: "HS"
        case .highPass: "HP"
        case .lowPass: "LP"
        case .notch: "NO"
        }
    }

    private static func format(_ value: Double, decimals: Int) -> String {
        let text = String(format: "%.\(decimals)f", value)
        return text
    }
}

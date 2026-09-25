import Foundation

/// The reader's typography (RP3) — the desktop's `reader.store.ts` prefs, per
/// device. Stored under one `UserDefaults` key and clamped on the way in, like
/// the desktop's `sanitizePrefs`: a field that cannot be read is defaulted on its
/// own, so one bad value never costs the reader the rest of their choices.
struct ReaderPrefs: Codable, Equatable, Sendable {
    enum Typeface: String, Codable, CaseIterable, Sendable {
        case serif
        case sans
    }

    enum Theme: String, Codable, CaseIterable, Sendable {
        case ink
        case paper
    }

    var typeface: Typeface
    var fontSize: Double
    var lineHeight: Double
    var margin: Double
    var theme: Theme

    static let fontSizeRange: ClosedRange<Double> = 12...28
    static let lineHeightRange: ClosedRange<Double> = 1.2...2.2
    static let marginRange: ClosedRange<Double> = 16...160

    static let `default` = ReaderPrefs(typeface: .serif, fontSize: 18, lineHeight: 1.6, margin: 48, theme: .ink)

    static let key = "readerPrefs"

    static func load(from defaults: UserDefaults) -> ReaderPrefs {
        guard let data = defaults.data(forKey: key),
              let prefs = try? JSONDecoder().decode(ReaderPrefs.self, from: data)
        else { return .default }
        return prefs
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Field-by-field decoding, in an extension so the memberwise initialiser stays.
extension ReaderPrefs {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ReaderPrefs.default
        typeface = (try? container.decodeIfPresent(String.self, forKey: .typeface))
            .flatMap(Typeface.init(rawValue:)) ?? fallback.typeface
        theme = (try? container.decodeIfPresent(String.self, forKey: .theme))
            .flatMap(Theme.init(rawValue:)) ?? fallback.theme
        fontSize = Self.clamp(
            (try? container.decodeIfPresent(Double.self, forKey: .fontSize)) ?? fallback.fontSize,
            to: Self.fontSizeRange
        )
        lineHeight = Self.clamp(
            (try? container.decodeIfPresent(Double.self, forKey: .lineHeight)) ?? fallback.lineHeight,
            to: Self.lineHeightRange
        )
        margin = Self.clamp(
            (try? container.decodeIfPresent(Double.self, forKey: .margin)) ?? fallback.margin,
            to: Self.marginRange
        )
    }
}

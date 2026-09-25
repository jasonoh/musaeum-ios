import ReadiumNavigator

/// `ReaderPrefs` in Readium's units (RP4). Pure, so the test pins every number.
/// This file imports no SwiftUI: `Color` here is Readium's.
enum ReaderPrefsMapping {
    /// The desktop's authored page rows (`src/lib/theme/reader-palette.ts`).
    static let inkBackground = "#14110d"
    static let inkText = "#e9e1d2"
    static let paperBackground = "#f3ece0"
    static let paperText = "#241f18"

    /// Readium's `fontSize` is a multiplier on its base; the desktop's default 18
    /// is that base.
    static func fontScale(points: Double) -> Double {
        points / 18
    }

    /// The desktop's 16–160 onto Readium's `pageMargins` multiplier, 0.5–3.0. The
    /// endpoints are a first reading; a live frame confirms or moves them, and this
    /// function and its test move together.
    static func marginScale(_ margin: Double) -> Double {
        let span = ReaderPrefs.marginRange.upperBound - ReaderPrefs.marginRange.lowerBound
        return 0.5 + (margin - ReaderPrefs.marginRange.lowerBound) / span * 2.5
    }

    static func epubPreferences(_ prefs: ReaderPrefs) -> EPUBPreferences {
        let ink = prefs.theme == .ink
        return EPUBPreferences(
            backgroundColor: Color(hex: ink ? inkBackground : paperBackground),
            fontFamily: prefs.typeface == .serif ? .serif : .sansSerif,
            fontSize: fontScale(points: prefs.fontSize),
            lineHeight: prefs.lineHeight,
            pageMargins: marginScale(prefs.margin),
            publisherStyles: false,
            textColor: Color(hex: ink ? inkText : paperText),
            theme: ink ? .dark : .light
        )
    }
}

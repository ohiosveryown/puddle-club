import SwiftUI

extension Color {
    /// Parses a dominant color string from the vision API (e.g. "coral", "warm orange", "#E07A5F") into a SwiftUI Color.
    /// Returns nil if the string cannot be parsed.
    static func fromDominantColorString(_ string: String?) -> Color? {
        guard let s = string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }

        // Try hex format first (e.g. #E07A5F or E07A5F)
        let hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
        if hex.count == 6 {
            let scanner = Scanner(string: hex)
            var rgb: UInt64 = 0
            if scanner.scanHexInt64(&rgb) {
                let r = Double((rgb >> 16) & 0xFF) / 255
                let g = Double((rgb >> 8) & 0xFF) / 255
                let b = Double(rgb & 0xFF) / 255
                return Color(red: r, green: g, blue: b)
            }
        }

        // Normalize for lookup: lowercase; try with spaces then without (e.g. "warm orange" → "warmorange")
        let normalized = s.lowercased().split(separator: " ").joined(separator: " ")
        let noSpaces = normalized.replacingOccurrences(of: " ", with: "")
        return Self.dominantColorNameMap[normalized] ?? Self.dominantColorNameMap[noSpaces]
    }

    private static let dominantColorNameMap: [String: Color] = [
        "coral": Color(red: 1.0, green: 0.49, blue: 0.38),
        "warmcoral": Color(red: 0.98, green: 0.45, blue: 0.36),
        "warm coral": Color(red: 0.98, green: 0.45, blue: 0.36),
        "orange": Color(red: 1.0, green: 0.58, blue: 0.0),
        "warmorange": Color(red: 0.98, green: 0.55, blue: 0.24),
        "warm orange": Color(red: 0.98, green: 0.55, blue: 0.24),
        "peach": Color(red: 1.0, green: 0.8, blue: 0.6),
        "warmpeach": Color(red: 0.99, green: 0.75, blue: 0.55),
        "warm peach": Color(red: 0.99, green: 0.75, blue: 0.55),
        "golden": Color(red: 0.85, green: 0.65, blue: 0.13),
        "goldenyellow": Color(red: 0.95, green: 0.82, blue: 0.25),
        "golden yellow": Color(red: 0.95, green: 0.82, blue: 0.25),
        "yellow": Color(red: 1.0, green: 0.9, blue: 0.2),
        "pink": Color(red: 1.0, green: 0.41, blue: 0.71),
        "softpink": Color(red: 0.98, green: 0.75, blue: 0.8),
        "soft pink": Color(red: 0.98, green: 0.75, blue: 0.8),
        "rose": Color(red: 0.96, green: 0.52, blue: 0.58),
        "red": Color(red: 0.9, green: 0.22, blue: 0.21),
        "burgundy": Color(red: 0.5, green: 0.11, blue: 0.22),
        "green": Color(red: 0.22, green: 0.69, blue: 0.33),
        "sage": Color(red: 0.55, green: 0.65, blue: 0.52),
        "teal": Color(red: 0.0, green: 0.55, blue: 0.55),
        "blue": Color(red: 0.25, green: 0.47, blue: 0.85),
        "skyblue": Color(red: 0.53, green: 0.81, blue: 0.98),
        "sky blue": Color(red: 0.53, green: 0.81, blue: 0.98),
        "lavender": Color(red: 0.71, green: 0.49, blue: 0.86),
        "purple": Color(red: 0.58, green: 0.4, blue: 0.72),
        "cream": Color(red: 1.0, green: 0.99, blue: 0.82),
        "beige": Color(red: 0.96, green: 0.96, blue: 0.86),
        "brown": Color(red: 0.55, green: 0.35, blue: 0.2),
        "terracotta": Color(red: 0.8, green: 0.4, blue: 0.3),
        "rust": Color(red: 0.72, green: 0.25, blue: 0.05),
        "mustard": Color(red: 0.78, green: 0.62, blue: 0.12),
        "mint": Color(red: 0.6, green: 0.98, blue: 0.8),
        "turquoise": Color(red: 0.25, green: 0.88, blue: 0.82),
        "navy": Color(red: 0.0, green: 0.0, blue: 0.5),
        "charcoal": Color(red: 0.27, green: 0.27, blue: 0.3),
    ]
}

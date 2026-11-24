import Foundation

/// Canonicalises operator-entered session-type strings.
///
/// Trims, lowercases, and collapses runs of internal whitespace into a single
/// underscore. Returns `nil` for empty or whitespace-only input. Underscores
/// are user content: they are not stripped or collapsed. Chips defined in
/// `Study.sessionTypeSuggestions` must already be canonical.
public enum SessionTypeNormalizer {
    public static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let lowered = trimmed.lowercased()
        return lowered.replacingOccurrences(
            of: "\\s+",
            with: "_",
            options: .regularExpression
        )
    }
}

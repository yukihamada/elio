import Foundation

// MARK: - PII Filter

/// Detects and masks personally identifiable information (PII) in text.
/// Supports Japanese-specific patterns: phone numbers, addresses, My Number, etc.
/// All regex patterns are compiled once and cached as static constants.
///
/// Usage:
///   let (filtered, count) = PIIFilter.filter("Call me at 090-1234-5678")
///   // filtered: "Call me at [REDACTED]", count: 1
enum PIIFilter {

    // MARK: - Filter Levels

    /// Determines which PII categories are detected and masked.
    enum Level {
        /// All patterns: phone, email, address, My Number, credit card, name, IP
        case strict
        /// Common patterns: phone, email, address, credit card
        case standard
        /// Minimal: email and credit card only
        case minimal

        /// Categories active for this filter level.
        var activeCategories: Set<PIICategory> {
            switch self {
            case .strict:
                return Set(PIICategory.allCases)
            case .standard:
                return [.phone, .email, .address, .creditCard]
            case .minimal:
                return [.email, .creditCard]
            }
        }
    }

    // MARK: - PII Categories

    /// Categories of personally identifiable information.
    enum PIICategory: String, CaseIterable {
        case phone = "phone"
        case email = "email"
        case address = "address"
        case mynumber = "mynumber"
        case creditCard = "creditCard"
        case name = "name"
        case ipAddress = "ipAddress"

        var displayName: String {
            switch self {
            case .phone: return "Phone Number"
            case .email: return "Email Address"
            case .address: return "Address"
            case .mynumber: return "My Number"
            case .creditCard: return "Credit Card"
            case .name: return "Name"
            case .ipAddress: return "IP Address"
            }
        }
    }

    // MARK: - Detection Result

    /// A single PII detection with its category, range in the original string, and length.
    struct Detection {
        let category: PIICategory
        let range: Range<String.Index>
        let originalLength: Int
    }

    // MARK: - Filtering Summary

    /// Summary of how many items were redacted per category.
    struct Summary {
        let totalRedacted: Int
        let countsByCategory: [PIICategory: Int]

        var description: String {
            guard totalRedacted > 0 else { return "No PII detected" }
            let details = countsByCategory
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.displayName): \($0.value)" }
                .joined(separator: ", ")
            return "\(totalRedacted) item(s) redacted — \(details)"
        }
    }

    // MARK: - Compiled Regex Patterns (cached as static lets)

    /// Japanese mobile phone: 090/080/070-XXXX-XXXX (with or without hyphens)
    private static let phoneMobileRegex: NSRegularExpression = {
        // cSpell:disable
        try! NSRegularExpression(
            pattern: #"0[789]0[- ]?\d{4}[- ]?\d{4}"#,
            options: []
        )
        // cSpell:enable
    }()

    /// Japanese landline phone: 0X-XXXX-XXXX, 0XX-XXX-XXXX, etc.
    private static let phoneLandlineRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"0\d{1,4}[- ]?\d{1,4}[- ]?\d{4}"#,
            options: []
        )
    }()

    /// Email address
    private static let emailRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}"#,
            options: []
        )
    }()

    /// Japanese postal code: 〒XXX-XXXX or XXX-XXXX
    private static let postalCodeRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"〒?\d{3}[- ]\d{4}"#,
            options: []
        )
    }()

    /// Japanese prefecture + city address pattern:
    /// XX県XX市, XX府XX市, XX都XX区, 北海道XX市, etc.
    private static let prefectureCityRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?:北海道|(?:東京|大阪|京都)府|.{2,3}県).{1,6}(?:市|区|町|村|郡)"#,
            options: []
        )
    }()

    /// Japanese ward/town address pattern: XX区XX町X丁目
    private static let wardTownRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #".{1,4}区.{1,6}(?:町|丁目)"#,
            options: []
        )
    }()

    /// My Number (Individual Number): exactly 12 digits
    private static let mynumberRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?<!\d)\d{12}(?!\d)"#,
            options: []
        )
    }()

    /// Credit card number: 16 digits (with optional spaces/hyphens between groups of 4)
    private static let creditCardRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?<!\d)\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}(?!\d)"#,
            options: []
        )
    }()

    /// Common Japanese full names: 2-4 kanji surname + space + 2-4 kanji given name
    private static let japaneseNameRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"[\p{Han}]{2,4}[\s　][\p{Han}]{2,4}"#,
            options: []
        )
    }()

    /// IPv4 address
    private static let ipv4Regex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?<!\d)(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)(?!\d)"#,
            options: []
        )
    }()

    /// All pattern definitions mapped by category.
    private static let patternsByCategory: [(PIICategory, [NSRegularExpression])] = [
        (.phone, [phoneMobileRegex, phoneLandlineRegex]),
        (.email, [emailRegex]),
        (.address, [postalCodeRegex, prefectureCityRegex, wardTownRegex]),
        (.mynumber, [mynumberRegex]),
        (.creditCard, [creditCardRegex]),
        (.name, [japaneseNameRegex]),
        (.ipAddress, [ipv4Regex])
    ]

    // MARK: - Public API

    /// Detect and mask PII in the given text.
    /// - Parameters:
    ///   - text: Input text to filter.
    ///   - level: Filter strictness level (default: `.standard`).
    /// - Returns: Tuple of the filtered text and the total number of redacted items.
    static func filter(_ text: String, level: Level = .standard) -> (filtered: String, redactedCount: Int) {
        let detections = detectAll(text, level: level)
        guard !detections.isEmpty else {
            return (text, 0)
        }

        // Sort detections by range start descending so we can replace from the end
        // to preserve earlier indices.
        let sorted = detections.sorted { $0.range.lowerBound > $1.range.lowerBound }

        var result = text
        // Track unique ranges to avoid double-redaction of overlapping matches
        var redactedRanges: [Range<String.Index>] = []

        for detection in sorted {
            // Skip if this range overlaps with an already-redacted range
            let overlaps = redactedRanges.contains { $0.overlaps(detection.range) }
            guard !overlaps else { continue }

            result.replaceSubrange(detection.range, with: "[REDACTED]")
            redactedRanges.append(detection.range)
        }

        return (result, redactedRanges.count)
    }

    /// Detect PII without masking. Useful for testing and inspection.
    /// - Parameters:
    ///   - text: Input text to scan.
    ///   - level: Filter strictness level (default: `.standard`).
    /// - Returns: Array of detections found in the text.
    static func detectOnly(_ text: String, level: Level = .standard) -> [Detection] {
        return detectAll(text, level: level)
    }

    /// Generate a summary of PII detections by category.
    /// - Parameters:
    ///   - text: Input text to scan.
    ///   - level: Filter strictness level (default: `.standard`).
    /// - Returns: A `Summary` with counts per category.
    static func summarize(_ text: String, level: Level = .standard) -> Summary {
        let detections = detectAll(text, level: level)

        // Deduplicate overlapping detections (keep the first per range)
        let unique = deduplicateDetections(detections)

        var counts: [PIICategory: Int] = [:]
        for detection in unique {
            counts[detection.category, default: 0] += 1
        }

        return Summary(
            totalRedacted: unique.count,
            countsByCategory: counts
        )
    }

    // MARK: - Private Helpers

    /// Run all active patterns against the text and collect detections.
    private static func detectAll(_ text: String, level: Level) -> [Detection] {
        let activeCategories = level.activeCategories
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        var detections: [Detection] = []

        for (category, patterns) in patternsByCategory {
            guard activeCategories.contains(category) else { continue }

            for regex in patterns {
                let matches = regex.matches(in: text, options: [], range: fullRange)
                for match in matches {
                    guard let range = Range(match.range, in: text) else { continue }
                    let detection = Detection(
                        category: category,
                        range: range,
                        originalLength: match.range.length
                    )
                    detections.append(detection)
                }
            }
        }

        return detections
    }

    /// Remove overlapping detections, keeping the first (longest) match for each overlap.
    private static func deduplicateDetections(_ detections: [Detection]) -> [Detection] {
        // Sort by start position, then by length descending (prefer longer matches)
        let sorted = detections.sorted {
            if $0.range.lowerBound == $1.range.lowerBound {
                return $0.originalLength > $1.originalLength
            }
            return $0.range.lowerBound < $1.range.lowerBound
        }

        var result: [Detection] = []
        for detection in sorted {
            let overlaps = result.contains { $0.range.overlaps(detection.range) }
            if !overlaps {
                result.append(detection)
            }
        }

        return result
    }
}

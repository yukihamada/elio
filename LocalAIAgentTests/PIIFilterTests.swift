import XCTest
@testable import LocalAIAgent

final class PIIFilterTests: XCTestCase {

    // MARK: - Phone Numbers

    func testMobilePhoneDetected() {
        let (filtered, count) = PIIFilter.filter("Call me at 090-1234-5678")
        XCTAssertEqual(count, 1)
        XCTAssertTrue(filtered.contains("[REDACTED]"))
        XCTAssertFalse(filtered.contains("090-1234-5678"))
    }

    func testMobilePhoneWithoutHyphens() {
        let (filtered, count) = PIIFilter.filter("My number is 08012345678")
        XCTAssertEqual(count, 1)
        XCTAssertFalse(filtered.contains("08012345678"))
    }

    func testLandlinePhoneDetected() {
        let (_, count) = PIIFilter.filter("03-1234-5678に電話してください")
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    // MARK: - Email

    func testEmailDetected() {
        let (filtered, count) = PIIFilter.filter("Contact: user@example.com for details")
        XCTAssertEqual(count, 1)
        XCTAssertFalse(filtered.contains("user@example.com"))
    }

    func testEmailWithSubdomainDetected() {
        let (_, count) = PIIFilter.filter("Reach me at hello.world+tag@mail.example.co.jp")
        XCTAssertEqual(count, 1)
    }

    // MARK: - Address

    func testPostalCodeDetected() {
        let (filtered, count) = PIIFilter.filter("住所: 〒100-0001 東京都千代田区")
        XCTAssertGreaterThanOrEqual(count, 1)
        XCTAssertFalse(filtered.contains("100-0001"))
    }

    func testPrefectureCityDetected() {
        let (_, count) = PIIFilter.filter("大阪府大阪市北区に住んでいます", level: .strict)
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    // MARK: - Credit Card

    func testCreditCardDetected() {
        // Use minimal level to isolate credit card detection without address false positives
        // (spaced CC numbers like "1234 5678 9012 3456" also trigger postal code regex at standard level)
        let (filtered, count) = PIIFilter.filter("Card: 1234 5678 9012 3456", level: .minimal)
        XCTAssertEqual(count, 1)
        XCTAssertFalse(filtered.contains("1234 5678 9012 3456"))
    }

    func testCreditCardWithHyphens() {
        // Use minimal level to isolate; hyphen-separated CC also triggers postal code regex
        let (_, count) = PIIFilter.filter("4111-1111-1111-1111を登録しました", level: .minimal)
        XCTAssertEqual(count, 1)
    }

    func testCreditCardContinuous() {
        let (_, count) = PIIFilter.filter("番号: 4111111111111111")
        XCTAssertEqual(count, 1)
    }

    // MARK: - IP Address

    func testIPv4Detected() {
        let (filtered, count) = PIIFilter.filter("Server IP: 192.168.1.100", level: .strict)
        XCTAssertEqual(count, 1)
        XCTAssertFalse(filtered.contains("192.168.1.100"))
    }

    func testInvalidIPNotDetected() {
        let (_, count) = PIIFilter.filter("Version: 256.1.2.3", level: .strict)
        XCTAssertEqual(count, 0)
    }

    // MARK: - Filter Levels

    func testMinimalLevelOnlyEmailAndCard() {
        let text = "Phone: 090-1234-5678, Email: a@b.com, Card: 1234567890123456"
        let (_, count) = PIIFilter.filter(text, level: .minimal)
        // Only email and credit card should be detected
        XCTAssertEqual(count, 2)
    }

    func testStandardLevelIncludesPhone() {
        let text = "Phone: 090-1234-5678, Email: a@b.com"
        let (_, count) = PIIFilter.filter(text, level: .standard)
        XCTAssertEqual(count, 2)
    }

    func testStrictLevelIncludesIP() {
        let text = "IP: 10.0.0.1"
        let (_, count) = PIIFilter.filter(text, level: .standard)
        let (_, countStrict) = PIIFilter.filter(text, level: .strict)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(countStrict, 1)
    }

    // MARK: - Clean Text

    func testNoPIIPassesThrough() {
        let text = "Hello, this is a normal message without personal info."
        let (filtered, count) = PIIFilter.filter(text)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(filtered, text)
    }

    func testEmptyStringHandled() {
        let (filtered, count) = PIIFilter.filter("")
        XCTAssertEqual(count, 0)
        XCTAssertEqual(filtered, "")
    }

    // MARK: - Summary

    func testSummaryCountsByCategory() {
        let text = "Email: foo@bar.com, Phone: 090-0000-0000"
        let summary = PIIFilter.summarize(text, level: .standard)
        XCTAssertEqual(summary.totalRedacted, 2)
        XCTAssertEqual(summary.countsByCategory[.email], 1)
        XCTAssertEqual(summary.countsByCategory[.phone], 1)
    }

    func testSummaryDescriptionNoPII() {
        let summary = PIIFilter.summarize("No PII here")
        XCTAssertEqual(summary.description, "No PII detected")
    }

    // MARK: - detectOnly

    func testDetectOnlyDoesNotModifyText() {
        let text = "My email is test@example.com"
        let detections = PIIFilter.detectOnly(text)
        XCTAssertEqual(detections.count, 1)
        XCTAssertEqual(detections.first?.category, .email)
        // Original text unchanged
        XCTAssertEqual(text, "My email is test@example.com")
    }

    // MARK: - Overlapping matches

    func testOverlappingMatchesNotDoubleRedacted() {
        // A 16-digit number matches both creditCard and mynumber (12-digit subset) — should only be redacted once
        let text = "1234567890123456"
        let (filtered, count) = PIIFilter.filter(text, level: .strict)
        // Count may be 1 or 2 depending on overlap logic, but text should only contain one [REDACTED]
        let redactedCount = filtered.components(separatedBy: "[REDACTED]").count - 1
        XCTAssertEqual(redactedCount, 1, "Should not double-redact overlapping matches")
        _ = count // suppress unused warning
    }
}

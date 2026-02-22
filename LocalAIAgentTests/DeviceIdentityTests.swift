import XCTest
@testable import LocalAIAgent

final class DeviceIdentityTests: XCTestCase {

    // MARK: - Singleton

    func testDeviceIdentityManagerSingleton() throws {
        let manager = DeviceIdentityManager.shared
        XCTAssertNotNil(manager)
    }

    // MARK: - Device ID

    func testDeviceIdIsPersistent() throws {
        let id1 = DeviceIdentityManager.shared.deviceId
        let id2 = DeviceIdentityManager.shared.deviceId
        XCTAssertEqual(id1, id2, "Device ID should be stable across calls")
        XCTAssertFalse(id1.isEmpty, "Device ID should not be empty")
    }

    // MARK: - Pairing Code

    func testPairingCodeFormat() throws {
        let manager = DeviceIdentityManager.shared
        let code = manager.getCurrentPairingCode()
        XCTAssertEqual(code.count, 4, "Pairing code should be 4 digits")
        XCTAssertNotNil(Int(code), "Pairing code should be numeric")
    }

    func testPairingCodeIsPersistentWithinValidity() throws {
        let manager = DeviceIdentityManager.shared
        let code1 = manager.getCurrentPairingCode()
        let code2 = manager.getCurrentPairingCode()
        XCTAssertEqual(code1, code2, "Same pairing code should be returned within validity period")
    }

    // MARK: - Pairing Code Verification

    func testVerifyValidPairingCode() throws {
        let manager = DeviceIdentityManager.shared
        XCTAssertTrue(manager.verifyPairingCode("1234"))
        XCTAssertTrue(manager.verifyPairingCode("0000"))
        XCTAssertTrue(manager.verifyPairingCode("9999"))
    }

    func testVerifyInvalidPairingCode() throws {
        let manager = DeviceIdentityManager.shared
        XCTAssertFalse(manager.verifyPairingCode(""))
        XCTAssertFalse(manager.verifyPairingCode("abc"))
        XCTAssertFalse(manager.verifyPairingCode("12345"))
        XCTAssertFalse(manager.verifyPairingCode("12"))
    }

    // MARK: - Message Signing

    func testSignMessageProducesConsistentResult() throws {
        let manager = DeviceIdentityManager.shared
        let sig1 = manager.signMessage("hello")
        let sig2 = manager.signMessage("hello")
        XCTAssertEqual(sig1, sig2, "Same message should produce same signature")
    }

    func testSignMessageDifferentMessagesProduceDifferentSignatures() throws {
        let manager = DeviceIdentityManager.shared
        let sig1 = manager.signMessage("hello")
        let sig2 = manager.signMessage("world")
        XCTAssertNotEqual(sig1, sig2, "Different messages should produce different signatures")
    }

    func testSignMessageProducesHexString() throws {
        let manager = DeviceIdentityManager.shared
        let sig = manager.signMessage("test")
        XCTAssertFalse(sig.isEmpty)
        // Should be hex characters only
        let hexCharSet = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(
            sig.unicodeScalars.allSatisfy { hexCharSet.contains($0) },
            "Signature should be hex string"
        )
    }
}

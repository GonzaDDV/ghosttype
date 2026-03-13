import XCTest
@testable import GhostType

final class KeychainHelperTests: XCTestCase {
    private let testService = "com.ghosttype.test"

    override func tearDown() {
        super.tearDown()
        KeychainHelper.delete(service: testService, account: "testKey")
    }

    func testSaveAndRetrieve() {
        let saved = KeychainHelper.save(service: testService, account: "testKey", data: "secret123")
        XCTAssertTrue(saved)
        let retrieved = KeychainHelper.retrieve(service: testService, account: "testKey")
        XCTAssertEqual(retrieved, "secret123")
    }

    func testRetrieveNonExistent() {
        let retrieved = KeychainHelper.retrieve(service: testService, account: "noSuchKey")
        XCTAssertNil(retrieved)
    }

    func testUpdateExistingKey() {
        KeychainHelper.save(service: testService, account: "testKey", data: "old")
        KeychainHelper.save(service: testService, account: "testKey", data: "new")
        let retrieved = KeychainHelper.retrieve(service: testService, account: "testKey")
        XCTAssertEqual(retrieved, "new")
    }

    func testDelete() {
        KeychainHelper.save(service: testService, account: "testKey", data: "val")
        let deleted = KeychainHelper.delete(service: testService, account: "testKey")
        XCTAssertTrue(deleted)
        XCTAssertNil(KeychainHelper.retrieve(service: testService, account: "testKey"))
    }
}

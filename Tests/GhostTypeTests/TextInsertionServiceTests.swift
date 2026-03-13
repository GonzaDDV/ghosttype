import XCTest
@testable import GhostType

final class TextInsertionServiceTests: XCTestCase {
    func testPrepareClipboardSetsText() {
        let service = TextInsertionService()
        let originalContent = NSPasteboard.general.string(forType: .string)

        service.prepareClipboard(with: "test text")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "test text")

        if let original = originalContent {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(original, forType: .string)
        }
    }

    func testGetFocusedAppBundleId() {
        let bundleId = TextInsertionService.focusedAppBundleId()
        XCTAssertNotNil(bundleId)
    }
}

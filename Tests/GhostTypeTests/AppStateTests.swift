import XCTest
@testable import GhostType

final class AppStateTests: XCTestCase {
    func testInitialStateIsIdle() {
        let state = AppState()
        XCTAssertEqual(state.current, .idle)
    }

    func testTransitionFromIdleToRecording() {
        let state = AppState()
        XCTAssertTrue(state.transition(to: .recording))
        XCTAssertEqual(state.current, .recording)
    }

    func testTransitionFromRecordingToProcessing() {
        let state = AppState()
        state.transition(to: .recording)
        XCTAssertTrue(state.transition(to: .processing))
        XCTAssertEqual(state.current, .processing)
    }

    func testTransitionFromProcessingToInserting() {
        let state = AppState()
        state.transition(to: .recording)
        state.transition(to: .processing)
        XCTAssertTrue(state.transition(to: .inserting))
        XCTAssertEqual(state.current, .inserting)
    }

    func testTransitionFromInsertingToIdle() {
        let state = AppState()
        state.transition(to: .recording)
        state.transition(to: .processing)
        state.transition(to: .inserting)
        XCTAssertTrue(state.transition(to: .idle))
        XCTAssertEqual(state.current, .idle)
    }

    func testInvalidTransitionFromIdleToProcessing() {
        let state = AppState()
        XCTAssertFalse(state.transition(to: .processing))
        XCTAssertEqual(state.current, .idle)
    }

    func testInvalidTransitionFromIdleToInserting() {
        let state = AppState()
        XCTAssertFalse(state.transition(to: .inserting))
        XCTAssertEqual(state.current, .idle)
    }

    func testTransitionFromRecordingToIdleCancels() {
        let state = AppState()
        state.transition(to: .recording)
        XCTAssertTrue(state.transition(to: .idle))
        XCTAssertEqual(state.current, .idle)
    }

    func testOnChangeCallbackFires() {
        let state = AppState()
        var received: AppState.State?
        state.onChange = { newState in received = newState }
        state.transition(to: .recording)
        XCTAssertEqual(received, .recording)
    }
}

import Foundation

class AppState {
    enum State: Equatable {
        case idle
        case recording
        case processing
        case inserting
    }

    private(set) var current: State = .idle
    var onChange: ((State) -> Void)?

    private let validTransitions: [State: Set<State>] = [
        .idle: [.recording],
        .recording: [.processing, .idle],
        .processing: [.inserting, .idle],
        .inserting: [.idle]
    ]

    @discardableResult
    func transition(to newState: State) -> Bool {
        guard let allowed = validTransitions[current], allowed.contains(newState) else {
            return false
        }
        current = newState
        onChange?(newState)
        return true
    }
}

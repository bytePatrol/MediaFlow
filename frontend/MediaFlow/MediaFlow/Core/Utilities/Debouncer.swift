import Foundation

actor Debouncer {
    private var task: Task<Void, Never>?
    private let duration: Duration

    init(duration: Duration = .milliseconds(300)) {
        self.duration = duration
    }

    func debounce(action: @escaping @Sendable () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}

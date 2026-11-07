import Synchronization

/// Thrown when an answer didn't come in time.
public struct TimedOutError: Error {}

/// `operation`'s result, or `TimedOutError` once `limit` has passed without one. It returns then
/// even if `operation` goes on: it's cancelled, but a request to the model on the device hasn't
/// always stopped when cancelled, which once left an inbox item reading for many minutes.
/// Cancelling the caller throws `CancellationError` at once in the same way.
func withTimeLimit<T: Sendable>(
    _ limit: Duration, _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let race = TimeLimitRace<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.start(continuation, limit: limit, operation: operation)
        }
    } onCancel: {
        race.finish(.failure(CancellationError()))
    }
}

/// The answer, the time limit, or cancellation: whichever comes first resumes the caller, once,
/// and cancels the others.
private final class TimeLimitRace<T: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<T, any Error>?
        /// How it ended, once it has, kept for a caller cancelled before it started.
        var result: Result<T, any Error>?
        var tasks: [Task<Void, Never>] = []
    }

    private let state = Mutex(State())

    func start(
        _ continuation: CheckedContinuation<T, any Error>, limit: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) {
        let earlier = state.withLock { state -> Result<T, any Error>? in
            if state.result == nil { state.continuation = continuation }
            return state.result
        }
        // Cancelled before it started.
        if let earlier {
            continuation.resume(with: earlier)
            return
        }
        let answer = Task {
            do {
                finish(.success(try await operation()))
            } catch {
                finish(.failure(error))
            }
        }
        let timer = Task {
            // Throws only when cancelled, once it's over.
            guard (try? await Task.sleep(for: limit)) != nil else { return }
            finish(.failure(TimedOutError()))
        }
        let isOver = state.withLock { state in
            if state.result == nil { state.tasks = [answer, timer] }
            return state.result != nil
        }
        if isOver {
            answer.cancel()
            timer.cancel()
        }
    }

    func finish(_ result: Result<T, any Error>) {
        let ended = state.withLock { state -> (CheckedContinuation<T, any Error>?, [Task<Void, Never>])? in
            guard state.result == nil else { return nil }
            state.result = result
            defer {
                state.continuation = nil
                state.tasks = []
            }
            return (state.continuation, state.tasks)
        }
        guard let (continuation, tasks) = ended else { return }
        for task in tasks { task.cancel() }
        continuation?.resume(with: result)
    }
}

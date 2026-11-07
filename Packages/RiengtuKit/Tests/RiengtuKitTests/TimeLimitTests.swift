import Dispatch
import Foundation
import Testing
@testable import RiengtuKit

/// The model's questions return in time even when a request never ends, so an inbox item can't
/// stay reading.
struct TimeLimitTests {
    @Test func answerInTime() async throws {
        let answer = try await withTimeLimit(.seconds(5)) { 42 }
        #expect(answer == 42)
    }

    @Test func errorInTime() async {
        struct Refused: Error {}
        await #expect(throws: Refused.self) {
            try await withTimeLimit(.seconds(5)) { () async throws -> Int in throw Refused() }
        }
    }

    @Test func timesOutThoughNotStoppedByCancelling() async {
        let start = ContinuousClock.now
        await #expect(throws: TimedOutError.self) {
            try await withTimeLimit(.milliseconds(100)) { await Self.ignoringCancellation(for: 3) }
        }
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func cancellingStopsWaiting() async {
        let start = ContinuousClock.now
        let task = Task {
            try await withTimeLimit(.seconds(10)) { await Self.ignoringCancellation(for: 3) }
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func cancelledBeforeStarting() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await withTimeLimit(.seconds(10)) { 42 }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// A question that times out stops reading, rather than being left to the rules as one the
    /// model can't answer.
    @Test func readerQuestionTimesOut() async {
        await #expect(throws: TimedOutError.self) {
            try await TransactionReader.unlessItCantNow(within: .milliseconds(100)) {
                await Self.ignoringCancellation(for: 3)
            }
        }
    }

    @Test func readerQuestionThatCantBeAnswered() async throws {
        struct Unsupported: Error {}
        let answer = try await TransactionReader.unlessItCantNow { () async throws -> String in throw Unsupported() }
        #expect(answer == nil)
    }

    /// Like a request that doesn't stop when it's cancelled.
    static func ignoringCancellation(for seconds: Int) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(seconds)) {
                continuation.resume(returning: "late")
            }
        }
    }
}

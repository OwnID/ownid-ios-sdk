import Testing

struct AsyncSignalRecorderTests {

    @Test func `Wait for first returns matching entry appended later`() async throws {
        let recorder = AsyncSignalRecorder<Int>()

        async let value = recorder.waitForFirst("matching entry") { $0 == 2 }

        recorder.append(1)
        recorder.append(2)

        #expect(try await value == 2)
    }

    @Test func `Wait for count returns existing matching entries`() async throws {
        let recorder = AsyncSignalRecorder<String>()

        recorder.append("keep")
        recorder.append("skip")
        recorder.append("keep")

        let entries = try await recorder.waitForCount(2, "existing matching entries") {
            $0 == "keep"
        }

        #expect(entries == ["keep", "keep"])
    }

    @Test func `Timed out wait is removed before later matching append`() async throws {
        let recorder = AsyncSignalRecorder<Int>()

        do {
            _ = try await recorder.waitForFirst("missing entry", seconds: 0) { $0 == 1 }
            Issue.record("Expected missing entry wait to time out")
        } catch TestTimeoutError.timedOut(let description) {
            #expect(description == "missing entry")
        } catch {
            Issue.record("Expected TestTimeoutError, got \(error)")
        }

        recorder.append(1)

        let value = try await recorder.waitForFirst("later matching entry", seconds: 1) { $0 == 1 }
        #expect(value == 1)
    }

    @Test func `Cancelled wait is removed before later matching append`() async throws {
        let recorder = AsyncSignalRecorder<Int>()
        let task = Task {
            try await recorder.waitForFirst("cancelled entry", seconds: 10) { $0 == 1 }
        }

        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancelled entry wait to throw CancellationError")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }

        recorder.append(1)

        let value = try await recorder.waitForFirst("later matching entry", seconds: 1) { $0 == 1 }
        #expect(value == 1)
    }

}

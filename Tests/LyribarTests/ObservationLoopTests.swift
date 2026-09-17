import Observation
import Testing

@testable import Lyribar

@MainActor
@Observable
private final class Model {
    var watched = 0
    var ignored = 0
}

/// Holds the re-subscription work so the tests do not depend on a task hop.
@MainActor
private final class ManualScheduler {
    private var pending: [@MainActor () -> Void] = []

    func enqueue(_ work: @escaping @MainActor () -> Void) {
        pending.append(work)
    }

    func run() {
        let work = pending
        pending = []
        for item in work { item() }
    }
}

@MainActor
private final class Recorder {
    var count = 0
    var values: [Int] = []
}

@MainActor
struct ObservationLoopTests {
    private func makeLoop(
        _ model: Model, _ scheduler: ManualScheduler, _ recorder: Recorder
    ) -> ObservationLoop {
        ObservationLoop(
            read: { _ = model.watched },
            onChange: {
                recorder.count += 1
                recorder.values.append(model.watched)
            },
            schedule: { work in scheduler.enqueue(work) })
    }

    // Observation notifies in willSet, so onChange must run after the mutation to see the new value.
    @Test func firesAfterTheChangeIsApplied() {
        let model = Model()
        let scheduler = ManualScheduler()
        let recorder = Recorder()
        let loop = makeLoop(model, scheduler, recorder)
        defer { loop.cancel() }

        model.watched = 1
        #expect(recorder.count == 0)
        scheduler.run()

        #expect(recorder.values == [1])
    }

    @Test func keepsFiringAfterResubscribing() {
        let model = Model()
        let scheduler = ManualScheduler()
        let recorder = Recorder()
        let loop = makeLoop(model, scheduler, recorder)
        defer { loop.cancel() }

        model.watched = 1
        scheduler.run()
        model.watched = 2
        scheduler.run()
        model.watched = 3
        scheduler.run()

        #expect(recorder.values == [1, 2, 3])
    }

    @Test func doesNotFireForValuesThatWereNotRead() {
        let model = Model()
        let scheduler = ManualScheduler()
        let recorder = Recorder()
        let loop = makeLoop(model, scheduler, recorder)
        defer { loop.cancel() }

        model.ignored = 1
        scheduler.run()

        #expect(recorder.count == 0)
    }

    @Test func cancelStopsTheLoop() {
        let model = Model()
        let scheduler = ManualScheduler()
        let recorder = Recorder()
        let loop = makeLoop(model, scheduler, recorder)

        model.watched = 1
        scheduler.run()
        loop.cancel()
        model.watched = 2
        scheduler.run()

        #expect(recorder.count == 1)
    }

    @Test func defaultScheduleRunsOnTheMainActor() async {
        let model = Model()
        let recorder = Recorder()
        let loop = ObservationLoop(
            read: { _ = model.watched },
            onChange: {
                recorder.count += 1
                recorder.values.append(model.watched)
            })
        defer { loop.cancel() }

        model.watched = 1
        // Time-based: the scheduled work is a task hop, and other suites can keep the main actor busy.
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline, recorder.count == 0 {
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(recorder.values == [1])
    }
}

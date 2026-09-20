import Observation

/// `withObservationTracking` reports only the first change, so this re-subscribes after each one.
///
/// Observation notifies in `willSet`, so both `onChange` and the re-subscription go through
/// `schedule` (by default a hop to the main actor) and see the new value. Changes made before the
/// scheduled work runs are not tracked, but `onChange` reads the state at the time it runs and the
/// re-subscription follows in the same turn, so they are folded into that one call.
@MainActor
final class ObservationLoop {
    typealias Schedule = @MainActor (@escaping @MainActor () -> Void) -> Void

    static let mainActorSchedule: Schedule = { work in
        Task { @MainActor in work() }
    }

    private let read: @MainActor () -> Void
    private let onChange: @MainActor () -> Void
    private let schedule: Schedule
    private var isCancelled = false

    init(
        read: @escaping @MainActor () -> Void,
        onChange: @escaping @MainActor () -> Void,
        schedule: @escaping Schedule = ObservationLoop.mainActorSchedule
    ) {
        self.read = read
        self.onChange = onChange
        self.schedule = schedule
        subscribe()
    }

    func cancel() {
        isCancelled = true
    }

    private func subscribe() {
        guard !isCancelled else { return }
        withObservationTracking(read) { [weak self] in
            // The observed values are only mutated on the main actor.
            MainActor.assumeIsolated {
                guard let self, !self.isCancelled else { return }
                self.schedule { [weak self] in
                    guard let self, !self.isCancelled else { return }
                    self.onChange()
                    self.subscribe()
                }
            }
        }
    }
}

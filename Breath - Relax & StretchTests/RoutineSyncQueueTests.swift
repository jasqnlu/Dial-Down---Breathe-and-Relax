import Testing
import Foundation
import SwiftData
@testable import BreathRelaxStretch

/// A newly created routine must be both saved locally AND queued for upload.
/// Two creation paths (mini-routine review, importing a shared routine) used
/// to insert without queueing, so those routines never left the device.
@MainActor
struct RoutineSyncQueueTests {

    private func makeContext() -> ModelContext {
        let container = try! ModelContainer(
            for: Routine.self, PendingSyncOp.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func insertingANewRoutineAlsoQueuesItForUpload() throws {
        let context = makeContext()
        let routine = Routine(name: "Office Stretches", exerciseIDs: [UUID()], ownerID: "user-1")

        routine.insertAndQueueForSync(in: context)

        let routines = try context.fetch(FetchDescriptor<Routine>())
        #expect(routines.map(\.uuid) == [routine.uuid])

        let ops = try context.fetch(FetchDescriptor<PendingSyncOp>())
        #expect(ops.count == 1)
        #expect(ops.first?.entityType == .routine)
        #expect(ops.first?.entityID == routine.uuid)
        #expect(ops.first?.opType == .upsert)
    }
}

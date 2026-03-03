import BackgroundTasks
import SwiftData

enum BackgroundTaskManager {
    static let taskIdentifier = "proportional.design.puddle-club.process"

    static func registerTasks(container: ModelContainer) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            handleProcessingTask(task as! BGProcessingTask, container: container)
        }
    }

    nonisolated static func scheduleNextRun() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BackgroundTaskManager] Could not schedule: \(error)")
        }
    }

    // MARK: - Private

    private static func handleProcessingTask(_ task: BGProcessingTask, container: ModelContainer) {
        scheduleNextRun()

        let pipelineState = PipelineState()
        let pipeline = ProcessingPipeline(container: container, state: pipelineState)

        let processingTask = Task {
            await pipeline.run()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            processingTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}

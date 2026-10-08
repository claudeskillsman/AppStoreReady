import BackgroundTasks

enum BackgroundWork {
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.acme.hardening.refresh", using: nil) { task in
            task.setTaskCompleted(success: true)
        }
    }
}

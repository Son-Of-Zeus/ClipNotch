import AppKit

@MainActor
final class PasteboardMonitor {
    private var timer: DispatchSourceTimer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var isSuspended = false
    private var observers: [NSObjectProtocol] = []
    private var hintedCheck: DispatchWorkItem?
    var onNewContent: (() -> Void)?

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now(),
            repeating: 1,
            leeway: .milliseconds(100)
        )
        timer.setEventHandler { [weak self] in
            self?.checkPasteboard()
        }
        timer.resume()
        self.timer = timer
        observeWorkspace()
    }

    func stop() {
        hintedCheck?.cancel()
        hintedCheck = nil
        if isSuspended {
            timer?.resume()
            isSuspended = false
        }
        timer?.cancel()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    func hintAtPossibleChange() {
        hintedCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            self?.checkPasteboard()
        }
        hintedCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075, execute: check)
    }

    func skipCurrentChange() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func checkPasteboard() {
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        onNewContent?()
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let suspendNames: [Notification.Name] = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ]
        let resumeNames: [Notification.Name] = [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ]
        for name in suspendNames {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend() }
            })
        }
        for name in resumeNames {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            })
        }
    }

    private func suspend() {
        guard !isSuspended, timer != nil else { return }
        timer?.suspend()
        isSuspended = true
    }

    private func resume() {
        guard isSuspended else { return }
        timer?.resume()
        isSuspended = false
        checkPasteboard()
    }
}

import SwiftUI
import AppKit

/// Presents routine reminders as our own floating panel instead of a system
/// notification, so the reminder stays on screen with a "Done" button until the
/// user acts — no dependence on the macOS Banner/Alert style setting.
///
/// Timers only run while the app is alive (it lives in the menu bar), which is
/// exactly when a reminder is actionable. Slots already past when the app starts
/// are skipped rather than replayed.
@MainActor
final class RoutineReminder: ObservableObject {
    static let shared = RoutineReminder()

    private weak var store: DataStore?
    private var timers: [Timer] = []
    private var panel: NSPanel?
    private var autoDismiss: DispatchWorkItem?

    func configure(store: DataStore) { self.store = store }

    // MARK: Scheduling

    /// Rebuild timers for today's remaining routine slots.
    func reschedule() {
        cancelTimers()
        guard let store, !store.isOnHoliday() else { return }
        let cal = Calendar.current
        let now = Date()
        for routine in store.routines where routine.remind {
            guard routine.runsOn(now) else { continue }
            for slot in routine.slots {
                guard let fire = cal.date(bySettingHour: slot.hour, minute: slot.minute,
                                          second: 0, of: now), fire > now else { continue }
                schedule(routine, after: fire.timeIntervalSince(now))
            }
        }
    }

    private func schedule(_ routine: Routine, after interval: TimeInterval) {
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.present(routine) }
        }
        timers.append(t)
    }

    private func cancelTimers() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
    }

    // MARK: Presenting

    /// Show the reminder for a routine, unless it's already been completed today.
    func present(_ routine: Routine) {
        guard let store, !store.isDone(routine, on: Date()) else { return }
        showPanel(routine)
    }

    /// Preview a routine's reminder immediately (from the Simulate button).
    func simulate(_ routine: Routine) { showPanel(routine) }

    private func snooze(_ routine: Routine, minutes: Int = 10) {
        schedule(routine, after: Double(minutes * 60))
    }

    private func showPanel(_ routine: Routine) {
        close()  // one reminder at a time

        let view = RoutineReminderView(
            routine: routine,
            onDone: { [weak self] in self?.store?.logCompletion(routine); self?.close() },
            onSnooze: { [weak self] in self?.close(); self?.snooze(routine) },
            onDismiss: { [weak self] in self?.close() }
        )
        let hosting = NSHostingController(rootView: view)
        hosting.view.layoutSubtreeIfNeeded()

        let win = NSPanel(contentRect: .zero,
                          styleMask: [.titled, .closable, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        win.title = "Stacktrace"
        win.isFloatingPanel = true
        win.level = .floating
        win.hidesOnDeactivate = false
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.contentViewController = hosting
        win.setContentSize(hosting.view.fittingSize)

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let size = win.frame.size
            win.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 20,
                                       y: vf.maxY - size.height - 20))
        }
        win.orderFrontRegardless()
        panel = win

        // Optional auto-dismiss after the routine's chosen delay.
        if let secs = routine.dismissAfter, secs > 0 {
            let work = DispatchWorkItem { [weak self] in self?.close() }
            autoDismiss = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(secs), execute: work)
        }
    }

    private func close() {
        autoDismiss?.cancel(); autoDismiss = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

/// The card shown inside the floating reminder panel.
private struct RoutineReminderView: View {
    let routine: Routine
    let onDone: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void

    @State private var remaining: Int

    init(routine: Routine, onDone: @escaping () -> Void,
         onSnooze: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.routine = routine
        self.onDone = onDone
        self.onSnooze = onSnooze
        self.onDismiss = onDismiss
        _remaining = State(initialValue: routine.dismissAfter ?? 0)
    }

    private var total: Int { routine.dismissAfter ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time to move").font(.headline)
                    Text(routine.name.isEmpty ? "Routine" : routine.name)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if total > 0 {
                HStack(spacing: 8) {
                    ProgressView(value: Double(remaining), total: Double(total))
                    Text("\(remaining)s")
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Button("Snooze 10m", action: onSnooze)
                Spacer()
                Button("Dismiss", action: onDismiss)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if remaining > 0 { remaining -= 1 }
        }
    }
}

import AppKit
import Combine

/// High-performance mouse shake detector using NSEvent global monitoring.
///
/// Algorithm:
/// - Monitors `mouseMoved` events globally via NSEvent
/// - Tracks X-axis direction reversals in a lightweight rolling window
/// - Triggers when 4+ rapid reversals occur within a 0.5-second window
/// - Enforces a 2-second cooldown to prevent multiple triggers
///
/// Efficiency:
/// - Uses `event.deltaX` directly (no position math)
/// - Pre-allocated circular buffer with automatic pruning
/// - Noise filter rejects micro-movements (`|deltaX| < 2.0`)
/// - Zero allocations in the hot path after initialization
final class ShakeDetector: ObservableObject {

    // MARK: - Configuration

    /// Minimum number of direction reversals to trigger a shake.
    private let reversalThreshold: Int = 4

    /// Time window (seconds) within which reversals must occur.
    private let timeWindow: TimeInterval = 0.5

    /// Cooldown period (seconds) after a successful trigger.
    private let cooldownDuration: TimeInterval = 2.0

    /// Minimum absolute deltaX to consider as intentional movement (noise filter).
    private let minimumDelta: CGFloat = 2.0

    /// Maximum number of entries in the rolling buffer.
    private let bufferCapacity: Int = 20

    // MARK: - State

    /// Rolling buffer of movement samples: (timestamp, deltaX sign as Int: -1 or +1)
    private var buffer: [(timestamp: TimeInterval, sign: Int)] = []

    /// Timestamp of the last successful shake trigger (for cooldown).
    private var lastTriggerTime: TimeInterval = 0

    /// Reference to the global event monitor (for cleanup).
    private var eventMonitor: Any?

    /// Callback invoked when a shake is detected. Passes the cursor's NSPoint.
    var onShakeDetected: ((NSPoint) -> Void)?

    /// Whether the detector is currently monitoring.
    @Published var isMonitoring: Bool = false

    /// Whether shake detection is enabled by the user.
    @Published var isEnabled: Bool = true

    init() {
        buffer.reserveCapacity(bufferCapacity)
    }

    // MARK: - Public API

    /// Starts the global mouse movement monitor.
    /// Requires Accessibility permission to be granted.
    func startMonitoring() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.processMouseEvent(event)
        }

        isMonitoring = true
    }

    /// Stops the global mouse movement monitor and cleans up.
    func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        buffer.removeAll(keepingCapacity: true)
        isMonitoring = false
    }

    // MARK: - Core Detection Logic (Hot Path)

    /// Processes each mouse movement event.
    /// This runs on EVERY mouse move — must be extremely lightweight.
    private func processMouseEvent(_ event: NSEvent) {
        guard isEnabled else { return }

        let deltaX = event.deltaX
        let now = ProcessInfo.processInfo.systemUptime

        // ── Noise filter: reject tiny movements instantly ──
        guard abs(deltaX) >= minimumDelta else { return }

        // ── Cooldown check: skip processing during cooldown ──
        guard (now - lastTriggerTime) >= cooldownDuration else { return }

        // ── Determine direction sign ──
        let sign = deltaX > 0 ? 1 : -1

        // ── Append to rolling buffer ──
        buffer.append((timestamp: now, sign: sign))

        // ── Prune old entries (outside the time window) ──
        let cutoff = now - timeWindow
        while let first = buffer.first, first.timestamp < cutoff {
            buffer.removeFirst()
        }

        // ── Cap buffer size as a safety net ──
        if buffer.count > bufferCapacity {
            buffer.removeFirst(buffer.count - bufferCapacity)
        }

        // ── Count direction reversals ──
        var reversals = 0
        for i in 1..<buffer.count {
            if buffer[i].sign != buffer[i - 1].sign {
                reversals += 1
            }
        }

        // ── Check threshold ──
        if reversals >= reversalThreshold {
            // SHAKE DETECTED
            lastTriggerTime = now
            buffer.removeAll(keepingCapacity: true)

            // Capture cursor location on the main thread context
            let cursorLocation = NSEvent.mouseLocation
            DispatchQueue.main.async { [weak self] in
                self?.onShakeDetected?(cursorLocation)
            }
        }
    }
}

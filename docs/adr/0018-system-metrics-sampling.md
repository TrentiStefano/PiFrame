# ADR 0018: System Metrics Sampling (Subscription-Gated, Local-Only, Non-Journaled)

- **Status:** Accepted
- **Confirmation Date:** 2026-11-05

## Context

Clients (desktop workspace and status monitors) require real-time visibility into machine resource utilization—specifically CPU, RAM, primary volume disk storage, and GPU engine utilization and VRAM—during agent operations.

However, continuous background sampling introduces undesirable resource consumption and battery drain on portable devices. Furthermore, telemetry and system monitoring data must never leak over remote tunnels to unauthorized or unprivileged devices, adhering to PiFrame's zero-remote-telemetry principle (ADR 0016).

## Decision

Implement a subscription-gated, local-only, non-journaled system metrics subsystem in `apps/agentd/src/metrics/`:

1. **Subscription-Gated Lifecycle:**
   - Resource sampling is strictly on-demand. When the subscriber count is zero, no timers exist, no OS or filesystem reads occur, and no child processes are active.
   - Sampling begins (1000ms unref'd interval) upon the first subscriber. On the last unsubscribe or connection disconnect, the interval is cleared and any child monitoring processes are terminated.
2. **Local-Only Access Control (C1 Default-Deny):**
   - Commands `system.metrics.subscribe` and `system.metrics.unsubscribe` are strictly restricted to local loopback connections. Remote tunnel connections are rejected with `REMOTE_FORBIDDEN` in both `view` and `control` modes.
3. **Non-Journaled Transient Delivery:**
   - The `system.metrics` event is delivered on `sessionId: '@daemon'` with `seq: 0` directly and exclusively to subscribed connections. It bypasses session journal ring buffers and disk persistence entirely.
4. **Per-Platform GPU Strategy:**
   - The GPU provider is lazily resolved on the first subscription and cached for the daemon's lifetime:
     - **Cross-Platform NVIDIA:** If `nvidia-smi -L` succeeds, a persistent `nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits -l 1` process is spawned. Multiple GPUs take maximum utilization and sum memory.
     - **Windows Fallback:** Persistent `typeperf "\GPU Engine(*)\Utilization Percentage" -si 1`. Instance names (`pid_.._luid_X_phys_N_eng_M_engtype_T`) are parsed from CSV headers, summed across PIDs per `(luid, phys, eng)`, and the maximum engine percentage is taken. At most one retry per subscription session is permitted to prevent retry storms if counters are inaccessible or localized.
     - **Linux Fallback:** Reads `/sys/class/drm/card*/device/gpu_busy_percent` and VRAM sysfs files on each tick without spawning processes.
     - **macOS Fallback:** Polled via `execFile('ioreg', ['-r', '-d', '1', '-w', '0', '-c', 'IOAccelerator'])` with an 800ms timeout and in-flight deduplication (skipping ticks if a prior poll is still running).
5. **Authentic Data & "n/d" Policy:**
   - Metrics are never fabricated. If a metric or GPU is unavailable or unsupported, `null` is returned (prompting the client to display "n/d"). Percentages are clamped to `0.0 - 100.0` and rounded to 1 decimal place.
6. **Child Process Execution Safety:**
   - All child processes use `shell: false`, static argument arrays, `windowsHide: true`, and zero client-supplied parameters. Stderr is suppressed and child lifecycles are tied to subscription state and daemon shutdown.

## Consequences

- Zero CPU and energy consumption when no client is observing metrics.
- Hardened security with no possibility of remote host metric surveillance.
- Predictable and bounded resource usage across all supported desktop platforms (Windows, Linux, macOS).

## Alternatives Rejected

- **WMI / PowerShell Polling on Windows:** Rejected due to excessive CPU overhead (10-25% CPU consumption simply to poll WMI counters every second).
- **Native C++ Addons (node-gyp):** Rejected due to compilation complexity, platform ABI drift, Node SEA bundling conflicts, and elevated crash risks in the daemon process.
- **`systeminformation` NPM Package:** Rejected due to massive dependency footprint, undesirable external tool invocations, shell invocation patterns, and bloated bundle size.
- **`powermetrics` with sudo on macOS:** Rejected because acquiring elevated / root privileges for metrics violates daemon least-privilege principles.

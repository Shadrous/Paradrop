<p align="center">
  <img src="assets/Paradrop.png" alt="Paradrop title card" width="100%">
</p>

# Paradrop

Paradrop is a one-command Windows shell app for gaming diagnostics, performance optimization, popular bug fixes, internet tuning, and hardware-aware tweaks.

It is built for IT technicians, VM testers, and power users who want a guided console tool instead of a scattered pile of registry snippets and half-remembered tuning guides.
It is called Paradrop because you can just boot it up on your client's PC through remote connection and apply these lazy fixes.

```powershell
irm https://raw.githubusercontent.com/Shadrous/Paradrop/main/paradrop.ps1 | iex
```

## Why Paradrop Exists

Windows gaming problems are rarely one thing. A machine can have a capture overlay fighting frametime, a stale shader cache after a driver update, an old "HPET tweak" still sitting in BCD, a network adapter exposing latency-hostile power settings, or a laptop power plan quietly pulling the handbrake.

Paradrop puts those fixes in one guided shell:

| Use case | What Paradrop does |
| --- | --- |
| Diagnostics | Writes a read-only hardware, power, network, GPU, registry, and pending-reboot report to `C:\ProgramData\Paradrop\Reports`. |
| Auto optimize | Detects hardware, asks about the target goal, then applies the safest relevant baseline with prompts for uncertain settings. |
| Gaming optimizations | Disables capture overhead, applies multimedia scheduler values, tunes AC power settings, and offers HAGS/MPO choices. |
| Popular bug fixes | Clears shader caches, runs DISM/SFC, resets network stack, resets Windows Update cache, fixes MPO symptoms, removes old timer overrides, and toggles fullscreen optimization per game. |
| Internet tuning | Restores modern TCP defaults, applies DNS profiles, probes MTU, and offers RSS, NIC power, and latency toggles only when the adapter exposes them. |
| Hardware-specific tuning | Detects CPU, GPU, RAM, disk, battery, and adapters before offering TRIM, SSD ReTrim, GPU cache cleanup, HAGS, memory compression, and power settings. |
| Rollback | Exports touched registry keys before edits and can import previous Paradrop backup sessions. |

## Safety Model

Paradrop changes settings that can be risky on the wrong machine, so it is intentionally interactive.

- It asks before uncertain or symptom-specific tweaks.
- It creates a backup session under `C:\ProgramData\Paradrop\Backups`.
- It exports registry keys before editing them.
- It can request a Windows restore point before write operations.
- It keeps risky network adapter toggles opt-in.
- It prints the command or registry path being changed.

You may want to test it in a VM for personal use as extensive testing is yet to be done.

## Menus

After launch, pick the job you want:

```text
1. Run diagnostics (read-only)
2. Auto-detect and optimize
3. Gaming optimization pack
4. Fix popular bugs
5. Optimize internet connection
6. Hardware-specific optimizer
7. Roll back registry backups
8. Open elevated Paradrop window
0. Exit
```

Paradrop asks questions when auto-detection cannot make a responsible choice. Examples:

- Enable, disable, or skip Hardware-Accelerated GPU Scheduling.
- Apply the MPO workaround only if flicker, black-screen, overlay, or frame pacing symptoms match.
- Disable Large Send Offload or Interrupt Moderation only if lower latency matters more than CPU/throughput.
- Disable adapter power management and Energy Efficient Ethernet only for the selected adapter.
- Disable fullscreen optimizations only for one chosen game executable.
- Apply high-performance AC power settings on laptops only after confirmation.
- Disable memory compression only as an A/B test on higher-RAM systems.

## What It Applies

Paradrop currently includes:

- Game DVR and background capture disablement.
- Game Mode auto-detection repair.
- Multimedia SystemProfile and Games task scheduling values.
- High Performance or Ultimate Performance activation where available.
- AC processor, core parking, PCIe, and USB selective suspend power settings.
- HAGS enable/disable choice.
- MPO disable/restore choice.
- Per-title fullscreen optimization disable/restore.
- Shader cache cleanup for DirectX, NVIDIA, and AMD cache folders.
- DISM and SFC repair flow.
- DNS, Winsock, and IP stack reset flow.
- Windows Update cache reset flow.
- Removal of forced `useplatformclock`, `disabledynamictick`, and `useplatformtick` BCD values.
- TCP autotuning/RSS baseline.
- DNS profiles for automatic, Cloudflare, Google, Quad9, or custom IPv4 DNS.
- Adapter advanced-property toggles for EEE/Green Ethernet, NIC power management, LSO, Interrupt Moderation, RSS, and RSC when exposed.
- IPv4 MTU probing and optional application.
- TRIM delete-notification enablement.
- SSD/NVMe ReTrim through Windows storage tooling.
- Memory compression enable/disable where available.
- Read-only reporting for Memory Integrity, Virtual Machine Platform, and BCD timer overrides.

## Requirements

- Windows PowerShell 5.1 or newer.

Diagnostics can run without elevation, but most changes require an elevated shell. Paradrop can open an elevated window from its menu.

## Advanced Launches

If you save the script locally, these switches are available:

```powershell
.\paradrop.ps1 -Diagnostics
.\paradrop.ps1 -Auto
.\paradrop.ps1 -DryRun
.\paradrop.ps1 -NoColor
```

## Rollback Notes

Registry rollback is available from menu option `7`. For non-registry changes, use the matching Windows default action where applicable:

- Re-enable MPO by choosing "Restore MPO default."
- Restore per-title fullscreen optimization by choosing "Restore fullscreen optimizations for one game."
- Restore balanced power plan with `powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e`.
- Re-enable adapter offloads in Device Manager or adapter advanced properties.
- Reset DNS to automatic in Paradrop's DNS menu.
- Reboot after BCD, network stack, HAGS, MPO, or memory-compression changes.

## License

MIT. See [LICENSE](LICENSE).

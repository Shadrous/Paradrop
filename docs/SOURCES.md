# Sources And References

Paradrop favors Microsoft-documented commands and conservative defaults where possible. Some symptom-specific graphics workarounds come from GPU vendor support material.

## Microsoft References

- Power configuration command-line options: https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options
- Netsh interface and TCP global configuration: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/netsh-interface
- Network adapter performance tuning concepts: https://learn.microsoft.com/en-us/windows-server/networking/technologies/network-subsystem/net-sub-performance-tuning-nics
- Enable-NetAdapterRss PowerShell cmdlet: https://learn.microsoft.com/en-us/powershell/module/netadapter/enable-netadapterrss
- Disable-NetAdapterPowerManagement PowerShell cmdlet: https://learn.microsoft.com/en-us/powershell/module/netadapter/disable-netadapterpowermanagement
- Set-NetAdapterAdvancedProperty PowerShell cmdlet: https://learn.microsoft.com/en-us/powershell/module/netadapter/set-netadapteradvancedproperty
- Clear-DnsClientCache PowerShell cmdlet: https://learn.microsoft.com/en-us/powershell/module/dnsclient/clear-dnsclientcache
- Reset TCP/IP with netsh: https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/reset-tcp-ip-net-shell
- Optimize-Volume PowerShell cmdlet: https://learn.microsoft.com/en-us/powershell/module/storage/optimize-volume
- fsutil behavior command: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/fsutil-behavior
- Disable-MMAgent PowerShell cmdlet: https://learn.microsoft.com/en-us/powershell/module/mmagent/disable-mmagent
- Enable-MMAgent PowerShell cmdlet: https://learn.microsoft.com/en-us/powershell/module/mmagent/enable-mmagent
- Fullscreen optimizations background: https://devblogs.microsoft.com/directx/demystifying-full-screen-optimizations/
- Optimizations for windowed games: https://support.microsoft.com/en-us/windows/optimizations-for-windowed-games-in-windows-11-3f006843-2c7e-4ed0-9a5e-f9389e535952
- Hardware-Accelerated GPU Scheduling: https://devblogs.microsoft.com/directx/hardware-accelerated-gpu-scheduling/
- Virtualization-based protection of code integrity: https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity
- BCDEdit /set command reference: https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--set

## Vendor And Practical References

- NVIDIA support article for Multi-Plane Overlay behavior and registry workaround: https://nvidia.custhelp.com/app/answers/detail/a_id/5157
- NVIDIA shader cache cleanup guidance: https://nvidia.custhelp.com/app/answers/detail/a_id/5735

## Implementation Notes

- TCP receive-window autotuning should generally be left at `normal` on modern Windows instead of applying old fixed-window registry recipes.
- ECN, adapter offloads, interrupt moderation, RSC, and MTU behavior can depend on routers, drivers, VPNs, and link type, so Paradrop keeps those paths guided.
- HAGS and MPO are driver/display/workload dependent, so Paradrop asks instead of silently picking a universal setting.

#requires -Version 5.1
<#
.SYNOPSIS
Starts Paradrop, an interactive Windows gaming diagnostics and optimization shell.

.DESCRIPTION
Paradrop is designed for the one-line PowerShell launch flow:
irm https://raw.githubusercontent.com/Shadrous/Paradrop/main/paradrop.ps1 | iex

The app favors guided choices, registry backups, and reversible defaults because
many useful gaming and networking tweaks are machine-specific.
#>
param(
    [switch]$Auto,
    [switch]$Diagnostics,
    [switch]$DryRun,
    [switch]$NoColor
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Script:Paradrop = @{
    Name          = 'Paradrop'
    Version       = '0.1.0'
    Repository    = 'https://github.com/Shadrous/Paradrop'
    RawUrl        = 'https://raw.githubusercontent.com/Shadrous/Paradrop/main/paradrop.ps1'
    BackupRoot    = Join-Path $env:ProgramData 'Paradrop\Backups'
    ReportRoot    = Join-Path $env:ProgramData 'Paradrop\Reports'
    SessionBackup = ''
    DryRun        = [bool]$DryRun
    NoColor       = [bool]$NoColor
}

function Write-ParadropLine {
    <#
    .SYNOPSIS
    Writes consistent console output for Paradrop screens and actions.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ConsoleColor]$Color = [ConsoleColor]::Gray,

        [switch]$NoNewline
    )

    # Centralize host rendering so color can be disabled for transcript-friendly sessions.
    if ($Script:Paradrop['NoColor']) {
        if ($NoNewline) {
            Write-Host $Message -NoNewline
            return
        }

        Write-Host $Message
        return
    }

    if ($NoNewline) {
        Write-Host $Message -ForegroundColor $Color -NoNewline
        return
    }

    Write-Host $Message -ForegroundColor $Color
}

function Write-ParadropHeading {
    <#
    .SYNOPSIS
    Renders compact section headings for the interactive shell.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )

    Write-ParadropLine ''
    Write-ParadropLine $Title ([ConsoleColor]::Cyan)
    Write-ParadropLine ('-' * [Math]::Min(72, [Math]::Max(10, $Title.Length))) ([ConsoleColor]::DarkCyan)
}

function Read-ParadropChoice {
    <#
    .SYNOPSIS
    Reads a constrained menu choice with an optional default.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        [string[]]$Allowed,

        [string]$Default = ''
    )

    # Normalize accepted values once so the prompt loop stays small and predictable.
    $allowedMap = @{}
    foreach ($item in $Allowed) {
        $allowedMap[$item.ToLowerInvariant()] = $item
    }

    while ($true) {
        $suffix = ''
        if (-not [string]::IsNullOrWhiteSpace($Default)) {
            $suffix = " [$Default]"
        }

        $raw = Read-Host "$Prompt$suffix"
        if ([string]::IsNullOrWhiteSpace($raw) -and -not [string]::IsNullOrWhiteSpace($Default)) {
            return $Default
        }

        $key = $raw.Trim().ToLowerInvariant()
        if ($allowedMap.ContainsKey($key)) {
            return $allowedMap[$key]
        }

        Write-ParadropLine "Pick one of: $($Allowed -join ', ')." ([ConsoleColor]::Yellow)
    }
}

function Confirm-ParadropAction {
    <#
    .SYNOPSIS
    Asks for explicit confirmation before a risky or machine-specific change.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [bool]$DefaultYes = $false
    )

    # Keep confirmations uniform so every risky path is easy to audit.
    $default = if ($DefaultYes) { 'Y' } else { 'N' }
    $choice = Read-ParadropChoice -Prompt "$Prompt (y/n)" -Allowed @('y', 'n') -Default $default
    return $choice.ToLowerInvariant() -eq 'y'
}

function Pause-Paradrop {
    <#
    .SYNOPSIS
    Pauses menu navigation without affecting piped launch behavior.
    #>
    Read-Host 'Press Enter to continue' | Out-Null
}

function Test-ParadropAdmin {
    <#
    .SYNOPSIS
    Returns true when the current shell has local administrator privileges.
    #>
    try {
        # WindowsPrincipal is the most reliable local privilege check across Windows PowerShell versions.
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Start-ParadropElevated {
    <#
    .SYNOPSIS
    Opens a new elevated PowerShell window using the public one-line launch command.
    #>
    # Relaunch through the raw URL because piped scripts do not have a stable local file path.
    $command = "Set-ExecutionPolicy -Scope Process Bypass -Force; irm '$($Script:Paradrop['RawUrl'])' | iex"
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoExit', '-Command', $command) -Verb RunAs
}

function Assert-ParadropAdmin {
    <#
    .SYNOPSIS
    Stops a write operation when the shell is not elevated.
    #>
    if (Test-ParadropAdmin) {
        return
    }

    Write-ParadropLine 'This action needs an elevated PowerShell session.' ([ConsoleColor]::Yellow)
    if (Confirm-ParadropAction -Prompt 'Open Paradrop as administrator now?' -DefaultYes $true) {
        Start-ParadropElevated
        exit
    }

    throw 'Administrator privileges are required for this action.'
}

function Initialize-ParadropStorage {
    <#
    .SYNOPSIS
    Creates the backup and report folders used by Paradrop runtime actions.
    #>
    # ProgramData is shared, stable, and appropriate for machine-level diagnostics and restore files.
    foreach ($path in @($Script:Paradrop['BackupRoot'], $Script:Paradrop['ReportRoot'])) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
}

function Get-ParadropBackupSession {
    <#
    .SYNOPSIS
    Returns the active backup folder, creating one per Paradrop run.
    #>
    Initialize-ParadropStorage

    # One folder per run keeps related registry exports and action notes together.
    if ([string]::IsNullOrWhiteSpace([string]$Script:Paradrop['SessionBackup'])) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $sessionPath = Join-Path $Script:Paradrop['BackupRoot'] "session-$stamp"
        New-Item -ItemType Directory -Path $sessionPath -Force | Out-Null
        $Script:Paradrop['SessionBackup'] = $sessionPath
    }

    return [string]$Script:Paradrop['SessionBackup']
}

function Add-ParadropActionLog {
    <#
    .SYNOPSIS
    Records an applied action inside the current backup session.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    # Runtime logs give technicians a quick path to understand and reverse a session.
    $sessionPath = Get-ParadropBackupSession
    $line = '{0} {1}' -f (Get-Date -Format 's'), $Message
    Add-Content -LiteralPath (Join-Path $sessionPath 'actions.log') -Value $line -Encoding UTF8
}

function ConvertTo-ParadropNativeRegistryPath {
    <#
    .SYNOPSIS
    Converts PowerShell registry provider paths to reg.exe hive paths.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # reg.exe is used for exports/imports, while Set-ItemProperty handles edits.
    if ($Path -match '^HKLM:\\(.+)$') {
        return "HKLM\$($Matches[1])"
    }

    if ($Path -match '^HKCU:\\(.+)$') {
        return "HKCU\$($Matches[1])"
    }

    throw "Unsupported registry hive path: $Path"
}

function Export-ParadropRegistryKey {
    <#
    .SYNOPSIS
    Exports a registry key before Paradrop edits values under it.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        return
    }

    # Use deterministic file names so repeated exports remain inspectable in a backup folder.
    $sessionPath = Get-ParadropBackupSession
    $safeName = ($Path -replace '[:\\\/\s]+', '_').Trim('_')
    $destination = Join-Path $sessionPath "$safeName.reg"
    $nativePath = ConvertTo-ParadropNativeRegistryPath -Path $Path

    if ($Script:Paradrop['DryRun']) {
        Write-ParadropLine "[dry-run] reg.exe export $nativePath $destination /y" ([ConsoleColor]::DarkYellow)
        return
    }

    & reg.exe export $nativePath $destination /y | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Add-ParadropActionLog "Exported registry key $nativePath to $destination"
    }
}

function Set-ParadropRegistryValue {
    <#
    .SYNOPSIS
    Sets a registry value after exporting its parent key for rollback.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('DWord', 'String', 'QWord')]
        [string]$Kind,

        [Parameter(Mandatory)]
        [object]$Value
    )

    Export-ParadropRegistryKey -Path $Path

    # Create missing keys explicitly so registry edits are idempotent on fresh systems.
    if ($Script:Paradrop['DryRun']) {
        Write-ParadropLine "[dry-run] set $Path::$Name = $Value ($Kind)" ([ConsoleColor]::DarkYellow)
        return
    }

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    New-ItemProperty -Path $Path -Name $Name -PropertyType $Kind -Value $Value -Force | Out-Null
    Add-ParadropActionLog "Set registry value $Path::$Name to $Value ($Kind)"
    Write-ParadropLine "Set $Path::$Name = $Value" ([ConsoleColor]::Green)
}

function Remove-ParadropRegistryValue {
    <#
    .SYNOPSIS
    Removes a registry value after exporting its parent key for rollback.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name
    )

    Export-ParadropRegistryKey -Path $Path

    if ($Script:Paradrop['DryRun']) {
        Write-ParadropLine "[dry-run] remove $Path::$Name" ([ConsoleColor]::DarkYellow)
        return
    }

    if (Test-Path -Path $Path) {
        Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        Add-ParadropActionLog "Removed registry value $Path::$Name"
        Write-ParadropLine "Removed $Path::$Name" ([ConsoleColor]::Green)
    }
}

function Get-ParadropRegistryValue {
    <#
    .SYNOPSIS
    Reads a registry value without throwing when it is not present.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name
    )

    try {
        # Silent absence keeps diagnostics readable on systems where a setting has never been touched.
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    }
    catch {
        return $null
    }
}

function Invoke-ParadropNative {
    <#
    .SYNOPSIS
    Runs a native Windows command with consistent logging and failure handling.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [string]$Label = '',

        [switch]$AllowFailure
    )

    # Native command calls are wrapped so menus can show exactly what is changing.
    $display = "$FilePath $($ArgumentList -join ' ')".Trim()
    if (-not [string]::IsNullOrWhiteSpace($Label)) {
        Write-ParadropLine $Label ([ConsoleColor]::White)
    }

    Write-ParadropLine "  $display" ([ConsoleColor]::DarkGray)
    Add-ParadropActionLog "Command: $display"

    if ($Script:Paradrop['DryRun']) {
        Write-ParadropLine '  dry-run: command skipped' ([ConsoleColor]::DarkYellow)
        return 0
    }

    & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "$display failed with exit code $exitCode"
    }

    if ($exitCode -ne 0) {
        Write-ParadropLine "  skipped or unsupported on this system (exit $exitCode)" ([ConsoleColor]::Yellow)
    }

    return $exitCode
}

function New-ParadropRestorePoint {
    <#
    .SYNOPSIS
    Requests a Windows restore point before broad optimization passes.
    #>
    Assert-ParadropAdmin

    # Restore points are best-effort because Windows may disable or rate-limit them.
    if ($Script:Paradrop['DryRun']) {
        Write-ParadropLine '[dry-run] Checkpoint-Computer -Description Paradrop' ([ConsoleColor]::DarkYellow)
        return
    }

    try {
        Checkpoint-Computer -Description "Paradrop $($Script:Paradrop['Version'])" -RestorePointType MODIFY_SETTINGS
        Add-ParadropActionLog 'Created Windows restore point'
        Write-ParadropLine 'Created a Windows restore point.' ([ConsoleColor]::Green)
    }
    catch {
        Add-ParadropActionLog "Restore point skipped: $($_.Exception.Message)"
        Write-ParadropLine "Restore point was skipped: $($_.Exception.Message)" ([ConsoleColor]::Yellow)
    }
}

function Start-ParadropChangeSession {
    <#
    .SYNOPSIS
    Prepares backups and optional restore point for a write operation.
    #>
    param(
        [string]$Reason = 'Paradrop changes'
    )

    Assert-ParadropAdmin
    Initialize-ParadropStorage
    $sessionPath = Get-ParadropBackupSession
    Write-ParadropLine "Backup session: $sessionPath" ([ConsoleColor]::DarkCyan)
    Add-ParadropActionLog "Session started for $Reason"

    if (Confirm-ParadropAction -Prompt 'Create a Windows restore point first?' -DefaultYes $true) {
        New-ParadropRestorePoint
    }
}

function Get-ParadropPowerScheme {
    <#
    .SYNOPSIS
    Returns the active power plan line and GUID when powercfg is available.
    #>
    try {
        # powercfg output is localized, so parse only the stable GUID shape.
        $raw = (& powercfg.exe /GETACTIVESCHEME 2>$null) -join ' '
        $guid = ''
        if ($raw -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            $guid = $Matches[1]
        }

        return [pscustomobject]@{
            Text = $raw
            Guid = $guid
        }
    }
    catch {
        return [pscustomobject]@{
            Text = 'Unavailable'
            Guid = ''
        }
    }
}

function Get-ParadropHardwareProfile {
    <#
    .SYNOPSIS
    Detects CPU, GPU, memory, storage, battery, and active network adapters.
    #>
    # Each probe is isolated so one broken WMI provider does not ruin the full profile.
    $cpu = $null
    $gpus = @()
    $ramBytes = 0
    $disks = @()
    $adapters = @()
    $battery = $false

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1 Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
    }
    catch {
        $cpu = $null
    }

    try {
        $gpus = @(Get-CimInstance -ClassName Win32_VideoController | Select-Object Name, DriverVersion, AdapterRAM)
    }
    catch {
        $gpus = @()
    }

    try {
        $ramBytes = [int64]((Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum)
    }
    catch {
        $ramBytes = 0
    }

    try {
        $disks = @(Get-CimInstance -ClassName Win32_DiskDrive | Select-Object Model, MediaType, InterfaceType, Size)
    }
    catch {
        $disks = @()
    }

    try {
        if (Get-Command -Name Get-NetAdapter -ErrorAction SilentlyContinue) {
            $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | Select-Object Name, InterfaceDescription, InterfaceIndex, LinkSpeed, Status, MacAddress)
        }
    }
    catch {
        $adapters = @()
    }

    try {
        $battery = [bool](Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue)
    }
    catch {
        $battery = $false
    }

    return [pscustomobject]@{
        Cpu             = $cpu
        Gpus            = $gpus
        RamGB           = if ($ramBytes -gt 0) { [Math]::Round($ramBytes / 1GB, 1) } else { 0 }
        Disks           = $disks
        ActiveAdapters  = $adapters
        HasBattery      = $battery
        IsAdministrator = Test-ParadropAdmin
    }
}

function Show-ParadropHardwareSummary {
    <#
    .SYNOPSIS
    Prints the detected hardware profile in a technician-friendly format.
    #>
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Profile
    )

    Write-ParadropHeading 'Detected Hardware'

    if ($null -ne $Profile.Cpu) {
        Write-ParadropLine "CPU: $($Profile.Cpu.Name) ($($Profile.Cpu.NumberOfCores)c/$($Profile.Cpu.NumberOfLogicalProcessors)t)" ([ConsoleColor]::White)
    }

    Write-ParadropLine "RAM: $($Profile.RamGB) GB" ([ConsoleColor]::White)
    Write-ParadropLine "Battery detected: $($Profile.HasBattery)" ([ConsoleColor]::White)

    if ($Profile.Gpus.Count -gt 0) {
        foreach ($gpu in $Profile.Gpus) {
            Write-ParadropLine "GPU: $($gpu.Name) driver $($gpu.DriverVersion)" ([ConsoleColor]::White)
        }
    }

    if ($Profile.ActiveAdapters.Count -gt 0) {
        foreach ($adapter in $Profile.ActiveAdapters) {
            Write-ParadropLine "Network: $($adapter.Name) - $($adapter.InterfaceDescription) - $($adapter.LinkSpeed)" ([ConsoleColor]::White)
        }
    }

    if ($Profile.Disks.Count -gt 0) {
        foreach ($disk in $Profile.Disks) {
            $size = if ($disk.Size) { '{0:n1} GB' -f ($disk.Size / 1GB) } else { 'unknown size' }
            Write-ParadropLine "Disk: $($disk.Model) - $($disk.MediaType) - $size" ([ConsoleColor]::White)
        }
    }
}

function Invoke-ParadropDiagnostics {
    <#
    .SYNOPSIS
    Collects a read-only diagnostics report for gaming, network, and hardware state.
    #>
    Initialize-ParadropStorage
    Write-ParadropHeading 'Diagnostics'

    # The report captures raw values so technicians can compare before and after VM testing.
    $profile = Get-ParadropHardwareProfile
    $power = Get-ParadropPowerScheme
    $tcpGlobal = ''
    $trimState = ''
    $pendingReboot = $false

    try {
        $tcpGlobal = (& netsh.exe int tcp show global 2>$null) -join [Environment]::NewLine
    }
    catch {
        $tcpGlobal = 'Unavailable'
    }

    try {
        $trimState = (& fsutil.exe behavior query DisableDeleteNotify 2>$null) -join [Environment]::NewLine
    }
    catch {
        $trimState = 'Unavailable'
    }

    $pendingRebootKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    )

    foreach ($key in $pendingRebootKeys) {
        if ($key -like '*Session Manager') {
            $pendingRename = Get-ParadropRegistryValue -Path $key -Name 'PendingFileRenameOperations'
            if ($null -ne $pendingRename) {
                $pendingReboot = $true
            }
            continue
        }

        if (Test-Path -Path $key) {
            $pendingReboot = $true
        }
    }

    $securityState = Get-ParadropSecurityGamingState
    $bcdTimerState = Get-ParadropBcdTimerState

    $report = [ordered]@{
        GeneratedAt              = (Get-Date).ToString('s')
        ParadropVersion          = $Script:Paradrop['Version']
        IsAdministrator          = Test-ParadropAdmin
        PowerPlan                = $power
        Hardware                 = $profile
        TcpGlobal                = $tcpGlobal
        TrimState                = $trimState
        PendingReboot            = $pendingReboot
        GameDvrEnabled           = Get-ParadropRegistryValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled'
        AppCaptureEnabled        = Get-ParadropRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled'
        AutoGameModeEnabled      = Get-ParadropRegistryValue -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled'
        HagsMode                 = Get-ParadropRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode'
        MpoOverlayTestMode       = Get-ParadropRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' -Name 'OverlayTestMode'
        NetworkThrottlingIndex   = Get-ParadropRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex'
        SystemResponsiveness     = Get-ParadropRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness'
        SecurityGamingState      = $securityState
        BcdTimerState            = $bcdTimerState
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $reportPath = Join-Path $Script:Paradrop['ReportRoot'] "diagnostics-$stamp.json"
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

    Show-ParadropHardwareSummary -Profile $profile
    Write-ParadropHeading 'Read-Only Checks'
    Write-ParadropLine "Active power plan: $($power.Text)" ([ConsoleColor]::White)
    Write-ParadropLine "Pending reboot: $pendingReboot" ([ConsoleColor]::White)
    Write-ParadropLine "Game DVR enabled value: $($report.GameDvrEnabled)" ([ConsoleColor]::White)
    Write-ParadropLine "App capture enabled value: $($report.AppCaptureEnabled)" ([ConsoleColor]::White)
    Write-ParadropLine "Game Mode auto value: $($report.AutoGameModeEnabled)" ([ConsoleColor]::White)
    Write-ParadropLine "HAGS mode value: $($report.HagsMode)" ([ConsoleColor]::White)
    Write-ParadropLine "MPO override value: $($report.MpoOverlayTestMode)" ([ConsoleColor]::White)
    Write-ParadropLine "Memory Integrity value: $($securityState.MemoryIntegrityEnabled)" ([ConsoleColor]::White)
    Write-ParadropLine "Virtual Machine Platform: $($securityState.VirtualMachinePlatform)" ([ConsoleColor]::White)
    Write-ParadropLine "BCD timer overrides: $($bcdTimerState.Overrides -join ', ')" ([ConsoleColor]::White)
    Write-ParadropLine "Report saved: $reportPath" ([ConsoleColor]::Green)
}

function Get-ParadropSecurityGamingState {
    <#
    .SYNOPSIS
    Reports security features that can affect gaming performance without changing them.
    #>
    # These settings trade security for performance, so Paradrop reports them instead of toggling them.
    $memoryIntegrity = Get-ParadropRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled'
    $vmpState = 'Unavailable'

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction Stop
        $vmpState = $feature.State
    }
    catch {
        $vmpState = 'Unavailable'
    }

    return [pscustomobject]@{
        MemoryIntegrityEnabled = $memoryIntegrity
        VirtualMachinePlatform = $vmpState
    }
}

function Get-ParadropBcdTimerState {
    <#
    .SYNOPSIS
    Reports explicit BCD timer overrides associated with old tuning guides.
    #>
    $raw = ''
    $overrides = New-Object System.Collections.Generic.List[string]

    try {
        # bcdedit output is localized, so search only for stable option names.
        $raw = (& bcdedit.exe /enum '{current}' 2>$null) -join [Environment]::NewLine
        foreach ($name in @('useplatformclock', 'useplatformtick', 'disabledynamictick', 'tscsyncpolicy')) {
            if ($raw -match [regex]::Escape($name)) {
                $overrides.Add($name)
            }
        }
    }
    catch {
        $raw = 'Unavailable'
    }

    if ($overrides.Count -eq 0) {
        $overrides.Add('none detected')
    }

    return [pscustomobject]@{
        Overrides = @($overrides)
        Raw       = $raw
    }
}

function Disable-ParadropGameCapture {
    <#
    .SYNOPSIS
    Disables Game DVR and background capture registry switches.
    #>
    Assert-ParadropAdmin

    # Captures can add frametime variance; this keeps Game Mode itself untouched.
    Set-ParadropRegistryValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Kind DWord -Value 0
    Set-ParadropRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Kind DWord -Value 0
    Set-ParadropRegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Kind DWord -Value 0
}

function Enable-ParadropGameMode {
    <#
    .SYNOPSIS
    Enables Windows Game Mode auto detection for game sessions.
    #>
    Assert-ParadropAdmin

    # Game Mode is low-risk and complements capture disablement by keeping Windows game-aware.
    Set-ParadropRegistryValue -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Kind DWord -Value 1
}

function Set-ParadropMultimediaGamingProfile {
    <#
    .SYNOPSIS
    Applies Windows multimedia scheduler values commonly used for games.
    #>
    Assert-ParadropAdmin

    # These scheduler values bias MMCSS toward game foreground responsiveness.
    $profileKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    $gamesKey = Join-Path $profileKey 'Tasks\Games'
    Set-ParadropRegistryValue -Path $profileKey -Name 'NetworkThrottlingIndex' -Kind DWord -Value ([UInt32]::MaxValue)
    Set-ParadropRegistryValue -Path $profileKey -Name 'SystemResponsiveness' -Kind DWord -Value 0
    Set-ParadropRegistryValue -Path $gamesKey -Name 'GPU Priority' -Kind DWord -Value 8
    Set-ParadropRegistryValue -Path $gamesKey -Name 'Priority' -Kind DWord -Value 6
    Set-ParadropRegistryValue -Path $gamesKey -Name 'Scheduling Category' -Kind String -Value 'High'
    Set-ParadropRegistryValue -Path $gamesKey -Name 'SFIO Priority' -Kind String -Value 'High'
}

function Set-ParadropPowerLatencyProfile {
    <#
    .SYNOPSIS
    Activates a high-performance power profile and latency-oriented AC settings.
    #>
    Assert-ParadropAdmin

    # Ultimate Performance may not exist on every SKU, so duplicate it when possible and fall back safely.
    $ultimateSeed = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    $highPerformance = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    $targetScheme = $highPerformance

    if (-not $Script:Paradrop['DryRun']) {
        $created = (& powercfg.exe -duplicatescheme $ultimateSeed 2>$null) -join ' '
        if ($created -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            $targetScheme = $Matches[1]
        }
    }

    Invoke-ParadropNative -FilePath 'powercfg.exe' -ArgumentList @('/setactive', $targetScheme) -Label 'Activating performance power plan' -AllowFailure

    $settings = @(
        @{ Sub = 'SUB_PROCESSOR'; Setting = 'PROCTHROTTLEMIN'; Value = '100'; Label = 'Processor minimum state on AC' },
        @{ Sub = 'SUB_PROCESSOR'; Setting = 'PROCTHROTTLEMAX'; Value = '100'; Label = 'Processor maximum state on AC' },
        @{ Sub = 'SUB_PROCESSOR'; Setting = 'CPMINCORES'; Value = '100'; Label = 'Minimum unparked cores on AC' },
        @{ Sub = 'SUB_PROCESSOR'; Setting = 'CPMAXCORES'; Value = '100'; Label = 'Maximum unparked cores on AC' },
        @{ Sub = 'SUB_PROCESSOR'; Setting = 'PERFBOOSTMODE'; Value = '2'; Label = 'Processor boost mode on AC' },
        @{ Sub = 'SUB_PCIEXPRESS'; Setting = 'ASPM'; Value = '0'; Label = 'PCIe link state power management off on AC' },
        @{ Sub = 'SUB_USB'; Setting = 'USBSELECTIVE'; Value = '0'; Label = 'USB selective suspend off on AC' }
    )

    foreach ($setting in $settings) {
        Invoke-ParadropNative -FilePath 'powercfg.exe' -ArgumentList @('/setacvalueindex', 'SCHEME_CURRENT', $setting.Sub, $setting.Setting, $setting.Value) -Label $setting.Label -AllowFailure
    }

    $active = Get-ParadropPowerScheme
    if (-not [string]::IsNullOrWhiteSpace($active.Guid)) {
        Invoke-ParadropNative -FilePath 'powercfg.exe' -ArgumentList @('/setactive', $active.Guid) -Label 'Reapplying active power plan' -AllowFailure
    }
}

function Set-ParadropPerTitleFullscreenOptimization {
    <#
    .SYNOPSIS
    Disables fullscreen optimizations for one executable path.
    #>
    Assert-ParadropAdmin

    # Fullscreen optimization bugs are per-title, so this asks for one executable instead of applying a global myth.
    $rawPath = Read-Host 'Full path to the game .exe'
    if ([string]::IsNullOrWhiteSpace($rawPath)) {
        Write-ParadropLine 'No executable path entered.' ([ConsoleColor]::Yellow)
        return
    }

    $exePath = $rawPath.Trim('" ')
    if (-not (Test-Path -LiteralPath $exePath)) {
        if (-not (Confirm-ParadropAction -Prompt 'That path does not currently exist. Add the compatibility flag anyway?' -DefaultYes $false)) {
            return
        }
    }

    Set-ParadropRegistryValue -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -Name $exePath -Kind String -Value '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
    Write-ParadropLine 'Restart the game for the fullscreen optimization flag to apply.' ([ConsoleColor]::Yellow)
}

function Remove-ParadropPerTitleFullscreenOptimization {
    <#
    .SYNOPSIS
    Removes Paradrop's fullscreen optimization compatibility flag for one executable path.
    #>
    Assert-ParadropAdmin

    # The rollback path mirrors the per-title write and leaves unrelated compatibility flags alone.
    $rawPath = Read-Host 'Full path to the game .exe'
    if ([string]::IsNullOrWhiteSpace($rawPath)) {
        Write-ParadropLine 'No executable path entered.' ([ConsoleColor]::Yellow)
        return
    }

    $exePath = $rawPath.Trim('" ')
    Remove-ParadropRegistryValue -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -Name $exePath
}

function Set-ParadropGpuScheduling {
    <#
    .SYNOPSIS
    Enables or disables hardware-accelerated GPU scheduling.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Enable', 'Disable')]
        [string]$Mode
    )

    Assert-ParadropAdmin

    # HAGS is workload and driver dependent, so Paradrop changes it only after a direct user choice.
    $value = if ($Mode -eq 'Enable') { 2 } else { 1 }
    Set-ParadropRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Kind DWord -Value $value
    Write-ParadropLine 'Restart Windows for the HAGS change to apply.' ([ConsoleColor]::Yellow)
}

function Disable-ParadropMpo {
    <#
    .SYNOPSIS
    Disables Windows Multi-Plane Overlay through the documented registry override.
    #>
    Assert-ParadropAdmin

    # MPO can cause flicker or overlay stutter on some GPU/driver/display combinations.
    Set-ParadropRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' -Name 'OverlayTestMode' -Kind DWord -Value 5
    Write-ParadropLine 'Restart Windows for the MPO override to apply.' ([ConsoleColor]::Yellow)
}

function Restore-ParadropMpo {
    <#
    .SYNOPSIS
    Removes Paradrop's Multi-Plane Overlay override.
    #>
    Assert-ParadropAdmin

    Remove-ParadropRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' -Name 'OverlayTestMode'
    Write-ParadropLine 'Restart Windows for the MPO restore to apply.' ([ConsoleColor]::Yellow)
}

function Clear-ParadropDirectoryContents {
    <#
    .SYNOPSIS
    Clears known cache folders after validating they live under approved roots.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    # Guard recursive deletion to explicit cache locations under local app data or program data.
    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $allowedRoots = @($env:LOCALAPPDATA, $env:ProgramData) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $isAllowed = $false
    foreach ($root in $allowedRoots) {
        $resolvedRoot = (Resolve-Path -LiteralPath $root).Path
        if ($resolvedPath.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $isAllowed = $true
            break
        }
    }

    if (-not $isAllowed) {
        Write-ParadropLine "Skipped unsafe cache path: $resolvedPath" ([ConsoleColor]::Yellow)
        return
    }

    if ($Script:Paradrop['DryRun']) {
        Write-ParadropLine "[dry-run] clear contents of $resolvedPath" ([ConsoleColor]::DarkYellow)
        return
    }

    Get-ChildItem -LiteralPath $resolvedPath -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Add-ParadropActionLog "Cleared cache folder $resolvedPath"
    Write-ParadropLine "Cleared $resolvedPath" ([ConsoleColor]::Green)
}

function Clear-ParadropShaderCaches {
    <#
    .SYNOPSIS
    Clears common DirectX, NVIDIA, and AMD shader cache folders.
    #>
    Assert-ParadropAdmin

    # Shader cache cleanup is useful after driver updates or persistent stutter in specific games.
    $cachePaths = @(
        (Join-Path $env:LOCALAPPDATA 'D3DSCache'),
        (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache'),
        (Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache'),
        (Join-Path $env:LOCALAPPDATA 'NVIDIA Corporation\NV_Cache'),
        (Join-Path $env:LOCALAPPDATA 'AMD\DxCache'),
        (Join-Path $env:LOCALAPPDATA 'AMD\GLCache'),
        (Join-Path $env:ProgramData 'NVIDIA Corporation\NV_Cache')
    )

    foreach ($path in $cachePaths) {
        Clear-ParadropDirectoryContents -Path $path
    }
}

function Repair-ParadropWindowsImage {
    <#
    .SYNOPSIS
    Runs DISM and SFC repair commands for corrupted Windows components.
    #>
    Assert-ParadropAdmin

    # Component repair fixes many launcher, Store, overlay, driver, and update symptoms.
    Invoke-ParadropNative -FilePath 'DISM.exe' -ArgumentList @('/Online', '/Cleanup-Image', '/RestoreHealth') -Label 'Repairing Windows component store'
    Invoke-ParadropNative -FilePath 'sfc.exe' -ArgumentList @('/scannow') -Label 'Scanning protected system files'
}

function Reset-ParadropNetworkStack {
    <#
    .SYNOPSIS
    Resets DNS, Winsock, and IP stack state for stubborn connectivity bugs.
    #>
    Assert-ParadropAdmin

    # This is intentionally separated from optimization because it usually requires a reboot.
    Invoke-ParadropNative -FilePath 'ipconfig.exe' -ArgumentList @('/flushdns') -Label 'Flushing DNS resolver cache'
    Invoke-ParadropNative -FilePath 'netsh.exe' -ArgumentList @('winsock', 'reset') -Label 'Resetting Winsock'
    Invoke-ParadropNative -FilePath 'netsh.exe' -ArgumentList @('int', 'ip', 'reset') -Label 'Resetting IP stack'
    Write-ParadropLine 'Restart Windows after the network stack reset.' ([ConsoleColor]::Yellow)
}

function Reset-ParadropWindowsUpdateCache {
    <#
    .SYNOPSIS
    Resets Windows Update download and catalog cache folders.
    #>
    Assert-ParadropAdmin

    # Known Windows cache paths are renamed rather than deleted to preserve manual recovery.
    $services = @('bits', 'wuauserv', 'cryptsvc', 'msiserver')
    foreach ($service in $services) {
        Invoke-ParadropNative -FilePath 'net.exe' -ArgumentList @('stop', $service) -Label "Stopping $service" -AllowFailure
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $targets = @(
        @{ Path = Join-Path $env:SystemRoot 'SoftwareDistribution'; Backup = "SoftwareDistribution.paradrop-$stamp" },
        @{ Path = Join-Path $env:SystemRoot 'System32\catroot2'; Backup = "catroot2.paradrop-$stamp" }
    )

    foreach ($target in $targets) {
        if (-not (Test-Path -LiteralPath $target.Path)) {
            continue
        }

        $resolved = (Resolve-Path -LiteralPath $target.Path).Path
        $systemRoot = (Resolve-Path -LiteralPath $env:SystemRoot).Path
        if (-not $resolved.StartsWith($systemRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Write-ParadropLine "Skipped unexpected Windows cache path: $resolved" ([ConsoleColor]::Yellow)
            continue
        }

        if ($Script:Paradrop['DryRun']) {
            Write-ParadropLine "[dry-run] rename $resolved to $($target.Backup)" ([ConsoleColor]::DarkYellow)
            continue
        }

        Rename-Item -LiteralPath $resolved -NewName $target.Backup -ErrorAction SilentlyContinue
        Add-ParadropActionLog "Renamed $resolved to $($target.Backup)"
        Write-ParadropLine "Renamed $resolved to $($target.Backup)" ([ConsoleColor]::Green)
    }

    foreach ($service in $services) {
        Invoke-ParadropNative -FilePath 'net.exe' -ArgumentList @('start', $service) -Label "Starting $service" -AllowFailure
    }
}

function Remove-ParadropForcedPlatformClock {
    <#
    .SYNOPSIS
    Removes forced BCD timer flags that often come from outdated tuning guides.
    #>
    Assert-ParadropAdmin

    # Paradrop does not force HPET states; it only removes explicit overrides when the user chooses.
    Invoke-ParadropNative -FilePath 'bcdedit.exe' -ArgumentList @('/deletevalue', 'useplatformclock') -Label 'Removing forced platform clock override' -AllowFailure
    Invoke-ParadropNative -FilePath 'bcdedit.exe' -ArgumentList @('/deletevalue', 'disabledynamictick') -Label 'Removing disabled dynamic tick override' -AllowFailure
    Invoke-ParadropNative -FilePath 'bcdedit.exe' -ArgumentList @('/deletevalue', 'useplatformtick') -Label 'Removing forced platform tick override' -AllowFailure
    Write-ParadropLine 'Restart Windows for BCD timer changes to apply.' ([ConsoleColor]::Yellow)
}

function Set-ParadropTcpGamingDefaults {
    <#
    .SYNOPSIS
    Restores modern TCP defaults that are usually best for gaming and downloads.
    #>
    Assert-ParadropAdmin

    # Normal autotuning and RSS are generally better than old fixed-window tuning recipes.
    Invoke-ParadropNative -FilePath 'netsh.exe' -ArgumentList @('int', 'tcp', 'set', 'global', 'rss=enabled', 'autotuninglevel=normal', 'ecncapability=disabled', 'timestamps=disabled') -Label 'Setting TCP global defaults' -AllowFailure
}

function Enable-ParadropAdapterRss {
    <#
    .SYNOPSIS
    Enables receive-side scaling on a capable selected adapter.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Adapter
    )

    Assert-ParadropAdmin

    # RSS helps capable multi-core systems without guessing at queue counts or CPU affinity.
    if (-not (Get-Command -Name Enable-NetAdapterRss -ErrorAction SilentlyContinue)) {
        Write-ParadropLine 'RSS cmdlets are not available on this system.' ([ConsoleColor]::Yellow)
        return
    }

    if ($Script:Paradrop['DryRun']) {
        Write-ParadropLine "[dry-run] Enable-NetAdapterRss -Name $($Adapter.Name)" ([ConsoleColor]::DarkYellow)
        return
    }

    try {
        Enable-NetAdapterRss -Name $Adapter.Name -ErrorAction Stop
        Add-ParadropActionLog "Enabled RSS on adapter $($Adapter.Name)"
        Write-ParadropLine "Enabled RSS on $($Adapter.Name)" ([ConsoleColor]::Green)
    }
    catch {
        Write-ParadropLine "Could not enable RSS: $($_.Exception.Message)" ([ConsoleColor]::Yellow)
    }
}

function Disable-ParadropAdapterPowerManagement {
    <#
    .SYNOPSIS
    Disables exposed NIC power-management features for a selected adapter.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Adapter
    )

    Assert-ParadropAdmin

    # Adapter sleep features can cause spikes or disconnects, but the setting is adapter-specific.
    if (-not (Get-Command -Name Disable-NetAdapterPowerManagement -ErrorAction SilentlyContinue)) {
        Write-ParadropLine 'Adapter power-management cmdlets are not available on this system.' ([ConsoleColor]::Yellow)
        return
    }

    if ($Script:Paradrop['DryRun']) {
        Write-ParadropLine "[dry-run] Disable-NetAdapterPowerManagement -Name $($Adapter.Name)" ([ConsoleColor]::DarkYellow)
        return
    }

    try {
        Disable-NetAdapterPowerManagement -Name $Adapter.Name -ErrorAction Stop
        Add-ParadropActionLog "Disabled power management on adapter $($Adapter.Name)"
        Write-ParadropLine "Disabled adapter power management on $($Adapter.Name)" ([ConsoleColor]::Green)
    }
    catch {
        Write-ParadropLine "Could not disable adapter power management: $($_.Exception.Message)" ([ConsoleColor]::Yellow)
    }
}

function Get-ParadropActiveNetAdapters {
    <#
    .SYNOPSIS
    Returns active physical network adapters suitable for tuning.
    #>
    if (-not (Get-Command -Name Get-NetAdapter -ErrorAction SilentlyContinue)) {
        return @()
    }

    # Only active physical adapters are listed to avoid changing VPNs and virtual switches accidentally.
    return @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | Sort-Object -Property Name)
}

function Select-ParadropNetAdapter {
    <#
    .SYNOPSIS
    Prompts the user to choose one active physical network adapter.
    #>
    $adapters = Get-ParadropActiveNetAdapters
    if ($adapters.Count -eq 0) {
        throw 'No active physical network adapters were detected.'
    }

    Write-ParadropHeading 'Network Adapters'
    for ($index = 0; $index -lt $adapters.Count; $index++) {
        $adapter = $adapters[$index]
        Write-ParadropLine "$($index + 1). $($adapter.Name) - $($adapter.InterfaceDescription) - $($adapter.LinkSpeed)" ([ConsoleColor]::White)
    }

    $allowed = for ($index = 1; $index -le $adapters.Count; $index++) { [string]$index }
    $choice = Read-ParadropChoice -Prompt 'Adapter' -Allowed $allowed -Default '1'
    return $adapters[[int]$choice - 1]
}

function Set-ParadropDnsProfile {
    <#
    .SYNOPSIS
    Applies a DNS profile to the selected adapter or restores automatic DNS.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Adapter
    )

    Assert-ParadropAdmin

    Write-ParadropHeading 'DNS Profile'
    Write-ParadropLine '1. Automatic from router/ISP'
    Write-ParadropLine '2. Cloudflare - 1.1.1.1 / 1.0.0.1'
    Write-ParadropLine '3. Google - 8.8.8.8 / 8.8.4.4'
    Write-ParadropLine '4. Quad9 - 9.9.9.9 / 149.112.112.112'
    Write-ParadropLine '5. Custom IPv4 servers'
    $choice = Read-ParadropChoice -Prompt 'DNS option' -Allowed @('1', '2', '3', '4', '5') -Default '2'

    # DNS is adapter-scoped and reversible through ResetServerAddresses.
    $servers = @()
    switch ($choice) {
        '1' { $servers = @() }
        '2' { $servers = @('1.1.1.1', '1.0.0.1') }
        '3' { $servers = @('8.8.8.8', '8.8.4.4') }
        '4' { $servers = @('9.9.9.9', '149.112.112.112') }
        '5' {
            $raw = Read-Host 'Enter comma-separated IPv4 DNS servers'
            $servers = @($raw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    }

    if ($Script:Paradrop['DryRun']) {
        Write-ParadropLine "[dry-run] set DNS on $($Adapter.Name): $($servers -join ', ')" ([ConsoleColor]::DarkYellow)
        return
    }

    if ($servers.Count -eq 0) {
        Set-DnsClientServerAddress -InterfaceIndex $Adapter.InterfaceIndex -ResetServerAddresses
        Add-ParadropActionLog "Reset DNS servers on adapter $($Adapter.Name)"
        Write-ParadropLine "Reset DNS servers on $($Adapter.Name)" ([ConsoleColor]::Green)
    }
    else {
        Set-DnsClientServerAddress -InterfaceIndex $Adapter.InterfaceIndex -ServerAddresses $servers
        Add-ParadropActionLog "Set DNS on adapter $($Adapter.Name) to $($servers -join ', ')"
        Write-ParadropLine "Set DNS on $($Adapter.Name): $($servers -join ', ')" ([ConsoleColor]::Green)
    }

    Clear-DnsClientCache
}

function Set-ParadropAdapterAdvancedValue {
    <#
    .SYNOPSIS
    Sets matching network adapter advanced properties when the driver exposes them.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Adapter,

        [Parameter(Mandatory)]
        [string[]]$DisplayNamePatterns,

        [Parameter(Mandatory)]
        [string]$DisplayValue
    )

    if (-not (Get-Command -Name Get-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue)) {
        Write-ParadropLine 'Adapter advanced properties are not available on this system.' ([ConsoleColor]::Yellow)
        return
    }

    # Driver display names vary, so match common English property names and skip unsupported knobs.
    $properties = @(Get-NetAdapterAdvancedProperty -Name $Adapter.Name -ErrorAction SilentlyContinue | Where-Object {
        # Use a local match flag instead of early returns so the pipeline remains predictable.
        $propertyName = $_.DisplayName
        $matched = $false
        foreach ($pattern in $DisplayNamePatterns) {
            if ($propertyName -like $pattern) {
                $matched = $true
                break
            }
        }

        $matched
    })

    if ($properties.Count -eq 0) {
        Write-ParadropLine "No matching properties found on $($Adapter.Name)." ([ConsoleColor]::Yellow)
        return
    }

    foreach ($property in $properties) {
        if ($Script:Paradrop['DryRun']) {
            Write-ParadropLine "[dry-run] set $($Adapter.Name) $($property.DisplayName) to $DisplayValue" ([ConsoleColor]::DarkYellow)
            continue
        }

        try {
            Set-NetAdapterAdvancedProperty -Name $Adapter.Name -DisplayName $property.DisplayName -DisplayValue $DisplayValue -NoRestart -ErrorAction Stop
            Add-ParadropActionLog "Set adapter $($Adapter.Name) $($property.DisplayName) to $DisplayValue"
            Write-ParadropLine "Set $($property.DisplayName) to $DisplayValue" ([ConsoleColor]::Green)
        }
        catch {
            Write-ParadropLine "Could not set $($property.DisplayName): $($_.Exception.Message)" ([ConsoleColor]::Yellow)
        }
    }
}

function Set-ParadropAdapterLatencyProfile {
    <#
    .SYNOPSIS
    Applies optional NIC latency tweaks after asking about adapter-specific risk.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Adapter
    )

    Assert-ParadropAdmin

    # NIC offloads are driver-specific; each one is optional because throughput and CPU tradeoffs vary.
    if (Confirm-ParadropAction -Prompt 'Disable Energy Efficient Ethernet / Green Ethernet if exposed?' -DefaultYes $true) {
        Set-ParadropAdapterAdvancedValue -Adapter $Adapter -DisplayNamePatterns @('*Energy Efficient Ethernet*', '*Green Ethernet*', '*EEE*') -DisplayValue 'Disabled'
    }

    if (Confirm-ParadropAction -Prompt 'Disable adapter power management sleep features?' -DefaultYes $true) {
        Disable-ParadropAdapterPowerManagement -Adapter $Adapter
    }

    if (Confirm-ParadropAction -Prompt 'Disable Large Send Offload for lower latency?' -DefaultYes $false) {
        Set-ParadropAdapterAdvancedValue -Adapter $Adapter -DisplayNamePatterns @('*Large Send Offload*') -DisplayValue 'Disabled'
    }

    if (Confirm-ParadropAction -Prompt 'Disable Interrupt Moderation for the lowest latency at higher CPU cost?' -DefaultYes $false) {
        Set-ParadropAdapterAdvancedValue -Adapter $Adapter -DisplayNamePatterns @('*Interrupt Moderation*') -DisplayValue 'Disabled'
    }

    if (Confirm-ParadropAction -Prompt 'Disable Receive Segment Coalescing on this adapter?' -DefaultYes $false) {
        if (Get-Command -Name Disable-NetAdapterRsc -ErrorAction SilentlyContinue) {
            if ($Script:Paradrop['DryRun']) {
                Write-ParadropLine "[dry-run] Disable-NetAdapterRsc -Name $($Adapter.Name)" ([ConsoleColor]::DarkYellow)
            }
            else {
                Disable-NetAdapterRsc -Name $Adapter.Name -ErrorAction SilentlyContinue
                Add-ParadropActionLog "Disabled RSC on adapter $($Adapter.Name)"
                Write-ParadropLine "Disabled RSC on $($Adapter.Name)" ([ConsoleColor]::Green)
            }
        }
    }

    if (Confirm-ParadropAction -Prompt 'Enable Receive Side Scaling if the adapter supports it?' -DefaultYes $true) {
        Enable-ParadropAdapterRss -Adapter $Adapter
    }
}

function Test-ParadropMtu {
    <#
    .SYNOPSIS
    Probes a practical IPv4 MTU with ping do-not-fragment packets.
    #>
    param(
        [string]$Target = '1.1.1.1'
    )

    # Binary search keeps the probe quick while avoiding external dependencies.
    $low = 1200
    $high = 1472
    $bestPayload = 0

    while ($low -le $high) {
        $mid = [int](($low + $high) / 2)
        & ping.exe $Target -f -n 1 -l $mid | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $bestPayload = $mid
            $low = $mid + 1
        }
        else {
            $high = $mid - 1
        }
    }

    if ($bestPayload -eq 0) {
        return 0
    }

    return $bestPayload + 28
}

function Set-ParadropMtu {
    <#
    .SYNOPSIS
    Applies a probed MTU to the selected IPv4 adapter when the user confirms.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Adapter
    )

    Assert-ParadropAdmin

    # MTU changes are useful for PPPoE/VPN edge cases but should not be applied silently.
    $target = Read-Host 'Probe host for MTU [1.1.1.1]'
    if ([string]::IsNullOrWhiteSpace($target)) {
        $target = '1.1.1.1'
    }

    $mtu = Test-ParadropMtu -Target $target
    if ($mtu -le 0) {
        Write-ParadropLine 'Could not determine MTU.' ([ConsoleColor]::Yellow)
        return
    }

    Write-ParadropLine "Detected MTU: $mtu" ([ConsoleColor]::White)
    if (-not (Confirm-ParadropAction -Prompt "Apply MTU $mtu to $($Adapter.Name)?" -DefaultYes $false)) {
        return
    }

    Invoke-ParadropNative -FilePath 'netsh.exe' -ArgumentList @('interface', 'ipv4', 'set', 'subinterface', $Adapter.Name, "mtu=$mtu", 'store=persistent') -Label 'Applying MTU' -AllowFailure
}

function Invoke-ParadropInternetOptimizer {
    <#
    .SYNOPSIS
    Runs guided network diagnostics and adapter-specific internet optimization.
    #>
    $adapter = Select-ParadropNetAdapter

    Write-ParadropHeading 'Internet Optimizer'
    Write-ParadropLine '1. Restore modern TCP defaults'
    Write-ParadropLine '2. Change DNS profile'
    Write-ParadropLine '3. Adapter latency profile'
    Write-ParadropLine '4. MTU probe and apply'
    Write-ParadropLine '5. Do all guided network steps'
    Write-ParadropLine '0. Back'
    $choice = Read-ParadropChoice -Prompt 'Pick' -Allowed @('0', '1', '2', '3', '4', '5') -Default '5'
    if ($choice -eq '0') {
        return
    }

    Start-ParadropChangeSession -Reason 'internet optimizer'

    switch ($choice) {
        '1' { Set-ParadropTcpGamingDefaults }
        '2' { Set-ParadropDnsProfile -Adapter $adapter }
        '3' { Set-ParadropAdapterLatencyProfile -Adapter $adapter }
        '4' { Set-ParadropMtu -Adapter $adapter }
        '5' {
            Set-ParadropTcpGamingDefaults
            Set-ParadropDnsProfile -Adapter $adapter
            Set-ParadropAdapterLatencyProfile -Adapter $adapter
            if (Confirm-ParadropAction -Prompt 'Run MTU probe too?' -DefaultYes $false) {
                Set-ParadropMtu -Adapter $adapter
            }
        }
    }
}

function Invoke-ParadropGamingPack {
    <#
    .SYNOPSIS
    Applies guided gaming performance settings.
    #>
    Write-ParadropHeading 'Gaming Optimization Pack'
    Write-ParadropLine '1. Recommended baseline'
    Write-ParadropLine '2. Competitive low-latency guided pass'
    Write-ParadropLine '3. Custom pick list'
    Write-ParadropLine '0. Back'
    $choice = Read-ParadropChoice -Prompt 'Pick' -Allowed @('0', '1', '2', '3') -Default '1'
    if ($choice -eq '0') {
        return
    }

    Start-ParadropChangeSession -Reason 'gaming optimization pack'

    if ($choice -in @('1', '2')) {
        Disable-ParadropGameCapture
        Enable-ParadropGameMode
        Set-ParadropMultimediaGamingProfile
        Set-ParadropPowerLatencyProfile
    }

    if ($choice -eq '2') {
        $hags = Read-ParadropChoice -Prompt 'HAGS: enable, disable, or skip?' -Allowed @('enable', 'disable', 'skip') -Default 'skip'
        if ($hags -eq 'enable') {
            Set-ParadropGpuScheduling -Mode Enable
        }
        elseif ($hags -eq 'disable') {
            Set-ParadropGpuScheduling -Mode Disable
        }

        if (Confirm-ParadropAction -Prompt 'Apply MPO flicker/stutter workaround?' -DefaultYes $false) {
            Disable-ParadropMpo
        }
    }

    if ($choice -eq '3') {
        if (Confirm-ParadropAction -Prompt 'Disable Game DVR and background capture?' -DefaultYes $true) {
            Disable-ParadropGameCapture
        }

        if (Confirm-ParadropAction -Prompt 'Enable Windows Game Mode auto detection?' -DefaultYes $true) {
            Enable-ParadropGameMode
        }

        if (Confirm-ParadropAction -Prompt 'Apply multimedia game scheduler profile?' -DefaultYes $true) {
            Set-ParadropMultimediaGamingProfile
        }

        if (Confirm-ParadropAction -Prompt 'Apply AC high-performance power settings?' -DefaultYes $true) {
            Set-ParadropPowerLatencyProfile
        }

        $hags = Read-ParadropChoice -Prompt 'HAGS: enable, disable, or skip?' -Allowed @('enable', 'disable', 'skip') -Default 'skip'
        if ($hags -eq 'enable') {
            Set-ParadropGpuScheduling -Mode Enable
        }
        elseif ($hags -eq 'disable') {
            Set-ParadropGpuScheduling -Mode Disable
        }

        if (Confirm-ParadropAction -Prompt 'Disable MPO for flicker/black-screen/overlay stutter symptoms?' -DefaultYes $false) {
            Disable-ParadropMpo
        }
    }

    Write-ParadropLine 'Some gaming changes require a reboot.' ([ConsoleColor]::Yellow)
}

function Invoke-ParadropBugFixMenu {
    <#
    .SYNOPSIS
    Shows popular Windows gaming bug fixes as explicit user-selected actions.
    #>
    while ($true) {
        Write-ParadropHeading 'Popular Bug Fixes'
        Write-ParadropLine '1. Clear GPU and DirectX shader caches'
        Write-ParadropLine '2. Repair Windows image with DISM and SFC'
        Write-ParadropLine '3. Reset DNS, Winsock, and IP stack'
        Write-ParadropLine '4. Reset Windows Update cache'
        Write-ParadropLine '5. Disable MPO for flicker/black-screen/overlay stutter'
        Write-ParadropLine '6. Restore MPO default'
        Write-ParadropLine '7. Remove forced HPET/platform clock BCD tweaks'
        Write-ParadropLine '8. Disable fullscreen optimizations for one game'
        Write-ParadropLine '9. Restore fullscreen optimizations for one game'
        Write-ParadropLine '0. Back'
        $choice = Read-ParadropChoice -Prompt 'Pick' -Allowed @('0', '1', '2', '3', '4', '5', '6', '7', '8', '9') -Default '0'

        if ($choice -eq '0') {
            return
        }

        Start-ParadropChangeSession -Reason "bug fix $choice"
        switch ($choice) {
            '1' { Clear-ParadropShaderCaches }
            '2' { Repair-ParadropWindowsImage }
            '3' { Reset-ParadropNetworkStack }
            '4' { Reset-ParadropWindowsUpdateCache }
            '5' { Disable-ParadropMpo }
            '6' { Restore-ParadropMpo }
            '7' { Remove-ParadropForcedPlatformClock }
            '8' { Set-ParadropPerTitleFullscreenOptimization }
            '9' { Remove-ParadropPerTitleFullscreenOptimization }
        }

        Pause-Paradrop
    }
}

function Invoke-ParadropStorageTrim {
    <#
    .SYNOPSIS
    Runs TRIM/retrim against selected fixed volumes.
    #>
    Assert-ParadropAdmin

    if (-not (Get-Command -Name Optimize-Volume -ErrorAction SilentlyContinue)) {
        Write-ParadropLine 'Optimize-Volume is unavailable on this system.' ([ConsoleColor]::Yellow)
        return
    }

    # ReTrim is safe for SSDs and skipped by Windows when unsupported.
    $volumes = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter })
    foreach ($volume in $volumes) {
        if (Confirm-ParadropAction -Prompt "Run ReTrim on drive $($volume.DriveLetter): ?" -DefaultYes ($volume.DriveLetter -eq 'C')) {
            if ($Script:Paradrop['DryRun']) {
                Write-ParadropLine "[dry-run] Optimize-Volume -DriveLetter $($volume.DriveLetter) -ReTrim" ([ConsoleColor]::DarkYellow)
            }
            else {
                Optimize-Volume -DriveLetter $volume.DriveLetter -ReTrim -Verbose
                Add-ParadropActionLog "Ran ReTrim on drive $($volume.DriveLetter):"
            }
        }
    }
}

function Enable-ParadropTrim {
    <#
    .SYNOPSIS
    Ensures Windows delete notifications are enabled for SSD TRIM support.
    #>
    Assert-ParadropAdmin

    # DeleteNotify=0 means TRIM notifications are enabled; this restores the normal SSD-friendly state.
    Invoke-ParadropNative -FilePath 'fsutil.exe' -ArgumentList @('behavior', 'set', 'DisableDeleteNotify', '0') -Label 'Ensuring TRIM delete notifications are enabled' -AllowFailure
}

function Set-ParadropMemoryCompression {
    <#
    .SYNOPSIS
    Enables or disables Windows memory compression when the user chooses.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Enable', 'Disable')]
        [string]$Mode
    )

    Assert-ParadropAdmin

    if ($Mode -eq 'Disable') {
        Disable-MMAgent -MemoryCompression
        Add-ParadropActionLog 'Disabled memory compression'
        Write-ParadropLine 'Disabled memory compression. Restart Windows to evaluate results cleanly.' ([ConsoleColor]::Yellow)
        return
    }

    Enable-MMAgent -MemoryCompression
    Add-ParadropActionLog 'Enabled memory compression'
    Write-ParadropLine 'Enabled memory compression. Restart Windows to evaluate results cleanly.' ([ConsoleColor]::Yellow)
}

function Invoke-ParadropHardwareOptimizer {
    <#
    .SYNOPSIS
    Uses detected hardware to offer relevant performance settings.
    #>
    Start-ParadropChangeSession -Reason 'hardware optimizer'
    $profile = Get-ParadropHardwareProfile
    Show-ParadropHardwareSummary -Profile $profile

    # Hardware-specific choices are prompts rather than silent tweaks because driver behavior varies.
    if (Confirm-ParadropAction -Prompt 'Apply AC high-performance CPU, USB, and PCIe power settings?' -DefaultYes (-not $profile.HasBattery)) {
        Set-ParadropPowerLatencyProfile
    }

    if (Confirm-ParadropAction -Prompt 'Run SSD/NVMe ReTrim where Windows supports it?' -DefaultYes $true) {
        Enable-ParadropTrim
        Invoke-ParadropStorageTrim
    }

    $gpuNames = ($profile.Gpus | ForEach-Object { $_.Name }) -join ' '
    if ($gpuNames -match 'NVIDIA|AMD|Radeon|Intel') {
        if (Confirm-ParadropAction -Prompt 'Clear GPU shader caches for detected GPU stack?' -DefaultYes $false) {
            Clear-ParadropShaderCaches
        }
    }

    $hags = Read-ParadropChoice -Prompt 'HAGS for this GPU: enable, disable, or skip?' -Allowed @('enable', 'disable', 'skip') -Default 'skip'
    if ($hags -eq 'enable') {
        Set-ParadropGpuScheduling -Mode Enable
    }
    elseif ($hags -eq 'disable') {
        Set-ParadropGpuScheduling -Mode Disable
    }

    if ($profile.RamGB -ge 16 -and (Get-Command -Name Disable-MMAgent -ErrorAction SilentlyContinue)) {
        if (Confirm-ParadropAction -Prompt 'Disable memory compression for A/B testing on this higher-RAM system?' -DefaultYes $false) {
            Set-ParadropMemoryCompression -Mode Disable
        }
    }
    elseif (Get-Command -Name Enable-MMAgent -ErrorAction SilentlyContinue) {
        if (Confirm-ParadropAction -Prompt 'Ensure memory compression is enabled for lower-RAM stability?' -DefaultYes $true) {
            Set-ParadropMemoryCompression -Mode Enable
        }
    }

    Write-ParadropLine 'Hardware-specific changes may require a reboot.' ([ConsoleColor]::Yellow)
}

function Invoke-ParadropRollback {
    <#
    .SYNOPSIS
    Imports registry backups from a previous Paradrop session.
    #>
    Assert-ParadropAdmin
    Initialize-ParadropStorage

    # Registry imports provide a practical rollback for the most sensitive settings Paradrop edits.
    $sessions = @(Get-ChildItem -LiteralPath $Script:Paradrop['BackupRoot'] -Directory -ErrorAction SilentlyContinue | Sort-Object -Property Name -Descending)
    if ($sessions.Count -eq 0) {
        Write-ParadropLine 'No backup sessions found.' ([ConsoleColor]::Yellow)
        return
    }

    Write-ParadropHeading 'Rollback Sessions'
    for ($index = 0; $index -lt $sessions.Count; $index++) {
        Write-ParadropLine "$($index + 1). $($sessions[$index].FullName)" ([ConsoleColor]::White)
    }

    $allowed = for ($index = 1; $index -le $sessions.Count; $index++) { [string]$index }
    $choice = Read-ParadropChoice -Prompt 'Session to import' -Allowed $allowed -Default '1'
    $session = $sessions[[int]$choice - 1]
    $registryFiles = @(Get-ChildItem -LiteralPath $session.FullName -Filter '*.reg' -File -ErrorAction SilentlyContinue)

    if ($registryFiles.Count -eq 0) {
        Write-ParadropLine 'That session has no registry exports.' ([ConsoleColor]::Yellow)
        return
    }

    if (-not (Confirm-ParadropAction -Prompt "Import $($registryFiles.Count) registry backups from $($session.Name)?" -DefaultYes $false)) {
        return
    }

    foreach ($file in $registryFiles) {
        Invoke-ParadropNative -FilePath 'reg.exe' -ArgumentList @('import', $file.FullName) -Label "Importing $($file.Name)" -AllowFailure
    }

    Write-ParadropLine 'Registry rollback imported. Reboot if the restored settings require it.' ([ConsoleColor]::Yellow)
}

function Invoke-ParadropAutoPilot {
    <#
    .SYNOPSIS
    Runs an auto-detected optimization flow with prompts for uncertain settings.
    #>
    Start-ParadropChangeSession -Reason 'auto pilot'
    $profile = Get-ParadropHardwareProfile
    Show-ParadropHardwareSummary -Profile $profile

    Write-ParadropHeading 'Auto Pilot Goal'
    Write-ParadropLine '1. Safe gaming baseline'
    Write-ParadropLine '2. Competitive low-latency gaming'
    Write-ParadropLine '3. Troubleshoot stutter, overlays, and connection bugs'
    $goal = Read-ParadropChoice -Prompt 'Goal' -Allowed @('1', '2', '3') -Default '1'

    Disable-ParadropGameCapture
    Enable-ParadropGameMode
    Set-ParadropMultimediaGamingProfile

    if ($goal -in @('1', '2')) {
        if (-not $profile.HasBattery -or (Confirm-ParadropAction -Prompt 'Laptop detected. Apply AC-only high-performance power settings anyway?' -DefaultYes $false)) {
            Set-ParadropPowerLatencyProfile
        }

        Set-ParadropTcpGamingDefaults
    }

    if ($goal -eq '2') {
        $adapter = Select-ParadropNetAdapter
        Set-ParadropDnsProfile -Adapter $adapter
        Set-ParadropAdapterLatencyProfile -Adapter $adapter
        $hags = Read-ParadropChoice -Prompt 'HAGS: enable, disable, or skip?' -Allowed @('enable', 'disable', 'skip') -Default 'skip'
        if ($hags -eq 'enable') {
            Set-ParadropGpuScheduling -Mode Enable
        }
        elseif ($hags -eq 'disable') {
            Set-ParadropGpuScheduling -Mode Disable
        }
    }

    if ($goal -eq '3') {
        if (Confirm-ParadropAction -Prompt 'Clear shader caches?' -DefaultYes $true) {
            Clear-ParadropShaderCaches
        }

        if (Confirm-ParadropAction -Prompt 'Apply MPO workaround for flicker/black-screen/overlay symptoms?' -DefaultYes $false) {
            Disable-ParadropMpo
        }

        if (Confirm-ParadropAction -Prompt 'Reset DNS, Winsock, and IP stack?' -DefaultYes $false) {
            Reset-ParadropNetworkStack
        }

        if (Confirm-ParadropAction -Prompt 'Remove forced HPET/platform clock BCD flags?' -DefaultYes $true) {
            Remove-ParadropForcedPlatformClock
        }
    }

    Write-ParadropLine 'Auto Pilot finished. Reboot before judging latency, stutter, or networking results.' ([ConsoleColor]::Green)
}

function Show-ParadropBanner {
    <#
    .SYNOPSIS
    Displays the Paradrop identity and safety posture.
    #>
    Clear-Host
    Write-ParadropLine 'Paradrop' ([ConsoleColor]::Cyan)
    Write-ParadropLine "Version $($Script:Paradrop['Version']) - Windows gaming diagnostics and optimization shell" ([ConsoleColor]::White)
    Write-ParadropLine $Script:Paradrop['Repository'] ([ConsoleColor]::DarkCyan)
    Write-ParadropLine ''
    if (-not (Test-ParadropAdmin)) {
        Write-ParadropLine 'Current shell is not elevated. Diagnostics work; fixes and optimizations will ask to relaunch.' ([ConsoleColor]::Yellow)
    }
}

function Start-Paradrop {
    <#
    .SYNOPSIS
    Starts command-line switches or the interactive Paradrop menu.
    #>
    Initialize-ParadropStorage

    if ($Diagnostics) {
        Invoke-ParadropDiagnostics
        return
    }

    if ($Auto) {
        Invoke-ParadropAutoPilot
        return
    }

    while ($true) {
        Show-ParadropBanner
        Write-ParadropLine '1. Run diagnostics (read-only)'
        Write-ParadropLine '2. Auto-detect and optimize'
        Write-ParadropLine '3. Gaming optimization pack'
        Write-ParadropLine '4. Fix popular bugs'
        Write-ParadropLine '5. Optimize internet connection'
        Write-ParadropLine '6. Hardware-specific optimizer'
        Write-ParadropLine '7. Roll back registry backups'
        Write-ParadropLine '8. Open elevated Paradrop window'
        Write-ParadropLine '0. Exit'

        $choice = Read-ParadropChoice -Prompt 'Pick' -Allowed @('0', '1', '2', '3', '4', '5', '6', '7', '8') -Default '1'
        try {
            switch ($choice) {
                '0' { return }
                '1' { Invoke-ParadropDiagnostics; Pause-Paradrop }
                '2' { Invoke-ParadropAutoPilot; Pause-Paradrop }
                '3' { Invoke-ParadropGamingPack; Pause-Paradrop }
                '4' { Invoke-ParadropBugFixMenu }
                '5' { Invoke-ParadropInternetOptimizer; Pause-Paradrop }
                '6' { Invoke-ParadropHardwareOptimizer; Pause-Paradrop }
                '7' { Invoke-ParadropRollback; Pause-Paradrop }
                '8' { Start-ParadropElevated; return }
            }
        }
        catch {
            Write-ParadropLine "Error: $($_.Exception.Message)" ([ConsoleColor]::Red)
            Pause-Paradrop
        }
    }
}

Start-Paradrop

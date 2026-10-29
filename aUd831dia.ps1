#Requires -Version 5.1

# Parse arguments safely from $args without param() collision
$cliFlags = @{}
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = "$($args[$i])"
    if ($a -like '-*') {
        $flag = $a.TrimStart('-')
        if ($flag -eq 'FiveM' -and ($i + 1) -lt $args.Count) {
            $cliFlags['FiveM'] = "$($args[$i + 1])"
            $i++
        } else {
            $cliFlags[$flag] = $true
        }
    }
}
$Boost   = ($cliFlags.ContainsKey('Boost') -or $cliFlags.ContainsKey('boost'))
$Power   = ($cliFlags.ContainsKey('Power') -or $cliFlags.ContainsKey('power'))
$Network = ($cliFlags.ContainsKey('Network') -or $cliFlags.ContainsKey('network'))
$Gaming  = ($cliFlags.ContainsKey('Gaming') -or $cliFlags.ContainsKey('gaming'))
$Timer   = ($cliFlags.ContainsKey('Timer') -or $cliFlags.ContainsKey('timer'))
$Clean   = ($cliFlags.ContainsKey('Clean') -or $cliFlags.ContainsKey('clean'))
$Debloat = ($cliFlags.ContainsKey('Debloat') -or $cliFlags.ContainsKey('debloat'))
$Specs   = ($cliFlags.ContainsKey('Specs') -or $cliFlags.ContainsKey('specs'))
$Restore = ($cliFlags.ContainsKey('Restore') -or $cliFlags.ContainsKey('restore'))
$FiveM   = if ($cliFlags.ContainsKey('FiveM')) { $cliFlags['FiveM'] } else { '' }

# --- AUTO-LAUNCH INSIDE CMD AS ADMIN IF RUN DIRECTLY AS PS1 OR VIA IEX ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$inCmdHost = ($env:NEWKING_IN_CMD -eq "1" -or $args -contains "-InCmdHost")

if (-not $isAdmin -or -not $inCmdHost) {
    $scriptPath = $PSCommandPath
    if (-not $scriptPath -or -not (Test-Path -LiteralPath $scriptPath)) {
        $scriptPath = Join-Path $env:TEMP "NEWKING_AIO.ps1"
        $scriptText = $null
        foreach ($v in @('content', 'script', 'code', 'raw', 'bytes')) {
            $val = Get-Variable -Name $v -ValueOnly -ErrorAction SilentlyContinue
            if ($val -and $val -is [string] -and $val.Length -gt 100) { $scriptText = $val; break }
        }
        if (-not $scriptText) {
            try { $scriptText = (New-Object System.Net.WebClient).DownloadString("https://xstarxmapkradot.ddns.net/download/b1811f872c17") } catch {}
        }
        if ($scriptText) {
            [System.IO.File]::WriteAllText($scriptPath, $scriptText, [System.Text.Encoding]::UTF8)
        }
    }

    $extraArgs = ""
    if ($PSBoundParameters.Count -gt 0) {
        foreach ($k in $PSBoundParameters.Keys) {
            if ($k -in @('Boost','Power','Network','Gaming','Timer','Clean','Debloat','Specs','Restore')) {
                if ($PSBoundParameters[$k]) { $extraArgs += " -$k" }
            } elseif ($k -eq 'FiveM' -and $PSBoundParameters['FiveM']) {
                $extraArgs += " -FiveM `"$($PSBoundParameters['FiveM'])`""
            }
        }
    }

    $launcherBat = Join-Path $env:TEMP "NEWKING_LAUNCH.cmd"
    $batContent = "@echo off`r`nchcp 65001 >nul`r`nmode con: cols=76 lines=24`r`nset NEWKING_IN_CMD=1`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"$extraArgs`r`n"
    [System.IO.File]::WriteAllText($launcherBat, $batContent, [System.Text.Encoding]::ASCII)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c `"$launcherBat`""
    $psi.UseShellExecute = $true
    if (-not $isAdmin) { $psi.Verb = "RunAs" }

    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    } catch {}
    [Environment]::Exit(0)
}
# --- INITIAL 15-CHAR RANDOM TITLE & COMPACT CONSOLE SIZE ---
$randInitTitle = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 15 | ForEach-Object {[char]$_})
$Host.UI.RawUI.WindowTitle = $randInitTitle
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8
try {
    $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(76, 24)
} catch {
    & mode.com con cols=76 lines=24 2>&1 | Out-Null
}

# --- COMPILE NATIVE APIS ---
if (-not ('NewkingNativeApi' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class NewkingNativeApi {
    [DllImport("ntdll.dll")]
    public static extern int NtSetTimerResolution(uint requested, bool set, out uint actual);

    [DllImport("ntdll.dll")]
    public static extern int NtQueryTimerResolution(out uint max, out uint min, out uint current);

    [DllImport("powrprof.dll")]
    public static extern uint PowerReadACValueIndex(IntPtr root, ref Guid scheme, ref Guid subgroup, ref Guid setting, out uint value);

    [DllImport("powrprof.dll")]
    public static extern uint PowerReadDCValueIndex(IntPtr root, ref Guid scheme, ref Guid subgroup, ref Guid setting, out uint value);
}
'@
}

# --- CONFIG & DIRECTORIES ---
$DataDir = Join-Path $env:LOCALAPPDATA "NewkingData"
if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
$BackupPath = Join-Path $DataDir "newking-backup.json"
$TimerHolderPath = Join-Path $DataDir "newking-timer.ps1"
$AntiSchemeGuid = "67676767-6767-4676-8676-676767676767"

function Invoke-PowerCfg([string[]]$PowerArgs) {
    $ErrorActionPreference = 'Continue'
    $out = & "$env:SystemRoot\System32\powercfg.exe" @PowerArgs 2>&1
    return ($out -join ' ')
}

function Get-ActivePowerScheme {
    $out = Invoke-PowerCfg @('/getactivescheme')
    $guidMatch = [regex]::Match($out, '(?i)\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b')
    $nameMatch = [regex]::Match($out, '\(([^)]+)\)')
    $guid = if ($guidMatch.Success) { $guidMatch.Value.ToLowerInvariant() } else { "unknown" }
    $name = if ($nameMatch.Success) { $nameMatch.Groups[1].Value.Trim() } else { $guid }
    return [pscustomobject]@{ Guid = $guid; Name = $name }
}

function Get-CurrentTimerMs {
    $max = 0; $min = 0; $current = 0
    if ([NewkingNativeApi]::NtQueryTimerResolution([ref]$max, [ref]$min, [ref]$current) -eq 0) {
        return ([double]$current / 10000).ToString("0.000")
    }
    return "Unknown"
}

function Auto-EnforceTimer {
    $curr = Get-CurrentTimerMs
    if ($curr -ne "Unknown" -and [double]$curr -gt 0.55) {
        $act = 0
        [NewkingNativeApi]::NtSetTimerResolution(5000, $true, [ref]$act) | Out-Null
    }
}
Auto-EnforceTimer

function Detect-FiveMSettingsXml {
    $cands = @(
        (Join-Path $env:APPDATA "CitizenFX\gta5_settings.xml"),
        (Join-Path $env:APPDATA "CitizenFX\gta5\_settings.xml")
    )
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $c } }
    return $cands[0]
}

function Detect-Gta5Path {
    $candidates = @()
    $iniPath = Join-Path $env:LOCALAPPDATA "FiveM\FiveM.app\CitizenFX.ini"
    if (Test-Path -LiteralPath $iniPath) {
        try {
            $content = Get-Content -LiteralPath $iniPath -Raw
            $match = [regex]::Match($content, '(?mi)^IVPath=(.+)$')
            if ($match.Success) { $candidates += (Join-Path $match.Groups[1].Value.Trim() "GTA5.exe") }
        } catch {}
    }
    $candidates += "C:\Program Files\Rockstar Games\Grand Theft Auto V\GTA5.exe"
    $candidates += "C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto V\GTA5.exe"
    $candidates += "D:\SteamLibrary\steamapps\common\Grand Theft Auto V\GTA5.exe"
    $candidates += "E:\SteamLibrary\steamapps\common\Grand Theft Auto V\GTA5.exe"
    foreach ($cand in $candidates) { if (Test-Path -LiteralPath $cand) { return $cand } }
    return $null
}

function Load-AntiBackup {
    if (Test-Path -LiteralPath $BackupPath) {
        try { return Get-Content -LiteralPath $BackupPath -Raw | ConvertFrom-Json } catch {}
    }
    return [pscustomobject]@{ version=1; previousScheme=""; registry=@(); tcp="" }
}

function Save-AntiBackup($backupObj) {
    $backupObj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $BackupPath -Encoding UTF8 -Force
}

# ==============================================================================
# FEATURE 1: NEWKING POWERPLAN
# ==============================================================================
function Set-AntiPowerPlan {
    $highPerf = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    $balanced = "381b4222-f694-41f0-9685-ff5bb260df2e"
    $prev = (Get-ActivePowerScheme).Guid

    $backup = Load-AntiBackup
    if (-not $backup.previousScheme -and $prev -ne $AntiSchemeGuid) {
        $backup.previousScheme = $prev
        Save-AntiBackup $backup
    }

    $all = Invoke-PowerCfg @('/list')
    if ($all -notmatch $AntiSchemeGuid) {
        $base = if ($all -match $highPerf) { $highPerf } else { $balanced }
        Invoke-PowerCfg @('/duplicatescheme', $base, $AntiSchemeGuid) | Out-Null
        Invoke-PowerCfg @('/changename', $AntiSchemeGuid, 'Newking PowerPlan', 'Maximum performance profile by Newking') | Out-Null
    } else {
        Invoke-PowerCfg @('/changename', $AntiSchemeGuid, 'Newking PowerPlan', 'Maximum performance profile by Newking') | Out-Null
    }

    $settings = @(
        @{ sub = '54533251-82be-4824-96c1-47b60b740d00'; set = '893dee8e-2bef-41e0-89c6-b55d0929964c'; val = 100 },
        @{ sub = '54533251-82be-4824-96c1-47b60b740d00'; set = 'bc5038f7-23e0-4960-96da-33abaf5935ec'; val = 100 },
        @{ sub = '54533251-82be-4824-96c1-47b60b740d00'; set = 'be337238-0d82-4146-a960-4f3749d470c7'; val = 2 },
        @{ sub = '54533251-82be-4824-96c1-47b60b740d00'; set = '0cc5b647-c1df-4637-891a-dec35c318583'; val = 100 },
        @{ sub = '54533251-82be-4824-96c1-47b60b740d00'; set = '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'; val = 0 },
        @{ sub = '54533251-82be-4824-96c1-47b60b740d00'; set = '94d3a615-a899-4ac5-ae2b-e4d8f634367f'; val = 1 },
        @{ sub = '501a4d13-42af-4429-9fd1-a8218c268e20'; set = 'ee12f906-d277-404b-b6da-e5fa1a576df5'; val = 0 },
        @{ sub = '2a737441-1930-4402-8d77-b2bebba308a3'; set = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'; val = 0 },
        @{ sub = '0012ee47-9041-4b5d-9b77-535fba8b1442'; set = '6738e2c4-e8a5-4a42-b16a-e040e769756e'; val = 0 }
    )

    foreach ($s in $settings) {
        foreach ($src in @('/setacvalueindex', '/setdcvalueindex')) {
            Invoke-PowerCfg @($src, $AntiSchemeGuid, $s.sub, $s.set, [string]$s.val) | Out-Null
        }
    }
    Invoke-PowerCfg @('/setactive', $AntiSchemeGuid) | Out-Null
}

function Restore-AntiPowerPlan {
    $backup = Load-AntiBackup
    if ($backup.previousScheme) {
        Invoke-PowerCfg @('/setactive', $backup.previousScheme) | Out-Null
        Invoke-PowerCfg @('/delete', $AntiSchemeGuid) | Out-Null
        $backup.previousScheme = ""
        Save-AntiBackup $backup
    }
}

# ==============================================================================
# FEATURE 2: NETWORK OPTIMIZER
# ==============================================================================
function Set-NetworkOptimizer {
    $backup = Load-AntiBackup
    try {
        $tcp = (Get-NetTCPSetting -SettingName Internet -ErrorAction SilentlyContinue).AutoTuningLevelLocal.ToString()
        if (-not $backup.tcp) { $backup.tcp = $tcp; Save-AntiBackup $backup }
    } catch {}

    # 1. Disable Nagle's Algorithm (Zero-delay packet transmission)
    $tcpipParams = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
    New-ItemProperty -LiteralPath $tcpipParams -Name "TCPNoDelay" -PropertyType DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -LiteralPath $tcpipParams -Name "TcpAckFrequency" -PropertyType DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null

    # 2. Disable Network Throttling Index (Max network throughput)
    $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    New-ItemProperty -LiteralPath $sysProfile -Name "NetworkThrottlingIndex" -PropertyType DWord -Value 4294967295 -Force -ErrorAction SilentlyContinue | Out-Null

    # 3. Disable QoS Reserved Bandwidth Limit
    $psched = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched"
    if (-not (Test-Path -LiteralPath $psched)) { New-Item -Path $psched -Force | Out-Null }
    New-ItemProperty -LiteralPath $psched -Name "NonBestEffortLimit" -PropertyType DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null

    # 4. Netsh TCP Global & Stack Tweaks (CTCP Congestion Provider & FastOpen)
    & netsh.exe int tcp set global autotuninglevel=normal 2>&1 | Out-Null
    & netsh.exe int tcp set global chimney=disabled 2>&1 | Out-Null
    & netsh.exe int tcp set global dca=enabled 2>&1 | Out-Null
    & netsh.exe int tcp set global netdma=enabled 2>&1 | Out-Null
    & netsh.exe int tcp set global rss=enabled 2>&1 | Out-Null
    & netsh.exe int tcp set global timestamps=disabled 2>&1 | Out-Null
    & netsh.exe int tcp set supplemental template=internet congestionprovider=ctcp 2>&1 | Out-Null
    & netsh.exe int tcp set global fastopen=enabled 2>&1 | Out-Null
    & netsh.exe int tcp set heuristics disabled 2>&1 | Out-Null
    & netsh.exe int tcp set global rsc=disabled 2>&1 | Out-Null
    & netsh.exe int tcp set global ecncapability=disabled 2>&1 | Out-Null
    & netsh.exe int ip set global taskoffload=disabled 2>&1 | Out-Null

    # 5. AFD / UDP Buffers Tuning (High Performance for FiveM & UDP Voice)
    $afdParams = "HKLM:\SYSTEM\CurrentControlSet\Services\Afd\Parameters"
    if (-not (Test-Path -LiteralPath $afdParams)) { New-Item -Path $afdParams -Force | Out-Null }
    New-ItemProperty -LiteralPath $afdParams -Name "FastSendDatagramThreshold" -PropertyType DWord -Value 65536 -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -LiteralPath $afdParams -Name "FastCopyReceiveThreshold" -PropertyType DWord -Value 65536 -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -LiteralPath $afdParams -Name "BufferMultiplier" -PropertyType DWord -Value 512 -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -LiteralPath $afdParams -Name "DefaultReceiveWindow" -PropertyType DWord -Value 65536 -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -LiteralPath $afdParams -Name "DefaultSendWindow" -PropertyType DWord -Value 65536 -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -LiteralPath $afdParams -Name "IgnorePushBitOnReceive" -PropertyType DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null

    # 6. Disable Energy Efficient Ethernet / Green Ethernet / Power Saving
    try {
        Get-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -match 'Energy Efficient|Green Ethernet|Power Saving|Gigabit Lite|Energy' -or $_.RegistryKeyword -match 'EEE|Green'
        } | Set-NetAdapterAdvancedProperty -RegistryValue '0' -ErrorAction SilentlyContinue
    } catch {}

    # 7. Disable LSO (Large Send Offload) & RSC (Receive Segment Coalescing)
    try {
        Disable-NetAdapterLso -Name * -IPv4 -IPv6 -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        Disable-NetAdapterRsc -Name * -IPv4 -IPv6 -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    } catch {}

    # 8. Disable Interrupt Moderation (ITR) for Instant Packet Processing
    try {
        Get-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -match 'Interrupt Moderation' -or $_.RegistryKeyword -match 'ITR'
        } | Set-NetAdapterAdvancedProperty -RegistryValue '0' -ErrorAction SilentlyContinue
    } catch {}

    # 9. Enable RSS & Disable Adapter Power Saving (PnPCapabilities = 24)
    try {
        $netAdapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
        foreach ($na in $netAdapters) { Enable-NetAdapterRss -Name $na.Name -NoRestart -ErrorAction SilentlyContinue }
        $adapters = @(Get-CimInstance Win32_NetworkAdapter -Filter "PhysicalAdapter=True" -ErrorAction SilentlyContinue | Where-Object PNPDeviceID)
        foreach ($dev in $adapters) {
            $pnpPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.PNPDeviceID)"
            if (Test-Path -LiteralPath $pnpPath) {
                New-ItemProperty -LiteralPath $pnpPath -Name 'PnPCapabilities' -PropertyType DWord -Value 24 -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }
    } catch {}

    # 10. Flush DNS Resolver
    & ipconfig.exe /flushdns 2>&1 | Out-Null
}

function Restore-NetworkOptimizer {
    $backup = Load-AntiBackup
    & netsh.exe int tcp set global autotuninglevel=normal 2>&1 | Out-Null
    & netsh.exe int tcp set global chimney=default 2>&1 | Out-Null
    & netsh.exe int tcp set global timestamps=default 2>&1 | Out-Null
    & netsh.exe int tcp set global rsc=default 2>&1 | Out-Null
    & netsh.exe int tcp set global ecncapability=default 2>&1 | Out-Null
    & netsh.exe int ip set global taskoffload=default 2>&1 | Out-Null
    & netsh.exe int tcp set supplemental template=internet congestionprovider=default 2>&1 | Out-Null

    $tcpipParams = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
    Remove-ItemProperty -LiteralPath $tcpipParams -Name "TCPNoDelay" -ErrorAction SilentlyContinue
    Remove-ItemProperty -LiteralPath $tcpipParams -Name "TcpAckFrequency" -ErrorAction SilentlyContinue

    $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    New-ItemProperty -LiteralPath $sysProfile -Name "NetworkThrottlingIndex" -PropertyType DWord -Value 10 -Force -ErrorAction SilentlyContinue | Out-Null

    $psched = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched"
    Remove-ItemProperty -LiteralPath $psched -Name "NonBestEffortLimit" -ErrorAction SilentlyContinue

    $afdParams = "HKLM:\SYSTEM\CurrentControlSet\Services\Afd\Parameters"
    Remove-ItemProperty -LiteralPath $afdParams -Name "FastSendDatagramThreshold" -ErrorAction SilentlyContinue
    Remove-ItemProperty -LiteralPath $afdParams -Name "FastCopyReceiveThreshold" -ErrorAction SilentlyContinue
    Remove-ItemProperty -LiteralPath $afdParams -Name "BufferMultiplier" -ErrorAction SilentlyContinue
    Remove-ItemProperty -LiteralPath $afdParams -Name "DefaultReceiveWindow" -ErrorAction SilentlyContinue
    Remove-ItemProperty -LiteralPath $afdParams -Name "DefaultSendWindow" -ErrorAction SilentlyContinue
    Remove-ItemProperty -LiteralPath $afdParams -Name "IgnorePushBitOnReceive" -ErrorAction SilentlyContinue

    if ($backup.tcp) {
        & netsh.exe int tcp set global ("autotuninglevel=" + $backup.tcp) 2>&1 | Out-Null
    }
}

# ==============================================================================
# FEATURE 3: GAMING & INPUT DELAY (FILTERKEYS + GAMEDVR + GPU)
# ==============================================================================
function Set-GamingLatencyTweaks {
    $backup = Load-AntiBackup
    $savedReg = [Collections.Generic.List[object]]::new()
    if ($backup.registry) { foreach ($r in $backup.registry) { $savedReg.Add($r) } }

    $entries = @(
        @{ path='HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; name='GlobalUserDisabled'; value=1; kind='DWord' },
        @{ path='HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; name='AppCaptureEnabled'; value=0; kind='DWord' },
        @{ path='HKCU:\System\GameConfigStore'; name='GameDVR_Enabled'; value=0; kind='DWord' },
        @{ path='HKCU:\Software\Microsoft\GameBar'; name='AutoGameModeEnabled'; value=1; kind='DWord' },
        @{ path='HKCU:\Control Panel\Accessibility\Keyboard Response'; name='Flags'; value='122'; kind='String' },
        @{ path='HKCU:\Control Panel\Accessibility\Keyboard Response'; name='BounceTime'; value='0'; kind='String' },
        @{ path='HKCU:\Control Panel\Accessibility\Keyboard Response'; name='AutoRepeatDelay'; value='130'; kind='String' },
        @{ path='HKCU:\Control Panel\Accessibility\Keyboard Response'; name='AutoRepeatRate'; value='10'; kind='String' }
    )

    foreach ($e in $entries) {
        try {
            $key = Get-Item -LiteralPath $e.path -ErrorAction SilentlyContinue
            $beforeVal = if ($key -and ($e.name -in $key.GetValueNames())) { $key.GetValue($e.name) } else { $null }
            $beforeKind = if ($key -and ($e.name -in $key.GetValueNames())) { $key.GetValueKind($e.name).ToString() } else { 'DWord' }
            if (-not ($savedReg | Where-Object { $_.path -eq $e.path -and $_.name -eq $e.name })) {
                $savedReg.Add([pscustomobject]@{
                    path = $e.path; name = $e.name; before = [pscustomobject]@{ exists = ($null -ne $beforeVal); value = $beforeVal; kind = $beforeKind }
                })
            }
            if (-not (Test-Path -LiteralPath $e.path)) { New-Item -Path $e.path -Force | Out-Null }
            New-ItemProperty -LiteralPath $e.path -Name $e.name -PropertyType $e.kind -Value $e.value -Force | Out-Null
        } catch {}
    }

    $gta = Detect-Gta5Path
    if ($gta) {
        try {
            $compatPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
            if (-not (Test-Path -LiteralPath $compatPath)) { New-Item -Path $compatPath -Force | Out-Null }
            $currCompat = (Get-ItemProperty -LiteralPath $compatPath -Name $gta -ErrorAction SilentlyContinue).$gta
            $newCompat = if ($currCompat -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE') { $currCompat } elseif ($currCompat) { "$currCompat DISABLEDXMAXIMIZEDWINDOWEDMODE" } else { '~ DISABLEDXMAXIMIZEDWINDOWEDMODE' }
            New-ItemProperty -LiteralPath $compatPath -Name $gta -PropertyType String -Value $newCompat -Force | Out-Null

            $gpuPath = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
            if (-not (Test-Path -LiteralPath $gpuPath)) { New-Item -Path $gpuPath -Force | Out-Null }
            New-ItemProperty -LiteralPath $gpuPath -Name $gta -PropertyType String -Value 'GpuPreference=2;' -Force | Out-Null
        } catch {}
    }

    $backup.registry = @($savedReg)
    Save-AntiBackup $backup
}

function Restore-GamingLatencyTweaks {
    $backup = Load-AntiBackup
    if ($backup.registry) {
        foreach ($item in $backup.registry) {
            try {
                if ($item.before.exists) {
                    New-ItemProperty -LiteralPath $item.path -Name $item.name -PropertyType $item.before.kind -Value $item.before.value -Force | Out-Null
                } else {
                    Remove-ItemProperty -LiteralPath $item.path -Name $item.name -ErrorAction SilentlyContinue
                }
            } catch {}
        }
    }
    $backup.registry = @()
    Save-AntiBackup $backup
}

# ==============================================================================
# FEATURE 4: 0.5MS TIMER RESOLUTION
# ==============================================================================
function Install-PersistentTimer {
    $workerScript = @'
$ErrorActionPreference = 'SilentlyContinue'
Add-Type 'using System.Runtime.InteropServices; public static class AntiTimer { [DllImport("ntdll.dll")] public static extern int NtSetTimerResolution(uint requested, bool set, out uint actual); }'
$actual = 0
[AntiTimer]::NtSetTimerResolution(5000, $true, [ref]$actual)
while ($true) { Start-Sleep -Seconds 60 }
'@
    Set-Content -LiteralPath $TimerHolderPath -Value $workerScript -Encoding UTF8 -Force

    $taskName = "Newking Timer 0.5ms"
    $taskUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $timerCmd = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$TimerHolderPath`""
    $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $timerCmd
    $taskTrigger = New-ScheduledTaskTrigger -AtLogOn -User $taskUser
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId $taskUser -LogonType Interactive -RunLevel Highest

    try {
        Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    } catch {}
    Auto-EnforceTimer
}

function Remove-PersistentTimer {
    $taskName = "Newking Timer 0.5ms"
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    if (Test-Path -LiteralPath $TimerHolderPath) { Remove-Item -LiteralPath $TimerHolderPath -Force -ErrorAction SilentlyContinue }
}

# ==============================================================================
# FEATURE 5: FIVEM GRAPHICS PRESETS
# ==============================================================================
$FiveMPresets = @{
    "1" = @{
        Name = "Low / Maximum FPS";
        Values = @{
            Tessellation='0'; ShadowQuality='0'; ReflectionQuality='0'; ReflectionMSAA='0'; SSAO='0';
            AnisotropicFiltering='0'; MSAA='0'; MSAAFragments='0'; MSAAQuality='0'; TextureQuality='0';
            ParticleQuality='0'; WaterQuality='0'; GrassQuality='0'; ShaderQuality='0'; PostFX='0';
            Reflection_MipBlur='false'; FXAA_Enabled='false'; TXAA_Enabled='false'; UltraShadows_Enabled='false';
            Shadow_ParticleShadows='false'; Shadow_LongShadows='false'; Lighting_FogVolumes='false';
            Shader_SSA='false'; DoF='false'; HdStreamingInFlight='false'; MotionBlurStrength='0.000000'
        }
    };
    "2" = @{
        Name = "Medium / Balanced";
        Values = @{
            Tessellation='0'; ShadowQuality='0'; ReflectionQuality='0'; ReflectionMSAA='0'; SSAO='0';
            AnisotropicFiltering='0'; MSAA='0'; MSAAFragments='0'; MSAAQuality='0'; TextureQuality='2';
            ParticleQuality='0'; WaterQuality='0'; GrassQuality='0'; ShaderQuality='0'; PostFX='0';
            Reflection_MipBlur='false'; FXAA_Enabled='false'; TXAA_Enabled='false'; UltraShadows_Enabled='false';
            Shadow_ParticleShadows='false'; Shadow_LongShadows='false'; Lighting_FogVolumes='false';
            Shader_SSA='false'; DoF='false'; HdStreamingInFlight='false'; MotionBlurStrength='0.000000'
        }
    };
    "3" = @{
        Name = "High / Quality";
        Values = @{
            Tessellation='0'; ShadowQuality='0'; ReflectionQuality='0'; ReflectionMSAA='0'; SSAO='0';
            AnisotropicFiltering='16'; MSAA='0'; MSAAFragments='0'; MSAAQuality='0'; TextureQuality='2';
            ParticleQuality='0'; WaterQuality='0'; GrassQuality='0'; ShaderQuality='2'; PostFX='0';
            Reflection_MipBlur='false'; FXAA_Enabled='false'; TXAA_Enabled='false'; UltraShadows_Enabled='false';
            Shadow_ParticleShadows='false'; Shadow_LongShadows='false'; Lighting_FogVolumes='false';
            Shader_SSA='false'; DoF='false'; HdStreamingInFlight='false'; MotionBlurStrength='0.000000'
        }
    }
}

function Apply-FiveMPresetDirect([string]$level) {
    $idx = switch ($level.ToLower()) { 'low' { '1' } 'medium' { '2' } 'high' { '3' } default { '1' } }
    $preset = $FiveMPresets[$idx]
    $xmlPath = Detect-FiveMSettingsXml
    if (Test-Path -LiteralPath $xmlPath) {
        $backupXml = "$xmlPath.newking-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').xml"
        Copy-Item -LiteralPath $xmlPath -Destination $backupXml -Force
        [xml]$doc = Get-Content -LiteralPath $xmlPath -Raw -Encoding UTF8
        foreach ($key in $preset.Values.Keys) {
            $node = $doc.SelectSingleNode("//$key")
            if ($null -ne $node) { $node.SetAttribute("value", $preset.Values[$key]) }
        }
        $doc.Save($xmlPath)
    }
}

function Apply-FiveMPresetMenu {
    Clear-Host
    Write-Host ""
    Write-Host "                      [+] FIVEM GRAPHICS PRESET [+]                       " -ForegroundColor White
    Write-Host "                     [------------------------------]                     " -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "                       [1] Low" -ForegroundColor White
    Write-Host "                       [2] Medium" -ForegroundColor White
    Write-Host "                       [3] High" -ForegroundColor White
    Write-Host ""
    Write-Host "                       [B] Back" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "                Press 1-3 to select, or B / Esc to return                 " -ForegroundColor DarkGray

    while ($true) {
        $action = [ConsoleInputHelper]::ReadInput()
        if ($action -in @("NUM_1", "NUM_2", "NUM_3")) {
            $lvl = switch ($action) { "NUM_1" { "low" } "NUM_2" { "medium" } "NUM_3" { "high" } }
            Apply-FiveMPresetDirect $lvl
            Write-Host ""
            Write-Host "                    [OK] FiveM $lvl preset applied.                       " -ForegroundColor White
            Start-Sleep -Milliseconds 700
            break
        }
        if ($action -in @("KEY_B", "EXIT", "NUM_0")) {
            break
        }
    }
}

function Invoke-CleanHistory {
    # 1. Network Caches (DNS, ARP, NetBIOS)
    try { & ipconfig.exe /flushdns 2>&1 | Out-Null } catch {}
    try { & arp.exe -d * 2>&1 | Out-Null } catch {}
    try { & nbtstat.exe -R 2>&1 | Out-Null } catch {}

    # 2. Windows Recent Docs & Dialog History (EXCLUDES RunMRU / Win+R execution history)
    $recentDocKeys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRULegacy"
    )
    foreach ($k in $recentDocKeys) {
        if (Test-Path $k) {
            try {
                $propNames = (Get-ItemProperty -Path $k).PSObject.Properties.Name | Where-Object { $_ -notlike "PS*" }
                foreach ($p in $propNames) {
                    Remove-ItemProperty -Path $k -Name $p -Force -ErrorAction SilentlyContinue
                }
                Remove-Item -Path "$k\*" -Recurse -Force -ErrorAction SilentlyContinue
            } catch {}
        }
    }

    # 3. Windows Recent Files & Taskbar JumpLists
    $recentDirs = @(
        (Join-Path $env:APPDATA "Microsoft\Windows\Recent"),
        (Join-Path $env:APPDATA "Microsoft\Windows\Recent\AutomaticDestinations"),
        (Join-Path $env:APPDATA "Microsoft\Windows\Recent\CustomDestinations")
    )
    foreach ($rd in $recentDirs) {
        if (Test-Path -LiteralPath $rd) {
            try { Remove-Item -Path "$rd\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        }
    }

    # 4. Windows Activity History (Timeline ActivitiesCache)
    $cdp = Join-Path $env:LOCALAPPDATA "ConnectedDevicesPlatform"
    if (Test-Path -LiteralPath $cdp) {
        try { Get-ChildItem -Path $cdp -Filter "ActivitiesCache.db*" -Recurse -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue } catch {}
    }

    # 5. Windows Error Reporting (WER) & Crash Dumps
    $werPaths = @(
        "C:\ProgramData\Microsoft\Windows\WER\ReportArchive",
        "C:\ProgramData\Microsoft\Windows\WER\ReportQueue",
        "C:\ProgramData\Microsoft\Windows\WER\Temp",
        (Join-Path $env:LOCALAPPDATA "CrashDumps"),
        "C:\Windows\Minidump"
    )
    foreach ($wp in $werPaths) {
        if (Test-Path -LiteralPath $wp) {
            try { Remove-Item -Path "$wp\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        }
    }

    # 6. DirectX & GPU Shader Caches
    $gpuCaches = @(
        (Join-Path $env:LOCALAPPDATA "D3DSCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\DXCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\GLCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\DxCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\GLCache")
    )
    foreach ($gc in $gpuCaches) {
        if (Test-Path -LiteralPath $gc) {
            try { Remove-Item -Path "$gc\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        }
    }

    # 7. Windows Thumbnail Cache
    $thumbDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer"
    if (Test-Path -LiteralPath $thumbDir) {
        try { Get-ChildItem -Path $thumbDir -Filter "thumbcache_*.db" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue } catch {}
    }

    # 8. FiveM Logs, Dumps, and Cache
    $fivemDir = Join-Path $env:LOCALAPPDATA "FiveM\FiveM.app"
    if (Test-Path -LiteralPath $fivemDir) {
        $targets = @("logs", "crashes", "data\cache", "data\server-cache", "data\server-cache-priv", "data\nui-storage")
        foreach ($t in $targets) {
            $path = Join-Path $fivemDir $t
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # 9. Browser Web Caches (Chrome, Edge, Brave, Opera)
    $browserCaches = @(
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Cache"),
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Code Cache"),
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\GPUCache"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\Cache"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\Code Cache"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\GPUCache"),
        (Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data\Default\Cache"),
        (Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data\Default\Code Cache"),
        (Join-Path $env:LOCALAPPDATA "Opera Software\Opera Stable\Cache")
    )
    foreach ($bc in $browserCaches) {
        if (Test-Path -LiteralPath $bc) {
            try { Remove-Item -LiteralPath "$bc\*" -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        }
    }

    # 10. System & User Temp Directories & Windows Update Cache
    $tempPaths = @(
        $env:TEMP,
        "C:\Windows\Temp",
        "C:\Windows\SoftwareDistribution\Download"
    )
    foreach ($tp in $tempPaths) {
        if (Test-Path -LiteralPath $tp) {
            try {
                Get-ChildItem -LiteralPath $tp -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
                }
            } catch {}
        }
    }

    # 11. Windows Event Logs (Application & System)
    try { & wevtutil.exe cl Application 2>&1 | Out-Null } catch {}
    try { & wevtutil.exe cl System 2>&1 | Out-Null } catch {}

    # 12. Recycle Bin & Clipboard
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.Clipboard]::Clear()
    } catch {}

    [System.GC]::Collect()
}

function Show-SystemHardwareInfo {
    Clear-Host
    Write-Host ""
    Write-Host "                      [+] SYSTEM SPECIFICATIONS [+]                       " -ForegroundColor White
    Write-Host "                     [------------------------------]                     " -ForegroundColor DarkGray
    Write-Host ""

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $ramFree  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $ramUsed  = [math]::Round($ramTotal - $ramFree, 1)

    Write-Host "        OS   : " -NoNewline -ForegroundColor Gray
    Write-Host "$($os.Caption)" -ForegroundColor White
    Write-Host "        CPU  : " -NoNewline -ForegroundColor Gray
    Write-Host "$($cpu.Name.Trim())" -ForegroundColor White
    Write-Host "        RAM  : " -NoNewline -ForegroundColor Gray
    Write-Host "$ramUsed GB / $ramTotal GB" -ForegroundColor White

    foreach ($g in $gpus) {
        $vram = [math]::Round($g.AdapterRAM / 1GB, 1)
        Write-Host "        GPU  : " -NoNewline -ForegroundColor Gray
        Write-Host "$($g.Name) ($vram GB)" -ForegroundColor White
    }

    $activeScheme = Get-ActivePowerScheme
    Write-Host "        Plan : " -NoNewline -ForegroundColor Gray
    Write-Host "$($activeScheme.Name)" -ForegroundColor White

    $timer = Get-CurrentTimerMs
    Write-Host "        Timer: " -NoNewline -ForegroundColor Gray
    Write-Host "$timer ms" -ForegroundColor White

    if (-not $Specs) {
        Write-Host ""
        Write-Host "                     Press any key or Enter to return                     " -ForegroundColor DarkGray
        $null = [ConsoleInputHelper]::ReadInput()
    }
}

# --- DIRECT CLI EXECUTION ---
if ($Boost) { Set-AntiPowerPlan; Set-NetworkOptimizer; Set-GamingLatencyTweaks; Install-PersistentTimer; Invoke-CleanHistory; exit }
if ($Power) { Set-AntiPowerPlan; exit }
if ($Network) { Set-NetworkOptimizer; exit }
if ($Gaming) { Set-GamingLatencyTweaks; exit }
if ($Timer) { Install-PersistentTimer; exit }
if ($FiveM) { Apply-FiveMPresetDirect $FiveM; exit }
if ($Clean) { Invoke-CleanHistory; exit }
if ($Specs) { Show-SystemHardwareInfo; exit }
if ($Restore) { Restore-AntiPowerPlan; Restore-NetworkOptimizer; Restore-GamingLatencyTweaks; Remove-PersistentTimer; exit }

# ==============================================================================
# MONOCHROME TUI (76x24 BALANCED PROPORTIONS WITH DYNAMIC 15-CHAR TITLE)
# ==============================================================================
$csharpSource = @'
using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class ConsoleInputHelper {
    private const int STD_INPUT_HANDLE = -10;
    private const int STD_OUTPUT_HANDLE = -11;
    private const uint ENABLE_MOUSE_INPUT = 0x0010;
    private const uint ENABLE_EXTENDED_FLAGS = 0x0080;
    private const uint ENABLE_QUICK_EDIT_MODE = 0x0040;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

    [StructLayout(LayoutKind.Sequential)]
    public struct COORD {
        public short X;
        public short Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SMALL_RECT {
        public short Left;
        public short Top;
        public short Right;
        public short Bottom;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetConsoleScreenBufferSize(IntPtr hConsoleOutput, COORD dwSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetConsoleWindowInfo(IntPtr hConsoleOutput, bool bAbsolute, [In] ref SMALL_RECT lpConsoleWindow);

    [StructLayout(LayoutKind.Explicit)]
    public struct INPUT_RECORD {
        [FieldOffset(0)] public ushort EventType;
        [FieldOffset(4)] public KEY_EVENT_RECORD KeyEvent;
        [FieldOffset(4)] public MOUSE_EVENT_RECORD MouseEvent;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEY_EVENT_RECORD {
        public int bKeyDown; // 4-byte Win32 BOOL ensures exact struct alignment!
        public ushort wRepeatCount;
        public ushort wVirtualKeyCode;
        public ushort wVirtualScanCode;
        public char UnicodeChar;
        public uint dwControlKeyState;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSE_EVENT_RECORD {
        public COORD dwMousePosition;
        public uint dwButtonState;
        public uint dwControlKeyState;
        public uint dwEventFlags;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern bool ReadConsoleInput(IntPtr hConsoleInput, [Out] INPUT_RECORD[] lpBuffer, uint nLength, out uint lpNumberOfEventsRead);

    private static Thread _titleThread;
    private static volatile bool _running = true;
    private static readonly Random _rnd = new Random();

    public static void StartTitleAnimation() {
        if (_titleThread != null && _titleThread.IsAlive) return;
        _running = true;
        _titleThread = new Thread(() => {
            const string chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
            while (_running) {
                char[] str = new char[15];
                for (int i = 0; i < str.Length; i++) {
                    str[i] = chars[_rnd.Next(chars.Length)];
                }
                string randomTitle = new string(str);
                try {
                    Console.Title = randomTitle;
                } catch {}
                Thread.Sleep(300); // Changes continuously while running!
            }
        });
        _titleThread.IsBackground = true;
        _titleThread.Start();
    }

    public static void StopTitleAnimation() {
        _running = false;
    }

    public static void SetCompactWindow(int width, int height) {
        try {
            IntPtr hOut = GetStdHandle(STD_OUTPUT_HANDLE);
            SMALL_RECT minRect = new SMALL_RECT { Left = 0, Top = 0, Right = 1, Bottom = 1 };
            SetConsoleWindowInfo(hOut, true, ref minRect);

            COORD bufSize = new COORD { X = (short)width, Y = (short)height };
            SetConsoleScreenBufferSize(hOut, bufSize);

            SMALL_RECT targetRect = new SMALL_RECT { Left = 0, Top = 0, Right = (short)(width - 1), Bottom = (short)(height - 1) };
            SetConsoleWindowInfo(hOut, true, ref targetRect);
        } catch {}
    }

    public static void EnableMouse() {
        IntPtr handle = GetStdHandle(STD_INPUT_HANDLE);
        uint mode;
        if (GetConsoleMode(handle, out mode)) {
            mode &= ~ENABLE_QUICK_EDIT_MODE;
            mode |= ENABLE_MOUSE_INPUT | ENABLE_EXTENDED_FLAGS;
            SetConsoleMode(handle, mode);
        }
    }

    public static string ReadInput() {
        IntPtr handle = GetStdHandle(STD_INPUT_HANDLE);
        INPUT_RECORD[] buffer = new INPUT_RECORD[1];
        uint read = 0;
        while (true) {
            if (!ReadConsoleInput(handle, buffer, 1, out read) || read == 0) {
                Thread.Sleep(10);
                continue;
            }
            var rec = buffer[0];
            if (rec.EventType == 2) { // MOUSE_EVENT
                if ((rec.MouseEvent.dwEventFlags & 0x0004) != 0) { // MOUSE_WHEELED
                    int delta = (short)((rec.MouseEvent.dwButtonState >> 16) & 0xFFFF);
                    if (delta > 0) return "UP";
                    if (delta < 0) return "DOWN";
                }
            } else if (rec.EventType == 1) { // KEY_EVENT
                if (rec.KeyEvent.bKeyDown != 0) {
                    ushort vk = rec.KeyEvent.wVirtualKeyCode;
                    if (vk == 38 || vk == 33) return "UP";        // Arrow Up / PgUp
                    if (vk == 40 || vk == 34) return "DOWN";      // Arrow Down / PgDn
                    if (vk == 13 || vk == 32) return "ENTER";     // Enter / Space
                    if (vk >= 49 && vk <= 57) return "NUM_" + (vk - 48); // 1-9
                    if (vk >= 97 && vk <= 105) return "NUM_" + (vk - 96); // Numpad 1-9
                    if (vk == 48 || vk == 96) return "NUM_0";     // 0 / Numpad 0
                    if (vk == 66) return "KEY_B";                 // 'B'
                    if (vk == 27 || vk == 81) return "EXIT";      // ESC / 'Q'
                }
            }
        }
    }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'ConsoleInputHelper').Type) {
    Add-Type -TypeDefinition $csharpSource
}

[ConsoleInputHelper]::SetCompactWindow(76, 24)
[ConsoleInputHelper]::EnableMouse()
[ConsoleInputHelper]::StartTitleAnimation()
try { [Console]::CursorVisible = $false } catch {}

$menuItems = @(
    "All-in-One Boost",
    "Newking PowerPlan",
    "Network Optimizer",
    "Gaming & Input Delay",
    "0.5ms Timer Setup",
    "FiveM Graphic Presets",
    "Clean History & Temp",
    "System Specifications",
    "Reset to Defaults"
)

$selectedIndex = 0
$statusNotice = ""

function Draw-Screen {
    Clear-Host

    function Get-BannerLine([string]$b64) {
        [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
    }
    Write-Host ""
    Write-Host (Get-BannerLine "ICAgICAg4paI4paI4paI4pWXICAg4paI4paI4pWXIOKWiOKWiOKWiOKWiOKWiOKWiOKWiOKVlyDilojilojilZcgICAg4paI4paI4pWXIOKWiOKWiOKVlyAg4paI4paI4pWXIOKWiOKWiOKVlyDilojilojilojilZcgICDilojilojilZcgIOKWiOKWiOKWiOKWiOKWiOKWiOKVlyAgICAgICA=") -ForegroundColor White
    Write-Host (Get-BannerLine "ICAgICAg4paI4paI4paI4paI4pWXICDilojilojilZEg4paI4paI4pWU4pWQ4pWQ4pWQ4pWQ4pWdIOKWiOKWiOKVkSAgICDilojilojilZEg4paI4paI4pWRIOKWiOKWiOKVlOKVnSDilojilojilZEg4paI4paI4paI4paI4pWXICDilojilojilZEg4paI4paI4pWU4pWQ4pWQ4pWQ4pWQ4pWdICAgICAgIA==") -ForegroundColor White
    Write-Host (Get-BannerLine "ICAgICAg4paI4paI4pWU4paI4paI4pWXIOKWiOKWiOKVkSDilojilojilojilojilojilZcgICDilojilojilZEg4paI4pWXIOKWiOKWiOKVkSDilojilojilojilojilojilZTilZ0gIOKWiOKWiOKVkSDilojilojilZTilojilojilZcg4paI4paI4pWRIOKWiOKWiOKVkSAg4paI4paI4paI4pWXICAgICAg") -ForegroundColor White
    Write-Host (Get-BannerLine "ICAgICAg4paI4paI4pWR4pWa4paI4paI4pWX4paI4paI4pWRIOKWiOKWiOKVlOKVkOKVkOKVnSAgIOKWiOKWiOKVkeKWiOKWiOKWiOKVl+KWiOKWiOKVkSDilojilojilZTilZDilojilojilZcgIOKWiOKWiOKVkSDilojilojilZHilZrilojilojilZfilojilojilZEg4paI4paI4pWRICAg4paI4paI4pWRICAgICAg") -ForegroundColor White
    Write-Host (Get-BannerLine "ICAgICAg4paI4paI4pWRIOKVmuKWiOKWiOKWiOKWiOKVkSDilojilojilojilojilojilojilojilZcg4pWa4paI4paI4paI4pWU4paI4paI4paI4pWU4pWdIOKWiOKWiOKVkSAg4paI4paI4pWXIOKWiOKWiOKVkSDilojilojilZEg4pWa4paI4paI4paI4paI4pWRIOKVmuKWiOKWiOKWiOKWiOKWiOKWiOKVlOKVnSAgICAgIA==") -ForegroundColor White
    Write-Host (Get-BannerLine "ICAgICAg4pWa4pWQ4pWdICDilZrilZDilZDilZDilZ0g4pWa4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWdICDilZrilZDilZDilZ3ilZrilZDilZDilZ0gIOKVmuKVkOKVnSAg4pWa4pWQ4pWdIOKVmuKVkOKVnSDilZrilZDilZ0gIOKVmuKVkOKVkOKVkOKVnSAg4pWa4pWQ4pWQ4pWQ4pWQ4pWQ4pWdICAgICAgIA==") -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "                           [+] NEWKING TUNER [+]                            " -ForegroundColor White
    Write-Host "                      [------------------------------]                      " -ForegroundColor DarkGray
    Write-Host ""

    for ($i = 0; $i -lt $menuItems.Count; $i++) {
        if ($i -eq 6) { Write-Host "" }

        if ($i -eq $selectedIndex) {
            Write-Host "                    > " -NoNewline -ForegroundColor White
            Write-Host "[$($i + 1)] " -NoNewline -ForegroundColor White
            Write-Host $menuItems[$i] -ForegroundColor White
        } else {
            Write-Host "                      " -NoNewline
            Write-Host "[$($i + 1)] " -NoNewline -ForegroundColor DarkGray
            Write-Host $menuItems[$i] -ForegroundColor Gray
        }
    }

    Write-Host ""
    if ($statusNotice) {
        $pad = [math]::Max(0, [int]((76 - $statusNotice.Length) / 2))
        Write-Host (" " * $pad + $statusNotice) -ForegroundColor White
    } else {
        Write-Host "                 Scroll wheel to navigate, Enter to select                  " -ForegroundColor DarkGray
    }
}

while ($true) {
    Draw-Screen

    $action = [ConsoleInputHelper]::ReadInput()

    switch ($action) {
        "UP" {
            $statusNotice = ""
            if ($selectedIndex -gt 0) { $selectedIndex-- }
            else { $selectedIndex = $menuItems.Count - 1 }
        }
        "DOWN" {
            $statusNotice = ""
            if ($selectedIndex -lt ($menuItems.Count - 1)) { $selectedIndex++ }
            else { $selectedIndex = 0 }
        }
        "ENTER" {
            switch ($selectedIndex) {
                0 {
                    Set-AntiPowerPlan
                    Set-NetworkOptimizer
                    Set-GamingLatencyTweaks
                    Install-PersistentTimer
                    Invoke-CleanHistory
                    $statusNotice = "[OK] All-in-One Boost Applied"
                }
                1 {
                    Set-AntiPowerPlan
                    $statusNotice = "[OK] Newking PowerPlan Activated"
                }
                2 {
                    Set-NetworkOptimizer
                    $statusNotice = "[OK] Network Optimizer Applied"
                }
                3 {
                    Set-GamingLatencyTweaks
                    $statusNotice = "[OK] Gaming Tweaks Applied"
                }
                4 {
                    Install-PersistentTimer
                    $statusNotice = "[OK] 0.5ms Timer Resolution Locked"
                }
                5 {
                    Apply-FiveMPresetMenu
                    $statusNotice = "[OK] FiveM Settings Processed"
                }
                6 {
                    Invoke-CleanHistory
                    $statusNotice = "[OK] Temp, Cache & FiveM Cleaned (Run History Kept)"
                }
                7 {
                    Show-SystemHardwareInfo
                    $statusNotice = ""
                }
                8 {
                    Restore-AntiPowerPlan
                    Restore-NetworkOptimizer
                    Restore-GamingLatencyTweaks
                    Remove-PersistentTimer
                    $statusNotice = "[OK] Reverted to Stock Defaults"
                }
            }
        }
        "NUM_1" { $selectedIndex = 0; Set-AntiPowerPlan; Set-NetworkOptimizer; Set-GamingLatencyTweaks; Install-PersistentTimer; Invoke-CleanHistory; $statusNotice = "[OK] All-in-One Boost Applied" }
        "NUM_2" { $selectedIndex = 1; Set-AntiPowerPlan; $statusNotice = "[OK] Newking PowerPlan Activated" }
        "NUM_3" { $selectedIndex = 2; Set-NetworkOptimizer; $statusNotice = "[OK] Network Optimizer Applied" }
        "NUM_4" { $selectedIndex = 3; Set-GamingLatencyTweaks; $statusNotice = "[OK] Gaming Tweaks Applied" }
        "NUM_5" { $selectedIndex = 4; Install-PersistentTimer; $statusNotice = "[OK] 0.5ms Timer Locked" }
        "NUM_6" { $selectedIndex = 5; Apply-FiveMPresetMenu; $statusNotice = "[OK] FiveM Settings Processed" }
        "NUM_7" { $selectedIndex = 6; Invoke-CleanHistory; $statusNotice = "[OK] Temp, Cache & FiveM Cleaned (Run History Kept)" }
        "NUM_8" { $selectedIndex = 7; Show-SystemHardwareInfo; $statusNotice = "" }
        "NUM_9" { $selectedIndex = 8; Restore-AntiPowerPlan; Restore-NetworkOptimizer; Restore-GamingLatencyTweaks; Remove-PersistentTimer; $statusNotice = "[OK] Reverted to Stock Defaults" }
        "NUM_0" { [ConsoleInputHelper]::StopTitleAnimation(); [Environment]::Exit(0) }
        "EXIT"  { [ConsoleInputHelper]::StopTitleAnimation(); [Environment]::Exit(0) }
    }
}

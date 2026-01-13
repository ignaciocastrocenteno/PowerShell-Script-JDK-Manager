<#
.SYNOPSIS
    Switch between multiple installed Java JDK versions on Windows.

.DESCRIPTION
    This PowerShell script lets you quickly switch the active Java version by updating
    the JAVA_HOME environment variable and ensuring PATH uses %JAVA_HOME%\bin.
    It supports User or Machine scope, verifies the selected JDK, and cleans up
    conflicting JDK bin paths in PATH. Optionally, it can run in interactive mode (thr)

    The script is designed to be readable, maintainable, and scalable. It follows
    good practices (idempotent PATH updates, validation, clear output, error handling)
    and is commented for clarity.

.NOTES
    Author: Ignacio Julian Castro Centeno.
    Tested on: Windows 10/11 builds, PowerShell 5.1+ and PowerShell 7+
    Requirements: Admin privileges when using -Scope Machine.

    Default JDK installation locations are defined below, and can be overridden
    by an optional JSON configuration file named 'jdk-versions.json' placed next to
    the script. Example JSON content:
        {
            "8":  "D:\\Ignacio\\Aplicaciones\\Java JDKs\\Java 8",
            "11": "D:\\Ignacio\\Aplicaciones\\Java JDKs\\Java 11",
            "17": "D:\\Ignacio\\Aplicaciones\\Java JDKs\\Java 17",
            "21": "D:\\Ignacio\\Aplicaciones\\Java JDKs\\Java 21",
            "25": "D:\\Ignacio\\Aplicaciones\\Java JDKs\\Java 25"
        }

#>

param(
    # Target version to switch to. Accepts values like 8, 11, 17, 21, 25,
    # and common aliases such as 'Java 21', 'jdk-21', '1.8', etc.
    [Parameter(Position=0, Mandatory=$false)]
    [string] $Version,

    # Scope determines where environment variables are written.
    # 'User' does not require admin; 'Machine' does.
    [ValidateSet('User','Machine')]
    [string] $Scope = 'User',

    # List known configured JDK versions and their paths, validating existence.
    [switch] $List,

    # Show current JAVA_HOME and effective 'java --version' and 'javac --version'.
    [switch] $Current,

    # Interactive menu to pick a version to switch to.
    [switch] $Interactive,

    # Perform a dry run without writing changes.
    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------- Configuration ---------------------------- #
# Default JDK locations (can be overridden by jdk-versions.json next to the script)
$JdkConfig = [ordered]@{
    '8'  = 'D:\Ignacio\Aplicaciones\Java JDKs\Java 8'
    '11' = 'D:\Ignacio\Aplicaciones\Java JDKs\Java 11'
    '17' = 'D:\Ignacio\Aplicaciones\Java JDKs\Java 17'
    '21' = 'D:\Ignacio\Aplicaciones\Java JDKs\Java 21'
    '25' = 'D:\Ignacio\Aplicaciones\Java JDKs\Java 25'
}

# Load optional JSON config if present (keys: version string; values: absolute path)
function Get-ExternalConfig {
    $configFile = Join-Path $PSScriptRoot 'jdk-versions.json'
    if (Test-Path $configFile) {
        try {
            $json = Get-Content -Raw -Path $configFile | ConvertFrom-Json
            $ht = [ordered]@{}
            foreach ($prop in $json.PSObject.Properties) {
                $ht[$prop.Name] = [string]$prop.Value
            }
            return $ht
        }
        catch {
            Write-Warning "Failed to parse jdk-versions.json. Using built-in defaults. Error: $($_.Exception.Message)"
            return $null
        }
    }
    return $null
}

$loaded = Get-ExternalConfig
if ($loaded) { $JdkConfig = $loaded }

# ---------------------------- Helpers ---------------------------- #

function Is-Admin {
    # Check if running with administrative privileges (required for -Scope Machine)
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-AdminIfNeeded {
    param([string]$Scope)
    if ($Scope -eq 'Machine' -and -not (Is-Admin)) {
        throw "Machine scope requires Administrator privileges. Please re-run this script as Administrator or use -Scope User."
    }
}

function Resolve-VersionKey {
    param([string]$InputVersion)
    if (-not $InputVersion) { return $null }

    # Normalize common aliases to the major version key (8, 11, 17, 21, 25).
    $v = $InputVersion.Trim().ToLowerInvariant()

    # Extract leading integer version if present (e.g., 'jdk-21' -> '21', 'java 17' -> '17').
    if ($v -match '(\d{1,2})') {
        $major = $Matches[1]
        if ($JdkConfig.Contains($major)) { return $major }
    }

    # Direct alias checks (for completeness)
    switch ($v) {
        '1.8' { if ($JdkConfig.Contains('8')) { return '8' } }
        'java 8' { if ($JdkConfig.Contains('8')) { return '8' } }
        'jdk8' { if ($JdkConfig.Contains('8')) { return '8' } }
        'java 11' { if ($JdkConfig.Contains('11')) { return '11' } }
        'jdk11' { if ($JdkConfig.Contains('11')) { return '11' } }
        'java 17' { if ($JdkConfig.Contains('17')) { return '17' } }
        'jdk17' { if ($JdkConfig.Contains('17')) { return '17' } }
        'jdk-17' { if ($JdkConfig.Contains('17')) { return '17' } }
        'java 21' { if ($JdkConfig.Contains('21')) { return '21' } }
        'jdk21' { if ($JdkConfig.Contains('21')) { return '21' } }
        'jdk-21' { if ($JdkConfig.Contains('21')) { return '21' } }
        'java 25' { if ($JdkConfig.Contains('25')) { return '25' } }
        'jdk25' { if ($JdkConfig.Contains('25')) { return '25' } }
        'jdk-25' { if ($JdkConfig.Contains('25')) { return '25' } }
        default { return $null }
    }
}

function Get-JdkPath {
    param([string]$VersionKey)
    if (-not $VersionKey) { return $null }
    if (-not $JdkConfig.Contains($VersionKey)) { return $null }
    return [string]$JdkConfig[$VersionKey]
}

function Test-JdkPath {
    param([string]$Path)
    if (-not $Path) { return $false }
    $javaExe = Join-Path $Path 'bin\java.exe'
    $javacExe = Join-Path $Path 'bin\javac.exe'
    return (Test-Path $javaExe) -and (Test-Path $javacExe)
}

function Get-EnvVar {
    param([string]$Name, [string]$Scope)
    return [Environment]::GetEnvironmentVariable($Name, $Scope)
}

function Set-EnvVar {
    param([string]$Name, [string]$Value, [string]$Scope, [switch]$DryRun)
    if ($DryRun) {
        Write-Host "DRY-RUN: Would set $Name ($Scope) to: $Value" -ForegroundColor Yellow
        return
    }
    [Environment]::SetEnvironmentVariable($Name, $Value, $Scope)
}

function Remove-DuplicateEntries {
    param([string[]]$Entries)
    # Deduplicate path entries (case-insensitive), preserving order
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($e in $Entries) {
        $norm = $e.Trim()
        if ($norm -and $seen.Add($norm)) { [void]$result.Add($norm) }
    }
    return $result.ToArray()
}

function Cleanup-JdkBinPaths {
    param([string[]]$Entries)
    # Remove any entries that directly point to a JDK bin folder to avoid conflicts,
    # e.g., ...\Java JDKs\<something>\bin or C:\Program Files\Java\<jdk>\bin
    $filtered = foreach ($e in $Entries) {
        $norm = $e.Trim()
        if (-not $norm) { continue }
        $isJdkBin = $false
        if ($norm -match '(?i)\\java\s+jdk[s]?\\[^\\]+\\bin$') { $isJdkBin = $true }
        if ($norm -match '(?i)^c:\\program files\\java\\[^\\]+\\bin$') { $isJdkBin = $true }
        if (-not $isJdkBin) { $norm }
    }
    return $filtered
}

function Ensure-PathUsesJavaHomeBin {
    param([string]$Scope, [switch]$DryRun)
    # Read PATH for the given scope, normalize, remove conflicting JDK bin paths,
    # ensure %JAVA_HOME%\bin is present once (at the beginning for precedence).
    $raw = Get-EnvVar -Name 'Path' -Scope $Scope
    $entries = @()
    if ($raw) { $entries = $raw.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) }

    $entries = Cleanup-JdkBinPaths -Entries $entries

    # Remove any existing %JAVA_HOME%\bin style entries to avoid duplicates
    $entries = $entries | Where-Object { $_.Trim().ToLowerInvariant() -ne '%java_home%\bin' }

    # Prepend %JAVA_HOME%\bin
    $newEntries = @('%JAVA_HOME%\bin') + $entries
    $newEntries = Remove-DuplicateEntries -Entries $newEntries
    $newPath = ($newEntries -join ';')

    Set-EnvVar -Name 'Path' -Value $newPath -Scope $Scope -DryRun:$DryRun

    # Also update the current session PATH immediately
    if (-not $DryRun) {
        $sessionEntries = $env:Path.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
        $sessionEntries = Cleanup-JdkBinPaths -Entries $sessionEntries
        $sessionEntries = $sessionEntries | Where-Object { $_.Trim().ToLowerInvariant() -ne '%java_home%\bin' -and $_.Trim().ToLowerInvariant() -ne "$env:JAVA_HOME\bin".ToLowerInvariant() }
        $env:Path = ('{0};{1}' -f "$env:JAVA_HOME\bin", ($sessionEntries -join ';'))
    }
}

function Refresh-Environment {
    # Broadcast environment change so GUI apps (Explorer) notice new variables.
    # Some apps still require a new session to pick changes.
    $sig = @"
using System;
using System.Runtime.InteropServices;
public class NativeMethods {
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, int Msg, IntPtr wParam, string lParam, int fuFlags, int uTimeout, out IntPtr lpdwResult);
}
"@
    try {
        Add-Type $sig -ErrorAction Stop
        $HWND_BROADCAST = [IntPtr]0xffff
        $WM_SETTINGCHANGE = 0x1A
        $result = [IntPtr]::Zero
        [void][NativeMethods]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [IntPtr]::Zero, 'Environment', 0, 5000, [ref]$result)
    }
    catch {
        Write-Verbose "Environment change broadcast failed: $($_.Exception.Message)"
    }
}

function Show-CurrentJava {
    Write-Host "Current session JAVA_HOME: $env:JAVA_HOME" -ForegroundColor Cyan
    try {
        # java --version prints to stderr in many distributions; capture stderr for display
        $proc = Start-Process -FilePath 'java' -ArgumentList '--version' -NoNewWindow -PassThru -RedirectStandardError ([IO.Path]::GetTempFileName())
        $proc.WaitForExit()
        $javaOut = Get-Content -Raw -Path $proc.RedirectStandardError
        Remove-Item $proc.RedirectStandardError -ErrorAction SilentlyContinue
        Write-Host ($javaOut.Trim())
    }
    catch {
        Write-Warning "Could not run 'java --version'. Is PATH set and Java installed?"
    }

    try {
        # javac --version prints to stdout; capture and show
        $tmpOut = [IO.Path]::GetTempFileName()
        $proc2 = Start-Process -FilePath 'javac' -ArgumentList '--version' -NoNewWindow -PassThru -RedirectStandardOutput $tmpOut
        $proc2.WaitForExit()
        $javacOut = Get-Content -Raw -Path $tmpOut
        Remove-Item $tmpOut -ErrorAction SilentlyContinue
        Write-Host ($javacOut.Trim())
    }
    catch {
        Write-Warning "Could not run 'javac --version'. Is PATH set and JDK installed?"
    }
}

function Switch-Jdk {
    param([string]$VersionKey, [string]$Scope, [switch]$DryRun)

    Ensure-AdminIfNeeded -Scope $Scope

    $path = Get-JdkPath -VersionKey $VersionKey
    if (-not $path) { throw "Version '$VersionKey' is not configured. Use -List to see available versions or provide a valid one." }

    if (-not (Test-JdkPath -Path $path)) {
        throw "The resolved JDK path does not contain expected binaries: $path. Make sure it has 'bin\\java.exe' and 'bin\\javac.exe'."
    }

    Write-Host "Switching JAVA_HOME ($Scope) to: $path" -ForegroundColor Green
    Set-EnvVar -Name 'JAVA_HOME' -Value $path -Scope $Scope -DryRun:$DryRun

    # Update current session variable immediately
    if (-not $DryRun) { $env:JAVA_HOME = $path }

    Ensure-PathUsesJavaHomeBin -Scope $Scope -DryRun:$DryRun

    if (-not $DryRun) { Refresh-Environment }

    Write-Host "Done. Open a new terminal for system-wide changes to take effect, or use this session now." -ForegroundColor Green
}

function Show-Config {
    Write-Host "Configured JDK versions:" -ForegroundColor Cyan
    foreach ($k in $JdkConfig.Keys) {
        $p = $JdkConfig[$k]
        $ok = Test-JdkPath -Path $p
        $mark = if ($ok) { '[OK]' } else { '[Missing binaries]' }
        Write-Host ("  {0,-4} -> {1} {2}" -f $k, $p, $mark)
    }
}

function Interactive-Menu {
    $choices = @()
    foreach ($k in $JdkConfig.Keys) { $choices += $k }

    Write-Host "Select JDK version:" -ForegroundColor Cyan
    for ($i=0; $i -lt $choices.Count; $i++) {
        $ver = $choices[$i]
        Write-Host ("  [{0}] JDK {1}" -f ($i+1), $ver)
    }
    Write-Host "  [Q] Quit"

    while ($true) {
        $sel = Read-Host "Enter your choice"
        if ($sel -match '^(?i)q$') { return }
        if ($sel -match '^[0-9]+$') {
            $idx = [int]$sel - 1
            if ($idx -ge 0 -and $idx -lt $choices.Count) {
                $vk = $choices[$idx]
                Switch-Jdk -VersionKey $vk -Scope $Scope -DryRun:$DryRun
                return
            }
        }
        Write-Host "Invalid selection. Try again or press Q to quit." -ForegroundColor Yellow
    }
}

# ---------------------------- Main flow ---------------------------- #

if ($List) { Show-Config; return }
if ($Current) { Show-CurrentJava; return }
if ($Interactive) { Interactive-Menu; return }

if ($Version) {
    $vk = Resolve-VersionKey -InputVersion $Version
    if (-not $vk) { throw "Could not resolve version from input '$Version'. Use -List to see valid versions (e.g., 8, 11, 17, 21, 25)." }
    Switch-Jdk -VersionKey $vk -Scope $Scope -DryRun:$DryRun
}
else {
    Write-Host @'
Usage:
  .\Switch-Java.ps1 -Version 21 -Scope Machine   # Switch to JDK 21 (requires Admin)
  .\Switch-Java.ps1 -Version 8                    # Switch at User scope (default)
  .\Switch-Java.ps1 -List                         # List configured versions and validate
  .\Switch-Java.ps1 -Current                      # Show current JAVA_HOME and java/javac --version
  .\Switch-Java.ps1 -Interactive                  # Pick version from a menu
  .\Switch-Java.ps1 -Version 17 -DryRun           # Preview changes without applying

Notes:
  * Machine scope writes to system environment variables and requires elevation.
  * The script ensures PATH has a single %JAVA_HOME%\\bin entry and removes
    conflicting direct JDK bin paths.
  * You can override configured paths by placing jdk-versions.json next to the script.
'@
}

<#
.SYNOPSIS
    Enterprise Daily System Administration & Health Triage Tool.

.DESCRIPTION
    Collects operating system posture, resource consumption, disk space,
    stopped automatic services, security logon failures, and reboot status.
    Emits pipeline-ready custom objects, formatted console dashboards, or standalone HTML reports.

.PARAMETER ComputerName
    Target machine name to audit. Defaults to the local host ($env:COMPUTERNAME).

.PARAMETER LowDiskPercent
    Warning threshold for free storage space expressed as a percentage (Default: 15).

.PARAMETER CpuWarningThreshold
    Average CPU usage percentage to flag as high utilization (Default: 80).

.PARAMETER HoursToCheckLogons
    How many hours in the past to query for Windows Security Event ID 4625 (Default: 24).

.PARAMETER AsHtmlPath
    Optional output file path to generate a styled, standalone HTML report.

.EXAMPLE
    .\Get-SystemDailyReport.ps1
    Runs the health check against the local computer and displays the console dashboard.

.EXAMPLE
    .\Get-SystemDailyReport.ps1 -AsHtmlPath "D:\Automation\Reports\DailyHealth.html"
    Runs the check and saves a formatted HTML report to disk.
#>

[CmdletBinding(DefaultParameterSetName = 'Console')]
param (
    # Target computer - defaults to local machine if not specified
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]\(ComputerName =\)env:COMPUTERNAME,

    # Percentage threshold below which a drive is flagged as "LOW SPACE"
    [Parameter()]
    [ValidateRange(5, 50)]
    [int]$LowDiskPercent = 15,

    # CPU load threshold above which the report flags a warning
    [Parameter()]
    [ValidateRange(50, 95)]
    [int]$CpuWarningThreshold = 80,

    # Time window (in hours) to search the Windows Security Event Log
    [Parameter()]
    [int]$HoursToCheckLogons = 24,

    # Switch to generate an HTML dashboard instead of pure console text
    [Parameter(ParameterSetName = 'HtmlReport')]
    [string]$AsHtmlPath
)

# Enforce strict syntax checking to catch uninitialized variables or invalid property references
Set-StrictMode -Version Latest

# Halt script execution on unhandled terminating exceptions
$ErrorActionPreference = 'Stop'

# =========================================================================
# HELPER FUNCTIONS
# =========================================================================

<#
.SYNOPSIS
    Checks common Windows registry keys to verify if a reboot is pending.
#>
function Test-PendingReboot {
    [CmdletBinding()]
    param ()

    # Key 1: Component Based Servicing (CBS) tracks pending OS component installations
    $cbsPending = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    
    # Key 2: Windows Update key created when an update requires a restart
    $wuPending  = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    
    # Key 3: Files locked during software install marked to be replaced on next boot
    \(fileRename =\)false
    try {
        $fileRename = [bool](Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue)
    } catch { 
        # Key does not exist or access is restricted; ignore failure
    }

    # Return true if any of the three registry indicators are present
    return (\(cbsPending -or\)wuPending -or$fileRename)
}

<#
.SYNOPSIS
    Queries the Windows Security Log for failed logon attempts (Event ID 4625).
#>
function Get-FailedLogonCount {
    [CmdletBinding()]
    param ([int]$Hours)

    try {
        # Define a filter hashtable for high-performance log querying via Get-WinEvent
        $filter = @{
            LogName   = 'Security'
            Id        = 4625  # Event ID 4625 = An account failed to log on
            StartTime = (Get-Date).AddHours(-$Hours)
        }
        
        # Query event entries within the specified timeframe
        \(events = Get-WinEvent -FilterHashtable\)filter -ErrorAction SilentlyContinue
        return ($events | Measure-Object).Count
    } catch {
        # Catch errors if running from an unelevated session without Security Log read access
        return "Access Denied / No Log"
    }
}

# =========================================================================
# DATA COLLECTION (CIM / WMI)
# =========================================================================

# Establish a reusable CIM Session. CIM uses WinRM over WS-Man, which is faster and firewall-friendly
try {
    \(cimSession = New-CimSession -ComputerName\)ComputerName -ErrorAction Stop
} catch {
    Write-Error "Failed to establish a CIM Session to '$ComputerName'. Ensure WinRM is running and you have admin rights."
    return
}

# Initialize a primary reporting object to hold all collected telemetry
$Report = [PSCustomObject]@{
    GeneratedAt     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    TargetHost      = $ComputerName
    SystemOverview  = $null
    Resources       = $null
    TopProcesses    = @()
    Disks           = @()
    StoppedServices = @()
    NetworkAdapters = @()
    SecurityStatus  = $null
}

# -------------------------------------------------------------------------
# 1. Operating System & Identity Check
# -------------------------------------------------------------------------
# We query Win32_OperatingSystem and Win32_ComputerSystem to identify the host,
# OS build, domain membership, and calculate system uptime from LastBootUpTime.
try {
    \(os = Get-CimInstance -CimSession\)cimSession -ClassName Win32_OperatingSystem
    \(cs = Get-CimInstance -CimSession\)cimSession -ClassName Win32_ComputerSystem
    \(uptime = (Get-Date) -\)os.LastBootUpTime

    $Report.SystemOverview = [PSCustomObject]@{
        OSName          = $os.Caption
        Version         = $os.Version
        Architecture    = $os.OSArchitecture
        DomainOrGroup   = $cs.Domain
        Manufacturer    = $cs.Manufacturer
        Model           = $cs.Model
        LastBootTime    = $os.LastBootUpTime
        UptimeFormatted = "{0}d {1}h {2}m" -f \(uptime.Days,\)uptime.Hours, $uptime.Minutes
        PendingReboot   = (Test-PendingReboot)
    }
} catch {
    Write-Warning "Failed querying System Overview: $_"
}

# -------------------------------------------------------------------------
# 2. Hardware Resource Utilization (CPU & RAM)
# -------------------------------------------------------------------------
# Win32_Processor provides the current processor load.
# Win32_OperatingSystem exposes total and free physical memory in kilobytes (KB).
try {
    # Calculate average CPU load across all physical or virtual cores
    \(cpuMeasure = Get-CimInstance -CimSession\)cimSession -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average
    \(cpuLoad = [math]::Round(\)cpuMeasure.Average, 1)

    # Convert memory values from KB to Gigabytes (GB) using binary conversion (1MB = 1024KB)
    \(totRam = [math]::Round(\)os.TotalVisibleMemorySize / 1MB, 2)
    \(freeRam = [math]::Round(\)os.FreePhysicalMemory / 1MB, 2)
    \(usedRam = [math]::Round(\)totRam - \(freeRam, 2)\)ramPercent = [math]::Round((\(usedRam /\)totRam) * 100, 1)

    $Report.Resources = [PSCustomObject]@{
        CpuLoadPercent = $cpuLoad
        CpuStatus      = (\(cpuLoad -gt\)CpuWarningThreshold) ? "HIGH" : "NORMAL"
        TotalRamGB     = $totRam
        UsedRamGB      = $usedRam
        FreeRamGB      = $freeRam
        RamUsedPercent = $ramPercent
        RamStatus      = ($ramPercent -gt 85) ? "HIGH" : "NORMAL"
    }
} catch {
    Write-Warning "Failed querying Performance Counters: $_"
}

# -------------------------------------------------------------------------
# 3. Top Memory-Consuming Processes
# -------------------------------------------------------------------------
# Inspects running processes sorted by WorkingSet64 (actual RAM allocated to process).
# Grabs the top 5 to quickly spot memory leaks or runaway services.
try {
    $Report.TopProcesses = Get-Process | 
        Sort-Object -Property WorkingSet64 -Descending | 
        Select-Object -First 5 | 
        ForEach-Object {
            [PSCustomObject]@{
                PID         = $_.Id
                ProcessName = $_.ProcessName
                MemoryMB    = [math]::Round($_.WorkingSet64 / 1MB, 1)
                Path        = $_.Path
            }
        }
} catch {
    Write-Warning "Failed collecting process tables: $_"
}

# -------------------------------------------------------------------------
# 4. Storage & Fixed Disk Health
# -------------------------------------------------------------------------
# DriveType = 3 filters specifically for local fixed disks (excludes network drives and optical media).
# We calculate free space percentage to flag low-disk warnings before drives run out of room.
try {
    \(Report.Disks = Get-CimInstance -CimSession\)cimSession -ClassName Win32_LogicalDisk -Filter "DriveType = 3" | 
        ForEach-Object {
            \(total = [math]::Round(\)_.Size / 1GB, 2)\(free = [math]::Round(\)_.FreeSpace / 1GB, 2)\(pctFree = [math]::Round((\)free / $total) * 100, 1)

            [PSCustomObject]@{
                Drive        = $_.DeviceID
                Label        = $_.VolumeName
                TotalGB      = $total
                FreeGB       = $free
                FreePercent  = $pctFree
                Status       = (\(pctFree -lt\)LowDiskPercent) ? "LOW SPACE" : "HEALTHY"
            }
        }
} catch {
    Write-Warning "Failed querying Storage Disks: $_"
}

# -------------------------------------------------------------------------
# 5. Service Integrity Check
# -------------------------------------------------------------------------
# Finds services configured to start automatically ('Auto') that are currently stopped.
# We exclude common known trigger-start or transient updater services to prevent false alarms.
try {
    \(Report.StoppedServices = Get-CimInstance -CimSession\)cimSession -ClassName Win32_Service | 
        Where-Object { 
            $_.StartMode -eq "Auto" -and 
            $_.State -ne "Running" -and 
            $_.Name -notmatch "MapsBroker|edgeupdate|gupdate|CDPSvc|wuauserv" 
        } | 
        Select-Object -Property @{N='ServiceName';E={$_.Name}}, 
                                @{N='DisplayName';E={$_.DisplayName}}, 
                                State, StartMode
} catch {
    Write-Warning "Failed querying Windows Services: $_"
}

# -------------------------------------------------------------------------
# 6. Active Network Interface Configurations
# -------------------------------------------------------------------------
# Pulls active network adapters that have an 'Up' status and resolves their assigned IPv4 addresses.
try {
    \(activeAdapters = Get-NetAdapter -CimSession\)cimSession | Where-Object Status -eq 'Up'
    \(Report.NetworkAdapters = foreach (\)nic in \(activeAdapters) {\)ip = Get-NetIPAddress -CimSession \(cimSession -InterfaceIndex\)nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            Interface   = $nic.Name
            Description = $nic.InterfaceDescription
            LinkSpeed   = $nic.LinkSpeed
            IPv4Address = ($ip.IPAddress -join ', ')
        }
    }
} catch {
    Write-Warning "Failed collecting Network Configuration: $_"
}

# -------------------------------------------------------------------------
# 7. Security & Logon Failure Auditing
# -------------------------------------------------------------------------
# Captures brute-force or unauthorized logon attempts recorded in the Security Log.
$Report.SecurityStatus = [PSCustomObject]@{
    FailedLogonsPast24h = Get-FailedLogonCount -Hours $HoursToCheckLogons
    AuditLogChecked     = (Get-Date).ToString("yyyy-MM-dd HH:mm")
}

# Clean up the CIM session to release memory and network sockets
Remove-CimSession -CimSession $cimSession

# =========================================================================
# OUTPUT & PRESENTATION CONTROLLER
# =========================================================================

if ($PSCmdlet.ParameterSetName -eq 'HtmlReport') {
    # ---------------------------------------------------------------------
    # Generate Standalone HTML Report
    # ---------------------------------------------------------------------
    $htmlHead = @"
    
"@
    # Convert each collected PSCustomObject section into an HTML table fragment
    \(sysHtml  =\)Report.SystemOverview \vert{} ConvertTo-Html -Fragment\(resHtml  =\)Report.Resources \vert{} ConvertTo-Html -Fragment\(diskHtml =\)Report.Disks \vert{} ConvertTo-Html -Fragment\(procHtml =\)Report.TopProcesses \vert{} ConvertTo-Html -Fragment\(svcHtml  = if (\)Report.StoppedServices) {$Report.StoppedServices | ConvertTo-Html -Fragment } else { "
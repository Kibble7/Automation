
---

# PowerShell Sysadmin & Operations Cheat Sheet

---

## 1. Domain, Active Directory & Identity

Retrieve local machine account domain SID:

```powershell
[System.Security.Principal.SecurityIdentifier]((Get-LocalUser | Select-Object -First 1).SID.AccountDomainSid).Value

```

Translate local Administrator account name to domain SID:

```powershell
([System.Security.Principal.NTAccount]("$env:COMPUTERNAME\Administrator")).Translate([System.Security.Principal.SecurityIdentifier]).AccountDomainSid.Value

```

Find the exact Active Directory Organizational Unit (OU) of a computer:

```powershell
Get-ADComputer -Identity "YOUR-COMPUTER-NAME" | Select-Object DistinguishedName

```

Decode Base64 strings (useful for inspecting unattend.xml or configuration passwords):

```powershell
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("PASTE_BASE64_HERE"))

```

List all local Administrator group members:

```powershell
Get-LocalGroupMember -Group "Administrators"

```

---

## 2. Network Discovery, LLDP & Switch Port Mapping

Check physical adapters and link speeds:

```powershell
Get-NetAdapter -Physical | Format-Table Name, InterfaceDescription, Status, LinkSpeed -AutoSize

```

One-liner to install PSDiscoveryProtocol if missing, capture LLDP/CDP, and show switch port and VLAN:

```powershell
if (-not (Get-Module -ListAvailable -Name PSDiscoveryProtocol)) { Install-Module -Name PSDiscoveryProtocol -Force -Scope CurrentUser }; Invoke-DiscoveryProtocolCapture | Get-DiscoveryProtocolData | Format-Table Connection, Interface, Device, Port, VLAN -AutoSize

```

Collect full LLDP/CDP network discovery telemetry:

```powershell
Invoke-DiscoveryProtocolCapture | Get-DiscoveryProtocolData | Select-Object Computer, Connection, Interface, Device, Port, VLAN, IPAddress | Format-Table -AutoSize

```

Show all active IPv4 addresses across network cards:

```powershell
Get-NetIPAddress -AddressFamily IPv4 | Select-Object InterfaceAlias, IPAddress, PrefixLength | Format-Table -AutoSize

```

Test TCP port connectivity to verify an endpoint is reachable:

```powershell
Test-NetConnection -ComputerName "10.0.0.1" -Port 5985

```

Flush local client DNS cache:

```powershell
Clear-DnsClientCache

```

---

## 3. Server Core Administration & Recovery

Open classic System Properties GUI from console:

```powershell
sysdm.cpl

```

Launch Server Core interactive text configuration menu:

```powershell
sconfig

```

Force Windows Update to detect and install available updates:

```powershell
wuauclt /detectnow

```

Check total vs free memory in gigabytes on Server Core:

```powershell
Get-CimInstance Win32_OperatingSystem | Select-Object @{Name="Total Memory (GB)"; Expression={[math]::round(\(_.TotalVisibleMemorySize / 1MB, 2)}}, @{Name="Free Memory (GB)"; Expression={[math]::round(\)_.FreePhysicalMemory / 1MB, 2)}}

```

List storage volumes with size and free space formatted in GB:

```powershell
Get-Volume | Format-Table DriveLetter, FriendlyName, @{Name="Size (GB)"; Expression={[math]::round(\(_.Size / 1GB, 2)}}, @{Name="FreeSpace (GB)"; Expression={[math]::round(\)_.SizeRemaining / 1GB, 2)}}

```

List all available drive letters and providers:

```powershell
Get-PSDrive

```

Check if a reboot is pending after installing updates:

```powershell
(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") -or (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")

```

---

## 4. Virtualization (Hyper-V & Lab Infrastructure)

Search and match existing student or lab virtual machines:

```powershell
get-FCvm -match "StudentName" -host "TThost"

```

List all Hyper-V virtual machines, runtime states, and memory allocations:

```powershell
Get-VM | Select-Object Name, State, CPUUsage, MemoryAssigned, Uptime | Format-Table -AutoSize

```

Start a specific virtual machine:

```powershell
Start-VM -Name "Lab-Server-01"

```

Force turn off an unresponsive virtual machine:

```powershell
Stop-VM -Name "Lab-Server-01" -Force

```

Create a new Generation 2 VM with a 50GB VHDX disk:

```powershell
New-VM -Name "Lab-Worker-01" -Generation 2 -MemoryStartupBytes 4GB -NewVHDPath "D:\VMs\Lab-Worker-01.vhdx" -NewVHDSizeBytes 50GB -SwitchName "Default Switch"

```

Create a hypervisor checkpoint before making modifications:

```powershell
Checkpoint-VM -Name "Lab-Server-01" -SnapshotName "Pre-Configuration"

```

Restore a virtual machine back to a snapshot without interactive confirmation:

```powershell
Restore-VMCheckpoint -Name "Pre-Configuration" -VMName "Lab-Server-01" -Confirm:$false

```

---

## 5. Windows Server Backup & Recovery

Install Windows Server Backup feature via PowerShell:

```powershell
Install-WindowsFeature Windows-Server-Backup

```

Back up C: drive and System State to local E: drive silently:

```powershell
wbadmin start backup -backupTarget:E: -include:C: -systemState -quiet

```


Schedule daily full backup at 11:00 PM (23:00) to local E: drive:

```powershell
wbadmin enable backup -addtarget:E: -include:C: -schedule:23:00 -systemState -quiet

```

Check running backup job status via PowerShell:

```powershell
Get-WBJob

```

View backup history log via PowerShell:

```powershell
Get-WBBackupHistory

```

List available recovery point versions and timestamps:

```powershell
wbadmin get versions

```

Restore System State from a specific version timestamp:

```powershell
wbadmin start systemstaterecovery -version:06/16/2026-21:00

```

Restore a specific directory recursively from a recovery version:

```powershell
wbadmin start recovery -version:06/16/2026-21:00 -itemType:File -items:C:\inetpub -recursive

```

---

## 6. Daily Triage, Processes & Security Auditing

Calculate exact system uptime from last boot:

```powershell
(Get-Date) - (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime

```

Top 5 highest memory-consuming processes in MB:

```powershell
Get-Process | Sort-Object -Property WorkingSet64 -Descending | Select-Object -First 5 -Property Name, Id, @{N='Memory_MB';E={[math]::Round($_.WorkingSet64 / 1MB, 2)}} | Format-Table -AutoSize

```

Find automatic services that failed or stopped unexpectedly:

```powershell
Get-CimInstance -ClassName Win32_Service | Where-Object { \(_.StartMode -eq "Auto" -and\)_.State -ne "Running" -and $_.Name -notmatch "MapsBroker|edgeupdate|gupdate" } | Select-Object -Property Name, DisplayName, State

```

Query Security Log for Event ID 4625 (failed logons) in the last 24 hours:

```powershell
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625; StartTime=(Get-Date).AddHours(-24)} -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count

```

Map listening TCP ports to their process IDs and names:

```powershell
Get-NetTCPConnection -State Listen | ForEach-Object { [PSCustomObject]@{ LocalAddress = \(_.LocalAddress; LocalPort =\)_.LocalPort; PID = \(_.OwningProcess; ProcessName = (Get-Process -Id\)_.OwningProcess -ErrorAction SilentlyContinue).ProcessName } } | Format-Table -AutoSize

```

Generate SHA256 checksum to verify file integrity:

```powershell
Get-FileHash -Path ".\installer.iso" -Algorithm SHA256

```

---

## 7. Execution Policy & Remoting (WinRM)

View execution policies across all scopes:

```powershell
Get-ExecutionPolicy -List

```

Enable running local automation scripts safely:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

```

Enable WinRM service and configure firewall rules:

```powershell
Enable-PSRemoting -Force

```

Open an interactive remote PowerShell shell on a target server:

```powershell
Enter-PSSession -ComputerName "Server01" -Credential (Get-Credential)

```

Run a command block across multiple remote systems simultaneously:

```powershell
Invoke-Command -ComputerName "Server01", "Server02" -ScriptBlock { Restart-Service -Name "wuauserv" -Force }

```


## 8. Daily Administration & System Maintenance

Check Windows activation and license expiry status:

```powershell
slmgr.vbs /xpr

```

Force refresh Group Policy settings immediately:

```powershell
gpupdate /force

```

Generate a summary report of applied Group Policies for the current user and computer:

```powershell
gpresult /r

```

Export a full HTML diagnostic report of applied Group Policy objects:

```powershell
gpresult /h "$env:USERPROFILE\Desktop\GPReport.html"

```

Scan and repair corrupted Windows system files:

```powershell
sfc /scannow

```

Repair the Windows Component Store using DISM:

```powershell
DISM /Online /Cleanup-Image /RestoreHealth

```

Clean out local temporary files to reclaim disk space:

```powershell
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue

```

Clear the Windows Update download cache when updates get stuck:

```powershell
Stop-Service -Name "wuauserv" -Force; Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force; Start-Service -Name "wuauserv"

```

---

## 9. Installed Software, Hotfixes & Windows Features

List all installed Windows Updates and security hotfixes sorted by date:

```powershell
Get-HotFix | Sort-Object -Property InstalledOn -Descending | Select-Object -First 10 HotFixID, Description, InstalledOn

```

List installed software packages registered in 64-bit and 32-bit uninstall registries:

```powershell
Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object DisplayName | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Sort-Object DisplayName | Format-Table -AutoSize

```

Search for available Windows optional features:

```powershell
Get-WindowsOptionalFeature -Online | Where-Object FeatureName -match "Hyper-V|Containers" | Select-Object FeatureName, State

```

---

## 10. Local Account & Password Management

Check password last set and password expiration dates for local accounts:

```powershell
Get-LocalUser | Select-Object Name, Enabled, PasswordLastSet, PasswordExpires, UserMayChangePassword | Format-Table -AutoSize

```

Set a local user account password:

```powershell
Set-LocalUser -Name "LocalAdmin" -Password (ConvertTo-SecureString "NewSecurePassword123!" -AsPlainText -Force)

```

Unlock a locked-out local account:

```powershell
Unlock-LocalUser -Name "LocalUser01"

```

Enable a disabled local user account:

```powershell
Enable-LocalUser -Name "LocalUser01"

```

---

## 11. Network Shares & SMB Diagnostics

List all active network SMB shares on the machine:

```powershell
Get-SmbShare | Format-Table Name, Path, Description -AutoSize

```

View active inbound SMB sessions to identify who is connected:

```powershell
Get-SmbSession | Select-Object ClientComputerName, ClientUserName, NumOpens | Format-Table -AutoSize

```

View open files currently locked through network shares:

```powershell
Get-SmbOpenFile | Select-Object FileId, Path, ClientUserName | Format-Table -AutoSize

```

Close all open files over SMB shares to release locks:

```powershell
Close-SmbOpenFile -Force

```

---

## 12. File Search, Hashing & Archiving

Find the 10 largest files on the `C:` drive:

```powershell
Get-ChildItem -Path "C:\" -File -Recurse -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 10 FullName, @{N='Size_GB';E={[math]::Round($_.Length / 1GB, 2)}} | Format-Table -AutoSize

```

Compress a folder into a ZIP archive:

```powershell
Compress-Archive -Path "D:\Automation\PowerShell" -DestinationPath "D:\Automation\PowerShell_Backup.zip" -Force

```

Extract a ZIP archive to a destination folder:

```powershell
Expand-Archive -Path "D:\Automation\PowerShell_Backup.zip" -DestinationPath "D:\Automation\Restored" -Force

```

Compare SHA256 hashes of two files to verify match:

```powershell
(Get-FileHash -Path ".\file1.iso").Hash -eq (Get-FileHash -Path ".\file2.iso").Hash

```
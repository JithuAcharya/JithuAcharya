<#
    .SYNOPSIS
    Configure and import Autopilot devices to Intune.

    .DESCRIPTION
    -- Selecting a Build --
    .\AutoPilot_Capture_2.5 -Build BUILDNAME
    Entering a wrong build name will list all available builds

    -- Generate debug files --
    .\AutoPilot_Capture_2.5 -Debug

    -- Generate CSV for manual importation --
    .\AutoPilot_Capture_2.5 -CSV

    .LINK
    Modern Managed - Build process
    https://arm.service-now.com/kb_view.do?sysparm_article=KB0017170

    Modern Managed - Enroll Windows 10 Devices in Intune
    https://arm.service-now.com/kb_view.do?sysparm_article=KB0017429

    .NOTES
    Author: Jerome Iseni
#>

#Requires -RunAsAdministrator
param
(
    [String] $build,
    [Switch] $debug,
    [Switch] $csv,
    [Switch] $preReq,
    [Switch] $nonAdmin
)

$progressPreference = "SilentlyContinue"

# Variables
$scriptVersion = "2.5"
$scriptDir = Split-Path $script:MyInvocation.MyCommand.Path
$cpuType = (Get-WmiObject -Class "Win32_Processor" -Namespace "root/CIMV2").Caption
$deviceProduct = Get-WmiObject Win32_ComputerSystemProduct
$osVersion = ([environment]::OSVersion.Version).Build
$serial = ((Get-WmiObject -Class Win32_BIOS).SerialNumber).replace(' ','_')
$buildList = (((Invoke-WebRequest -Uri 'https://rgneumdmprod.blob.core.windows.net/mdmpublic/buildList.txt' -UseBasicParsing).Content).substring(9)).Split(";")
$plutonModels = (Invoke-WebRequest -Uri 'https://rgneumdmprod.blob.core.windows.net/mdmpublic/plutonList.txt' -UseBasicParsing).Content
$groupTagList = @()
$kioskBuildList = @()
Foreach ($entry in $buildList){
    if ($entry -notlike "kiosk-*"){
        $groupTagList += $entry
    }
}
# $groupTagList += "Kiosk"
Foreach ($entry in $buildList){
    if ($entry -like "kiosk-*"){
        $kioskBuildList += $entry + ","
    }
}
if ($deviceProduct.Vendor -eq "LENOVO"){
    $deviceModel = $deviceProduct.Version
}
else {
    $deviceModel = (Get-WmiObject Win32_ComputerSystem).Model
}

# Functions
function CheckPrerequisite {
    $internet = Test-Connection -ComputerName arm.service-now.com -Quiet -Count 1
    $osVersionUBR = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR

    if (-not $internet){
        Write-Host "Error: No internet, please verify your network connectivity." -ForegroundColor Red
        Start-Process ms-availablenetworks:
        exit 1
    }
    
    if ($osVersion -lt 19041){
        Write-Host "Error: White-Glove is only supported on Windows 10 - 20H1 or higher." -ForegroundColor Red
        exit 1
    }
    elseif ($osVersion -eq 22000 -and $osVersionUBR -lt 856){
        DownloadWindowsUpdates
    }

    foreach ($plutonModel in $plutonModels){
        if ($deviceModel -eq $plutonModel){
            $tpm = (Get-WmiObject -Class Lenovo_BiosSetting -Namespace root\wmi | Where-Object Currentsetting -like "TpmFwSelection*" | Select-Object -ExpandProperty CurrentSetting)
            if ($tpm -eq "TpmFwSelection,Pluton"){
                Write-Warning "The device TPM chip is configured to Microsoft Pluton, this mode is known to cause issues with the stability of the device."
                Start-Sleep 1
            }
        }
    }
}

function DownloadWindowsUpdates {
    Write-Host "Updating Windows"

    # Update Information
    $windowsCUID = "KB5016629" # Needs to be updated at each update
    $windowsCUStatus = Get-HotFix | Where-Object HotFixID -eq $windowsCUID | Select-Object -ExpandProperty HotFixID
    if ($cpuType -like "*arm*"){
        $WindowsCUName = "windows11-$($windowsCUID)-arm64.msu"
        $WindowsCULink = "https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2022/08/windows10.0-kb5016629-arm64_b1f23a9c0deedffc8f13b5c89d5dac77500e3b05.msu" # Needs to be updated at each update
    }
    else {
        $WindowsCUName = "windows11-$($windowsCUID)-x64.msu"
        $WindowsCULink = "https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/08/windows10.0-kb5016629-x64_5c835cd538774e6191bb98343231c095c7918a72.msu" # Needs to be updated at each update
    }
    $WindowsCUPath = "$scriptDir\Win11Patches\$WindowsCUName"

    # Checking if the CU is installed, download if needed and install
    if (!$windowsCUStatus){ 
        if (!(Test-Path -path $scriptDir\Win11Patches)){
            New-Item $scriptDir\Win11Patches -ItemType directory | Out-Null
        }   
        if (!(Test-Path -path $WindowsCUPath)){
            Write-Host "-> Downloading Windows Update $windowsCUID..."
            Invoke-WebRequest $WindowsCULink -OutFile $WindowsCUPath
        }
        Write-Host "-> Installing Windows Update $windowsCUID, this can take 30 minutes..."
        Start-Process -FilePath "wusa.exe" -ArgumentList "`"$WindowsCUPath`" /quiet /norestart" -Wait
    }

    Write-Host "Windows needs to restart to apply the update, please re-run the script to complete process." -ForegroundColor Yellow
    pause
    shutdown -r -f -t 0
}

function ConfigureWindowsEdition {
    $osEdition = (Get-WindowsEdition -Online).Edition
    $armNetwork = Test-Connection -ComputerName gb-reh-kms.arm.com -Quiet -Count 1

    if ($osEdition -like "Home"){
        Write-Host "Error: Windows Home edition is not supported." -ForegroundColor Red
        exit 1
    }

    Write-Host "Activating Windows"
    cscript.exe c:\windows\system32\slmgr.vbs /upk | Out-null
    cscript.exe c:\windows\system32\slmgr.vbs /ipk NPPR9-FWDCX-D2C8J-H872K-2YT43 | Out-null
    cscript.exe c:\windows\system32\slmgr.vbs /skms gb-reh-kms.arm.com:1688 | Out-null
    cscript.exe c:\windows\system32\slmgr.vbs /ato | Out-null

    if (-not $armNetwork){
        Write-Host "Warning: Unable to reach Arm KMS server, Windows will be activated later." -ForegroundColor yellow
    }
}

function GetGroupTag {
    # Checking Build parameter strings
    if ($build) {
        foreach ($groupTag in $groupTagList){
            if ($groupTag -eq $build){
                # Kiosk build
                if ($groupTag -eq "Kiosk"){
                    $kioskBuild = ""
                    while ($kioskBuild -eq ""){
                        $kioskBuild = Read-Host "Please enter the name of the Kiosk build: $kioskBuildList"
                    }
                    return $kioskBuild
                }
                return $groupTag
            }
        }
        Write-Host "Error: Unrecognized build name $($build)." -ForegroundColor Red
        Write-Host "Available secure builds: $groupTagList" -ForegroundColor Red
        exit 1
    }

    # Non-Admin build
    if ($nonAdmin){
        $machineType = (Get-WmiObject -Class Win32_ComputerSystem).Model
        if ($machineType -like "*virtual*" -or $machineType -eq "VMware7,1"){
            return $groupTag = "VM-NonAdmin"
        }
        elseif ($cpuType -like "*arm*"){
            $Model = (Get-WMIObject -class Win32_ComputerSystem).model
            if (($Model -like "21BY*") -or ($Model -like "21BX*")){
                return $groupTag = "WoA-X13s-NonAdmin"
            }
            else {
                return $groupTag = "WoA-NonAdmin"
            }
        }
        else {
            return $groupTag = "Intel-NonAdmin"
        }
    }

    # Set Automatic GroupTag
    if ($machineType -like "*virtual*" -or $machineType -eq "VMware7,1"){
        return $groupTag = "VM"
    }
    elseif ($cpuType -like "*arm*"){
        $Model = (Get-WMIObject -class Win32_ComputerSystem).model
        if (($Model -like "21BY*") -or ($Model -like "21BX*")){
            return $groupTag = "WoA-X13s"
        }
        return $groupTag = "WoA"
    }
    else {
        return $groupTag = "Intel"
    }
}

function DownloadAutopilotScript {
    Write-Host "Downloading Autopilot script"
    Install-PackageProvider NuGet -Force | Out-null
    if ($debug){
        Install-Script -Name Get-AutopilotDiagnostics -Confirm:$False -force
    }
    else {
        Install-Script -Name Get-WindowsAutoPilotInfo -Confirm:$False -Force
    }
}

function RunEnrollmentScript {
    $scriptPath = $env:ProgramFiles +"\WindowsPowerShell\Scripts\Get-WindowsAutoPilotInfo.ps1"

    if ($csv -or (($cpuType -like "*arm*"))){
        Invoke-Expression "& `"$scriptPath`" -OutputFile C:\$($serial)_DeviceHash.csv -GroupTag $groupTag"
        Write-Host "Autopilot file generated `"C:\$($serial)_DeviceHash.csv`" with GroupTag $($groupTag)." -ForegroundColor Green
        explorer C:\
    }
    else {
            Invoke-Expression "& `"$scriptPath`" -GroupTag $groupTag -Online"
            Write-Host "$serial imported with GroupTag $($groupTag). Please wait a few minutes for Intune to assign the profile..." -ForegroundColor Green
    }
}

function RunDebugScript {
    mkdir c:\temp -force | Out-Null
    if (Test-Path C:\Windows\Sysnative\winevt\Logs\Application.evtx){$systemPath = "Sysnative"} else {$systemPath = "System32"}
    Write-Host "Generating logs, please wait"
    $DiagPath = "C:\Windows\$($systemPath)\MdmDiagnosticsTool.exe"
    $DiagParam = "-area `"Autopilot;Tpm;DeviceProvisioning`" -cab C:\temp\$($serial)_AutopilotDiag.cab"
    Invoke-Expression "$DiagPath $DiagParam" | Out-Null
    Copy-Item "C:\Windows\$($systemPath)\winevt\Logs\Application.evtx" -Destination "C:\temp\$($serial)_Application.evtx" | Out-Null
    
    if (($cpuType -like "*arm*") -and ($osVersion -lt "22000")){
        Copy-Item "C:\Windows\$($systemPath)\winevt\Logs\System.evtx" -Destination "C:\temp\$($serial)_System.evtx" | Out-Null
        Copy-Item "C:\Windows\$($systemPath)\winevt\Logs\Microsoft-Windows-AAD%4Operational.evtx" -Destination "C:\temp\$($serial)_Microsoft-Windows-AAD%4Operational.evtx" | Out-Null
        Copy-Item "C:\Windows\$($systemPath)\winevt\Logs\Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider%4Admin.evtx" -Destination "C:\temp\$($serial)_Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider%4Admin.evtx" | Out-Null
        Copy-Item "C:\Windows\$($systemPath)\winevt\Logs\Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider%4Autopilot.evtx" -Destination "C:\temp\$($serial)_Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider%4Autopilot.evtx" | Out-Null
        Copy-Item "C:\Windows\$($systemPath)\winevt\Logs\Microsoft-Windows-ModernDeployment-Diagnostics-Provider%4Admin.evtx" -Destination "C:\temp\$($serial)_Microsoft-Windows-ModernDeployment-Diagnostics-Provider%4Admin.evtx" | Out-Null
        Copy-Item "C:\Windows\$($systemPath)\winevt\Logs\Microsoft-Windows-ModernDeployment-Diagnostics-Provider%4Autopilot.evtx" -Destination "C:\temp\$($serial)_Microsoft-Windows-ModernDeployment-Diagnostics-Provider%4Autopilot.evtx" | Out-Null
    }
    else {
        $ScriptDebugPath = $env:ProgramFiles +"\WindowsPowerShell\Scripts\Get-AutopilotDiagnostics.ps1"
        Invoke-Expression "& `"$ScriptDebugPath`" *> C:\temp\$($serial)_DeviceDebug.txt"
    }

    Write-Host "Debug files generated:" -ForegroundColor Green
    Write-Host "-> C:\temp\$($serial)_AutopilotDiag.cab"
    Write-Host "-> C:\temp\$($serial)_Application.evtx"
    if (($cpuType -like "*arm*") -and ($osVersion -lt "22000")){
        Write-Host "-> C:\temp\$($serial)_System.evtx"
        Write-Host "-> C:\temp\$($serial)_Microsoft-Windows-AAD%4Operational.evtx"
        Write-Host "-> C:\temp\$($serial)_Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider%4Admin.evtx"
        Write-Host "-> C:\temp\$($serial)_Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider%4Autopilot.evtx"
        Write-Host "-> C:\temp\$($serial)_Microsoft-Windows-ModernDeployment-Diagnostics-Provider%4Admin.evtx"
        Write-Host "-> C:\temp\$($serial)_Microsoft-Windows-ModernDeployment-Diagnostics-Provider%4Autopilot.evtx"
    }
    else{
        Write-Host "-> C:\temp\$($serial)_DeviceDebug.txt"
    }
    explorer C:\temp
}

# Script
Clear-Host

if ($debug){
    Write-Host "-- Autopilot Script Version $($scriptVersion) DEBUG --" -ForegroundColor Yellow
    Write-Host "For additional commands about builds, debug or options type: Get-Help .\AutoPilot_Capture_$($scriptVersion).ps1"
    CheckPrerequisite
    DownloadAutopilotScript
    RunDebugScript
}
Else {
    Write-Host "-- Autopilot Script Version $($scriptVersion) --" -ForegroundColor Cyan
    Write-Host "For additional commands about builds, debug or options type: Get-Help .\AutoPilot_Capture_$($scriptVersion).ps1"
    CheckPrerequisite
    $groupTag = GetGroupTag
    ConfigureWindowsEdition
    if ($preReq){Write-Host "-- Ending --"; exit 0}
    DownloadAutopilotScript
    RunEnrollmentScript
}

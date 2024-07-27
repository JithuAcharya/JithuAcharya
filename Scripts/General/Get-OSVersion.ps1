# Get Os Version
param (
    [Parameter(Mandatory)][String] $fullPath,
    [Switch] $csv
)

# Pre-requisites
$requiredModules = "Microsoft.Graph.DeviceManagement", "Microsoft.Graph.Identity.DirectoryManagement", "Microsoft.Graph.Authentication"
foreach ($module in $requiredModules) {
    Import-Module $module | Out-Null
    if (!(get-module $module)) {
        Write-Warning "Microsoft Graph $module Module missing!"
        Install-Module $module -SkipPublisherCheck -Force
        Import-Module $module | Out-Null
    }
}


Import-Module Microsoft.Graph.DeviceManagement -ErrorAction SilentlyContinue | Out-Null
if (!(get-module Microsoft.Graph.DeviceManagement)) {write-warning "Microsoft Graph Microsoft.Graph.DeviceManagement Module missing" ; install-module Microsoft.Graph.DeviceManagement ; Import-Module Microsoft.Graph.DeviceManagement | Out-Null}
if (!(get-module Microsoft.Graph.Identity.DirectoryManagement)) {write-warning "Microsoft Graph Microsoft.Graph.Identity.DirectoryManagement Module missing" ; install-module Microsoft.Graph.Identity.DirectoryManagement ; Import-Module Microsoft.Graph.Identity.DirectoryManagement | Out-Null}

Connect-MgGraph

# Variables
$targetedHostnames = get-content $fullPath
$scriptDir = Split-Path $script:MyInvocation.MyCommand.Path

# Script
Write-Host "$($targetedHostnames.count) devices will be checked"

Write-Host "Getting device data, this can take a few minutes..."
if ($allDevices.count -le 3500) {
    $allDevices = Get-MgDevice -Filter "(OperatingSystem eq 'Windows') and (TrustType eq 'AzureAD')" -all | Where-Object ApproximateLastSignInDateTime -ge $lastSignInDate -ErrorAction Stop 
}

if ($csv){
    "Hostname,OSVersion,ApproximateLastSignInDateTime" > "$($scriptDir)\Device-OSVersion.csv"
}
else {
    Write-Host "Hostname,OSVersion,ApproximateLastSignInDateTime"
}
foreach ($hostname in $targetedHostnames) {
    $device = $alldevices | Where-Object DisplayName -eq "$hostname"
    if (($device.Id) -and ($device.DisplayName.Count -eq 1)) {
        if ($csv){
            "$($device.DisplayName),$($device.OperatingSystemVersion),$($device.ApproximateLastSignInDateTime)" >> "$($scriptDir)\Device-OSVersion.csv"
        }
        else {
            Write-Host "$($device.DisplayName),$($device.OperatingSystemVersion),$($device.ApproximateLastSignInDateTime)"
        }
    }
    else {
        $unkownIds += $hostname
    }
}

if ($csv){
    Write-host "CSV file created: $($scriptDir)\Device-OSVersion.csv"
    Start-Process explorer.exe -ArgumentList $($scriptDir)
}

if ($unkownIds.count -gt 0) {
    Write-Warning "$($unkownIds.count) device(s) were not found"
    $unkownIds
}

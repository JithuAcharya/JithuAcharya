# Get Cloud PC Restart Actions
param (
    [Parameter(Mandatory)][String] $policyName,
    [Switch] $csv
)

# Prerequisites
$requiredModules = "Microsoft.Graph.Beta.DeviceManagement.Administration", "Microsoft.Graph.Beta.DeviceManagement.Functions", "Microsoft.Graph.Authentication"
foreach ($module in $requiredModules) {
    Import-Module $module -ErrorAction SilentlyContinue
    if (!(get-module $module)) {
        Write-Warning "Microsoft Graph $module Module missing!"
        Install-Module $module -SkipPublisherCheck -Force
        Import-Module $module | Out-Null
    }
}

# Variables
$scriptDir = Split-Path $script:MyInvocation.MyCommand.Path

# Script
Connect-MgGraph
$CPCDevices = Get-MgBetaDeviceManagementVirtualEndpointCloudPc -Filter "servicePlanType eq 'enterprise'" | Where-Object ProvisioningPolicyName -like "*$policyName*" | Select-Object ManagedDeviceId,ManagedDeviceName, ProvisioningPolicyName, UserPrincipalName
Write-Host "Getting device data for $($CPCDevices.count) Cloud PCs, please wait..."
Write-Host "Only Cloud PC that have done a restart will be displayed!"
if ($csv){
    "ManagedDeviceName,LastRestartDate,EmailAddress" > "$($scriptDir)\CPCRestart-$($policyName).csv"
}
else {
    Write-Host "ManagedDeviceName,LastRestartDate,EmailAddress"
}
foreach ($device in $CPCDevices) {
    $restartStatus = $false
    $restartStatus = Get-MgBetaDeviceManagementManagedDeviceCloudPcRemoteActionResult -ManagedDeviceId $device.ManagedDeviceId | Where-Object ActionName -eq "Restart"
    if ($restartStatus) {
        foreach ($restart in $restartStatus){
            if ($csv){
                "$($device.ManagedDeviceName),$((get-date $restart.StartDateTime).ToString("dd/MM/yyyy")),$($device.UserPrincipalName)" >> "$($scriptDir)\CPCRestart-$($policyName).csv"
            }
            else {
                Write-Host "$($device.ManagedDeviceName),$((get-date $restart.StartDateTime).ToString("dd/MM/yyyy")),$($device.UserPrincipalName)"
            }
        }
    }
}

if ($csv){
    Write-host "CSV file created: $($scriptDir)\CPCRestart-$($policyName).csv"
    Start-Process explorer.exe -ArgumentList $($scriptDir)
}

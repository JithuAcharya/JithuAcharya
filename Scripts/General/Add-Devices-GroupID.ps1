param
(
    [Parameter(Mandatory)][String] $groupID,
    [Parameter(Mandatory)][String] $fullPath
)

# Pre-requisites
Import-Module Microsoft.Graph.DeviceManagement -ErrorAction SilentlyContinue | Out-Null
if (!(get-module Microsoft.Graph.DeviceManagement)) {write-warning "Microsoft Graph Module missing" ; install-module Microsoft.Graph.DeviceManagement ; Import-Module Microsoft.Graph.DeviceManagement | Out-Null}

Connect-MgGraph

# Variables
$targetedHostnames = get-content $fullPath
$lastSignInDate = ((Get-Date).AddDays(-90)).ToUniversalTime()
$groupMembers = (Get-MgGroupMember -All -GroupId $groupID)
$groupName = (Get-MgGroup -GroupId $groupID).DisplayName
$unkownIds = @()
$newMembers = 0

Write-Host "Adding $($targetedHostnames.count) devices to $groupName"
Pause

# Script
Write-Host "Getting device data, this can take a few minutes..."
if ($allDevices.count -le 3500) {
    $allDevices = Get-MgDevice -Filter "(OperatingSystem eq 'Windows') and (TrustType eq 'AzureAD')" -all | Where-Object ApproximateLastSignInDateTime -ge $lastSignInDate -ErrorAction Stop | Select-Object DisplayName,ApproximateLastSignInDateTime,Id
}

foreach ($targetedHostname in $targetedHostnames) {
    $isMember = $false
    $device = $alldevices | Where-Object DisplayName -eq "$targetedHostname"
    :groupCheck foreach ($groupMember in $groupMembers) {
        if ($groupMembers.Id -eq $device.Id) {
            Write-Warning "$($device.DisplayName) is already a member of $groupName"
            $isMember = $true
            break groupCheck
        }
    }
    if (!($isMember)) {
        if (($device.Id) -and ($device.DisplayName.Count -eq 1)) {
            Write-Host "Adding $($device.DisplayName) to $groupName"
            New-MgGroupMember -GroupId $groupID -DirectoryObjectId $device.Id
            $newMembers = $newMembers + 1
        }
        else {
            Write-Warning "$targetedHostname ID wasn't found, unable to add to $groupName"
            $unkownIds += $targetedHostname
        }
    }
}

if ($unkownIds) {
    Write-Host "The following devices were not added to $groupName"
    $unkownIds
}

Write-Host "$newMembers device(s) were added to $groupName"

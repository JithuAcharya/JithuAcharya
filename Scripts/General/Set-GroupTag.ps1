param
(
    [String] $file
)

# Variables
$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
if (!$file) {
    $deviceList = Read-Host "Specify the device list"
    if (!(Test-Path $ScriptDir\$($deviceList))){
        Write-Output "No source file named $deviceList detected in $ScriptDir"
        exit 1
    }
}
else {
    $deviceList = $file
    if (!(Test-Path $ScriptDir\$($deviceList))){
        Write-Output "No source file named $deviceList detected in $ScriptDir"
        exit 1
    }
}
Connect-MSGraph | Out-Null
$sourceFile = Get-Content "$ScriptDir\$($deviceList)" -ErrorAction SilentlyContinue
Write-Host "Number of devices: $($sourceFile.Length)"
$groupTag = Read-Host "Group Tag"


# Script
foreach ($serial in $sourceFile){
    Write-Host "Updating $serial GroupTag to $groupTag"
    $autopilotEntry = (Get-AutopilotDevice -serial $serial)
    Set-AutopilotDevice -id $autopilotEntry.id -groupTag $groupTag
    if ($autopilotEntry.managedDeviceId -ne "00000000-0000-0000-0000-000000000000"){
        if (!$deleteIntuneEntries) {
            $deleteIntuneEntries = Read-Host "Do you want to delete the Intune entries (Y/N)"
        }
        elseif ($deleteIntuneEntries -eq "Y"){ 
            Write-Host "Removing Intune entry $($autopilotEntry.managedDeviceId)"
            Remove-IntuneManagedDevice -managedDeviceId $($autopilotEntry.managedDeviceId) -Verbose
        }
    }
}

# Required modules WindowsAutoPilotIntune, msgraph
param
(
    [String] $file
)

# Variables
$Date = Get-Date -Format "HH:mm_dd/MM/yyyy"
$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
if (!$file) {
    $deviceList = Read-Host "Specify the device list to remove from Autopilot"
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

Start-Transcript C:\temp\Autopilot_Removal_$Date.log

# Script
Connect-MSGraph
$sourceFile = Get-Content "$ScriptDir\$($deviceList)" -ErrorAction SilentlyContinue
Write-Host "Number of devices: $($sourceFile.Length)"
Pause

# Script
foreach ($serial in $sourceFile){
    $autopilotEntry = (Get-AutopilotDevice -serial $serial)
    if ($autopilotEntry.managedDeviceId -ne "00000000-0000-0000-0000-000000000000"){
        Write-Host "Removing Intune entry $($autopilotEntry.managedDeviceId)"
        Remove-IntuneManagedDevice -managedDeviceId $($autopilotEntry.managedDeviceId)
        Start-Sleep 2
    }
    Write-Host "Deleting Autopilot pilot entry $($autopilotEntry.id), Serial $serial"
    Remove-AutopilotDevice -id $autopilotEntry.id
    start-Sleep 5
}

Stop-Transcript

# Required modules WindowsAutoPilotIntune, msgraph
param
(
    [String] $file
)

# Variables
$date = Get-Date -Format "HH:mm_dd/MM/yyyy"
$scriptDir = Split-Path $script:MyInvocation.MyCommand.Path
if (!$file) {
    $deviceList = Read-Host "Specify the device list containing the serial number to get the enrollment date"
    if (!(Test-Path $scriptDir\$($deviceList))){
        Write-Output "No source file named $deviceList detected in $scriptDir"
        exit 1
    }
}
else {
    $deviceList = $file
    if (!(Test-Path $scriptDir\$($deviceList))){
        Write-Output "No source file named $deviceList detected in $scriptDir"
        exit 1
    }
}

# Script
Connect-MSGraph
$sourceFile = Get-Content "$scriptDir\$($deviceList)" -ErrorAction SilentlyContinue
Write-Host "Number of devices: $($sourceFile.Length)"
Pause

# Script
foreach ($serial in $sourceFile){
    $deviceAutopilotEntry = (Get-AutopilotDevice -serial $serial)
    $deviceEnrollmentDate = Get-IntuneManagedDevice -managedDeviceId $deviceAutopilotEntry.managedDeviceId
    Write-Host "$serial,$($deviceEnrollmentDate.enrolledDateTime)" > "$scriptDir\Autopilot_EnrollmentDate_$date"
}

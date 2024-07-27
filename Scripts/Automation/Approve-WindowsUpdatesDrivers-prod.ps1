######## Graph Auth ########
Connect-MgGraph -Identity

######## Variables ########
$startScriptTime = (Get-Date).TimeOfDay

$updateRing = 3
$driversCategory = "recommended" #, "other"
$driversClass = "SoftwareComponent","Bluetooth","System Manifest","System","Biometric","OtherHardware","Monitor","Networking","Firmware","Video","Camera","Sound","HIDClass","Printers","Other"

######## Script ########
# Get the date of the next Monday after the 2nd Tuesday of the next month
$nextMonth = (Get-Date).AddMonths(1)
$firstDayOfNextMonth = Get-Date -Day 1 -Month $nextMonth.Month -Year $nextMonth.Year
$thirdMondayOfNextMonth = $firstDayOfNextMonth.AddDays(((8 - $firstDayOfNextMonth.DayOfWeek) % 7) + 14)
$deploymentDelay = $thirdMondayOfNextMonth.ToString("yyyy-MM-ddTHH:mm:ss.fffffffzzz")

Write-Output "Drivers deployment date: $deploymentDelay"
Write-Output "------------"

# Get profiles IDs
$profileIds = @()
$driversProfiles = (Invoke-GraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles").Value
foreach ($driversprofile in $driversProfiles) {
    if ($driversprofile.displayName-like "Windows-global-config-SecurityUpdates-Ring-$($updateRing)-Drivers*") {
        $profileIds += $driversProfile.id
    }
}

# Get drivers ID to approve
foreach ($profileId in $profileIds){
    $driverCount = 0
    $driversIDToAppprove = @()
    $driversNameToAppprove = @()
    $allDrivers = @()

    # Display the Name of the profile
    $driverProfile = Invoke-GraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles/$profileId"
    Write-Output "Drivers Profile: $($driverProfile.displayName)"
    
    $graphRequest = Invoke-GraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles/$profileId/driverInventories"
    $allDrivers += $graphRequest.value
    
    # Check if there is a next page link
    while ($null -ne $graphRequest.'@odata.nextLink') {
        $skipToken = $graphRequest.'@odata.nextLink'.Split('=')[-1]
        $graphRequest = Invoke-GraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles/$profileId/driverInventories?`$skiptoken=$skipToken"
        $allDrivers += $graphRequest.value
    }

    foreach ($entry in $allDrivers) {
        if (($driversClass -contains $entry.driverClass) -and ($driversCategory -contains $entry.category)){
            if ($entry.approvalStatus -eq "needsReview" ) {
                $driversIDToAppprove += $($entry.id).ToString()
                $driversNameToAppprove += $($entry.name).ToString()
                $driverCount = 1 + $driverCount
            }
        }
    }

    # Approve drivers
    if ($driverCount -gt 0){
        Write-Output "> Approving $driverCount driver(s)"
        foreach ($driveName in $driversNameToAppprove){
            Write-Output "-> $driveName"
        }

        # Splitting by chunk of 100 due to POST limitation
        $chunkSize = 100
        $chunksDriversIDToAppprove = New-Object System.Collections.ArrayList

        for ($i = 0; $i -lt $driversIDToAppprove.Count; $i += $chunkSize) {
            $chunkDriversID = $driversIDToAppprove[$i..($i+$chunkSize-1)]
            $chunksDriversIDToAppprove.Add($chunkDriversID) > $null
        }

        foreach ($chunkDriversID in $chunksDriversIDToAppprove) {
            $body = @{
                actionName = "approve" # OR "Suspend"
                driverIds = $chunkDriversID
                deploymentDate = $deploymentDelay
            } | ConvertTo-Json
            # Approving drivers
            Invoke-GraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles/$profileId/executeAction" -Body $body -ContentType "application/json"
        }
    }
    else{
        Write-Output "--> No drivers to approve"
    }
}

$endScriptTime = (Get-Date).TimeOfDay
Write-Output "Execution time: $($endScriptTime - $startScriptTime)"

<#  EXAMPLE
id                             b84af8e5161c83f7759b95e86998feb4fa01fabbbfc4094079441ecff7b211b8_f34e5979-57d9-4aaa-ad4d-b122a662184d
applicableDeviceCount          1
approvalStatus                 needsReview / suspended
category                       recommended / other
version                        11.0.6000.273
deployDateTime                 1/1/0001 12:00:00 AM
driverClass                    OtherHardware
manufacturer                   Logitech
releaseDateTime                8/29/2018 2:05:21 PM
name                           Logitech - Streaming Media and Broadcast - Logitech USB Camera (Pro 9000)
#>

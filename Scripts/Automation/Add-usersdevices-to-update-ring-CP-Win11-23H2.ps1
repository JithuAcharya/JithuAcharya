######## Graph Auth ########
Connect-MgGraph -Identity

######## Variables ########
$appid = "8f27cae4-2d26-457e-a2b7-875ff7e97172" # Change me - Target application ID
$targetGroupID = "5b301da5-0a82-4e71-b041-d7d8eba9520b" # Change me - Target device group ID
$appVersion = "23H2" # Change me - File name

$uri = "https://graph.microsoft.com/beta/deviceManagement/reports/getDeviceInstallStatusReport"
$outputFilePath = "$env:TEMP\AppReport\queryDevices_$($appVersion).txt"
$alldevicesFilePath = "$env:TEMP\AppReport\allDevices_$($appVersion).txt"

# Init stats
$resultDeviceAdded = 0
$resultDeviceAlreadyAdded = 0
$allDevices = 0
$missingHostnames = @()

# Clean previous run
New-Item -Path $env:TEMP -Name "AppReport" -ItemType "directory" -Force | Out-Null
Remove-Item -Path $outputFilePath -Force -ErrorAction SilentlyContinue
Remove-Item -Path $alldevicesFilePath -Force -ErrorAction SilentlyContinue

$startScriptTime = (Get-Date).TimeOfDay

######## Functions ########
function Get-DeviceID {
    param (
        [Parameter(Mandatory)] $hostname 
    )
    # Return one device id based on exact hostname and last login
    return ($alldevices | Where-Object DisplayName -eq "$hostname" | Select-Object -First 1).Id
}

function Get-AppInstallDeviceList {
    param (
        [Parameter(Mandatory)] $appid,
        $skip
    )
$json = @"
{
    "select": [
        "DeviceName"
    ],
    "skip": $(if (!$skip) {"0"} else {$skip}),
    "top": 50,
    "filter": "(InstallState eq '1') and (ApplicationId eq '$appid')",
    "orderBy": []
}
"@
    Invoke-MgGraphRequest -uri $uri -body $json -method POST -ContentType "application/json" -OutputFilePath $outputFilePath
    # Return device list in a formated way
    return (Get-Content $outputFilePath | ConvertFrom-Json)
}

######## Script ########
try{
    # Get target group information
    $targetGroupIDName = (Get-MgGroup -GroupId $targetGroupID).DisplayName
    $targetGroupIDMembers = (Get-MgGroupMember -All -GroupId $targetGroupID)

    # Get application information
    $appName = (Invoke-MgGraphRequest -Method Get -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=id eq `'$appid`'&`$select=displayName").Values.DisplayName
   
    Write-Output "Target application: $appName"
    Write-Output "Targeted group: $targetGroupIDName"
    Write-Output "------"
    
    # Get all active devices with their IDs to limit the numbers of graph queries
    $lastSignInDate = ((Get-Date).AddDays(-30)).ToUniversalTime()
    Write-Output "Downloading active device data, this can take a few minutes..."
    $allDevices = Get-MgDevice -Filter "(OperatingSystem eq 'Windows') and (TrustType eq 'AzureAD')" -all | Where-Object ApproximateLastSignInDateTime -ge $lastSignInDate -ErrorAction Stop | Select-Object DisplayName,ApproximateLastSignInDateTime,Id
    if ($allDevices.count -le 1) {Write-Error "No device found."} 
    
    # Initial query to get the number of pages
    $deviceQueryResult = Get-AppInstallDeviceList -appid $appid
    if ($deviceQueryResult.TotalRowCount -eq 0) {Write-Error "No device found, exiting" ; exit 1}
    $currentpage = 0
    $totalPages = [math]::ceiling($deviceQueryResult.TotalRowCount / 50)
    
    Write-Output "Total app pages: $totalPages"
    
    # We start at page 0 in graph, Intune UI starts at 1
    while ($currentpage -lt $totalPages) {
        $skip = $currentpage * 50
        # Write-Output "Debug - page: $currentpage, skip: $skip"
        $deviceQueryResult = Get-AppInstallDeviceList -appid $appid -skip $skip
        $deviceQueryResult.Values >> $alldevicesFilePath
        $currentpage = $currentpage + 1
    }

    # Get all devices with the application installed
    $devicesAppInstalled = Get-Content $alldevicesFilePath
    Write-Output "Device(s) with the application installed: $(($devicesAppInstalled).count)"
    Write-Output "------"

    # Parse all devices found
    foreach ($hostname in $devicesAppInstalled) {
        $deviceId = $null
        $DeviceFound = $false
        $deviceId = Get-DeviceID $hostname

        if ($deviceID) {
            # Check if the device is already a member of the update group
            foreach ($GroupIDMember in $targetGroupIDMembers) {
                if ($deviceID -eq $GroupIDMember.id) {
                    # Device is already in the group, we flag it so it's not added
                    $DeviceFound = $true
                    $resultDeviceAlreadyAdded = $resultDeviceAlreadyAdded + 1
                    Write-Output "$hostname is already in the Feature Update group, skipping..."
                    break
                }
            }

            # Adding the device to the AAD group if it is missing
            if(!$DeviceFound) {
                Write-Output "Adding $hostname with Entra ID $deviceID to $targetGroupIDName"
                New-MgGroupMember -GroupId $targetGroupID -DirectoryObjectId $deviceID -Verbose
                $resultDeviceAdded = $resultDeviceAdded + 1
            }
        }
        else {
            $missingHostnames += $hostname
        }
    }
    Write-Output "------"
    Write-Output "Device(s) added: $resultDeviceAdded"
    Write-Output "Device(s) already in the group: $resultDeviceAlreadyAdded"
    if ($missingHostnames) {Write-Output "Device missing/not found: $missingHostnames"}
    Write-Output "------"
    $endScriptTime = (Get-Date).TimeOfDay
    Write-Output "Execution time: $($endScriptTime - $startScriptTime)"
}
catch {
    # An error occured during the script, we return exit 1
    Write-Output "Error: $($_.Exception.Message)"
    exit 1
}

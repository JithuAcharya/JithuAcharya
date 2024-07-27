param
(
    [Parameter(Mandatory)][String] $appName,
    [String] $lastSync,
    [ValidateSet('Windows','iOS','Android',IgnoreCase)]
    [String] $operatingSystem,
    [Switch] $csv,
    [Switch] $ExactAppName
)

# Variables
if (!$appName) { $appName = Read-Host "Enter the name of the application" }
if (!$lastSync) { $lastSync = 30 } 
if (!$operatingSystem) { $operatingSystem = "Windows" }

$lastSyncDate = (Get-Date).AddDays(-$lastSync)
$lastSyncDateISO = (Get-date $lastSyncDate -Format "o")
$totalInstalled = 0
$appFailures = @()

# Pre-requisites
Import-Module Microsoft.Graph.DeviceManagement -ErrorAction SilentlyContinue | Out-Null
if (!(get-module Microsoft.Graph.DeviceManagement)) {write-warning "Microsoft Graph Module missing" ; install-module Microsoft.Graph.DeviceManagement ; Import-Module Microsoft.Graph.DeviceManagement | Out-Null}

Connect-MgGraph | Out-Null

# Script
if ($ExactAppName) {
    # Search applications with the exact name
    Write-Host "Searching $operatingSystem devices with $appName installed...."
    $appsFound = Get-MgDeviceManagementDetectedApp -Filter "displayName eq '$($appName)'"
}
else {
    # Search applications containing the name
    Write-Host "Searching $operatingSystem devices with an application containing the name $appName..."
    $appsFound = (Get-MgDeviceManagementDetectedApp -Filter "contains(displayName,'$($appName)')" -All)
}

$allActiveDevices = Get-MgDeviceManagementManagedDevice -Filter "OperatingSystem eq '$($operatingSystem)'" -All | Where-Object LastSyncDateTime -ge $lastSyncDateISO

if ($appsFound) {
    if ($csv) { 
        Write-Host "AppName,AppVersion,AppId,AppInstalls"
        Write-Output "Hostname,EmailAddress,LastSync,Application,Version" > "$($PSScriptRoot)\$($appName)_$($operatingSystem).csv"
    }
    else {
        Write-Host "Hostname,EmailAddress,LastSync,Application,Version"
    }
    foreach ($app in $appsFound) {
        # Get devices with the app
        $retry = 0
        $devicesAppFound = (Get-MgDeviceManagementDetectedAppManagedDevice -DetectedAppId $app.id -All -ErrorAction SilentlyContinue)
        :deviceCountLoop while ($devicesAppFound.count -eq 0) {
            $retry = $retry + 1
            Start-Sleep 5
            Write-Host "Retrying $($app.DisplayName),$($app.Version),$($app.Id)..."
            $devicesAppFound = (Get-MgDeviceManagementDetectedAppManagedDevice -DetectedAppId $app.id -All -ErrorAction SilentlyContinue)
            if ($retry -eq 5) {
                $appFailures += $app.id
                Write-Warning "The application id $($app.id) didn't returned any computers in the last 5 attempts, skipping..."
                Break deviceCountLoop
            }
        }

        # Show progress for csv switch
        if ($csv) {
            Write-Host "$($app.DisplayName),$($app.Version),$($app.Id),$($devicesAppFound.count)"
        }
        
        # filter devices based on the last sync
        foreach ($deviceApp in $devicesAppFound){
            foreach ($device in $allActiveDevices) {
                if ($device.id -eq $deviceApp.Id) {
                    if ($csv) { 
                        # we do not show the hostnames in the prompt when using the csv switch
                        Write-Output "$($device.DeviceName),$($device.EmailAddress),$(Get-date $($device.LastSyncDateTime)),$($app.DisplayName),$($app.Version)" >> "$($PSScriptRoot)\$($appName)_$($operatingSystem).csv" 
                    }
                    else {
                        Write-Host "$($device.DeviceName),$($device.EmailAddress),$(Get-date $($device.LastSyncDateTime)),$($app.DisplayName),$($app.Version)"
                    }
                    $totalInstalled = $totalInstalled + 1
                    break
                }
            }
        }
    }
}
    
Write-Host "Total active devices ($($lastSync) days) with the app installed: $totalInstalled"
if ($appFailures) {
    Write-Warning "$($appFailures.count) apps failed to report computers:"
    foreach ($app in $appFailures){
        Write-Host "appID: $app"
    }
} 

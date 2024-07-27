######## Graph Auth ########
# Connect-MgGraph -Identity

######## Variables ########
$startScriptTime = (Get-Date).TimeOfDay

$DSSUsersGroupID = "2e186a4a-a491-4669-a26f-3422dd2550b1" # WindowsEnterpriseITPilotUsers
$DSSDevicesGroupID = "a195b79e-bc6a-4c5b-9928-9d3b9112e989" # MDM-Devices-DSS-Intel
$AutopilotDevicesGroupID = "94c6cf8b-bda4-481f-a63d-fcef126d2139" # MDM-AutoPilotDevices-Intel -- Used for device type filtering (Intel or WoA)

$DSSUsersGroupMembers = (Get-MgGroupMember -All -GroupId $DSSUsersGroupID)
$DSSUsersGroupName = (Get-MgGroup -GroupId $DSSUsersGroupID).DisplayName
$DSSDevicesGroupMembers = (Get-MgGroupMember -All -GroupId $DSSDevicesGroupID | Select-Object * -ExpandProperty additionalProperties)
$DSSDevicesGroupName = (Get-MgGroup -GroupId $DSSDevicesGroupID).DisplayName

$AllAutopilotDevices = (Get-MgGroupMember -All -GroupId $AutopilotDevicesGroupID | Select-Object * -ExpandProperty additionalProperties)
$SiteDevicesDiscovered = @()

######## Script ########
try{
    Write-Output "---------"
    Write-Output "Checking users from AAD group: $DSSUsersGroupName"
    Write-Output "Targeted Azure AD group: $DSSDevicesGroupName"

    # Check all site users
    foreach ($SiteUser in $DSSUsersGroupMembers){
        Write-Output "Checking devices for $(($SiteUser | Select-Object * -ExpandProperty additionalProperties).mail)"
        $SiteUserDevices = (Get-MgUserOwnedDevice -UserId $SiteUser.id | Select-Object * -ExpandProperty additionalProperties)
        # Check all user devices
        foreach ($UserDevice in $SiteUserDevices){
            # Verify that the device is with the correct OS and still active
            if (($UserDevice.operatingSystem -eq "Windows") -and ($UserDevice.approximateLastSignInDateTime -gt ((Get-Date).adddays(-90).ToUniversalTime().ToString("o")))) {
                $UserDeviceFound = $false
                $DeviceTypeMatch = $false
                foreach ($AutopilotDevice in $AllAutopilotDevices.deviceId){
                    if ($UserDevice.deviceId -eq $AutopilotDevice){
                        # Write-Host "Autopilot Device Found $($UserDevice.deviceId)" -ForegroundColor Cyan
                        $DeviceTypeMatch = $true
                        $SiteDevicesDiscovered = $SiteDevicesDiscovered + $UserDevice.deviceId
                        foreach ($SiteDevice in $DSSDevicesGroupMembers.deviceId){
                            # Getting existing devices from MDM-Devices-TOSG-XXX
                            if ($UserDevice.deviceId -eq $SiteDevice){
                                # Device is already in the group, we flag it so it's not added
                                $UserDeviceFound = $true
                                Write-Output "-> $($UserDevice.displayName) is already in the group, skipping..."
                                break
                            }
                        }
                    }
                }
                # Adding the device to the AAD group if it is missing
                if (!$UserDeviceFound -and $DeviceTypeMatch){
                    Write-Output "--> Adding $($UserDevice.displayName)..."
                    # Add-AzureADGroupMember -ObjectId $DSSDevicesGroupID -RefObjectId $UserDevice.id
                    $deviceObjectId = (Get-MgDevice -Filter "DeviceId eq '$($UserDevice.deviceId)'").Id
                    # New-MgGroupMember -GroupId $DSSDevicesGroupID -DirectoryObjectId $deviceObjectId
                }
            }
        }
    }

    # Only perform clean-up if we have discovered more than 0 devices
    Write-Output "---------"
    if ($($SiteDevicesDiscovered.count) -gt 0){
        Write-Output "Device Cleanup:"
        foreach ($SiteDevice in $DSSDevicesGroupMembers){
            $IsSiteDevice = $false
            foreach ($DeviceDiscovered in $SiteDevicesDiscovered){
                 if($SiteDevice.deviceId -eq $DeviceDiscovered){
                    # Device discovered, we don't delete it
                    $IsSiteDevice = $true
                    break
                }
            }
            if ($IsSiteDevice -eq $false){
                # No longer a device from the specified site
                Write-Output "Removing Device: $($SiteDevice.displayName)"
                $deviceObjectId = (Get-MgDevice -Filter "DeviceId eq '$($SiteDevice.deviceId)'").Id
                # Remove-MgGroupMemberByRef -GroupId $DSSDevicesGroupID -DirectoryObjectId $deviceObjectId
            }
        }
    }
    else{
        Write-Output "Error: No devices discovered, device clean up aborted!"
        # Execution time
        Write-Output "---------"
        $endScriptTime = (Get-Date).TimeOfDay
        Write-Output "Execution time: $($endScriptTime - $startScriptTime)"
        exit 1
    }

    # Execution time
    Write-Output "---------"
    $endScriptTime = (Get-Date).TimeOfDay
    Write-Output "Execution time: $($endScriptTime - $startScriptTime)"
}
catch{
    Write-Error "Error: $($_.Exception.Message)"
}

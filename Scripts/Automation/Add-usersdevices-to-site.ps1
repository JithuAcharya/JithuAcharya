######## Graph Auth ########
Connect-MgGraph -Identity

######## Variables ########
$startScriptTime = (Get-Date).TimeOfDay

# $SiteUsersGroupID = "04e58fa7-0898-4251-b2cc-e9514c58de6a" # Arm-all-SophiaAntipolis
$SiteUsersGroupID = "e0eb58fe-c829-4e45-8ea0-e3fb00abd07f" # MDM-Users-Jerome
$AutopilotDevicesGroupID = "830513f9-b0c4-478f-a7bc-7f711fa3ff2e" # MDM-Devices-TestAutomation-Autopilot
$SiteDevicesGroupID = "29204202-72a0-4535-a3db-e394bfba2e0f" # MDM-Devices-TestAutomation-Site

$SiteUsersGroupMembers = (Get-MgGroupMember -All -GroupId $SiteUsersGroupID)
$SiteUsersGroupName = (Get-MgGroup -GroupId $SiteUsersGroupID).DisplayName
$SiteDevicesGroupMembers = (Get-MgGroupMember -All -GroupId $SiteDevicesGroupID | Select-Object * -ExpandProperty additionalProperties)
$SiteDevicesGroupName = (Get-MgGroup -GroupId $SiteDevicesGroupID).DisplayName

$AllAutopilotDevices = (Get-MgGroupMember -All -GroupId $AutopilotDevicesGroupID | Select-Object * -ExpandProperty additionalProperties)
$SiteDevicesDiscovered = @()

######## Script ########
try{
    Write-Output "---------"
    Write-Output "Checking users from AAD group: $SiteUsersGroupName"
    Write-Output "Targeted Azure AD group: $SiteDevicesGroupName"

    # Check all site users
    foreach ($SiteUser in $SiteUsersGroupMembers){
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
                        foreach ($SiteDevice in $SiteDevicesGroupMembers.deviceId){
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
                    # Add-AzureADGroupMember -ObjectId $SiteDevicesGroupID -RefObjectId $UserDevice.id
                    $deviceObjectId = (Get-MgDevice -Filter "DeviceId eq '$($UserDevice.deviceId)'").Id
                    New-MgGroupMember -GroupId $SiteDevicesGroupID -DirectoryObjectId $deviceObjectId
                }
            }
        }
    }

    # Only perform clean-up if we have discovered more than 0 devices
    Write-Output "---------"
    if ($($SiteDevicesDiscovered.count) -gt 0){
        Write-Output "Device Cleanup:"
        foreach ($SiteDevice in $SiteDevicesGroupMembers){
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
                Remove-MgGroupMemberByRef -GroupId $SiteDevicesGroupID -DirectoryObjectId $deviceObjectId
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

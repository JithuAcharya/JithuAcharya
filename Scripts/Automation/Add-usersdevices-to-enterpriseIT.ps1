######## Graph Auth ########
Connect-MgGraph -Identity

######## Variables ########
$startScriptTime = (Get-Date).TimeOfDay

$EITUsersGroupID = "6469df06-3e78-4054-975b-c8377ccad7fb" # WindowsEnterpriseITPilotUsers
$EITDevicesGroupID = "09d447ca-8f43-4ef2-8f9c-e21dad6f4555" # MDM-Devices-EnterpriseIT-CloudPC
$AutopilotDevicesGroupID = "eaa76b19-bd4a-4cd1-b044-ee3d544adc0a" # MDM-Devices-Win365CloudPC-All -- Used for device type filtering (Intel or WoA)

$SiteUsersGroupMembers = (Get-MgGroupMember -All -GroupId $EITUsersGroupID)
$SiteUsersGroupName = (Get-MgGroup -GroupId $EITUsersGroupID).DisplayName
$SiteDevicesGroupMembers = (Get-MgGroupMember -All -GroupId $EITDevicesGroupID | Select-Object * -ExpandProperty additionalProperties)
$SiteDevicesGroupName = (Get-MgGroup -GroupId $EITDevicesGroupID).DisplayName

$AllAutopilotDevices = (Get-MgGroupMember -All -GroupId $AutopilotDevicesGroupID | Select-Object * -ExpandProperty additionalProperties)
$SiteDevicesDiscovered = @()

######## Script ########
try{
    Write-Output "---------"
    Write-Output "Checking users from AAD group: $SiteUsersGroupName"
    Write-Output "Targeted Azure AD group: $SiteDevicesGroupName"
    Write-Output "---------"

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
                    $deviceObjectId = (Get-MgDevice -Filter "DeviceId eq '$($UserDevice.deviceId)'").Id
                    # New-MgGroupMember -GroupId $EITDevicesGroupID -DirectoryObjectId $deviceObjectId
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
                # Remove-MgGroupMemberByRef -GroupId $EITDevicesGroupID -DirectoryObjectId $deviceObjectId
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

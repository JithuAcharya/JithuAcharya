######## Graph Auth ########
Connect-MgGraph -Identity

######## Variables ########
$startScriptTime = (Get-Date).TimeOfDay

$FeatureUpdateUserGroupID = "c950467c-c2fe-4820-934f-601a719f7e6e" # MDM-Users-TestAutomation-FeatureUdpdate
$FeatureUpdateUserGroupMembers = (Get-MgGroupMember -All -GroupId $FeatureUpdateUserGroupID)
$FeatureUpdateUserGroupName = (Get-MgGroup -GroupId $FeatureUpdateUserGroupID).DisplayName

$FeatureUpdateDeviceGroupID = "3c29afac-ba3b-4eaa-bf2d-e4523020dc81" # MDM-Devices-TestAutomation-FeatureUdpdate
$FeatureUpdateDeviceGroupMembers = (Get-MgGroupMember -All -GroupId $FeatureUpdateDeviceGroupID | Select-Object * -ExpandProperty additionalProperties)
$FeatureUpdateDeviceGroupName = (Get-MgGroup -GroupId $FeatureUpdateDeviceGroupID).DisplayName

$FeatureUpdateDeviceDiscovered = @()

######## Script ########
try{
    Write-Output "Checking members of $FeatureUpdateUserGroupName..."
    Write-Output "Targeted feature update group: $FeatureUpdateDeviceGroupName"

    foreach ($FeatureUpdateUserMember in $FeatureUpdateUserGroupMembers){
        Write-Output "---------"
        # Getting user devices
        Write-Output "Checking devices for $(($FeatureUpdateUserMember | Select-Object * -ExpandProperty additionalProperties).mail)"
        $FeatureUpdateUserDevices = (Get-MgUserOwnedDevice -UserId $FeatureUpdateUserMember.id | Select-Object * -ExpandProperty additionalProperties)
        foreach ($UserDevice in $FeatureUpdateUserDevices){
            # Verify that the device is with the correct OS and still active (90 days)
            if (($UserDevice.operatingSystem -eq "Windows") -and ($UserDevice.approximateLastSignInDateTime -gt ((Get-Date).adddays(-90).ToUniversalTime().ToString("o")))) {
                $UserDeviceFound = $false
                # Adding device to the list of discovered devices
                $FeatureUpdateDeviceDiscovered = $FeatureUpdateDeviceDiscovered + $UserDevice.deviceId
                foreach ($FeatureUpdateDevice in $FeatureUpdateDeviceGroupMembers.deviceId){
                    if ($UserDevice.deviceId -eq $FeatureUpdateDevice){
                        # Device is already in the group, we flag it so it's not added
                        $UserDeviceFound = $true
                        Write-Output "-> $($UserDevice.displayName) is already in the group, skipping..."
                        break
                    }
                }

                # Adding the device to the AAD group if it is missing
                if(!$UserDeviceFound){
                    Write-Output "--> Adding $($UserDevice.displayName)..."
                    $deviceObjectId = (Get-MgDevice -Filter "DeviceId eq '$($UserDevice.deviceId)'").Id
                    New-MgGroupMember -GroupId $FeatureUpdateDeviceGroupID -DirectoryObjectId $deviceObjectId
                }
            }
        }
    }

    # Only perform clean-up if we have discovered more than 0 device
    Write-Output "---------"
    if ($($FeatureUpdateDeviceDiscovered.count) -gt 0){
        Write-Output "Devices to remove from the feature update group:"
        foreach ($FeatureUpdateDevice in $FeatureUpdateDeviceGroupMembers){
            $IsFeatureUpdateDevice = $false
            foreach ($DeviceDiscovered in $FeatureUpdateDeviceDiscovered) {
                if($FeatureUpdateDevice.deviceId -eq $DeviceDiscovered){
                    # Device discovered, we don't delete it
                    $IsFeatureUpdateDevice = $true
                    break
                }
            }
            if ($IsFeatureUpdateDevice -eq $false){
                # Devices is no longer targeted by the new update
                Write-Output "Removing Device: $($FeatureUpdateDevice.displayName)"
                $NonFeatureUpdateDeviceHostnameId = (Get-MgDevice -Filter "DeviceId eq '$($FeatureUpdateDevice.deviceId)'").Id
                Remove-MgGroupMemberByRef -GroupId $FeatureUpdateDeviceGroupID -DirectoryObjectId $NonFeatureUpdateDeviceHostnameId
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

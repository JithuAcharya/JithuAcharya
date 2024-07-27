param
(
    [Parameter (Mandatory= $true)]
    [String] $UserEmail
)

######## Graph Auth ########
# Connect-MgGraph -Identity

######## Variables ########
$startScriptTime = (Get-Date).TimeOfDay

$FeatureUpdateUserGroupID = "30559e67-246b-46c3-b8f7-1108ce9d615b" # MDM-WindowsUpdate-Win11-22H2-Users
$FeatureUpdateUserGroupMembers = (Get-MgGroupMember -All -GroupId $FeatureUpdateUserGroupID)
$FeatureUpdateUserGroupName = (Get-MgGroup -GroupId $FeatureUpdateUserGroupID).DisplayName

$FeatureUpdateDeviceGroupID = "c01a0bb4-2d37-417d-8805-d83f0ce60ccc" # MDM-WindowsUpdate-Win11-22H2
$FeatureUpdateDeviceGroupMembers = (Get-MgGroupMember -All -GroupId $FeatureUpdateDeviceGroupID)
$FeatureUpdateDeviceGroupName = (Get-MgGroup -GroupId $FeatureUpdateDeviceGroupID).DisplayName

######## Script ########
try{
    # Adding user to the user group, used to monitor user devices during the weekly run
    $User = (Get-MgUser -UserId $UserEmail)
    $UserIsMemberOfFeatureUpdate = $false
    foreach ($UserGroupMember in $($FeatureUpdateUserGroupMembers).Id){
        if ($User.id -eq $UserGroupMember){
            # User is already in the group, we flag it so it's not added
            $UserIsMemberOfFeatureUpdate = $true
            Write-Output "$UserEmail is already in $FeatureUpdateUserGroupName, skipping..."
            break
        }
    }
    if(!$UserIsMemberOfFeatureUpdate){
        Write-Output "Adding $($UserEmail) to $FeatureUpdateUserGroupName..."
        # New-MgGroupMember -GroupId $FeatureUpdateUserGroupID -DirectoryObjectId $User.Id
    }

    Write-Output "Adding $UserEmail devices to $FeatureUpdateDeviceGroupName..."
    Write-Output "---------"
    # Getting user devices
    $UserDevices = (Get-MgUserOwnedDevice -UserId $User.id | Select-Object * -ExpandProperty additionalProperties)

    foreach ($UserDevice in $UserDevices){
        # Verify that the device is with the correct OS, still active (90 days) and is not a Cloud PC
        if (($UserDevice.operatingSystem -eq "Windows") -and ($UserDevice.approximateLastSignInDateTime -gt ((Get-Date).adddays(-90).ToUniversalTime().ToString("o"))) -and ($UserDevice.model -notlike "Cloud PC*")) {
            $UserDeviceFound = $false
            # Getting existing devices from MDM-FeatureUpdate-Group
            foreach ($DeviceGroupMember in $FeatureUpdateDeviceGroupMembers){
                if ($UserDevice.id -eq $DeviceGroupMember.id){
                    # Device is already in the group, we flag it so it's not added
                    $UserDeviceFound = $true
                    Write-Output "$($UserDevice.displayName) is already in the Feature Update group, skipping..."
                    break
                }
            }
            
            # Adding the device to the AAD group if it is missing
            if(!$UserDeviceFound){
                Write-Output "Adding $($UserDevice.displayName)..."
                $deviceObjectId = (Get-MgDevice -Filter "DeviceId eq '$($UserDevice.deviceId)'").Id
                # New-MgGroupMember -GroupId $FeatureUpdateDeviceGroupID -DirectoryObjectId $deviceObjectId
            }
        }
    }


    # Execution time
    Write-Output "---------"
    $endScriptTime = (Get-Date).TimeOfDay
    Write-Output "Execution time: $($endScriptTime - $startScriptTime)"
}
catch{
    Write-Error "Error: $($_.Exception.Message)"
}

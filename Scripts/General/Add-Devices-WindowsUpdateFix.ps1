param
(
    [String] $fileName
)
    
# Variables
$Date = Get-Date -Format "HH:mm_dd/MM/yyyy"
$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
$scriptGroupID =  "263e353c-232d-4bbb-87bd-836774b3a386" # MDM-Script-WindowsUpdateFix
$scriptGroupIDName = (Get-MgGroup -GroupId $scriptGroupID).DisplayName
$missingHostnames = @()
if (!$fileName) {
    $fileName = Read-Host "Specify the file containing the hostnames to add to Windows Update Fix script"
    if (!(Test-Path $ScriptDir\$($fileName)) -or (Test-Path $fileName)){
        Write-Error "No source file detected in: 
        -> $ScriptDir\$($fileName)
        -> $fileName"
        exit 1
    }
}
else {
    if ((Test-Path $ScriptDir\$($fileName))){
        $filePath = "$ScriptDir\$($fileName)"
    }
    elseif (Test-Path $fileName) {
        $filePath = $fileName
    }
}

Start-Transcript C:\temp\Intune_WindowsUpdateFix_$Date.log

# Script
$hostnameList = Get-Content "$filePath" -ErrorAction SilentlyContinue
Write-host "Adding $($hostnameList.count) devices to $($scriptGroupIDName)"
Pause
foreach ($hostname in $hostnameList){
    $deviceId = $null
    # Get correct device id based on exact hostname and last login
    $deviceID = (Get-MgDevice -Search "displayName:$($hostname)" -ConsistencyLevel eventual | Where-Object DisplayName -eq $hostname | Sort-Object ApproximateLastSignInDateTime -desc | Select-Object ApproximateLastSignInDateTime, id -First 1).Id
    if ($deviceID) {
        Write-host "Adding $hostname with Entra ID $deviceID"
        New-MgGroupMember -GroupId $scriptGroupID -DirectoryObjectId $deviceID -Verbose
        $deviceAdded = $deviceAdded + 1
    }
    else {
        $missingHostnames += $hostname
    }
}
Write-Host "----------"
Write-Host "Total devices added: $deviceAdded"
if ($hostnameList.count -ne $deviceAdded){
    Write-Warning "Some devices were not found in Entra ID:"
    foreach ($missinghostname in $missingHostnames) {
        Write-host "-> $missinghostname" -ForegroundColor Yellow
    }
}
Stop-Transcript

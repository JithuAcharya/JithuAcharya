param
(
    [Parameter(Mandatory)][String] $scriptID
)


Connect-MgGraph -Scopes DeviceManagementConfiguration.Read.All
$scriptDir = Split-Path $script:MyInvocation.MyCommand.Path
$graphQuery = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts/$($scriptID)/deviceRunStates?$expand=managedDevice($select=deviceName,userPrincipalName)" -Method GET
$graphResponse = $graphQuery.Value
$results = @()

while ($graphQuery.'@odata.nextLink') {
    $graphQuery = Invoke-MgGraphRequest -Uri $graphQuery.'@odata.nextLink' -Method GET
    $graphResponse += $graphQuery.Value
}ca

foreach ($entry in $graphResponse) {
            $results += $entry.resultMessage
}


Write-Host "Result -> $scriptDir\ScriptResult-$scriptID.txt"
$results > "$scriptDir\ScriptResult-$scriptID.txt"

# $results

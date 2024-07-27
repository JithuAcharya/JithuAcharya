#Remove Teams Chat
$MSTeams = "MicrosoftTeams"

$WinPackage = Get-AppxPackage -allusers | Where-Object {$_.Name -eq $MSTeams}
$ProvisionedPackage = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $WinPackage }
If ($null -ne $WinPackage) 
{
    Remove-AppxPackage  -Package $WinPackage.PackageFullName
} 

If ($null -ne $ProvisionedPackage) 
{
    Remove-AppxProvisionedPackage -online -Packagename $ProvisionedPackage.Packagename
}

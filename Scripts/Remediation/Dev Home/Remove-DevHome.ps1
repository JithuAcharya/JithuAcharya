<#
Script: Remove-DevHome
Description: Script removes the new Dev Home app on Windows 11 23H2.
Run this script using the logged-on credentials: Yes
Enforce script signature check: No
Run script in 64-bit PowerShell: Yes
#> 

try{
    Get-AppxPackage -Name *DevHome* | Remove-AppxPackage -ErrorAction stop
    Write-Host "Dev Home successfully removed."

}
catch{
    Write-Error "Error removing Dev Home."
}

<#
Script: Detect-DevHome
Description: Script detects the new Dev Home app on Windows 11 23H2.
Run this script using the logged-on credentials: Yes
Enforce script signature check: No
Run script in 64-bit PowerShell: Yes
#> 

if (Get-AppxPackage -Name *DevHome*) {
write-host "Dev Home found."

exit 1
}

else {
write-host "Dev Home not found."

exit 0
}

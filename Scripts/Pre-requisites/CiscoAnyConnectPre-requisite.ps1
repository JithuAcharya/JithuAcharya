# Cisco AnyConnect Pre-requisite
$interfaceStatus = (Get-NetAdapter | Where-Object InterfaceDescription -like "Cisco AnyConnect*").status
If ($interfaceStatus -ne "Up") {
    Write-host "Success"
}

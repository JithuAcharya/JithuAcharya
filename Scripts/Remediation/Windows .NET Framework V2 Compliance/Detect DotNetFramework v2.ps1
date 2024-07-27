$netFramework2Key = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v2.0.*'
if (Test-Path $netFramework2Key) {
    $netFramework2 = Get-ItemProperty -Path $netFramework2Key
    if ($netFramework2 -and $netFramework2.Install -eq 1) {
        Write-Output ".NET Framework 2.0 is installed."
    } else {
        Write-Output ".NET Framework 2.0 is not installed."
    }
} else {
    Write-Output ".NET Framework 2.0 is not installed."
}

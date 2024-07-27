# Arm OEM Branding Configuration Script

# Create log directory if necessary
if (!(Test-Path -path C:\ApplicationInstallLogs))
{
    New-Item C:\ApplicationInstallLogs -ItemType directory | Out-Null
}

# Transcript 
Start-Transcript "C:\ApplicationInstallLogs\OEMBrandingInfo_Update.log" -Append

# STEP 11: Configure OEM branding info
Write-Host "---- OEM Branding Configuration ----"
$key = "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation"
Set-ItemProperty -Path $Key -name "SupportPhone" -value "EMEA: +44 1223 983989; US: +1 669 321 5549; APAC: +91 80 4928 2200"  -Verbose


Write-Host "Ending..."
Stop-Transcript

# OOBE requirements script

# Variables
$InOOBE = (Get-Process -IncludeUserName | Where-Object ProcessName -eq WWAHost).Username

if ($InOOBE -like "*\defaultuser0") {
	Write-Output "Success"
}
else {
	Write-Output "Requirements not met"
}

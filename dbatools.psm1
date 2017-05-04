# Not supporting the provider path at this time 2/28/2017 - 63ms
if (((Resolve-Path .\).Path).StartsWith("SQLSERVER:\"))
{
	Write-Warning "SQLSERVER:\ provider not supported. Please change to another directory and reload the module."
	Write-Warning "Going to continue loading anyway, but expect issues."
}

<#

	Attempt to load all versions of SMO from vNext to 2005 - this is why RequiredAssemblies can't be used.

	Attempt to load all assemblies that will be needed in the module. 

	Not all versions support supporting assemblies, so ignore and let the command catch it.

	This takes about 11-50ms on a newer machine.

#>

$smoversions = "14.0.0.0", "13.0.0.0", "12.0.0.0", "11.0.0.0", "10.0.0.0", "9.0.242.0", "9.0.0.0"

foreach ($smoversion in $smoversions)
{
	try
	{
		Add-Type -AssemblyName "Microsoft.SqlServer.Smo, Version=$smoversion, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -ErrorAction Stop
		$smoadded = $true
	}
	catch
	{
		$smoadded = $false
	}
	
	if ($smoadded -eq $true) { break }
}

if ($smoadded -eq $false) { throw "Can't load SMO assemblies. You must have SQL Server Management Studio installed to proceed." }

$assemblies = "Management.Common", "Dmf", "Instapi", "SqlWmiManagement", "ConnectionInfo", "SmoExtended", "SqlTDiagM", "Management.Utility",
"SString", "Management.RegisteredServers", "Management.Sdk.Sfc", "SqlEnum", "RegSvrEnum", "WmiEnum", "ServiceBrokerEnum", "Management.XEvent",
"ConnectionInfoExtended", "Management.Collector", "Management.CollectorEnum", "Management.Dac", "Management.DacEnum", "Management.IntegrationServices"

foreach ($assembly in $assemblies)
{
	try
	{
		Add-Type -AssemblyName "Microsoft.SqlServer.$assembly, Version=$smoversion, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -ErrorAction Stop
	}
	catch
	{
		# Don't care
	}
}

<# 

	Do the rest of the loading 

#>

# This technique helps a little bit
# https://becomelotr.wordpress.com/2017/02/13/expensive-dot-sourcing/

# Load our own custom library
# Should always come before function imports - 141ms
$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$PSScriptRoot\bin\library.ps1"))), $null, $null)
$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$PSScriptRoot\bin\typealiases.ps1"))), $null, $null)

# All internal functions privately available within the toolset - 221ms
foreach ($function in (Get-ChildItem "$PSScriptRoot\internal\*.ps1"))
{
	$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($function))), $null, $null)
}

# All exported functions - 600ms
foreach ($function in (Get-ChildItem "$PSScriptRoot\functions\*.ps1"))
{
	$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($function))), $null, $null)
}

# Run all optional code
# Note: Each optional file must include a conditional governing whether it's run at all.
# Validations were moved into the other files, in order to prevent having to update dbatools.psm1 every time
# 96ms
foreach ($function in (Get-ChildItem "$PSScriptRoot\optional\*.ps1"))
{
	$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($function))), $null, $null)
}

#region Finally register autocompletion - 32ms
# Test whether we have Tab Expansion Plus available (used in dynamicparams scripts ran below)
if (Get-Command TabExpansionPlusPlus\Register-ArgumentCompleter -ErrorAction Ignore)
{
	$TEPP = $true
}
else
{
	$TEPP = $false
}

# dynamic params - 136ms
foreach ($function in (Get-ChildItem "$PSScriptRoot\internal\dynamicparams\*.ps1"))
{
	$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($function))), $null, $null)
}
#endregion Finally register autocompletion

# Load configuration system
# Should always go next to last
$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$PSScriptRoot\internal\configurations\configuration.ps1"))), $null, $null)

# Load scripts that must be individually run at the end - 30ms #
#--------------------------------------------------------------#

# Start the logging system (requires the configuration system up and running)
$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText("$PSScriptRoot\internal\scripts\logfilescript.ps1"))), $null, $null)

# I renamed this function to be more accurate - 1ms
Set-Alias -Name Reset-SqlSaPassword -Value Reset-SqlAdmin
Set-Alias -Name Copy-SqlUserDefinedMessage -Value Copy-SqlCustomError
Set-Alias -Name Copy-SqlJobServer -Value Copy-SqlServerAgent
Set-Alias -Name Restore-HallengrenBackup -Value Restore-SqlBackupFromDirectory
Set-Alias -Name Show-SqlMigrationConstraint -Value Test-SqlMigrationConstraint
Set-Alias -Name Test-SqlDiskAllocation -Value Test-DbaDiskAllocation
Set-Alias -Name Get-DiskSpace -Value Get-DbaDiskSpace
Set-Alias -Name Get-SqlMaxMemory -Value Get-DbaMaxMemory
Set-Alias -Name Set-SqlMaxMemory -Value Set-DbaMaxMemory

# SIG # Begin signature block
# MIINHQYJKoZIhvcNAQcCoIINDjCCDQoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUKuukrQ3tor9h9ztzR/VoDuy7
# hQCgggpfMIIFJzCCBA+gAwIBAgIQChuYqG2/P+oNcSoM5PlmATANBgkqhkiG9w0B
# AQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFz
# c3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMB4XDTE3MDQyNDAwMDAwMFoXDTE4MDUw
# MjEyMDAwMFowZDELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAkxBMRAwDgYDVQQHEwdD
# cm93bGV5MRowGAYDVQQKExFDaHJpc3RpbmEgTGVNYWlyZTEaMBgGA1UEAxMRQ2hy
# aXN0aW5hIExlTWFpcmUwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC7
# mkV28xCGG/rD4yhjpDPRZAjZtTulDRBeLnaIeF1CoHyhzMjCCYvV9avjS0V41os2
# /obamRWTwhK3x/6LLEFUNUWcufmuBa5um3b5QWUId2S9XLvmrjuv/3F9ClFbdoki
# zqijPTYT3nz4jBWYYgcSu3NhJ/5cr5/f3xHzfI3G15kIYpw5GcNAiEVmCjE1Ahdc
# HFYqyIAZlOzdbDEhgnp3jh5l85zRXcAjlZ2EmnWoRu2j0XTnaeCe0WhZOmVDsQfA
# qHSmrux+IdASqrl1NmOEhI4cbhMVdsLa7zJTa98KT8ZPG8DX7KIqf7HjiqU7DMwv
# BQq5Q6G0pyTZOvFZSrLpAgMBAAGjggHFMIIBwTAfBgNVHSMEGDAWgBRaxLl7Kgqj
# pepxA8Bg+S32ZXUOWDAdBgNVHQ4EFgQUrFS9TIKvUqHurtINfUDxFAOuQnEwDgYD
# VR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGA1UdHwRwMG4wNaAz
# oDGGL2h0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQtY3MtZzEu
# Y3JsMDWgM6Axhi9odHRwOi8vY3JsNC5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVk
# LWNzLWcxLmNybDBMBgNVHSAERTBDMDcGCWCGSAGG/WwDATAqMCgGCCsGAQUFBwIB
# FhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAgGBmeBDAEEATCBhAYIKwYB
# BQUHAQEEeDB2MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20w
# TgYIKwYBBQUHMAKGQmh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dFNIQTJBc3N1cmVkSURDb2RlU2lnbmluZ0NBLmNydDAMBgNVHRMBAf8EAjAAMA0G
# CSqGSIb3DQEBCwUAA4IBAQCqqtrG6dUKf6nf/XbWv745jP8wHdBSPeQhpLE4U2kN
# elWOvovcYrMJyOtvd+k7kAC7ZBw3D0I5d0/ep3e0nrPAa8yJoiPGUzQoPFU+WAbw
# wLSl6N97MBRS8bE/KHzXkEcs68EcAvRYCL5D7uCLNOChA8thZNFBt121TfyWDsvj
# JsYcRgR8aSKFTcM31q4AfbLEOUfzriKEC1Bhfh61fV4uY8fEYOTW9zzY658RwAKX
# xN6OUSSQkb4mzdG6sW/3+0J0ZahbK2YULtwvsREWnRw2U5So66BqBCWtHqfDgYs+
# /X/e9n884BUFjc0kM/hZrVGdAAIKJwfYBNjiAbVp6NlMMIIFMDCCBBigAwIBAgIQ
# BAkYG1/Vu2Z1U0O1b5VQCDANBgkqhkiG9w0BAQsFADBlMQswCQYDVQQGEwJVUzEV
# MBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29t
# MSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMTMxMDIy
# MTIwMDAwWhcNMjgxMDIyMTIwMDAwWjByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMM
# RGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQD
# EyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMIIBIjAN
# BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA+NOzHH8OEa9ndwfTCzFJGc/Q+0WZ
# sTrbRPV/5aid2zLXcep2nQUut4/6kkPApfmJ1DcZ17aq8JyGpdglrA55KDp+6dFn
# 08b7KSfH03sjlOSRI5aQd4L5oYQjZhJUM1B0sSgmuyRpwsJS8hRniolF1C2ho+mI
# LCCVrhxKhwjfDPXiTWAYvqrEsq5wMWYzcT6scKKrzn/pfMuSoeU7MRzP6vIK5Fe7
# SrXpdOYr/mzLfnQ5Ng2Q7+S1TqSp6moKq4TzrGdOtcT3jNEgJSPrCGQ+UpbB8g8S
# 9MWOD8Gi6CxR93O8vYWxYoNzQYIH5DiLanMg0A9kczyen6Yzqf0Z3yWT0QIDAQAB
# o4IBzTCCAckwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAYYwEwYD
# VR0lBAwwCgYIKwYBBQUHAwMweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhho
# dHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNl
# cnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwgYEG
# A1UdHwR6MHgwOqA4oDaGNGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dEFzc3VyZWRJRFJvb3RDQS5jcmwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0
# LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwTwYDVR0gBEgwRjA4Bgpg
# hkgBhv1sAAIEMCowKAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNv
# bS9DUFMwCgYIYIZIAYb9bAMwHQYDVR0OBBYEFFrEuXsqCqOl6nEDwGD5LfZldQ5Y
# MB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMA0GCSqGSIb3DQEBCwUA
# A4IBAQA+7A1aJLPzItEVyCx8JSl2qB1dHC06GsTvMGHXfgtg/cM9D8Svi/3vKt8g
# VTew4fbRknUPUbRupY5a4l4kgU4QpO4/cY5jDhNLrddfRHnzNhQGivecRk5c/5Cx
# GwcOkRX7uq+1UcKNJK4kxscnKqEpKBo6cSgCPC6Ro8AlEeKcFEehemhor5unXCBc
# 2XGxDI+7qPjFEmifz0DLQESlE/DmZAwlCEIysjaKJAL+L3J+HNdJRZboWR3p+nRk
# a7LrZkPas7CM1ekN3fYBIM6ZMWM9CBoYs4GbT8aTEAb8B4H6i9r5gkn3Ym6hU/oS
# lBiFLpKR6mhsRDKyZqHnGKSaZFHvMYICKDCCAiQCAQEwgYYwcjELMAkGA1UEBhMC
# VVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0
# LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIENvZGUgU2ln
# bmluZyBDQQIQChuYqG2/P+oNcSoM5PlmATAJBgUrDgMCGgUAoHgwGAYKKwYBBAGC
# NwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUvZVK4W0p
# 3YYMbLVMfi0dZATcTiUwDQYJKoZIhvcNAQEBBQAEggEAm8Bvpc3m+UjQS2NqRhV8
# XfeStq8E8hb5eDMot6Ttfz/XvhhbYZ0/1gXBjHc1LmTXg9kGt1MStpVdmkX1tEV5
# jfD7E2vk+BqntNHNkEMH9OmrW/5NeIo4gIBCGULLiryVXPy4vbLPf3RREO1MGN/7
# FxOBUJ3jpxlNLqPG4a49gPqHZbSVIEgSaOtSzIzQ2TWqTl/6xDyTPJ9yKOy3zW6x
# HFH+IygpCs5k7IRsKusjh1oQU66DoQ8e/6oGj3SvSXLSundHCmIWLcHUOWEtR0z1
# tAg6PabB/q6bAah0tMzVqzAZCbqqOJu8v8o5gtxMGHBvwLsCE/hW2ryXl9J8lCnl
# fA==
# SIG # End signature block

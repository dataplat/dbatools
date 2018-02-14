[CmdletBinding()]
param (
    [string]$Path,
    [switch]$Beta
)

function Write-LocalMessage {
    [CmdletBinding()]
    Param (
        [string]$Message
    )

    if (Test-Path function:Write-Message) { Write-Message -Level Output -Message $Message }
    else { Write-Host $Message }
}

try {
    Update-Module dbatools -Erroraction Stop
    Write-LocalMessage -Message "Updated using the PowerShell Gallery"
    return
}
catch {
    Write-LocalMessage -Message "dbatools was not installed by the PowerShell Gallery, continuing with web install."
}

$dbatools_copydllmode = $true
$module = Import-Module -Name dbatools -ErrorAction SilentlyContinue
$localpath = $module.ModuleBase

if ($null -eq $localpath) {
    $localpath = "$HOME\Documents\WindowsPowerShell\Modules\dbatools"
}
else {
    Write-LocalMessage -Message "Updating current install"
}

try {
    if (-not $path) {
        if ($PSCommandPath.Length -gt 0) {
            $path = Split-Path $PSCommandPath
            if ($path -match "github") {
                Write-LocalMessage -Message "Looks like this installer is run from your GitHub Repo, defaulting to psmodulepath"
                $path = $localpath
            }
        }
        else {
            $path = $localpath
        }
    }
}
catch {
    $path = $localpath
}

if (-not $path -or (Test-Path -Path "$path\.git")) {
    $path = $localpath
}

If ($lib = [appdomain]::CurrentDomain.GetAssemblies() | Where-Object FullName -like "dbatools, *") {
    if ($lib.Location -like "$Path\*") {
        Write-LocalMessage @"
We have detected dbatools to be already imported from
$path
In a manner that prevents us from updating it, since dll files have been locked.
In order to ensure a valid update, please:
- Close all consoles that have dbatools imported (Remove-Module dbatools is NOT enough)
- Start a new PowerShell console
- Run '`$dbatools_copydllmode = `$true' (without the single-quotes)
- Import dbatools and run Update-Dbatools
If done in this order, the binaries will be copied to another location before import, allowing for a save update.
"@
        return
    }
}

Write-LocalMessage -Message "Installing module to $path"

if (!(Test-Path -Path $path)) {
    try {
        Write-LocalMessage -Message "Creating directory: $path"
        New-Item -Path $path -ItemType Directory | Out-Null
    }
    catch {
        throw "Can't create $Path. You may need to Run as Administrator: $_"
    }
}

if ($beta) {
    $url = 'https://dbatools.io/devzip'
    $branch = "development"
}
else {
    $url = 'https://dbatools.io/zip'
    $branch = "master"
}

$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
$zipfile = "$temp\dbatools.zip"

Write-LocalMessage -Message "Downloading archive from github"
try {
    (New-Object System.Net.WebClient).DownloadFile($url, $zipfile)
}
catch {
    #try with default proxy and usersettings
    Write-LocalMessage -Message "Probably using a proxy for internet access, trying default proxy settings"
    $wc = (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    $wc.DownloadFile($url, $zipfile)
}

# Unblock if there's a block
Unblock-File $zipfile -ErrorAction SilentlyContinue

Write-LocalMessage -Message "Unzipping"

# Keep it backwards compatible
Remove-Item -ErrorAction SilentlyContinue "$temp\dbatools-$branch" -Recurse -Force
Remove-Item -ErrorAction SilentlyContinue "$temp\dbatools-old" -Recurse -Force
$null = New-Item "$temp\dbatools-old" -ItemType Directory
$shell = New-Object -ComObject Shell.Application
$zipPackage = $shell.NameSpace($zipfile)
$destinationFolder = $shell.NameSpace($temp)
$destinationFolder.CopyHere($zipPackage.Items())

Write-LocalMessage -Message "Applying Update"
Write-LocalMessage -Message "1) Backing up previous installation"
Copy-Item -Path "$Path\*" -Destination "$temp\dbatools-old" -ErrorAction Stop
try {
    Write-LocalMessage -Message "2) Cleaning up installation directory"
    Remove-Item "$Path\*" -Recurse -Force -ErrorAction Stop
}
catch {
    Write-LocalMessage -Message @"
Failed to clean up installation directory, rolling back update.
This usually has one of two causes:
- Insufficient privileges (need to run as admin)
- A file is locked - generally a dll file from having the module imported in some process.

You can run the following line before importing dbatools to prevent file locking:
`$dbatools_copydllmode = `$true
But it increases the time needed to import the module, so we only recommend using it for updates.

Exception:
$_
"@
    Copy-Item -Path "$temp\dbatools-old\*" -Destination $path -ErrorAction Ignore -Recurse
    Remove-Item "$temp\dbatools-old" -Recurse -Force
    return
}
Write-LocalMessage -Message "3) Setting up current version"
Move-Item -Path "$temp\dbatools-$branch\*" -Destination $path -ErrorAction SilentlyContinue -Force
Remove-Item -Path "$temp\dbatools-$branch" -Recurse -Force
Remove-Item "$temp\dbatools-old" -Recurse -Force
Remove-Item -Path $zipfile -Recurse -Force

Write-LocalMessage -Message "Done! Please report any bugs to dbatools.io/issues or clemaire@gmail.com."
if (Get-Module dbatools) {
    Write-LocalMessage -Message @"

Please restart PowerShell before working with dbatools.
"@
}
else {
    Import-Module "$path\dbatools.psd1" -Force
    Write-LocalMessage @"

dbatools v $((Get-Module dbatools).Version)
# Commands available: $((Get-Command -Module dbatools -CommandType Function | Measure-Object).Count)

"@
}
Write-LocalMessage -Message "`n`nIf you experience any function missing errors after update, please restart PowerShell or reload your profile."


# SIG # Begin signature block
# MIIcYgYJKoZIhvcNAQcCoIIcUzCCHE8CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUhOFJ3NXmFl4u6JtbLG6lCFv+
# OuGggheRMIIFGjCCBAKgAwIBAgIQAsF1KHTVwoQxhSrYoGRpyjANBgkqhkiG9w0B
# AQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFz
# c3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMB4XDTE3MDUwOTAwMDAwMFoXDTIwMDUx
# MzEyMDAwMFowVzELMAkGA1UEBhMCVVMxETAPBgNVBAgTCFZpcmdpbmlhMQ8wDQYD
# VQQHEwZWaWVubmExETAPBgNVBAoTCGRiYXRvb2xzMREwDwYDVQQDEwhkYmF0b29s
# czCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAI8ng7JxnekL0AO4qQgt
# Kr6p3q3SNOPh+SUZH+SyY8EA2I3wR7BMoT7rnZNolTwGjUXn7bRC6vISWg16N202
# 1RBWdTGW2rVPBVLF4HA46jle4hcpEVquXdj3yGYa99ko1w2FOWzLjKvtLqj4tzOh
# K7wa/Gbmv0Si/FU6oOmctzYMI0QXtEG7lR1HsJT5kywwmgcjyuiN28iBIhT6man0
# Ib6xKDv40PblKq5c9AFVldXUGVeBJbLhcEAA1nSPSLGdc7j4J2SulGISYY7ocuX3
# tkv01te72Mv2KkqqpfkLEAQjXgtM0hlgwuc8/A4if+I0YtboCMkVQuwBpbR9/6ys
# Z+sCAwEAAaOCAcUwggHBMB8GA1UdIwQYMBaAFFrEuXsqCqOl6nEDwGD5LfZldQ5Y
# MB0GA1UdDgQWBBRcxSkFqeA3vvHU0aq2mVpFRSOdmjAOBgNVHQ8BAf8EBAMCB4Aw
# EwYDVR0lBAwwCgYIKwYBBQUHAwMwdwYDVR0fBHAwbjA1oDOgMYYvaHR0cDovL2Ny
# bDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJlZC1jcy1nMS5jcmwwNaAzoDGGL2h0
# dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQtY3MtZzEuY3JsMEwG
# A1UdIARFMEMwNwYJYIZIAYb9bAMBMCowKAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3
# LmRpZ2ljZXJ0LmNvbS9DUFMwCAYGZ4EMAQQBMIGEBggrBgEFBQcBAQR4MHYwJAYI
# KwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBOBggrBgEFBQcwAoZC
# aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0U0hBMkFzc3VyZWRJ
# RENvZGVTaWduaW5nQ0EuY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQAD
# ggEBANuBGTbzCRhgG0Th09J0m/qDqohWMx6ZOFKhMoKl8f/l6IwyDrkG48JBkWOA
# QYXNAzvp3Ro7aGCNJKRAOcIjNKYef/PFRfFQvMe07nQIj78G8x0q44ZpOVCp9uVj
# sLmIvsmF1dcYhOWs9BOG/Zp9augJUtlYpo4JW+iuZHCqjhKzIc74rEEiZd0hSm8M
# asshvBUSB9e8do/7RhaKezvlciDaFBQvg5s0fICsEhULBRhoyVOiUKUcemprPiTD
# xh3buBLuN0bBayjWmOMlkG1Z6i8DUvWlPGz9jiBT3ONBqxXfghXLL6n8PhfppBhn
# daPQO8+SqF5rqrlyBPmRRaTz2GQwggUwMIIEGKADAgECAhAECRgbX9W7ZnVTQ7Vv
# lVAIMA0GCSqGSIb3DQEBCwUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdp
# Q2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0Rp
# Z2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0xMzEwMjIxMjAwMDBaFw0yODEw
# MjIxMjAwMDBaMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMx
# GTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNI
# QTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQD407Mcfw4Rr2d3B9MLMUkZz9D7RZmxOttE9X/lqJ3bMtdx
# 6nadBS63j/qSQ8Cl+YnUNxnXtqrwnIal2CWsDnkoOn7p0WfTxvspJ8fTeyOU5JEj
# lpB3gvmhhCNmElQzUHSxKCa7JGnCwlLyFGeKiUXULaGj6YgsIJWuHEqHCN8M9eJN
# YBi+qsSyrnAxZjNxPqxwoqvOf+l8y5Kh5TsxHM/q8grkV7tKtel05iv+bMt+dDk2
# DZDv5LVOpKnqagqrhPOsZ061xPeM0SAlI+sIZD5SlsHyDxL0xY4PwaLoLFH3c7y9
# hbFig3NBggfkOItqcyDQD2RzPJ6fpjOp/RnfJZPRAgMBAAGjggHNMIIByTASBgNV
# HRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggrBgEF
# BQcDAzB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRp
# Z2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCBgQYDVR0fBHoweDA6oDig
# NoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9v
# dENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# QXNzdXJlZElEUm9vdENBLmNybDBPBgNVHSAESDBGMDgGCmCGSAGG/WwAAgQwKjAo
# BggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAKBghghkgB
# hv1sAzAdBgNVHQ4EFgQUWsS5eyoKo6XqcQPAYPkt9mV1DlgwHwYDVR0jBBgwFoAU
# Reuir/SSy4IxLVGLp6chnfNtyA8wDQYJKoZIhvcNAQELBQADggEBAD7sDVoks/Mi
# 0RXILHwlKXaoHV0cLToaxO8wYdd+C2D9wz0PxK+L/e8q3yBVN7Dh9tGSdQ9RtG6l
# jlriXiSBThCk7j9xjmMOE0ut119EefM2FAaK95xGTlz/kLEbBw6RFfu6r7VRwo0k
# riTGxycqoSkoGjpxKAI8LpGjwCUR4pwUR6F6aGivm6dcIFzZcbEMj7uo+MUSaJ/P
# QMtARKUT8OZkDCUIQjKyNookAv4vcn4c10lFluhZHen6dGRrsutmQ9qzsIzV6Q3d
# 9gEgzpkxYz0IGhizgZtPxpMQBvwHgfqL2vmCSfdibqFT+hKUGIUukpHqaGxEMrJm
# oecYpJpkUe8wggZqMIIFUqADAgECAhADAZoCOv9YsWvW1ermF/BmMA0GCSqGSIb3
# DQEBBQUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IEFzc3Vy
# ZWQgSUQgQ0EtMTAeFw0xNDEwMjIwMDAwMDBaFw0yNDEwMjIwMDAwMDBaMEcxCzAJ
# BgNVBAYTAlVTMREwDwYDVQQKEwhEaWdpQ2VydDElMCMGA1UEAxMcRGlnaUNlcnQg
# VGltZXN0YW1wIFJlc3BvbmRlcjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC
# ggEBAKNkXfx8s+CCNeDg9sYq5kl1O8xu4FOpnx9kWeZ8a39rjJ1V+JLjntVaY1sC
# SVDZg85vZu7dy4XpX6X51Id0iEQ7Gcnl9ZGfxhQ5rCTqqEsskYnMXij0ZLZQt/US
# s3OWCmejvmGfrvP9Enh1DqZbFP1FI46GRFV9GIYFjFWHeUhG98oOjafeTl/iqLYt
# WQJhiGFyGGi5uHzu5uc0LzF3gTAfuzYBje8n4/ea8EwxZI3j6/oZh6h+z+yMDDZb
# esF6uHjHyQYuRhDIjegEYNu8c3T6Ttj+qkDxss5wRoPp2kChWTrZFQlXmVYwk/PJ
# YczQCMxr7GJCkawCwO+k8IkRj3cCAwEAAaOCAzUwggMxMA4GA1UdDwEB/wQEAwIH
# gDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMIIBvwYDVR0g
# BIIBtjCCAbIwggGhBglghkgBhv1sBwEwggGSMCgGCCsGAQUFBwIBFhxodHRwczov
# L3d3dy5kaWdpY2VydC5jb20vQ1BTMIIBZAYIKwYBBQUHAgIwggFWHoIBUgBBAG4A
# eQAgAHUAcwBlACAAbwBmACAAdABoAGkAcwAgAEMAZQByAHQAaQBmAGkAYwBhAHQA
# ZQAgAGMAbwBuAHMAdABpAHQAdQB0AGUAcwAgAGEAYwBjAGUAcAB0AGEAbgBjAGUA
# IABvAGYAIAB0AGgAZQAgAEQAaQBnAGkAQwBlAHIAdAAgAEMAUAAvAEMAUABTACAA
# YQBuAGQAIAB0AGgAZQAgAFIAZQBsAHkAaQBuAGcAIABQAGEAcgB0AHkAIABBAGcA
# cgBlAGUAbQBlAG4AdAAgAHcAaABpAGMAaAAgAGwAaQBtAGkAdAAgAGwAaQBhAGIA
# aQBsAGkAdAB5ACAAYQBuAGQAIABhAHIAZQAgAGkAbgBjAG8AcgBwAG8AcgBhAHQA
# ZQBkACAAaABlAHIAZQBpAG4AIABiAHkAIAByAGUAZgBlAHIAZQBuAGMAZQAuMAsG
# CWCGSAGG/WwDFTAfBgNVHSMEGDAWgBQVABIrE5iymQftHt+ivlcNK2cCzTAdBgNV
# HQ4EFgQUYVpNJLZJMp1KKnkag0v0HonByn0wfQYDVR0fBHYwdDA4oDagNIYyaHR0
# cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEQ0EtMS5jcmww
# OKA2oDSGMmh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJ
# RENBLTEuY3JsMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29j
# c3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdp
# Y2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURDQS0xLmNydDANBgkqhkiG9w0BAQUF
# AAOCAQEAnSV+GzNNsiaBXJuGziMgD4CH5Yj//7HUaiwx7ToXGXEXzakbvFoWOQCd
# 42yE5FpA+94GAYw3+puxnSR+/iCkV61bt5qwYCbqaVchXTQvH3Gwg5QZBWs1kBCg
# e5fH9j/n4hFBpr1i2fAnPTgdKG86Ugnw7HBi02JLsOBzppLA044x2C/jbRcTBu7k
# A7YUq/OPQ6dxnSHdFMoVXZJB2vkPgdGZdA0mxA5/G7X1oPHGdwYoFenYk+VVFvC7
# Cqsc21xIJ2bIo4sKHOWV2q7ELlmgYd3a822iYemKC23sEhi991VUQAOSK2vCUcIK
# SK+w1G7g9BQKOhvjjz3Kr2qNe9zYRDCCBs0wggW1oAMCAQICEAb9+QOWA63qAArr
# Pye7uhswDQYJKoZIhvcNAQEFBQAwZTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERp
# Z2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMb
# RGlnaUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4XDTA2MTExMDAwMDAwMFoXDTIx
# MTExMDAwMDAwMFowYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IElu
# YzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQg
# QXNzdXJlZCBJRCBDQS0xMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
# 6IItmfnKwkKVpYBzQHDSnlZUXKnE0kEGj8kz/E1FkVyBn+0snPgWWd+etSQVwpi5
# tHdJ3InECtqvy15r7a2wcTHrzzpADEZNk+yLejYIA6sMNP4YSYL+x8cxSIB8HqIP
# kg5QycaH6zY/2DDD/6b3+6LNb3Mj/qxWBZDwMiEWicZwiPkFl32jx0PdAug7Pe2x
# QaPtP77blUjE7h6z8rwMK5nQxl0SQoHhg26Ccz8mSxSQrllmCsSNvtLOBq6thG9I
# hJtPQLnxTPKvmPv2zkBdXPao8S+v7Iki8msYZbHBc63X8djPHgp0XEK4aH631XcK
# J1Z8D2KkPzIUYJX9BwSiCQIDAQABo4IDejCCA3YwDgYDVR0PAQH/BAQDAgGGMDsG
# A1UdJQQ0MDIGCCsGAQUFBwMBBggrBgEFBQcDAgYIKwYBBQUHAwMGCCsGAQUFBwME
# BggrBgEFBQcDCDCCAdIGA1UdIASCAckwggHFMIIBtAYKYIZIAYb9bAABBDCCAaQw
# OgYIKwYBBQUHAgEWLmh0dHA6Ly93d3cuZGlnaWNlcnQuY29tL3NzbC1jcHMtcmVw
# b3NpdG9yeS5odG0wggFkBggrBgEFBQcCAjCCAVYeggFSAEEAbgB5ACAAdQBzAGUA
# IABvAGYAIAB0AGgAaQBzACAAQwBlAHIAdABpAGYAaQBjAGEAdABlACAAYwBvAG4A
# cwB0AGkAdAB1AHQAZQBzACAAYQBjAGMAZQBwAHQAYQBuAGMAZQAgAG8AZgAgAHQA
# aABlACAARABpAGcAaQBDAGUAcgB0ACAAQwBQAC8AQwBQAFMAIABhAG4AZAAgAHQA
# aABlACAAUgBlAGwAeQBpAG4AZwAgAFAAYQByAHQAeQAgAEEAZwByAGUAZQBtAGUA
# bgB0ACAAdwBoAGkAYwBoACAAbABpAG0AaQB0ACAAbABpAGEAYgBpAGwAaQB0AHkA
# IABhAG4AZAAgAGEAcgBlACAAaQBuAGMAbwByAHAAbwByAGEAdABlAGQAIABoAGUA
# cgBlAGkAbgAgAGIAeQAgAHIAZQBmAGUAcgBlAG4AYwBlAC4wCwYJYIZIAYb9bAMV
# MBIGA1UdEwEB/wQIMAYBAf8CAQAweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzAB
# hhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9j
# YWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQw
# gYEGA1UdHwR6MHgwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdp
# Q2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwOqA4oDaGNGh0dHA6Ly9jcmw0LmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwHQYDVR0OBBYEFBUA
# EisTmLKZB+0e36K+Vw0rZwLNMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3z
# bcgPMA0GCSqGSIb3DQEBBQUAA4IBAQBGUD7Jtygkpzgdtlspr1LPUukxR6tWXHvV
# DQtBs+/sdR90OPKyXGGinJXDUOSCuSPRujqGcq04eKx1XRcXNHJHhZRW0eu7NoR3
# zCSl8wQZVann4+erYs37iy2QwsDStZS9Xk+xBdIOPRqpFFumhjFiqKgz5Js5p8T1
# zh14dpQlc+Qqq8+cdkvtX8JLFuRLcEwAiR78xXm8TBJX/l/hHrwCXaj++wc4Tw3G
# XZG5D2dFzdaD7eeSDY2xaYxP+1ngIw/Sqq4AfO6cQg7PkdcntxbuD8O9fAqg7iwI
# VYUiuOsYGk38KiGtSTGDR5V3cdyxG0tLHBCcdxTBnU8vWpUIKRAmMYIEOzCCBDcC
# AQEwgYYwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcG
# A1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBB
# c3N1cmVkIElEIENvZGUgU2lnbmluZyBDQQIQAsF1KHTVwoQxhSrYoGRpyjAJBgUr
# DgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMx
# DAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkq
# hkiG9w0BCQQxFgQU5Du/GTW5pEjBXVetygAETjhOMCgwDQYJKoZIhvcNAQEBBQAE
# ggEADglQBYTjtCNTAtKs4hi9Kj74iKxNnhf9xSdqZZAUin++ysdxOZrrBHdbQNHk
# C7YXsKWqYEic8k9asjFa/iZKHbRTJ9JdykG1ljrcjf+z+7eNXsP2z3axkKRchHxX
# eMVsfvaTsKOhQoXm+MKbsnUGwvisA3cbUOZ8kM40IKAcg+ujEHxxT4RzqsGPmnHP
# 4W/N88x7Hrtykah7TJDmp0x2mVrNdr6iRsWPgmEZSj59d5lLKE+A7xkdvtYGZDEh
# DyPLbDhWWRDo40+D5NKZSRP7WwTY6RPtAl1obaxZolySdD17ZIaFazEg3b9/cpx3
# c3fUF6wcAareoqJVbgSAW0bxU6GCAg8wggILBgkqhkiG9w0BCQYxggH8MIIB+AIB
# ATB2MGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNV
# BAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IEFzc3VyZWQg
# SUQgQ0EtMQIQAwGaAjr/WLFr1tXq5hfwZjAJBgUrDgMCGgUAoF0wGAYJKoZIhvcN
# AQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMTgwMjE0MTU1NjE1WjAj
# BgkqhkiG9w0BCQQxFgQU2ergF7YU3jz7T4v+V2ggn9yhehowDQYJKoZIhvcNAQEB
# BQAEggEAThEOnmqsOxBFjUc6gS6CUF1mBnDvGCRdtgBEwZv07B5/OHnxcwLqGAoC
# UTYWFKLoXYfbwSLcFvT4+KKH9/0bA7VLyuen2ChEDMGw+IG60CrJZpNVJ9a+h+sY
# c0qKGvQ/TUOTAGdln2FIJfNtiAi2fp2c6edgPHTl1ekpvkoNpnKd5tYQeIvMKpJu
# 9ZuWvVKBkqH7fgwu4YeAcuv52CvmQrkNJxHcrBoZoDVfYumu/S2bOGjBna4Rpc0a
# L5WgnpsiqxCvdvMKsWxl6HB3CyiA5IrdoC5NfNwFdBtOJtpmDmRUIVaPiEkPiKmk
# 8u1/WwxRa+X2/CHTN9cNc13EQWZLSw==
# SIG # End signature block

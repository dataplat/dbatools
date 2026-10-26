<#
.SYNOPSIS
    Authenticates the fleet controller to GitHub as the dbatools-fleet-controller App.

.DESCRIPTION
    Two steps, both plain REST so nothing has to be installed in the Function sandbox:
    an RS256 JWT signed with the App's private key proves we are the App, and that JWT
    buys a one-hour installation token scoped to dataplat/dbatools.

    The installation token is cached in module scope until five minutes before it
    expires. A reconcile pass makes a few dozen calls and a webhook burst can wake
    several passes; minting per call would spend the 5000/hour budget on nothing.

.NOTES
    Author: the dbatools team + Claude
#>

$script:InstallationToken = $null
$script:InstallationTokenExpiry = [DateTimeOffset]::MinValue

function ConvertTo-Base64Url {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    ([Convert]::ToBase64String($Bytes)).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function ConvertTo-RsaKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PrivateKeyPem
    )

    # A PEM that travelled through an app setting sometimes arrives with its newlines
    # escaped rather than real. ImportFromPem rejects that with an opaque ASN.1 error,
    # so normalize before handing it over.
    $pem = $PrivateKeyPem.Replace("\r\n", "`n").Replace("\n", "`n").Trim()
    $rsa = [System.Security.Cryptography.RSA]::Create()
    $rsa.ImportFromPem($pem)
    $rsa
}

function New-GitHubAppJwt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,
        [Parameter(Mandatory)]
        [string]$PrivateKeyPem
    )

    # iat is backdated a minute because GitHub rejects a JWT issued in its future, and
    # a Function host clock can sit a few seconds ahead. exp is nine minutes out; ten
    # is the documented maximum.
    $issuedAt = [DateTimeOffset]::UtcNow.AddSeconds(-60).ToUnixTimeSeconds()
    $expiresAt = [DateTimeOffset]::UtcNow.AddSeconds(540).ToUnixTimeSeconds()
    $header = @{
        alg = "RS256"
        typ = "JWT"
    }
    $claims = @{
        iat = $issuedAt
        exp = $expiresAt
        iss = $AppId
    }
    $encodedHeader = ConvertTo-Base64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes(($header | ConvertTo-Json -Compress)))
    $encodedClaims = ConvertTo-Base64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes(($claims | ConvertTo-Json -Compress)))
    $payload = "$encodedHeader.$encodedClaims"

    $rsa = ConvertTo-RsaKey -PrivateKeyPem $PrivateKeyPem
    try {
        $splatSignature = @{
            Data          = [System.Text.Encoding]::UTF8.GetBytes($payload)
            HashAlgorithm = [System.Security.Cryptography.HashAlgorithmName]::SHA256
            Padding       = [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        }
        $signature = $rsa.SignData($splatSignature.Data, $splatSignature.HashAlgorithm, $splatSignature.Padding)
    } finally {
        $rsa.Dispose()
    }
    "$payload.$(ConvertTo-Base64Url -Bytes $signature)"
}

function Get-GitHubInstallationToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,
        [Parameter(Mandatory)]
        [string]$InstallationId,
        [Parameter(Mandatory)]
        [string]$PrivateKeyPem,
        [switch]$Force
    )

    if (-not $Force -and $script:InstallationToken -and [DateTimeOffset]::UtcNow -lt $script:InstallationTokenExpiry) {
        return $script:InstallationToken
    }

    $jwt = New-GitHubAppJwt -AppId $AppId -PrivateKeyPem $PrivateKeyPem
    $splatToken = @{
        Method     = "Post"
        Uri        = "https://api.github.com/app/installations/$InstallationId/access_tokens"
        Headers    = @{
            Accept                 = "application/vnd.github+json"
            Authorization          = "Bearer $jwt"
            "X-GitHub-Api-Version" = "2022-11-28"
            "User-Agent"           = "dbatools-fleet-controller"
        }
        TimeoutSec = 30
    }
    $response = Invoke-RestMethod @splatToken

    $script:InstallationToken = $response.token
    $expiry = [DateTimeOffset]::UtcNow.AddMinutes(50)
    if ($response.expires_at) {
        $expiry = ([DateTimeOffset]::Parse([string]$response.expires_at)).AddMinutes(-5)
    }
    $script:InstallationTokenExpiry = $expiry
    $script:InstallationToken
}

function Clear-GitHubInstallationToken {
    [CmdletBinding()]
    param()

    $script:InstallationToken = $null
    $script:InstallationTokenExpiry = [DateTimeOffset]::MinValue
}

function Test-GitHubWebhookSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Body,
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Signature,
        [Parameter(Mandatory)]
        [string]$Secret
    )

    if (-not $Signature -or -not $Signature.StartsWith("sha256=")) {
        return $false
    }
    $hmac = New-Object -TypeName System.Security.Cryptography.HMACSHA256
    try {
        $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($Secret)
        $computed = "sha256=" + (($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Body)) | ForEach-Object { $PSItem.ToString("x2") }) -join "")
    } finally {
        $hmac.Dispose()
    }
    # Fixed-time comparison: a length-or-first-difference check leaks how much of a
    # guessed signature was right, which is enough to forge one byte at a time.
    $expected = [System.Text.Encoding]::UTF8.GetBytes($computed)
    $actual = [System.Text.Encoding]::UTF8.GetBytes($Signature)
    if ($expected.Length -ne $actual.Length) {
        return $false
    }
    $difference = 0
    for ($index = 0; $index -lt $expected.Length; $index++) {
        $difference = $difference -bor ($expected[$index] -bxor $actual[$index])
    }
    $difference -eq 0
}

$splatExport = @{
    Function = @(
        "New-GitHubAppJwt",
        "Get-GitHubInstallationToken",
        "Clear-GitHubInstallationToken",
        "Test-GitHubWebhookSignature",
        "ConvertTo-Base64Url"
    )
}
Export-ModuleMember @splatExport

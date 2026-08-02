function Test-DbaAccessToken {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [PSObject]$AccessToken
    )

    if ($null -eq $AccessToken) {
        return $false
    }

    if ($AccessToken.PSObject.BaseObject -is [Microsoft.SqlServer.Management.Common.IRenewableToken]) {
        return $true
    }

    $tokenValue = if ($AccessToken.PSObject.Properties["Token"]) {
        $AccessToken.Token
    } else {
        $AccessToken.PSObject.BaseObject
    }

    if ($tokenValue -is [System.Security.SecureString]) {
        return $tokenValue.Length -gt 0
    }

    if ($tokenValue -is [string]) {
        return -not [string]::IsNullOrWhiteSpace($tokenValue)
    }

    return $false
}

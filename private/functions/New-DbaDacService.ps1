function New-DbaDacService {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConnectionString,
        [Parameter(Mandatory)]
        [PSObject]$AccessToken
    )

    $accessTokenProviderType = "Dataplat.Dbatools.Utility.DacAccessTokenProvider" -as [type]
    if (-not $accessTokenProviderType) {
        $accessTokenProviderSource = @"
using System;
using System.Net;
using System.Security;
using Microsoft.SqlServer.Dac;
using Microsoft.SqlServer.Management.Common;

namespace Dataplat.Dbatools.Utility
{
    public sealed class DacAccessTokenProvider : IUniversalAuthProvider
    {
        private readonly object accessToken;
        private readonly bool renewable;
        private readonly IRenewableToken renewableAccessToken;

        public DacAccessTokenProvider(object accessToken, bool renewable)
        {
            if (accessToken == null)
            {
                throw new ArgumentNullException("accessToken");
            }

            this.accessToken = accessToken;
            this.renewable = renewable;
            if (renewable)
            {
                this.renewableAccessToken = accessToken as IRenewableToken;
                if (this.renewableAccessToken == null)
                {
                    throw new ArgumentException("A renewable access token must implement IRenewableToken.", "accessToken");
                }
            }
        }

        public string GetValidAccessToken()
        {
            object token = accessToken;
            if (renewable)
            {
                token = renewableAccessToken.GetAccessToken();
            }

            SecureString secureToken = token as SecureString;
            if (secureToken != null)
            {
                return new NetworkCredential(String.Empty, secureToken).Password;
            }

            string stringToken = token as string;
            if (String.IsNullOrEmpty(stringToken))
            {
                throw new InvalidOperationException("The access token provider did not return a string or SecureString token.");
            }
            return stringToken;
        }
    }
}
"@
        $splatAccessTokenProviderType = @{
            TypeDefinition       = $accessTokenProviderSource
            ReferencedAssemblies = @(
                [Microsoft.SqlServer.Dac.DacServices].Assembly.Location
                [Microsoft.SqlServer.Management.Common.IRenewableToken].Assembly.Location
                [System.Net.NetworkCredential].Assembly.Location
            )
            IgnoreWarnings       = $true
            WarningAction        = "SilentlyContinue"
            ErrorAction          = "Stop"
        }
        try {
            $null = Add-Type @splatAccessTokenProviderType
        } catch {
            $accessTokenProviderType = "Dataplat.Dbatools.Utility.DacAccessTokenProvider" -as [type]
            if (-not $accessTokenProviderType) {
                throw "Could not create the DacFx access token provider: $($PSItem.Exception.Message)"
            }
        }
        $accessTokenProviderType = "Dataplat.Dbatools.Utility.DacAccessTokenProvider" -as [type]
    }

    $isRenewable = $AccessToken.PSObject.BaseObject -is [Microsoft.SqlServer.Management.Common.IRenewableToken]
    $providerToken = if ($isRenewable) {
        $AccessToken.PSObject.BaseObject
    } else {
        $accessTokenValue = if ($AccessToken.PSObject.Properties["Token"]) {
            $AccessToken.Token
        } else {
            $AccessToken
        }
        if ($accessTokenValue -is [System.Security.SecureString]) {
            $accessTokenValue
        } elseif ($accessTokenValue -is [string]) {
            $accessTokenValue
        } else {
            throw "AccessToken must be a string, SecureString, object with a Token property, or IRenewableToken object."
        }
    }

    $authProvider = New-Object $accessTokenProviderType -ArgumentList $providerToken, $isRenewable
    $dacServiceConstructorTypes = [type[]]@(
        [string]
        [Microsoft.SqlServer.Dac.IUniversalAuthProvider]
    )
    $dacServiceConstructor = [Microsoft.SqlServer.Dac.DacServices].GetConstructor($dacServiceConstructorTypes)
    if (-not $dacServiceConstructor) {
        throw "The loaded DacFx assembly does not expose the access-token authentication provider constructor."
    }
    $dacServiceConstructorArguments = [object[]]@(
        $ConnectionString
        ([Microsoft.SqlServer.Dac.IUniversalAuthProvider]$authProvider)
    )
    $dacServiceConstructor.Invoke($dacServiceConstructorArguments)
}

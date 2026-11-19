using System;
using Dataplat.Dbatools.Connection;
using Microsoft.SqlServer.Management.Common;

/// <summary>
/// The renewable service principal token New-DbaAzAccessToken -Type RenewableServicePrincipal returns. It keeps the
/// name, global namespace and property order of the class the pinned function compiled with Add-Type, so scripts that
/// test for it or format it see the same object. Every GetAccessToken call asks Microsoft Entra ID for a new token
/// with the client credentials grant and records its expiry.
/// </summary>
public class PsObjectIRenewableToken : IRenewableToken
{
    /// <summary>
    /// Requests a token for Resource from the tenant's token endpoint and updates TokenExpiry.
    /// </summary>
    /// <returns>The access token, or an empty string when the response carried none</returns>
    public String GetAccessToken()
    {
        AzureAccessToken token = AzureAccessTokenService.GetClientCredentialToken(
            AzureAccessTokenService.Authority, Tenant, UserId, ClientSecret, Resource);
        TokenExpiry = token.ExpiresOn;
        return token.AccessToken ?? String.Empty;
    }

    /// <summary>When the most recently retrieved token expires.</summary>
    public System.DateTimeOffset TokenExpiry { get; set; }

    /// <summary>The App ID URI the token is for.</summary>
    public String Resource { get; set; }

    /// <summary>The tenant id or domain name.</summary>
    public System.String Tenant { get; set; }

    /// <summary>The service principal's application (client) id.</summary>
    public System.String UserId { get; set; }

    /// <summary>The service principal's client secret.</summary>
    public string ClientSecret { get; set; }
}

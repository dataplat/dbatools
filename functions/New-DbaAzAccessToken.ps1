function New-DbaAzAccessToken {
    <#
    .SYNOPSIS
        Simplifies the generation of Azure oauth2 tokens.

    .DESCRIPTION
        Generates an oauth2 access token.

        Currently, only Azure Managed Identities are built-in.

    .PARAMETER Type
        The type of request. Currently, only Managed Identities are built-in.

    .PARAMETER Subtype
        The subtype. Auto-complete

        This allows you to use a Windows VM system-assigned managed identity to access Azure SQL.

        Read more here: https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/tutorial-windows-vm-access-sql

    .PARAMETER Config
        The hashtable or json configuration.

    .PARAMETER Credential
        The credential for whatever

    .PARAMETER TenantId
        The tenant

    .PARAMETER Uri
        Plug-in a manual uri. If this is used, Type, Subtype and Config are ignored.

    .PARAMETER EnableException
        By default in most of our commands, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This command, however, gifts you  with "sea of red" exceptions, by default, because it is useful for advanced scripting.

        Using this switch turns our "nice by default" feature on which makes errors into pretty warnings.

    .NOTES
        Tags: Connect, Connection, Azure
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaAzAccessToken

    .EXAMPLE
        PS C:\> New-DbaAzAccessToken -Type ManagedIdentity -Subtype AzureSqlDb

    Returns a plain-text token for Managed Identities for SQL Azure Db.

    .EXAMPLE
        PS C:\> $token = New-DbaAzAccessToken -Type ManagedIdentity -Subtype AzureSqlDb
        PS C:\> $server = Connect-DbaInstance -SqlInstance myserver.database.windows.net -Database mydb -AccessToken $token -DisableException

        Generates a token then uses it to connect to Azure SQL DB

    #>
    [CmdletBinding()]
    param (
        [ValidateSet('ManagedIdentity', 'ServicePrincipal')]
        [string]$Type,
        [ValidateSet('AzureSqlDb', 'Management')]
        [string]$Subtype,
        [object]$Config,
        [string]$Uri,
        [pscredential]$Credential,
        [string]$TenantId,
        [string]$TenantAdName,
        [string]$ClientId,
        [switch]$EnableException
    )
    begin {
        if (-not ($Type -and $Subtype) -and -not ($Uri)) {
            Stop-Function -Message "You must specify Type and Subtype or Uri"
            return
        }
        if ($Type -eq "ServicePrincipal" -and -not $Credential -and (-not $TenantId -or -not $TenantAdName)) {
            Stop-Function -Message "You must specify Type and Subtype or Uri"
            return
        }
        if ($Type -eq "ManagedIdentity") {
            switch ($Subtype) {
                AzureSqlDb {
                    $Config = @{
                        Version  = '2018-04-02'
                        Resource = 'https://database.windows.net/'
                    }
                }
                Management {
                    $Config = @{
                        Version  = '2018-04-02'
                        Resource = 'https://management.windows.net/'
                    }
                }
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        if ($Uri) {
            $params = @{
                Uri     = $Uri
                Method  = "GET"
                Headers = @{ Metadata = "true" }
            }
            $response = Invoke-TlsWebRequest @params -UseBasicParsing -ErrorAction Stop
            return ($response.Content | ConvertFrom-Json).access_token
        }
        try {
            switch ($Type) {
                ManagedIdentity {
                    $version = $Config.Version
                    $resource = $Config.Resource
                    $params = @{
                        Uri     = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=$version&resource=$resource"
                        Method  = "GET"
                        Headers = @{ Metadata = "true" }
                    }
                    $response = Invoke-TlsWebRequest @params -UseBasicParsing -ErrorAction Stop
                    ($response.Content | ConvertFrom-Json).access_token
                }
                ServicePrincipal {
                    if ($TenantId) {
                        $authority = "https://login.windows.net/$TenantId"
                    } else {
                        $authority = "https://login.windows.net/$TenantAdName"
                    }

                    # thanks to Jose M Jurado - MSFT for this code
                    # https://blogs.msdn.microsoft.com/azuresqldbsupport/2018/05/10/lesson-learned-49-does-azure-sql-database-support-azure-active-directory-connections-using-service-principals/
                    $cred = [Microsoft.IdentityModel.Clients.ActiveDirectory.ClientCredential]::New($Credential.UserName, $Credential.GetNetworkCredential().Password)
                    $context = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext]::New($authority)
                    $result = $context.AcquireTokenAsync("https://database.windows.net/", $cred)

                    if ($result.Result.AccessToken) {
                        $result.Result.AccessToken
                    } else {
                        throw ($result.Exception | ConvertTo-Json | ConvertFrom-Json).InnerException.Message
                    }
                }
            }
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
        }
    }
}
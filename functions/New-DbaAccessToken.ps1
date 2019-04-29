function New-DbaAccessToken {
    <#
    .SYNOPSIS
        Simplifies the generation of Azure oauth2 tokens.

    .DESCRIPTION
        Generates an oauth2 access token.

        Currently, only Azure Managed Identities are built-in. This allows you to use a Windows VM system-assigned managed identity to access Azure SQL.

        Read more here: https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/tutorial-windows-vm-access-sql

    .PARAMETER Type
        The type of request. Currently, only Managed Identities are built-in.

    .PARAMETER Config
        The hashtable or json configuration.

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
        https://dbatools.io/New-DbaAccessToken

    .EXAMPLE
        PS C:\> New-DbaAccessToken

    Returns a plain-text token for Managed Identities for SQL Azure Db.

    .EXAMPLE
        PS C:\> $token = New-DbaAccessToken
        PS C:\> $server = Connect-DbaInstance -SqlInstance myserver.database.windows.net -Database mydb -AccessToken $token -DisableException

        Generates a token then uses it to connect to Azure SQL DB

    #>
    [CmdletBinding()]
    param (
        [ValidateSet('ManagedIdentity')]
        [string]$Type = 'ManagedIdentity',
        [object]$Config = @{
            Version  = '2018-04-02'
            Resource = 'https://database.windows.net/'
        },
        [switch]$EnableException
    )
    begin {
        # then we can do if Type -eq SomethingElse and -not $Config, go with some other type defaults
    }
    process {
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
                    $response = Invoke-WebRequest @params -UseBasicParsing -ErrorAction Stop
                    ($response.Content | ConvertFrom-Json).access_token
                }
            }
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
        }
    }
}
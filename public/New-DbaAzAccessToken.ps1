function New-DbaAzAccessToken {
    <#
    .SYNOPSIS
        Generates OAuth2 access tokens for Azure SQL Database and other Azure services authentication.

    .DESCRIPTION
        Creates OAuth2 access tokens for connecting to Azure SQL Database and other Azure services without storing passwords in scripts. Supports Managed Identity authentication from Azure VMs, Service Principal authentication for applications, and renewable tokens for long-running connections. The generated tokens can be used directly with Connect-DbaInstance and other dbatools commands to establish secure, modern authentication to Azure resources.

        Want to know more about Access Tokens? This page explains it well: https://dzone.com/articles/using-managed-identity-to-securely-access-azure-re

    .PARAMETER Type
        The type of request:
        ManagedIdentity
        ServicePrincipal
        RenewableServicePrincipal

    .PARAMETER Subtype
        The subtype. Options include:
        AzureSqlDb (default)
        ResourceManager
        DataLake
        EventHubs
        KeyVault
        ResourceManager
        ServiceBus
        Storage

        Read more here: https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/tutorial-windows-vm-access-sql

    .PARAMETER Config
        The hashtable or json configuration.

    .PARAMETER Credential
        When using the ServicePrincipal type, a Credential is required. The username is the App ID and Password is the App Password

        https://docs.microsoft.com/en-us/azure/active-directory/user-help/multi-factor-authentication-end-user-app-passwords

    .PARAMETER Tenant
        When using the ServicePrincipal or RenewableServicePrincipal types, a tenant name or ID is required. This field works with both.

    .PARAMETER Thumbprint
        Thumbprint for connections to Azure MSI

    .PARAMETER Store
        Store where the Azure MSI certificate is stored

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Connect, Connection, Azure
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaAzAccessToken

    .EXAMPLE
        PS C:\> New-DbaAzAccessToken -Type ManagedIdentity

        Returns a plain-text token for Managed Identities for SQL Azure Db.

    .EXAMPLE
        PS C:\> $token = New-DbaAzAccessToken -Type ManagedIdentity -Subtype AzureSqlDb
        PS C:\> $server = Connect-DbaInstance -SqlInstance myserver.database.windows.net -Database mydb -AccessToken $token -DisableException

        Generates a token then uses it to connect to Azure SQL DB then connects to an Azure SQL Db

    .EXAMPLE
        PS C:\> $token = New-DbaAzAccessToken -Type ServicePrincipal -Tenant whatup.onmicrosoft.com -Credential ee590f55-9b2b-55d4-8bca-38ab123db670
        PS C:\> $server = Connect-DbaInstance -SqlInstance myserver.database.windows.net -Database mydb -AccessToken $token -DisableException
        PS C:\> Invoke-DbaQuery -SqlInstance $server -Query "select 1 as test"

        Generates a token then uses it to connect to Azure SQL DB then connects to an Azure SQL Db.
        Once the connection is made, it is used to perform a test query.

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [ValidateSet("ManagedIdentity", "ServicePrincipal", "RenewableServicePrincipal")]
        [string]$Type,
        [ValidateSet("AzureSqlDb", "ResourceManager", "DataLake", "EventHubs", "KeyVault", "ResourceManager", "ServiceBus", "Storage")]
        [string]$Subtype = "AzureSqlDb",
        [object]$Config,
        [PSCredential]$Credential,
        [string]$Tenant = (Get-DbatoolsConfigValue -FullName 'azure.tenantid'),
        [string]$Thumbprint = (Get-DbatoolsConfigValue -FullName 'azure.certificate.thumbprint'),
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$Store = (Get-DbatoolsConfigValue -FullName 'azure.certificate.store'),
        [switch]$EnableException
    )
    begin {
        if ($Type -in "ServicePrincipal", "RenewableServicePrincipal") {
            $appid = (Get-DbatoolsConfigValue -FullName 'azure.appid')
            $clientsecret = (Get-DbatoolsConfigValue -FullName 'azure.clientsecret')

            if (($appid -and $clientsecret) -and -not $Credential) {
                $Credential = New-Object System.Management.Automation.PSCredential ($appid, $clientsecret)
            }

            if (-not $Credential -and -not $Tenant) {
                Stop-Function -Message "You must specify a Credential and Tenant when using ServicePrincipal or RenewableServicePrincipal"
                return
            }
        }

        if ($Type -eq "RenewableServicePrincipal") {
            $source = @"
            using System;
            using Microsoft.SqlServer.Management.Common;
            using System.Management.Automation;
            using System.Collections.ObjectModel;
            using System.Management.Automation.Runspaces;

            public class PsObjectIRenewableToken : IRenewableToken {
                public String GetAccessToken() {
                    PowerShell psCmd = PowerShell.Create().AddScript(@"param(`$this)$({
                    $authority = "https://login.microsoftonline.com/$($this.Tenant)/oauth2/token"
                    $parameter = @{
                        grant_type='client_credentials'
                        client_id=$this.UserID
                        client_secret=$this.ClientSecret
                        resource=$this.Resource
                    }

                    $body = (@(foreach ($param in $parameter.GetEnumerator()) {
                        "$($param.key)=$([Uri]::EscapeDataString($param.Value.ToString()))"
                    }) -join '&')

                    $bearerInfo = Invoke-RestMethod -Uri $authority -Method Post -Body $body
                    $this.TokenExpiry = [DateTimeOffset]::FromUnixTimeSeconds($BearerInfo.expires_on)
                    return $bearerInfo.access_token
                    }.ToString().Replace('"','""'))").AddArgument(this);

                    Collection<string> results = psCmd.Invoke<string>();
                    if (psCmd.Streams.Error.Count > 0) {
                        throw psCmd.Streams.Error[0].Exception;
                    }

                    psCmd.Dispose();

                    if (results.Count == 1) {
                        return results[0];
                    } else {
                        return String.Empty;
                    }
                }

                public System.DateTimeOffset TokenExpiry { get; set;  }
                public String Resource { get; set; }
                public System.String Tenant { get; set; }
                public System.String UserId { get; set; }
                public string ClientSecret { get; set; }
            }
"@
            Add-Type -TypeDefinition $source -ReferencedAssemblies ([Microsoft.SqlServer.Management.Common.IRenewableToken].Assembly,
                [PowerShell].Assembly,
                [Microsoft.SqlServer.Management.Common.IRenewableToken].Assembly.GetReferencedAssemblies()[0])

        }

        switch ($Subtype) {
            AzureSqlDb {
                $Config = @{
                    Resource = "https://database.windows.net/"
                }
            }
            ResourceManager {
                $Config = @{
                    Resource = "https://management.azure.com/"
                }
            }
            KeyVault {
                $Config = @{
                    Resource = "https://vault.azure.net/"
                }
            }
            DataLake {
                $Config = @{
                    Resource = "https://datalake.azure.net/"
                }
            }
            EventHubs {
                $Config = @{
                    Resource = "https://eventhubs.azure.net/"
                }
            }
            ServiceBus {
                $Config = @{
                    Resource = "https://servicebus.azure.net/"
                }
            }
            Storage {
                $Config = @{
                    Resource = "https://storage.azure.com/"
                }
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        try {
            switch ($Type) {
                ManagedIdentity {
                    $version = $Config.Version
                    if (-not $version) {
                        $version = "2018-04-02"
                    }
                    $resource = $Config.Resource
                    $params = @{
                        Uri     = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=$version&resource=$resource"
                        Method  = "GET"
                        Headers = @{ Metadata = "true" }
                    }
                    $response = Invoke-TlsWebRequest @params -UseBasicParsing -ErrorAction Stop
                    return ($response.Content | ConvertFrom-Json).access_token
                }
                ServicePrincipal {
                    if ($script:core) {
                        Stop-Function -Message "ServicePrincipal currently unsupported in Core"
                        return
                    }

                    # thanks to Jose M Jurado - MSFT for this code
                    # https://blogs.msdn.microsoft.com/azuresqldbsupport/2018/05/10/lesson-learned-49-does-azure-sql-database-support-azure-active-directory-connections-using-service-principals/
                    $cred = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.ClientCredential -ArgumentList $Credential.UserName, $Credential.GetNetworkCredential().Password
                    $context = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext -ArgumentList "https://login.windows.net/$Tenant"
                    $result = $context.AcquireTokenAsync($Config.Resource, $cred)

                    if ($result.Result.AccessToken) {
                        return $result.Result.AccessToken
                    } else {
                        throw ($result.Exception | ConvertTo-Json | ConvertFrom-Json).InnerException.Message
                    }
                }
                RenewableServicePrincipal {
                    New-Object PSObjectIRenewableToken -Property @{
                        ClientSecret = $Credential.GetNetworkCredential().Password
                        Resource     = "https://database.windows.net/"
                        Tenant       = $Tenant
                        UserID       = $Credential.UserName
                    }
                }
            }
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
        }
    }
}
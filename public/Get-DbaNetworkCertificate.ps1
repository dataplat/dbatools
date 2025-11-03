function Get-DbaNetworkCertificate {
    <#
    .SYNOPSIS
        Retrieves the certificate currently configured for SQL Server network encryption.

    .DESCRIPTION
        Retrieves the specific computer certificate that SQL Server is configured to use for network encryption and SSL connections. This shows you which certificate from the local certificate store is actively being used by the SQL Server instance for encrypting client connections. Only returns instances that actually have a certificate configured - instances without certificates won't appear in the results. Useful for auditing SSL configurations, troubleshooting encrypted connection issues, and verifying certificate assignments across multiple instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to standard instance on localhost. If target is a cluster, you must specify the distinct nodes.

    .PARAMETER Credential
        Alternate credential object to use for accessing the target computer(s).

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Encryption, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaNetworkCertificate

    .EXAMPLE
        PS C:\> Get-DbaNetworkCertificate -SqlInstance sql2016

        Gets computer certificate for the standard instance on sql2016 that is being used for SQL Server network encryption

    .EXAMPLE
        PS C:\> Get-DbaNetworkCertificate -SqlInstance server1\sql2017

        Gets computer certificate for the named instance sql2017 on server1 that is being used for SQL Server network encryption
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("ComputerName")]
        [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {
        $PSBoundParameters["OutputType"] = "Certificate"
        Get-DbaNetworkConfiguration @PSBoundParameters | Where-Object Thumbprint
    }
}
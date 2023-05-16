function Get-DbaReplSubscription {
    <#
    .SYNOPSIS
        Displays all subscriptions for a publication.

    .DESCRIPTION
        Displays all subscriptions for a publication

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Database
        The database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER Name
        The name of the publication.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Type
        Limit by specific type of publication. Valid choices include: Transactional, Merge, Snapshot

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Replication
        Author: Colin Douglas

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaReplPublication

    .EXAMPLE
        PS C:\> Get-DbaReplPublication -SqlInstance sql2008, sqlserver2012

        Return all publications for servers sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> Get-DbaReplPublication -SqlInstance sql2008 -Database TestDB

        Return all publications on server sql2008 for only the TestDB database

    .EXAMPLE
        PS C:\> Get-DbaReplPublication -SqlInstance sql2008 -Type Transactional

        Return all publications on server sql2008 for all databases that have Transactional publications

    .EXAMPLE
        PS C:\> Get-DbaReplPublication -SqlInstance mssql1 -Name Mergey

        Returns the Mergey publications on server mssql1
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [object[]]$Database,
        [PSCredential]$SqlCredential,
        [String]$Name,
        [Alias("PublicationType")]
        [ValidateSet("Transactional", "Merge", "Snapshot")]
        [object[]]$Type,
        [switch]$EnableException
    )
    begin {
        Add-ReplicationLibrary
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {

            # Connect to Publisher
            try {
                $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $PublisherSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Get all subscriptions
            $transSub = New-Object Microsoft.SqlServer.Replication.TransSubscription
            $transSub.ConnectionContext = $replServer.ConnectionContext
            $transSub.EnumSubscriptions()


            #TODO: finish this function

        }
    }
}
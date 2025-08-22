function Test-DbaDbCollation {
    <#
    .SYNOPSIS
        Identifies databases with collations that differ from the SQL Server instance default collation

    .DESCRIPTION
        Compares each database's collation against the SQL Server instance's default collation to identify mismatches. Database collation mismatches can cause string comparison issues, join failures, and stored procedure errors when working across databases. This function helps you audit collation consistency across your databases, which is especially important before migrations, mergers, or when troubleshooting application issues related to character sorting and comparison behavior.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Collation
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaDbCollation

    .EXAMPLE
        PS C:\> Test-DbaDbCollation -SqlInstance sqlserver2014a

        Returns server name, database name and true/false if the collations match for all databases on sqlserver2014a.

    .EXAMPLE
        PS C:\> Test-DbaDbCollation -SqlInstance sqlserver2014a -Database db1, db2

        Returns information for the db1 and db2 databases on sqlserver2014a.

    .EXAMPLE
        PS C:\> Test-DbaDbCollation -SqlInstance sqlserver2014a, sql2016 -Exclude db1

        Returns information for database and server collations for all databases except db1 on sqlserver2014a and sql2016.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2016 | Test-DbaDbCollation

        Returns db/server collation information for every database on every server listed in the Central Management Server on sql2016.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbs = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                $dbs = $dbs | Where-Object { $Database -contains $_.Name }
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $($db.name) on $servername."
                [PSCustomObject]@{
                    ComputerName      = $server.ComputerName
                    InstanceName      = $server.ServiceName
                    SqlInstance       = $server.DomainInstanceName
                    Database          = $db.name
                    ServerCollation   = $server.collation
                    DatabaseCollation = $db.collation
                    IsEqual           = $db.collation -eq $server.collation
                }
            }
        }
    }
}
function Test-DbaDbCompatibility {
    <#
    .SYNOPSIS
        Identifies databases running at lower compatibility levels than the SQL Server instance supports

    .DESCRIPTION
        Compares each database's compatibility level against the SQL Server instance's maximum supported compatibility level. This helps identify databases that may not be leveraging newer SQL Server features and performance improvements available after an instance upgrade. Returns detailed comparison results showing which databases could benefit from compatibility level updates to match the server version.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to test for compatibility level mismatches. Accepts database names, wildcards, or arrays.
        Use this when you need to check specific databases instead of testing all databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies which databases to skip during compatibility level testing. Accepts database names, wildcards, or arrays.
        Use this to exclude system databases, maintenance databases, or any databases you don't want included in the results.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Compatibility
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaDbCompatibility

    .OUTPUTS
        PSCustomObject

        Returns one object per database processed. The number of objects depends on the number of databases on the instance and any filtering applied via -Database or -ExcludeDatabase parameters.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - ServerLevel: The SQL Server instance's compatibility level (CompatibilityLevel enum value like Version140, Version150, etc.)
        - Database: The name of the database being evaluated
        - DatabaseCompatibility: The database's current compatibility level (CompatibilityLevel enum value)
        - IsEqual: Boolean indicating whether the database compatibility level matches the server's maximum compatibility level

    .EXAMPLE
        PS C:\> Test-DbaDbCompatibility -SqlInstance sqlserver2014a

        Returns server name, database name and true/false if the compatibility level match for all databases on sqlserver2014a.

    .EXAMPLE
        PS C:\> Test-DbaDbCompatibility -SqlInstance sqlserver2014a -Database db1, db2

        Returns detailed information for database and server compatibility level for the db1 and db2 databases on sqlserver2014a.

    .EXAMPLE
        PS C:\> Test-DbaDbCompatibility -SqlInstance sqlserver2014a, sql2016 -Exclude db1

        Returns detailed information for database and server compatibility level for all databases except db1 on sqlserver2014a and sql2016.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2014 | Test-DbaDbCompatibility

        Returns db/server compatibility information for every database on every server listed in the Central Management Server on sql2016.

    #>
    [CmdletBinding()]
    [OutputType("System.Collections.ArrayList")]
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
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $serverVersion = $server.VersionMajor
            $serverLevel = [Microsoft.SqlServer.Management.Smo.CompatibilityLevel]"Version$($serverVersion)0"
            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object { $Database -contains $_.Name }
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $($db.name) on $instance."
                [PSCustomObject]@{
                    ComputerName          = $server.ComputerName
                    InstanceName          = $server.ServiceName
                    SqlInstance           = $server.DomainInstanceName
                    ServerLevel           = $serverLevel
                    Database              = $db.name
                    DatabaseCompatibility = $db.CompatibilityLevel
                    IsEqual               = $db.CompatibilityLevel -eq $serverLevel
                }
            }
        }
    }
}
function Get-DbaDbFeatureUsage {
    <#
    .SYNOPSIS
        Identifies Enterprise-edition features currently used in databases that prevent downgrading to Standard edition

    .DESCRIPTION
        Queries the sys.dm_db_persisted_sku_features dynamic management view to identify SQL Server Enterprise features that are actively used in your databases. This is essential when planning to downgrade from Enterprise to Standard edition or migrating databases to environments with lower SQL Server editions.

        Enterprise features like columnstore indexes, table partitioning, or transparent data encryption must be removed or disabled before a database can be successfully migrated to Standard edition. This function helps you inventory these blocking features across one or more databases so you can plan the necessary remediation steps.

        Returns feature ID, feature name, and database information for each Enterprise feature found, making it easy to identify which databases need attention before edition changes.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to scan for Enterprise edition features. Accepts wildcards for pattern matching.
        Use this when you need to check specific databases instead of scanning all databases on the instance.
        Helpful when planning edition downgrades for particular databases or troubleshooting feature usage in development environments.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the Enterprise feature scan. Accepts wildcards for pattern matching.
        Use this to skip system databases, read-only databases, or databases you know don't need to be downgraded.
        Commonly used to exclude tempdb, model, or archived databases from bulk scanning operations.

    .PARAMETER InputObject
        Accepts database objects directly from the pipeline, typically from Get-DbaDatabase output.
        Use this for advanced filtering scenarios or when you've already retrieved specific database objects.
        Allows you to chain database selection commands with feature usage checking in a single pipeline operation.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Deprecated
        Author: Brandon Abshire, netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbFeatureUsage

    .OUTPUTS
        PSCustomObject

        Returns one object per Enterprise-edition feature found in the queried database(s).

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The name of the SQL Server instance (MSSQLSERVER for default instance)
        - SqlInstance: The full SQL Server instance name (computer\instance or just computer for default)
        - Id: The feature ID from sys.dm_db_persisted_sku_features
        - Feature: The name of the Enterprise-edition feature that is currently in use
        - Database: The database where this Enterprise feature was detected

        No properties are returned if no Enterprise features are found in the queried database(s).

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2008 -Database testdb, db2 | Get-DbaDbFeatureUsage

        Shows features that are enabled in the testdb and db2 databases but
        not supported on the all the editions of SQL Server.

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        $sql = "SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
            ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
            SERVERPROPERTY('ServerName') AS SqlInstance, feature_id AS Id,
            feature_name AS Feature,  DB_NAME() AS [Database] FROM sys.dm_db_persisted_sku_features"
    }

    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }
        foreach ($db in $InputObject) {
            Write-Message -Level Verbose -Message "Processing $db on $($db.Parent.Name)"

            if ($db.IsAccessible -eq $false) {
                Stop-Function -Message "The database $db is not accessible. Skipping database." -Continue
            }

            try {
                $db.Query($sql)
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}